FROM apache/airflow:2.7.1-python3.10

USER airflow

# Install packages NOT in constraints (like feast) separately
RUN pip install --no-cache-dir --default-timeout=1000 \
    feast==0.31.1 \
    python-dotenv \
    psycopg2-binary \
    mlflow \
    scikit-learn \
    pandas \
    pyarrow

# Install packages that ARE in constraints using the constraints file
RUN pip install --no-cache-dir \
    --constraint "https://raw.githubusercontent.com/apache/airflow/constraints-2.7.1/constraints-3.10.txt" \
    redis
