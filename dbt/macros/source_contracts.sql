{% macro source_window_dates(source_name, etl_date) %}
  {%- set late_arrival_days = var('source_windows', {}).get(source_name, {}).get('late_arrival_days', 0) | int -%}
  {%- set end = modules.datetime.datetime.strptime(etl_date, '%Y-%m-%d') -%}
  {%- set start = end - modules.datetime.timedelta(days=late_arrival_days) -%}
  {%- if late_arrival_days == 0 -%}
    {{ return([etl_date]) }}
  {%- else -%}
    {{ return([etl_date, start.strftime('%Y-%m-%d')]) }}
  {%- endif -%}
{% endmacro %}
