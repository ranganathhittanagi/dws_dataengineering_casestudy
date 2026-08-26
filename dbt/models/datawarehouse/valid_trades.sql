{{ config(
    materialized='incremental',
    unique_key='TRADE_ID',
    incremental_strategy='merge',
    post_hook="UPDATE {{ this }} SET TRADE_STATUS = 'EXPIRED' WHERE MATURITY_DATE < CURRENT_DATE() AND TRADE_STATUS != 'EXPIRED'",
    tags=['publish']
) }}

select
    TRADE_ID,
    VERSION,
    COUNTERPARTY,
    NOTIONAL,
    CURRENCY,
    MATURITY_DATE,
    EXECUTION_DATE,
    TRADE_STATUS,
    ETL_DATE,
    SOURCE_FILENAME,
    SOURCE_ROW_NUMBER,
    DBT_INVOCATION_ID,
    LAST_UPDATED_DATE
from {{ ref('candidate_valid_trades') }}
