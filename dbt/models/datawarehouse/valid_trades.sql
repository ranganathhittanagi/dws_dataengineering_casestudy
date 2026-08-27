{{ config(
    materialized='incremental',
    unique_key='TRADE_ID',
    incremental_strategy='merge',
    post_hook="UPDATE {{ this }} SET TRADE_STATUS = 'EXPIRED' WHERE MATURITY_DATE < CURRENT_DATE() AND TRADE_STATUS != 'EXPIRED'",
    tags=['warehouse_candidate']
) }}

{%- set etl_date = var('etl_date', run_started_at.strftime('%Y-%m-%d')) -%}
{%- set source_dates = source_window_dates('trades', etl_date) -%}
{%- set late_arrival_date = source_dates[-1] -%}

with new_trades as (

    select * from {{ ref('stg_trades') }}
    where ETL_DATE between '{{ late_arrival_date }}' and '{{ etl_date }}'
        and IS_VALID

),

existing_trades as (

    select
        TRADE_ID,
        VERSION as CURRENT_VERSION
    from {{ source('datawarehouse', 'valid_trades') }}

),

candidates as (

    select
        s.TRADE_ID,
        s.VERSION,
        s.COUNTERPARTY,
        s.NOTIONAL,
        s.CURRENCY,
        s.MATURITY_DATE,
        s.EXECUTION_DATE,
        s.ETL_DATE,
        s.SOURCE_FILENAME,
        s.ROW_ID,
        row_number() over (
            partition by s.TRADE_ID
            order by s.VERSION desc, s.ETL_DATE desc
        ) as rn
    from new_trades s
    left join existing_trades e
        on s.TRADE_ID = e.TRADE_ID
    where e.TRADE_ID is null or s.VERSION >= e.CURRENT_VERSION

),

accepted as (

    select
        TRADE_ID,
        VERSION,
        COUNTERPARTY,
        NOTIONAL,
        CURRENCY,
        MATURITY_DATE,
        EXECUTION_DATE,
        case
            when MATURITY_DATE < CURRENT_DATE() then 'EXPIRED'
            else 'ACTIVE'
        end as TRADE_STATUS,
        ETL_DATE,
        SOURCE_FILENAME,
        ROW_ID,
        CURRENT_TIMESTAMP()::TIMESTAMP_NTZ as LAST_UPDATED_DATE
    from candidates
    where rn = 1

)

select * from accepted
