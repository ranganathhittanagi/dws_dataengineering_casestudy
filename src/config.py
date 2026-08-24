"""Runtime configuration.

Non-sensitive Snowflake settings (account, user, role, warehouse) come from the
environment. The RSA key pair lives in AWS SSM Parameter Store as SecureString
parameters, so no key material sits in the repo or on the container filesystem.

AWS credentials are resolved by boto3's default chain: an AWS_PROFILE locally, or an
attached IAM role once the pipeline runs on AWS compute.
"""
import os
from functools import lru_cache

import boto3
from cryptography.hazmat.primitives import serialization
import snowflake.connector


AWS_REGION = os.getenv("AWS_REGION", "ap-south-1")
SNOWFLAKE_PARAM_PATH = os.getenv(
    "SNOWFLAKE_PARAM_PATH", "/dws/snowflake/dws-service-user"
).rstrip("/")

RAW_DATABASE = os.getenv("SNOWFLAKE_DATABASE_RAW_DB", "RAW_DB")
RAW_SCHEMA = os.getenv("SNOWFLAKE_DATABASE_RAW_SCHEMA", "RAW_SCHEMA")


@lru_cache(maxsize=None)
def get_parameter(name: str) -> str:
    """Return a decrypted SSM parameter from under the Snowflake parameter path.

    Decryption requires kms:Decrypt on the key backing the parameter, in addition
    to ssm:GetParameter.
    """
    client = boto3.client("ssm", region_name=AWS_REGION)
    response = client.get_parameter(
        Name=f"{SNOWFLAKE_PARAM_PATH}/{name}", WithDecryption=True
    )
    return response["Parameter"]["Value"]


def private_key_pem() -> str:
    """Return the service user's private key as PEM text."""
    return get_parameter("private_key")


def private_key_der() -> bytes:
    """Return the private key as DER bytes, the form the Snowflake connector expects."""
    private_key = serialization.load_pem_private_key(
        private_key_pem().encode(), password=None
    )
    return private_key.private_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )


def snowflake_connection_params() -> dict:
    """Return Snowflake connection parameters."""
    return {
        "account": os.environ["SNOWFLAKE_ACCOUNT"],
        "user": os.environ["SNOWFLAKE_USER"],
        "role": os.environ["SNOWFLAKE_ROLE"],
        "warehouse": os.environ["SNOWFLAKE_WAREHOUSE"],
        "database": RAW_DATABASE,
        "schema": RAW_SCHEMA,
        "private_key": private_key_der(),
    }


def dbt_environment() -> dict:
    """Return the extra env vars dbt needs, so profiles.yml never reads a key file."""
    return {"SNOWFLAKE_PRIVATE_KEY": private_key_pem()}


def get_snowflake_connection():
    """Open and return a Snowflake connection using the configured key pair."""
    return snowflake.connector.connect(**snowflake_connection_params())
