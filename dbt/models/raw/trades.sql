{%- set etl_date = var('etl_date', run_started_at.strftime('%Y-%m-%d')) -%}
{%- set source_dates = source_window_dates('trades', etl_date) -%}
{%- set file_pattern = '.*trades_(' ~ source_dates | join('|') ~ ').*' -%}

{{ config(
    materialized='copy_into_table',
    meta={
        "stage": "@RAW_DB.RAW_SCHEMA.RAW_DATA_STAGE",
        "file_format": "RAW_DB.RAW_SCHEMA.CSV_FORMAT",
        "header_file_format": "RAW_DB.RAW_SCHEMA.CSV_HEADER_FORMAT",
        "copy_options": "ON_ERROR = 'ABORT_STATEMENT' FORCE = FALSE PURGE = FALSE",
        "pattern": file_pattern,
        "known_columns": ['TRADE_ID', 'VERSION', 'COUNTERPARTY', 'NOTIONAL', 'CURRENCY', 'MATURITY_DATE', 'EXECUTION_DATE']
    },
    tags=['ingest']
) }}

select 1
