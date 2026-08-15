"""Upload generated trade files to the Snowflake internal stage."""
import os
from pathlib import Path

import snowflake.connector

from src.config import RAW_DATABASE, RAW_SCHEMA, snowflake_connection_params


def stage_name() -> str:
    """Return the fully-qualified internal stage used for raw trade files."""
    return f"{RAW_DATABASE}.{RAW_SCHEMA}.RAW_DATA_STAGE"


def upload_files(data_dir: str) -> None:
    """PUT all CSV trade files from `data_dir` into the raw Snowflake stage."""
    data_path = Path(data_dir).resolve()
    files = sorted(data_path.glob("trades_*.csv"))
    if not files:
        print(f"No trades_*.csv files found in {data_dir}")
        return

    conn = snowflake.connector.connect(**snowflake_connection_params())
    try:
        cursor = conn.cursor()
        for file_path in files:
            # PUT expects an absolute file:// URI and uploads to the named stage.
            put_cmd = (
                f"PUT file://{file_path} @{stage_name()} "
                "AUTO_COMPRESS=TRUE OVERWRITE=FALSE"
            )
            cursor.execute(put_cmd)
            print(f"Uploaded {file_path.name} to @{stage_name()}")
    finally:
        conn.close()


if __name__ == "__main__":
    data_dir = os.getenv("TRADE_DATA_DIR", "data/raw")
    upload_files(data_dir)
