{{ config(
    materialized='incremental',
    unique_key=['TRADE_ID', 'VERSION', 'ROW_ID', 'LOAD_TIMESTAMP'],
    incremental_strategy='merge',
    tags=['streaming', 'prepare_quality']
) }}

{%- set approved_currencies = var('approved_currencies') -%}

with raw_stream as (

    select * from {{ source('raw', 'trades_stream') }}
    {% if is_incremental() %}
    where LOAD_TIMESTAMP > COALESCE((select max(LOAD_TIMESTAMP) from {{ this }}), '2026-01-01'::TIMESTAMP_NTZ)
    {% endif %}

),

parsed as (

    select
        ROW_ID,
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

    from raw_stream

),

deduplicated as (

    select
        *,
        row_number() over (
            partition by TRADE_ID, VERSION
            order by LOAD_TIMESTAMP desc, ROW_ID desc
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
        {{ date_string('LOAD_TIMESTAMP') }} as ETL_DATE,
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
