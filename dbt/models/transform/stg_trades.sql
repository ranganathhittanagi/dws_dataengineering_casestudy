{{ config(
    materialized='incremental',
    unique_key=['TRADE_ID', 'VERSION']
) }}

{%- set etl_date = var('etl_date', run_started_at.strftime('%Y-%m-%d')) -%}
{%- set late_arrival_date = (modules.datetime.datetime.strptime(etl_date, '%Y-%m-%d') - modules.datetime.timedelta(days=1)).strftime('%Y-%m-%d') -%}

with raw_trades as (

    select * from {{ ref('trades') }}
    where ETL_DATE between '{{ late_arrival_date }}' and '{{ etl_date }}'

),

cleaned as (

    select
        COALESCE(NULLIF(TRIM(TRADE_ID), ''), 'UNKNOWN')            as TRADE_ID,
        COALESCE(TRY_CAST(TRIM(VERSION) as NUMBER(10,0)), 0)       as VERSION,
        COALESCE(NULLIF(TRIM(COUNTERPARTY), ''), 'UNKNOWN')        as COUNTERPARTY,
        COALESCE(TRY_CAST(TRIM(NOTIONAL) as NUMBER(18,2)), 0.00)   as NOTIONAL,
        COALESCE(NULLIF(TRIM(CURRENCY), ''), 'USD')                as CURRENCY,
        TRY_CAST(TRIM(MATURITY_DATE) as DATE)                      as MATURITY_DATE,
        COALESCE(TRY_CAST(TRIM(EXECUTION_DATE) as DATE), CURRENT_DATE()) as EXECUTION_DATE,
        ETL_DATE,
        CURRENT_TIMESTAMP()::TIMESTAMP_NTZ                         as LAST_UPDATED_DATE
    from raw_trades

)

select * from cleaned
