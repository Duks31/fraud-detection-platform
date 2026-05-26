import os
from fastapi import FastAPI, HTTPException
import mlflow.sklearn
import pandas as pd
from feast import FeatureStore
from dotenv import load_dotenv
from pathlib import Path
from contextlib import asynccontextmanager

current_dir = Path(__file__).parent
dotenv_path = current_dir.parent / "infrastructure" / ".env"

load_dotenv(dotenv_path)

MINIO_ROOT_USER = os.getenv("MINIO_ROOT_USER")
MINIO_ROOT_PASSWORD = os.getenv("MINIO_ROOT_PASSWORD")

os.environ["MLFLOW_S3_ENDPOINT_URL"] = "http://s3:9000"
os.environ["AWS_ACCESS_KEY_ID"] = MINIO_ROOT_USER
os.environ["AWS_SECRET_ACCESS_KEY"] = MINIO_ROOT_PASSWORD
os.environ["MLFLOW_S3_IGNORE_TLS"] = "true"

mlflow.set_tracking_uri("http://sentinel_mlflow:5000")

model = None
store = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global model, store

    try:
        store = FeatureStore(repo_path="/app/feature_store")

        experiment = mlflow.get_experiment_by_name("Fraud detection")
        if experiment is None:
            raise ValueError("Experiment 'Fraud detection' not found")

        runs = mlflow.search_runs(
            experiment_ids=[experiment.experiment_id],
            order_by=["start_time DESC"],
            max_results=1,
        )

        if runs.empty:
            raise ValueError("No runs found in experiment")

        RUN_ID = runs.iloc[0]["run_id"]
        print(f"Latest run ID: {RUN_ID}")

        # Find the latest model in MinIO
        import boto3

        s3 = boto3.client(
            "s3",
            endpoint_url="http://s3:9000",
            aws_access_key_id=os.getenv("MINIO_ROOT_USER"),
            aws_secret_access_key=os.getenv("MINIO_ROOT_PASSWORD"),
        )

        # List models sorted by last modified
        exp_id = experiment.experiment_id
        objects = s3.list_objects_v2(Bucket="mlflow", Prefix=f"{exp_id}/models/")
        if "Contents" not in objects:
            raise ValueError("No models found in MinIO")

        # Find the most recent model directory
        model_dirs = {}
        for obj in objects["Contents"]:
            # Extract model ID from path like: 2/models/m-xxx/artifacts/...
            parts = obj["Key"].split("/")
            if len(parts) >= 3 and parts[2].startswith("m-"):
                model_id = parts[2]
                if (
                    model_id not in model_dirs
                    or obj["LastModified"] > model_dirs[model_id]
                ):
                    model_dirs[model_id] = obj["LastModified"]

        if not model_dirs:
            raise ValueError("No valid model directories found")

        # Get the most recent model
        latest_model_id = max(model_dirs.items(), key=lambda x: x[1])[0]
        print(f" Latest model ID: {latest_model_id}")

        # Load model directly from S3 path
        model_uri = f"s3://mlflow/{exp_id}/models/{latest_model_id}/artifacts"
        print(f" Loading model from: {model_uri}")

        model = mlflow.sklearn.load_model(model_uri)
        print(" Model loaded successfully!")

        yield
    except Exception as e:
        import traceback

        print(f" CRITICAL STARTUP ERROR: {e}")
        print(traceback.format_exc())
        model = None
        store = None
        yield
    finally:
        print("Shutting down application...")


app = FastAPI(title="Sentinel Fraud Detection API", lifespan=lifespan)


@app.get("/predict/{transaction_id}")
def predict(transaction_id: int):
    # Check if model is loaded
    if model is None:
        raise HTTPException(
            status_code=503,
            detail="Model not loaded. Please check MLflow and MinIO connections.",
        )

    if store is None:
        raise HTTPException(status_code=503, detail="Feature Store not loaded.")

    try:
        # Fetch features from Feast
        feature_vector = store.get_online_features(
            features=[
                "transaction_stats:TransactionAmt",
                "transaction_stats:card1",
                "transaction_stats:card2",
                "transaction_stats:addr1",
            ],
            entity_rows=[{"TransactionID": transaction_id}],
        ).to_dict()

        features_df = pd.DataFrame.from_dict(feature_vector)
        expected_columns = ["TransactionAmt", "card1", "card2", "addr1"]
        X = features_df[expected_columns].fillna(0)

        # Make prediction
        prediction = model.predict(X)[0]
        probability = model.predict_proba(X)[0][1]

        return {
            "transaction_id": transaction_id,
            "is_fraud": bool(prediction),
            "fraud_probability": float(probability),
            "status": "Success",
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Prediction failed: {str(e)}")


@app.get("/health")
def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "model_loaded": model is not None,
        "feature_store_loaded": store is not None,
    }


@app.get("/")
def home():
    return {
        "project": "Sentinel Fraud Detection",
        "status": "Online",
        "model_status": "Loaded" if model is not None else "Not Loaded",
        "endpoints": {
            "prediction": "/predict/{transaction_id}",
            "health": "/health",
            "docs": "/docs",
        },
    }
