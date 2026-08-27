{{ config(
    materialized='incremental',
    unique_key=['TRADE_ID', 'VERSION', 'ETL_DATE', 'ROW_ID'],
    tags=['prepare_quality']
) }}

{%- set etl_date = var('etl_date', run_started_at.strftime('%Y-%m-%d')) -%}
{%- set source_dates = source_window_dates('trades', etl_date) -%}
{%- set late_arrival_date = source_dates[-1] -%}

{%- set approved_currencies = var('approved_currencies') -%}

with raw_trades as (

    select * from {{ ref('trades') }}
    where ETL_DATE between '{{ late_arrival_date }}' and '{{ etl_date }}'

),

parsed as (

    select
        ROW_ID,
        ETL_DATE,
        LOAD_TIMESTAMP,

        TRIM(TRADE_ID) as TRADE_ID,
        TRY_CAST(TRIM(VERSION) as NUMBER(10,0)) as VERSION,
        TRIM(COUNTERPARTY) as COUNTERPARTY,
        TRY_CAST(TRIM(NOTIONAL) as NUMBER(18,2)) as NOTIONAL,
        TRIM(CURRENCY) as CURRENCY,
        TRY_TO_DATE(TRIM(MATURITY_DATE)) as MATURITY_DATE,
        TRY_TO_DATE(TRIM(EXECUTION_DATE)) as EXECUTION_DATE,
        CURRENT_TIMESTAMP()::TIMESTAMP_NTZ as LAST_UPDATED_DATE,

        -- validity flags; preserve invalid indicators instead of masking them
        TRIM(TRADE_ID) is not null and TRIM(TRADE_ID) <> '' as IS_TRADE_ID_VALID,
        TRY_CAST(TRIM(VERSION) as NUMBER(10,0)) is not null and TRY_CAST(TRIM(VERSION) as NUMBER(10,0)) >= 0 as IS_VERSION_VALID,
        TRY_CAST(TRIM(NOTIONAL) as NUMBER(18,2)) is not null and TRY_CAST(TRIM(NOTIONAL) as NUMBER(18,2)) > 0 as IS_NOTIONAL_VALID,
        TRIM(CURRENCY) is not null and TRIM(CURRENCY) in ({{ approved_currencies | join(', ') }}) as IS_CURRENCY_VALID,
        TRY_TO_DATE(TRIM(MATURITY_DATE)) is not null as IS_MATURITY_VALID,
        TRY_TO_DATE(TRIM(MATURITY_DATE)) >= CURRENT_DATE() as IS_MATURITY_NOT_EXPIRED,
        TRY_TO_DATE(TRIM(EXECUTION_DATE)) is not null as IS_EXECUTION_VALID,
        (TRY_TO_DATE(TRIM(MATURITY_DATE)) is not null and TRY_TO_DATE(TRIM(EXECUTION_DATE)) is not null and TRY_TO_DATE(TRIM(MATURITY_DATE)) >= TRY_TO_DATE(TRIM(EXECUTION_DATE))) as IS_DATE_ORDER_VALID

    from raw_trades

),

deduplicated as (

    select
        *,
        row_number() over (
            partition by TRADE_ID, VERSION, ETL_DATE
            order by ROW_ID desc
        ) as rn
    from parsed

),

final as (

    select
        TRADE_ID,
        VERSION,
        COUNTERPARTY,
        NOTIONAL,
        CURRENCY,
        MATURITY_DATE,
        EXECUTION_DATE,
        ROW_ID,
        ETL_DATE,
        LOAD_TIMESTAMP,
        LAST_UPDATED_DATE,
        IS_TRADE_ID_VALID,
        IS_VERSION_VALID,
        IS_NOTIONAL_VALID,
        IS_CURRENCY_VALID,
        IS_MATURITY_VALID,
        IS_MATURITY_NOT_EXPIRED,
        IS_EXECUTION_VALID,
        IS_DATE_ORDER_VALID,
        IS_TRADE_ID_VALID
            and IS_VERSION_VALID
            and IS_NOTIONAL_VALID
            and IS_CURRENCY_VALID
            and IS_MATURITY_VALID
            and IS_MATURITY_NOT_EXPIRED
            and IS_EXECUTION_VALID
            and IS_DATE_ORDER_VALID as IS_VALID
    from deduplicated
    where rn = 1

)

select * from final
