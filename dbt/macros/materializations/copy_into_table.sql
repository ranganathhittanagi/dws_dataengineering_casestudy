{% materialization copy_into_table, adapter='snowflake' %}

{%- set database_name = config.get('database') or target.database -%}
{%- set schema_name = config.get('schema') or target.schema -%}
{%- set target_relation = api.Relation.create(
    database=database_name,
    schema=schema_name,
    identifier=model['alias'],
    type='table'
) -%}
{%- set grant_config = config.get('grants') -%}
{%- set meta = config.get('meta', {}) or {} -%}
{%- set stage = meta.get('stage', '@RAW_DB.RAW_SCHEMA.RAW_DATA_STAGE') -%}
{%- set file_format = meta.get('file_format', 'RAW_DB.RAW_SCHEMA.CSV_FORMAT') -%}
{%- set header_file_format = meta.get('header_file_format', 'RAW_DB.RAW_SCHEMA.CSV_HEADER_FORMAT') -%}
{%- set copy_options = meta.get('copy_options', "ON_ERROR = 'ABORT_STATEMENT' FORCE = FALSE PURGE = FALSE") -%}
{%- set pattern = meta.get('pattern', '.*') -%}
{%- set known_columns = meta.get('known_columns', ['TRADE_ID', 'VERSION', 'COUNTERPARTY', 'NOTIONAL', 'CURRENCY', 'MATURITY_DATE', 'EXECUTION_DATE']) -%}
{%- set metadata_columns = ['SOURCE_FILENAME', 'SOURCE_ROW_NUMBER', 'ETL_DATE', 'DBT_INVOCATION_ID', 'LOAD_TIMESTAMP'] -%}

{%- set etl_date = var('etl_date', run_started_at.strftime('%Y-%m-%d')) -%}
{%- set invocation = invocation_id -%}

{%- if execute -%}
  {%- set header_scan_sql -%}
    select
      {%- for i in range(1, 101) -%}
        ${{ i }}::varchar as c{{ i }}{% if not loop.last %},{% endif %}
      {%- endfor -%}
    from {{ stage }} (FILE_FORMAT => '{{ header_file_format }}', PATTERN => '{{ pattern }}')
    where metadata$file_row_number = 1
  {%- endset -%}
  {%- set header_result = run_query(header_scan_sql) -%}

  {%- set best = namespace(values=[], count=0) -%}
  {%- for row in header_result.rows -%}
    {%- set row_values = [] -%}
    {%- for v in row.values() -%}
      {%- if v is not none and v | string != '' -%}{%- do row_values.append(v | string) -%}{%- endif -%}
    {%- endfor -%}
    {%- if row_values | length > best.count -%}
      {%- set best.count = row_values | length -%}
      {%- set best.values = row_values -%}
    {%- endif -%}
  {%- endfor -%}

  {%- set file_headers = best.values -%}
{%- else -%}
  {%- set file_headers = known_columns -%}
{%- endif -%}

{%- if execute -%}
  {%- for i in range(known_columns | length) -%}
    {%- if (file_headers[i] | upper) != (known_columns[i] | upper) -%}
      {{ exceptions.raise_compiler_error("CSV schema drift at position " ~ (i+1) ~ ": expected '" ~ known_columns[i] ~ "', found '" ~ file_headers[i] ~ "'") }}
    {%- endif -%}
  {%- endfor -%}
{%- endif -%}

{%- set file_col_positions = {} -%}
{%- for h in file_headers -%}
  {%- do file_col_positions.update({(h | upper): loop.index}) -%}
{%- endfor -%}

{%- set extra_headers = file_headers[known_columns | length:] -%}
{%- set extra_columns = [] -%}
{%- for extra in extra_headers -%}
  {%- set safe_extra = extra | upper | replace('"', '') -%}
  {%- if safe_extra == '' -%}
    {%- set safe_extra = 'EXTRA_' ~ loop.index -%}
  {%- endif -%}
  {%- do extra_columns.append('"' ~ safe_extra ~ '"') -%}
{%- endfor -%}

{%- set all_columns = known_columns + metadata_columns + extra_columns -%}

{{ run_hooks(pre_hooks, inside_transaction=False) }}
{{ run_hooks(pre_hooks, inside_transaction=True) }}

{% if should_full_refresh() %}
  {% do adapter.drop_relation(target_relation) %}
{% endif %}

{%- if execute -%}
  {%- set create_ddl_sql -%}
    create table if not exists {{ target_relation }} as (
      select
        {%- for col in all_columns -%}
          {%- set col_unquoted = col | replace('"', '') -%}
          {%- if col in metadata_columns -%}
            {%- if col == 'SOURCE_FILENAME' -%}METADATA$FILENAME::VARCHAR
            {%- elif col == 'SOURCE_ROW_NUMBER' -%}METADATA$FILE_ROW_NUMBER::VARCHAR
            {%- elif col == 'ETL_DATE' -%}'{{ etl_date }}'::VARCHAR
            {%- elif col == 'DBT_INVOCATION_ID' -%}'{{ invocation }}'::VARCHAR
            {%- elif col == 'LOAD_TIMESTAMP' -%}CURRENT_TIMESTAMP()::VARCHAR
            {%- endif -%}
          {%- elif col_unquoted in known_columns -%}
            ${{ file_col_positions[col_unquoted] }}::VARCHAR
          {%- else -%}
            ${{ file_col_positions[col_unquoted] }}::VARCHAR
          {%- endif -%} as {{ col }}{% if not loop.last %},{% endif %}
        {%- endfor -%}
      from {{ stage }} (FILE_FORMAT => '{{ file_format }}', PATTERN => '{{ pattern }}')
      where 1=0
    )
  {%- endset -%}
  {% do run_query(create_ddl_sql) %}

  {%- set existing_cols = [] -%}
  {%- for c in adapter.get_columns_in_relation(target_relation) -%}
    {%- do existing_cols.append(c.name) -%}
  {%- endfor -%}

  {%- for col in all_columns -%}
    {%- set col_unquoted = col | replace('"', '') -%}
    {%- if col_unquoted not in existing_cols -%}
      {%- set alter_sql -%}
        alter table {{ target_relation }} add column {{ col }} varchar
      {%- endset -%}
      {% do run_query(alter_sql) %}
    {%- endif -%}
  {%- endfor -%}

  {%- set table_cols = [] -%}
  {%- for c in adapter.get_columns_in_relation(target_relation) -%}
    {%- do table_cols.append(c.name) -%}
  {%- endfor -%}
{%- else -%}
  {%- set table_cols = all_columns | map('replace', '"', '') | list -%}
{%- endif -%}

{% call statement('main') -%}
  COPY INTO {{ target_relation }}
  FROM (
    select
      {%- for col in table_cols -%}
        {%- set col_unquoted = col | replace('"', '') -%}
        {%- if col_unquoted in metadata_columns -%}
          {%- if col_unquoted == 'SOURCE_FILENAME' -%}METADATA$FILENAME::VARCHAR
          {%- elif col_unquoted == 'SOURCE_ROW_NUMBER' -%}METADATA$FILE_ROW_NUMBER::VARCHAR
          {%- elif col_unquoted == 'ETL_DATE' -%}'{{ etl_date }}'::VARCHAR
          {%- elif col_unquoted == 'DBT_INVOCATION_ID' -%}'{{ invocation }}'::VARCHAR
          {%- elif col_unquoted == 'LOAD_TIMESTAMP' -%}CURRENT_TIMESTAMP()::VARCHAR
          {%- endif -%}
        {%- elif col_unquoted in file_col_positions -%}
          ${{ file_col_positions[col_unquoted] }}::VARCHAR
        {%- else -%}
          NULL::VARCHAR
        {%- endif -%}{% if not loop.last %},{% endif %}
      {%- endfor -%}
    from {{ stage }} (PATTERN => '{{ pattern }}')
  )
  FILE_FORMAT = (FORMAT_NAME = {{ file_format }})
  {{ copy_options }}
{%- endcall %}

{% do apply_grants(target_relation, grant_config, should_revoke=False) %}

{{ adapter.commit() }}
{{ run_hooks(post_hooks, inside_transaction=False) }}

{{ return({'relations': [target_relation]}) }}

{% endmaterialization %}
