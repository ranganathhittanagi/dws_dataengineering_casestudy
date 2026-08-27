{% macro date_string(date_expr) -%}
    TO_VARCHAR({{ date_expr }}, '{{ var('date_format') }}')
{%- endmacro %}

{% macro batch_window_filter(etl_date, late_arrival_date, etl_col='ETL_DATE') -%}
    {{ etl_col }} between '{{ late_arrival_date }}' and '{{ etl_date }}'
{%- endmacro %}

{% macro stream_window_filter(etl_date, late_arrival_date, ts_col='LOAD_TIMESTAMP') -%}
    TO_VARCHAR({{ ts_col }}, '{{ var('date_format') }}') between '{{ late_arrival_date }}' and '{{ etl_date }}'
{%- endmacro %}
