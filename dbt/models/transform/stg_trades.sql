{{ config(
    materialized='incremental',
    unique_key=['TRADE_ID', 'VERSION', 'ETL_DATE', 'SOURCE_ROW_NUMBER'],
    tags=['prepare_quality']
) }}

{%- set etl_date = var('etl_date', run_started_at.strftime('%Y-%m-%d')) -%}
{%- set late_arrival_date = (modules.datetime.datetime.strptime(etl_date, '%Y-%m-%d') - modules.datetime.timedelta(days=1)).strftime('%Y-%m-%d') -%}

{%- set approved_currencies = ["'USD'","'EUR'","'GBP'","'JPY'","'AUD'","'CAD'","'CHF'"] -%}

with raw_trades as (

    select * from {{ ref('trades') }}
    where ETL_DATE between '{{ late_arrival_date }}' and '{{ etl_date }}'

),

parsed as (

    select
        TRADE_ID as RAW_TRADE_ID,
        VERSION as RAW_VERSION,
        COUNTERPARTY as RAW_COUNTERPARTY,
        NOTIONAL as RAW_NOTIONAL,
        CURRENCY as RAW_CURRENCY,
        MATURITY_DATE as RAW_MATURITY_DATE,
        EXECUTION_DATE as RAW_EXECUTION_DATE,
        SOURCE_FILENAME,
        SOURCE_ROW_NUMBER,
        ETL_DATE,
        DBT_INVOCATION_ID,
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
        TRY_TO_DATE(TRIM(EXECUTION_DATE)) is not null as IS_EXECUTION_VALID,
        (TRY_TO_DATE(TRIM(MATURITY_DATE)) is not null and TRY_TO_DATE(TRIM(EXECUTION_DATE)) is not null and TRY_TO_DATE(TRIM(MATURITY_DATE)) >= TRY_TO_DATE(TRIM(EXECUTION_DATE))) as IS_DATE_ORDER_VALID

    from raw_trades

),

deduplicated as (

    select
        *,
        row_number() over (
            partition by TRADE_ID, VERSION, ETL_DATE
            order by SOURCE_ROW_NUMBER desc
        ) as rn
    from parsed

),

final as (

    select
        RAW_TRADE_ID,
        RAW_VERSION,
        RAW_COUNTERPARTY,
        RAW_NOTIONAL,
        RAW_CURRENCY,
        RAW_MATURITY_DATE,
        RAW_EXECUTION_DATE,
        TRADE_ID,
        VERSION,
        COUNTERPARTY,
        NOTIONAL,
        CURRENCY,
        MATURITY_DATE,
        EXECUTION_DATE,
        SOURCE_FILENAME,
        SOURCE_ROW_NUMBER,
        ETL_DATE,
        DBT_INVOCATION_ID,
        LOAD_TIMESTAMP,
        LAST_UPDATED_DATE,
        IS_TRADE_ID_VALID,
        IS_VERSION_VALID,
        IS_NOTIONAL_VALID,
        IS_CURRENCY_VALID,
        IS_MATURITY_VALID,
        IS_EXECUTION_VALID,
        IS_DATE_ORDER_VALID,
        IS_TRADE_ID_VALID
            and IS_VERSION_VALID
            and IS_NOTIONAL_VALID
            and IS_CURRENCY_VALID
            and IS_MATURITY_VALID
            and IS_EXECUTION_VALID
            and IS_DATE_ORDER_VALID as IS_VALID
    from deduplicated
    where rn = 1

)

select * from final
