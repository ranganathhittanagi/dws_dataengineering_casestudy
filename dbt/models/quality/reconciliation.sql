{{ config(
    materialized='table',
    tags=['warehouse_quality']
) }}

{%- set etl_date = var('etl_date', run_started_at.strftime('%Y-%m-%d')) -%}
{%- set late_arrival_date = (modules.datetime.datetime.strptime(etl_date, '%Y-%m-%d') - modules.datetime.timedelta(days=1)).strftime('%Y-%m-%d') -%}

with raw_count as (
    select count(*) as cnt from {{ ref('trades') }}
    where ETL_DATE between '{{ late_arrival_date }}' and '{{ etl_date }}'
),

valid_count as (
    select count(*) as cnt from {{ ref('candidate_valid_trades') }}
    where ETL_DATE between '{{ late_arrival_date }}' and '{{ etl_date }}'
),

quarantine_distinct as (
    select count(distinct SOURCE_FILENAME || '~' || SOURCE_ROW_NUMBER) as cnt
    from {{ ref('rejected_trades') }}
    where ETL_DATE between '{{ late_arrival_date }}' and '{{ etl_date }}'
)

select
    '{{ etl_date }}'::VARCHAR as etl_date,
    r.cnt as source_rows,
    v.cnt as candidate_valid_rows,
    q.cnt as quarantined_distinct_records,
    r.cnt - v.cnt - q.cnt as unaccounted_rows,
    CURRENT_TIMESTAMP()::TIMESTAMP_NTZ as recorded_at
from raw_count r
left join valid_count v on true
left join quarantine_distinct q on true
