{{ config(
    materialized='incremental',
    unique_key=['TRADE_ID', 'VERSION']
) }}

{%- set etl_date = var('etl_date', run_started_at.strftime('%Y-%m-%d')) -%}
{%- set late_arrival_date = (modules.datetime.datetime.strptime(etl_date, '%Y-%m-%d') - modules.datetime.timedelta(days=1)).strftime('%Y-%m-%d') -%}

with staged as (

    select * from {{ ref('stg_trades') }}
    where ETL_DATE between '{{ late_arrival_date }}' and '{{ etl_date }}'

),

existing_valid as (

    select
        TRADE_ID,
        MAX(VERSION) as MAX_VERSION
    from {{ ref('valid_trades') }}
    group by TRADE_ID

),

rejected as (

    select
        s.TRADE_ID,
        s.VERSION,
        s.COUNTERPARTY,
        s.NOTIONAL,
        s.CURRENCY,
        s.MATURITY_DATE,
        s.EXECUTION_DATE,
        s.ETL_DATE,
        case
            when s.MATURITY_DATE is null
                then 'INVALID_MATURITY_DATE: NULL or unparseable date'
            when s.MATURITY_DATE < s.EXECUTION_DATE
                then 'MATURITY_BEFORE_EXECUTION: maturity_date (' || s.MATURITY_DATE::VARCHAR || ') < execution_date (' || s.EXECUTION_DATE::VARCHAR || ')'
            when e.TRADE_ID is not null and s.VERSION < e.MAX_VERSION
                then 'STALE_VERSION: incoming version (' || s.VERSION::VARCHAR || ') < existing version (' || e.MAX_VERSION::VARCHAR || ')'
            else 'UNKNOWN_REJECTION'
        end as REJECTION_REASON,
        CURRENT_TIMESTAMP()::TIMESTAMP_NTZ as LAST_UPDATED_DATE
    from staged s
    left join existing_valid e
        on s.TRADE_ID = e.TRADE_ID
    where
        s.MATURITY_DATE is null
        or s.MATURITY_DATE < s.EXECUTION_DATE
        or (e.TRADE_ID is not null and s.VERSION < e.MAX_VERSION)

)

select * from rejected
