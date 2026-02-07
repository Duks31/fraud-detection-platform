import pandas as pd
import os
from datetime import datetime, timedelta


csv_path = "data/train_transaction.csv"
parquet_path = "data/train_transaction.parquet"

if not os.path.exists(csv_path):
    print(f"❌ ERROR: Can't find {csv_path}")
    print("Please check where you put the CSV file!")
    exit()

print(f"⏳ Loading top 50,000 rows from {csv_path}...")
df = pd.read_csv(csv_path, nrows=50000)

print("🕒 Adding fake timestamps...")
base_date = datetime.now() - timedelta(days=30)

df['event_timestamp'] = [base_date + timedelta(seconds=i*10) for i in range(len(df))]

print(f"💾 Saving to {parquet_path}...")
df.to_parquet(parquet_path)
print("✅ Success! Data is ready for Feast.")