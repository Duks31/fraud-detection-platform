import boto3
from botocore.exceptions import ClientError
import os
from dotenv import load_dotenv

load_dotenv('infrastructure/.env')

s3_client = boto3.client(
    's3',
    endpoint_url='http://localhost:9000',
    aws_access_key_id=os.getenv('MINIO_ROOT_USER'),
    aws_secret_access_key=os.getenv('MINIO_ROOT_PASSWORD'),
    region_name='us-east-1'
)

bucket_name = 'mlflow'

try:
    s3_client.head_bucket(Bucket=bucket_name)
    print(f'Bucket "{bucket_name}" already exists')
except ClientError:
    try:
        s3_client.create_bucket(Bucket=bucket_name)
        print(f'Created bucket "{bucket_name}"')
    except Exception as e:
        print(f'Failed to create bucket: {e}')