{{ config(
    materialized='table',
    tags=['post_publish_audit']
) }}

{%- set etl_date = var('etl_date', run_started_at.strftime('%Y-%m-%d')) -%}
{%- set source_dates = source_window_dates('trades', etl_date) -%}
{%- set late_arrival_date = source_dates[-1] -%}

with rule_totals as (

    select
        RULE_ID,
        RULE_NAME,
        count(*) as failure_count
    from {{ ref('rejected_trades') }}
    where ETL_DATE between '{{ late_arrival_date }}' and '{{ etl_date }}'
    group by RULE_ID, RULE_NAME

),

catalog as (
    select * from {{ ref('dq_rule_catalog') }}
),

batch_raw_count as (
    select count(*) as cnt from {{ ref('trades') }}
    where ETL_DATE between '{{ late_arrival_date }}' and '{{ etl_date }}'
),

stream_raw_count as (
    select count(*) as cnt from {{ source('raw', 'trades_stream') }}
    where TO_VARCHAR(LOAD_TIMESTAMP, 'YYYY-MM-DD') between '{{ late_arrival_date }}' and '{{ etl_date }}'
),

raw_count as (
    select b.cnt + s.cnt as cnt
    from batch_raw_count b
    cross join stream_raw_count s
)

select
    '{{ etl_date }}'::VARCHAR as etl_date,
    c.RULE_ID,
    coalesce(r.RULE_NAME, c.DESCRIPTION) as RULE_NAME,
    c.DIMENSION,
    c.SEVERITY,
    coalesce(r.failure_count, 0) as failure_count,
    rc.cnt as total_rows,
    case when rc.cnt > 0 then (1.0 - (coalesce(r.failure_count, 0) / rc.cnt)) * 100.0 else 100.0 end as score,
    CURRENT_TIMESTAMP()::TIMESTAMP_NTZ as recorded_at
from catalog c
left join rule_totals r on c.RULE_ID = r.RULE_ID
left join raw_count rc on true
