SELECT 'CREATE DATABASE feast_registry'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'feast_registry')\gexec

SELECT 'CREATE DATABASE mlflow_db' 
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'mlflow_db')\gexec

SELECT 'CREATE DATABASE airflow_db' 
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'airflow_db')\gexec

\c feast_registry
GRANT ALL PRIVILEGES ON DATABASE feast_registry TO sentinel_user;
GRANT ALL PRIVILEGES ON DATABASE mlflow_db TO sentinel_user;
GRANT ALL PRIVILEGES ON DATABASE airflow_db TO sentinel_user;