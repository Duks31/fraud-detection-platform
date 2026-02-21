### Defining Transformation Data

from datetime import timedelta
from feast import Entity, FeatureView, Field, FileSource, ValueType
from feast.types import Float32, Int64

transaction = Entity(
    name="transaction", join_keys=["TransactionID"], value_type=ValueType.INT64
)

transaction_source = FileSource(
    name="transaction_source",
    path="../data/train_transaction_clean.parquet",
    timestamp_field="event_timestamp",
)

transaction_stats = FeatureView(
    name="transaction_stats",
    entities=[transaction],
    ttl=timedelta(days=1),
    schema=[
        Field(name="TransactionAmt", dtype=Float32),
        Field(name="card1", dtype=Int64),
        Field(name="card2", dtype=Int64),
        Field(name="addr1", dtype=Float32),
    ],
    online=True,
    source=transaction_source,
)
