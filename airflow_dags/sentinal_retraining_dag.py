from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime, timedelta
import subprocess
import os
from dotenv import load_dotenv

load_dotenv("/app/.env")

os.environ["MLFLOW_TRACKING_URI"] = "http://sentinel_mlflow:5000"
os.environ["MLFLOW_S3_ENDPOINT_URL"] = "http://sentinel_minio:9000"
os.environ["AWS_ACCESS_KEY_ID"] = os.getenv("MINIO_ROOT_USER", "minio_admin")
os.environ["AWS_SECRET_ACCESS_KEY"] = os.getenv(
    "MINIO_ROOT_PASSWORD", "minio_secure_pass"
)
os.environ["MLFLOW_S3_IGNORE_TLS"] = "true"

default_args = {
    "owner": "sentinel_admin",
    "depends_on_past": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
}


def apply_feast_definitions():
    """Apply Feast feature definitions"""
    print("=" * 60)
    print("Applying Feast feature definitions...")
    print("=" * 60)

    result = subprocess.run(
        ["feast", "apply"],
        cwd="/app/feature_store",
        capture_output=True,
        text=True,
        check=False,
        env=os.environ.copy(),
    )

    if result.returncode != 0:
        print(f"STDOUT: {result.stdout}")
        print(f"STDERR: {result.stderr}")
        raise subprocess.CalledProcessError(result.returncode, result.args)

    print(f"SUCCESS: {result.stdout}")


def run_feast_materialize():
    """Syncs features to Redis - handles both initial and incremental loads"""

    print("=" * 60)
    print("Starting feature materialization...")
    print("=" * 60)

    import redis

    # Check if Redis already has data
    try:
        r = redis.Redis(host="sentinel_redis", port=6379, decode_responses=True)
        key_count = r.dbsize()
        print(f"Current Redis key count: {key_count}")
    except Exception as e:
        print(f"Warning: Could not check Redis: {e}")
        key_count = 0

    # If Redis is empty, do full materialization
    # Otherwise, do incremental
    if key_count == 0:
        print("Redis is empty - performing FULL materialization...")
        result = subprocess.run(
            ["feast", "materialize", "2026-01-08T00:00:00", "2026-01-14T23:59:59"],
            cwd="/app/feature_store",
            capture_output=True,
            text=True,
            check=False,
            env=os.environ.copy(),
        )
    else:
        print("Redis has data - performing INCREMENTAL materialization...")
        result = subprocess.run(
            ["feast", "materialize-incremental", datetime.now().isoformat()],
            cwd="/app/feature_store",
            capture_output=True,
            text=True,
            check=False,
            env=os.environ.copy(),
        )

    # Print output
    print(f"STDOUT: {result.stdout}")
    if result.stderr:
        print(f"STDERR: {result.stderr}")

    # Check exit code - but be lenient with warnings
    if result.returncode != 0:
        # Check if it's just a "no new data" scenario
        if "0it" in result.stdout or "Materializing 0 feature views" in result.stdout:
            print("No new data to materialize - this is OK!")
            return
        else:
            # Real error
            raise subprocess.CalledProcessError(result.returncode, result.args)

    print(" Materialization completed successfully")


def run_mlflow_training():
    """Triggers the model training script and logs to MLflow"""

    print("=" * 60)
    print("Starting model training...")
    print("=" * 60)

    result = subprocess.run(
        ["python", "train_model.py"],
        cwd="/app",
        capture_output=True,
        text=True,
        check=False,
        env=os.environ.copy(),
    )

    print(f"STDOUT: {result.stdout}")
    if result.stderr:
        print(f"STDERR: {result.stderr}")

    if result.returncode != 0:
        raise subprocess.CalledProcessError(result.returncode, result.args)

    print(" Training completed successfully")


with DAG(
    "sentinel_mlops_pipeline",
    default_args=default_args,
    description="Automates feature syncing and model retraining",
    schedule_interval="@daily",
    start_date=datetime(2026, 1, 1),
    catchup=False,
    tags=["sentinel", "fraud_detection"],
) as dag:

    apply_features = PythonOperator(
        task_id="apply_feature_definitions", python_callable=apply_feast_definitions
    )

    sync_features = PythonOperator(
        task_id="sync_features_to_redis", python_callable=run_feast_materialize
    )

    train_model = PythonOperator(
        task_id="train_and_log_model", python_callable=run_mlflow_training
    )

    apply_features >> sync_features >> train_model
