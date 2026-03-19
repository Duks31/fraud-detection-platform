import pandas as pd

df = pd.read_parquet('../data/train_transaction.parquet')

df['card2'] = df['card2'].fillna(-1).astype('int64')
df['addr1'] = df['addr1'].fillna(-1).astype('float32')

df.to_parquet('../data/train_transaction_clean.parquet', index=False)