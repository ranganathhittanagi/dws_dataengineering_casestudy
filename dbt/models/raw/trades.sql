{%- set etl_date = var('etl_date', run_started_at.strftime('%Y-%m-%d')) -%}
{%- set late_arrival_date = (modules.datetime.datetime.strptime(etl_date, '%Y-%m-%d') - modules.datetime.timedelta(days=1)).strftime('%Y-%m-%d') -%}

{{ config(
    materialized='copy_into_table',
    stage='@RAW_DB.RAW_SCHEMA.RAW_DATA_STAGE',
    file_format='RAW_DB.RAW_SCHEMA.CSV_FORMAT',
    meta={"copy_options": "ON_ERROR = 'CONTINUE' FORCE = FALSE PURGE = FALSE PATTERN = '.*trades_(" ~ late_arrival_date ~ "|" ~ etl_date ~ ").*'"},
    tags=['ingest']
) }}

select
    $1::VARCHAR  as TRADE_ID,
    $2::VARCHAR  as VERSION,
    $3::VARCHAR  as COUNTERPARTY,
    $4::VARCHAR  as NOTIONAL,
    $5::VARCHAR  as CURRENCY,
    $6::VARCHAR  as MATURITY_DATE,
    $7::VARCHAR  as EXECUTION_DATE,
    METADATA$FILENAME::VARCHAR as SOURCE_FILENAME,
    METADATA$FILE_ROW_NUMBER::VARCHAR as SOURCE_ROW_NUMBER,
    '{{ etl_date }}'::VARCHAR as ETL_DATE,
    '{{ invocation_id }}'::VARCHAR as DBT_INVOCATION_ID,
    CURRENT_TIMESTAMP()::VARCHAR as LOAD_TIMESTAMP
from @RAW_DB.RAW_SCHEMA.RAW_DATA_STAGE
