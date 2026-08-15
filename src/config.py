import os
from pathlib import Path

from cryptography.hazmat.primitives import serialization
import snowflake.connector


RAW_DATABASE = os.getenv("SNOWFLAKE_DATABASE_RAW_DB", "RAW_DB")
RAW_SCHEMA = os.getenv("SNOWFLAKE_DATABASE_RAW_SCHEMA", "RAW_SCHEMA")


def snowflake_connection_params():
    """Return a dict of Snowflake connection parameters from environment variables."""
    return {
        "account": os.environ["SNOWFLAKE_ACCOUNT"],
        "user": os.environ["SNOWFLAKE_USER"],
        "role": os.environ["SNOWFLAKE_ROLE"],
        "warehouse": os.environ["SNOWFLAKE_WAREHOUSE"],
        "database": RAW_DATABASE,
        "schema": RAW_SCHEMA,
        "private_key": _load_private_key(),
    }


def _load_private_key():
    """Load the Snowflake private key file and return DER-encoded key bytes."""
    key_path = Path(os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"])
    pem_data = key_path.read_bytes()
    private_key = serialization.load_pem_private_key(pem_data, password=None)
    return private_key.private_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )


def get_snowflake_connection():
    """Open and return a Snowflake connection using the configured key pair."""
    return snowflake.connector.connect(**snowflake_connection_params())
