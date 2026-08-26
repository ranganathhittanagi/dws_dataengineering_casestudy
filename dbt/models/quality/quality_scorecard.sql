{{ config(
    materialized='table',
    tags=['post_publish_audit']
) }}

{%- set etl_date = var('etl_date', run_started_at.strftime('%Y-%m-%d')) -%}
{%- set late_arrival_date = (modules.datetime.datetime.strptime(etl_date, '%Y-%m-%d') - modules.datetime.timedelta(days=1)).strftime('%Y-%m-%d') -%}

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

raw_count as (
    select count(*) as cnt from {{ ref('trades') }}
    where ETL_DATE between '{{ late_arrival_date }}' and '{{ etl_date }}'
)

select
    '{{ etl_date }}'::VARCHAR as etl_date,
    c.RULE_ID,
    c.RULE_NAME,
    c.DIMENSION,
    c.SEVERITY,
    coalesce(r.failure_count, 0) as failure_count,
    rc.cnt as total_rows,
    case when rc.cnt > 0 then (1.0 - (coalesce(r.failure_count, 0) / rc.cnt)) * 100.0 else 100.0 end as score,
    CURRENT_TIMESTAMP()::TIMESTAMP_NTZ as recorded_at
from catalog c
left join rule_totals r on c.RULE_ID = r.RULE_ID
left join raw_count rc on true
