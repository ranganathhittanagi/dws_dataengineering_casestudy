{{ config(
    materialized='incremental',
    unique_key='TRADE_ID',
    incremental_strategy='merge',
    post_hook="UPDATE {{ this }} SET TRADE_STATUS = 'EXPIRED' WHERE MATURITY_DATE < CURRENT_DATE() AND TRADE_STATUS != 'EXPIRED'"
) }}

{%- set etl_date = var('etl_date', run_started_at.strftime('%Y-%m-%d')) -%}
{%- set late_arrival_date = (modules.datetime.datetime.strptime(etl_date, '%Y-%m-%d') - modules.datetime.timedelta(days=1)).strftime('%Y-%m-%d') -%}

with new_trades as (

    select * from {{ ref('stg_trades') }}
    where ETL_DATE between '{{ late_arrival_date }}' and '{{ etl_date }}'

),

{% if is_incremental() %}
existing_trades as (

    select
        TRADE_ID,
        VERSION as CURRENT_VERSION
    from {{ this }}

),
{% endif %}

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
        row_number() over (
            partition by s.TRADE_ID
            order by s.VERSION desc
        ) as rn
    from new_trades s
    {% if is_incremental() %}
    left join existing_trades e
        on s.TRADE_ID = e.TRADE_ID
    {% endif %}
    where
        s.MATURITY_DATE is not null
        and s.MATURITY_DATE >= s.EXECUTION_DATE
        {% if is_incremental() %}
        and (e.TRADE_ID is null or s.VERSION >= e.CURRENT_VERSION)
        {% endif %}

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
        CURRENT_TIMESTAMP()::TIMESTAMP_NTZ as LAST_UPDATED_DATE
    from candidates
    where rn = 1

)

select * from accepted
