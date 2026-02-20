import os

import mlflow
import mlflow.sklearn
import pandas as pd
from feast import FeatureStore
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import recall_score, precision_score

os.environ['MLFLOW_S3_ENDPOINT_URL'] = "http://localhost:9000"
os.environ['AWS_ACCESS_KEY_ID'] = "minio_admin"
os.environ['AWS_SECRET_ACCESS_KEY'] = "minio_secure_pass"
os.environ['MLFLOW_S3_IGNORE_TLS'] = "true"

store = FeatureStore(repo_path="feature_store")

print("Fetching features from the Feast...")

entity_df = pd.read_parquet("data/train_transaction.parquet", columns=["TransactionID", "event_timestamp", "isFraud"])

training_df = store.get_historical_features(
    entity_df=entity_df,
    features=[
        "transaction_stats:TransactionAmt",
        "transaction_stats:card1",
        "transaction_stats:card2",
        "transaction_stats:addr1",
    ],
).to_df()

print(training_df.head())

X = training_df.drop(columns=["isFraud", "TransactionID", "event_timestamp"])
y = training_df["isFraud"].fillna(0)

X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

mlflow.set_tracking_uri("http://localhost:5000")
mlflow.set_experiment("Fraud detection")

with mlflow.start_run():
    params = {"n_estimators": 100, "max_depth":10, "random_state": 42}
    mlflow.log_params(params)

    model = RandomForestClassifier(n_estimators=100, random_state=42)
    model.fit(X_train, y_train)

    y_pred = model.predict(X_test)
    acc = model.score(X_test, y_test)
    recall = recall_score(y_test, y_pred)
    precision = precision_score(y_test, y_pred)

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

    print(f"Model trained with accuracy: {acc}, recall: {recall}, precision: {precision}")