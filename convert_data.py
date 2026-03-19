import pandas as pd
import os
from datetime import datetime, timedelta


csv_path = "data/train_transaction.csv"
parquet_path = "data/train_transaction.parquet"

df = pd.read_csv(csv_path, nrows=50000)

base_date = datetime.now() - timedelta(days=30)

df['event_timestamp'] = [base_date + timedelta(seconds=i*10) for i in range(len(df))]

df.to_parquet(parquet_path)