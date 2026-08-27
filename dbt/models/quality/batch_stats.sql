{{ config(
    materialized='table',
    tags=['post_publish_audit']
) }}

{%- set etl_date = var('etl_date', run_started_at.strftime('%Y-%m-%d')) -%}
{%- set source_dates = source_window_dates('trades', etl_date) -%}
{%- set late_arrival_date = source_dates[-1] -%}

with control_totals as (

    select
        'raw' as stage,
        'trades' as model,
        '{{ etl_date }}'::VARCHAR as etl_date,
        count(*) as row_count
    from {{ ref('trades') }}
    where {{ batch_window_filter(etl_date, late_arrival_date) }}

    union all

    select
        'transform' as stage,
        'stg_trades' as model,
        '{{ etl_date }}'::VARCHAR as etl_date,
        count(*) as row_count
    from {{ ref('stg_trades') }}
    where {{ batch_window_filter(etl_date, late_arrival_date) }}

    union all

    select
        'raw' as stage,
        'trades_stream' as model,
        '{{ etl_date }}'::VARCHAR as etl_date,
        count(*) as row_count
    from {{ source('raw', 'trades_stream') }}
    where {{ stream_window_filter(etl_date, late_arrival_date) }}

    union all

    select
        'transform' as stage,
        'stg_trades_stream' as model,
        '{{ etl_date }}'::VARCHAR as etl_date,
        count(*) as row_count
    from {{ ref('stg_trades_stream') }}
    where {{ batch_window_filter(etl_date, late_arrival_date) }}

    union all

    select
        'quarantine' as stage,
        'rejected_trades' as model,
        '{{ etl_date }}'::VARCHAR as etl_date,
        count(*) as row_count
    from {{ ref('rejected_trades') }}
    where {{ batch_window_filter(etl_date, late_arrival_date) }}

    union all

    select
        'warehouse' as stage,
        'valid_trades' as model,
        '{{ etl_date }}'::VARCHAR as etl_date,
        count(*) as row_count
    from {{ ref('valid_trades') }}
    where {{ batch_window_filter(etl_date, late_arrival_date) }}

)

select
    *,
    CURRENT_TIMESTAMP()::TIMESTAMP_NTZ as recorded_at
from control_totals
