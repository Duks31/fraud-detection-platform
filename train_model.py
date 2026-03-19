import os

import mlflow
import mlflow.sklearn
import pandas as pd
from feast import FeatureStore
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import recall_score, precision_score
from dotenv import load_dotenv

dotenv_path = os.path.join("infrastructure", ".env")
load_dotenv(dotenv_path)

MINIO_ROOT_USER = os.getenv("MINIO_ROOT_USER", "default_user")
MINIO_ROOT_PASSWORD = os.getenv("MINIO_ROOT_PASSWORD", "default_password")

os.environ["MLFLOW_S3_ENDPOINT_URL"] = "http://s3:9000"
os.environ["AWS_ACCESS_KEY_ID"] = MINIO_ROOT_USER
os.environ["AWS_SECRET_ACCESS_KEY"] = MINIO_ROOT_PASSWORD
os.environ["MLFLOW_S3_IGNORE_TLS"] = "true"

store = FeatureStore(repo_path="feature_store")

entity_df = pd.read_parquet(
    "data/train_transaction_clean.parquet",
    columns=["TransactionID", "event_timestamp", "isFraud"],
)

training_df = store.get_historical_features(
    entity_df=entity_df,
    features=[
        "transaction_stats:TransactionAmt",
        "transaction_stats:card1",
        "transaction_stats:card2",
        "transaction_stats:addr1",
    ],
).to_df()

X = training_df.drop(columns=["isFraud", "TransactionID", "event_timestamp"])
y = training_df["isFraud"].fillna(0)

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42
)

mlflow.set_tracking_uri("http://sentinel_mlflow:5000")
mlflow.set_experiment("Fraud detection")

with mlflow.start_run():
    params = {"n_estimators": 100, "max_depth": 10, "random_state": 42}
    mlflow.log_params(params)

    model = RandomForestClassifier(n_estimators=100, random_state=42)
    model.fit(X_train, y_train)

    y_pred = model.predict(X_test)
    acc = float(model.score(X_test, y_test))
    recall = float(recall_score(y_test, y_pred))
    precision = float(precision_score(y_test, y_pred))

    mlflow.log_metric("accuracy", acc)
    mlflow.log_metric("recall", recall)
    mlflow.log_metric("precision", precision)

    # loggin the model to MinIO
    # mlflow.sklearn.log_model(
    #     sk_model=model,
    #     artifact_path="random_forest_model",
    #     serialization_format=mlflow.sklearn.SERIALIZATION_FORMAT_PICKLE,
    # )

    mlflow.sklearn.log_model(model, artifact_path="random_forest_model")
