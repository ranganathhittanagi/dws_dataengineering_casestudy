{{ config(
    materialized='incremental',
    unique_key=['SOURCE_TYPE', 'ROW_ID', 'RULE_ID', 'ETL_DATE'],
    tags=['prepare_quality']
) }}

{%- set etl_date = var('etl_date', run_started_at.strftime('%Y-%m-%d')) -%}
{%- set source_dates = source_window_dates('trades', etl_date) -%}
{%- set late_arrival_date = source_dates[-1] -%}

with staged as (

    select
        'BATCH' as SOURCE_TYPE,
        TRADE_ID,
        VERSION,
        COUNTERPARTY,
        NOTIONAL,
        CURRENCY,
        MATURITY_DATE,
        EXECUTION_DATE,
        ETL_DATE,
        ROW_ID,
        LAST_UPDATED_DATE,
        IS_TRADE_ID_VALID,
        IS_VERSION_VALID,
        IS_NOTIONAL_VALID,
        IS_CURRENCY_VALID,
        IS_MATURITY_VALID,
        IS_MATURITY_NOT_EXPIRED,
        IS_EXECUTION_VALID,
        IS_DATE_ORDER_VALID
    from {{ ref('stg_trades') }}
    where ETL_DATE between '{{ late_arrival_date }}' and '{{ etl_date }}'

    union all

    select
        'STREAM' as SOURCE_TYPE,
        TRADE_ID,
        VERSION,
        COUNTERPARTY,
        NOTIONAL,
        CURRENCY,
        MATURITY_DATE,
        EXECUTION_DATE,
        ETL_DATE,
        ROW_ID,
        LAST_UPDATED_DATE,
        IS_TRADE_ID_VALID,
        IS_VERSION_VALID,
        IS_NOTIONAL_VALID,
        IS_CURRENCY_VALID,
        IS_MATURITY_VALID,
        IS_MATURITY_NOT_EXPIRED,
        IS_EXECUTION_VALID,
        IS_DATE_ORDER_VALID
    from {{ ref('stg_trades_stream') }}
    where ETL_DATE between '{{ late_arrival_date }}' and '{{ etl_date }}'

),

existing_valid as (

    select
        TRADE_ID,
        MAX(VERSION) as MAX_VERSION
    from {{ source('datawarehouse', 'valid_trades') }}
    group by TRADE_ID

),

invalid_trade_id as (
    select
        {{ rejection_base_columns(
            'RULE_TRN_001',
            'TRADE_ID missing or empty',
            'Trade ID must be a non-empty string after trim'
        ) }}
    from staged
    where not IS_TRADE_ID_VALID
),

invalid_version as (
    select
        {{ rejection_base_columns(
            'RULE_TRN_002',
            'VERSION unparseable or negative',
            'VERSION must parse as a non-negative integer'
        ) }}
    from staged
    where not IS_VERSION_VALID
),

invalid_notional as (
    select
        {{ rejection_base_columns(
            'RULE_TRN_003',
            'NOTIONAL unparseable or not positive',
            'NOTIONAL must parse as a positive number'
        ) }}
    from staged
    where not IS_NOTIONAL_VALID
),

invalid_currency as (
    select
        {{ rejection_base_columns(
            'RULE_TRN_004',
            'CURRENCY not in approved domain',
            'CURRENCY must belong to the accepted ISO domain'
        ) }}
    from staged
    where not IS_CURRENCY_VALID
),

invalid_maturity as (
    select
        {{ rejection_base_columns(
            'RULE_TRN_005',
            'MATURITY_DATE unparseable',
            'MATURITY_DATE must parse as a valid date'
        ) }}
    from staged
    where not IS_MATURITY_VALID
),

invalid_execution as (
    select
        {{ rejection_base_columns(
            'RULE_TRN_006',
            'EXECUTION_DATE unparseable',
            'EXECUTION_DATE must parse as a valid date'
        ) }}
    from staged
    where not IS_EXECUTION_VALID
),

maturity_before_execution as (
    select
        'RULE_TRN_007' as RULE_ID,
        'MATURITY_DATE before EXECUTION_DATE' as RULE_NAME,
        SOURCE_TYPE,
        'MATURITY_DATE (' || MATURITY_DATE::VARCHAR || ') is earlier than EXECUTION_DATE (' || EXECUTION_DATE::VARCHAR || ')' as REJECTION_REASON,
        TRADE_ID,
        VERSION,
        COUNTERPARTY,
        NOTIONAL,
        CURRENCY,
        MATURITY_DATE,
        EXECUTION_DATE,
        ETL_DATE,
        ROW_ID,
        CURRENT_TIMESTAMP()::TIMESTAMP_NTZ as LAST_UPDATED_DATE
    from staged
    where IS_MATURITY_VALID and IS_EXECUTION_VALID and MATURITY_DATE < EXECUTION_DATE
),

expired_maturity as (
    select
        {{ rejection_base_columns(
            'RULE_TRN_008',
            'MATURITY_DATE in the past',
            'MATURITY_DATE must be today or in the future'
        ) }}
    from staged
    where IS_MATURITY_VALID and not IS_MATURITY_NOT_EXPIRED
),

stale_version as (
    select
        'RULE_WH_002' as RULE_ID,
        'VERSION lower than published' as RULE_NAME,
        s.SOURCE_TYPE,
        'Incoming version (' || s.VERSION::VARCHAR || ') is lower than published version (' || e.MAX_VERSION::VARCHAR || ')' as REJECTION_REASON,
        s.TRADE_ID,
        s.VERSION,
        s.COUNTERPARTY,
        s.NOTIONAL,
        s.CURRENCY,
        s.MATURITY_DATE,
        s.EXECUTION_DATE,
        s.ETL_DATE,
        s.ROW_ID,
        CURRENT_TIMESTAMP()::TIMESTAMP_NTZ as LAST_UPDATED_DATE
    from staged s
    left join existing_valid e
        on s.TRADE_ID = e.TRADE_ID
    where s.IS_VERSION_VALID
        and s.IS_TRADE_ID_VALID
        and e.TRADE_ID is not null
        and s.VERSION < e.MAX_VERSION
)

select * from invalid_trade_id
union all
select * from invalid_version
union all
select * from invalid_notional
union all
select * from invalid_currency
union all
select * from invalid_maturity
union all
select * from invalid_execution
union all
select * from maturity_before_execution
union all
select * from expired_maturity
union all
select * from stale_version
