{%- set etl_date = var('etl_date', run_started_at.strftime('%Y-%m-%d')) -%}

{{ config(
    materialized='copy_into_table',
    stage='@RAW_DB.RAW_SCHEMA.RAW_DATA_STAGE',
    file_format='RAW_DB.RAW_SCHEMA.CSV_FORMAT',
    copy_options="ON_ERROR = 'CONTINUE' FORCE = FALSE PURGE = FALSE PATTERN = '.*trades_" ~ etl_date ~ ".*'"
) }}

select
    $1::VARCHAR  as TRADE_ID,
    $2::VARCHAR  as VERSION,
    $3::VARCHAR  as COUNTERPARTY,
    $4::VARCHAR  as NOTIONAL,
    $5::VARCHAR  as CURRENCY,
    $6::VARCHAR  as MATURITY_DATE,
    $7::VARCHAR  as EXECUTION_DATE,
    '{{ etl_date }}'::DATE as ETL_DATE
from @RAW_DB.RAW_SCHEMA.RAW_DATA_STAGE
