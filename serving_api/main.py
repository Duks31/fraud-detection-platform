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

os.environ["MLFLOW_S3_ENDPOINT_URL"] = "http://sentinel_minio:9000"
os.environ["AWS_ACCESS_KEY_ID"] = MINIO_ROOT_USER
os.environ["AWS_SECRET_ACCESS_KEY"] = MINIO_ROOT_PASSWORD
os.environ["MLFLOW_S3_IGNORE_TLS"] = "true"

mlflow.set_tracking_uri("http://sentinel_mlflow:5000")

model = None
store = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: Load model and feature store
    global model, store

    try:
        store = FeatureStore(repo_path="../feature_store")

        RUN_ID = "c8ef81eddff247918e8b15373227757d"
        model_uri = f"runs:/{RUN_ID}/random_forest_model"

        model = mlflow.sklearn.load_model(model_uri)

    except Exception as e:
        print("⚠️  API will start but predictions will fail until model is loaded")

    yield


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
