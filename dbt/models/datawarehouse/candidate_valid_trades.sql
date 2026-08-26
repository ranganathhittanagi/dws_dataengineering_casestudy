{{ config(
    materialized='table',
    tags=['warehouse_candidate']
) }}

{%- set etl_date = var('etl_date', run_started_at.strftime('%Y-%m-%d')) -%}
{%- set late_arrival_date = (modules.datetime.datetime.strptime(etl_date, '%Y-%m-%d') - modules.datetime.timedelta(days=1)).strftime('%Y-%m-%d') -%}

with new_trades as (

    select * from {{ ref('stg_trades') }}
    where ETL_DATE between '{{ late_arrival_date }}' and '{{ etl_date }}'
        and IS_VALID

),

existing_trades as (

    select
        TRADE_ID,
        VERSION as CURRENT_VERSION
    from {{ ref('valid_trades') }}

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
        s.SOURCE_ROW_NUMBER,
        s.DBT_INVOCATION_ID,
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
        SOURCE_ROW_NUMBER,
        DBT_INVOCATION_ID,
        CURRENT_TIMESTAMP()::TIMESTAMP_NTZ as LAST_UPDATED_DATE
    from candidates
    where rn = 1

)

select * from accepted
