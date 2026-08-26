{% materialization copy_into_table, adapter='snowflake' %}

  {%- set database_name = config.get('database') or target.database %}
  {%- set schema_name = config.get('schema') or target.schema %}
  {%- set target_relation = api.Relation.create(
      database=database_name,
      schema=schema_name,
      identifier=model['alias'],
      type='table'
  ) %}
  {%- set grant_config = config.get('grants') %}
  {%- set stage = config.require('stage') %}
  {%- set file_format = config.require('file_format') %}
  {%- set copy_options = (config.get('meta', {}) or {}).get('copy_options', "ON_ERROR = 'CONTINUE' FORCE = FALSE PURGE = FALSE") %}

  {{ run_hooks(pre_hooks, inside_transaction=False) }}
  {{ run_hooks(pre_hooks, inside_transaction=True) }}

  {% if should_full_refresh() %}
    {% do adapter.drop_relation(target_relation) %}
  {% endif %}

  {% call statement('create_target') -%}
    create table if not exists {{ target_relation }} as (
      select * from (
        {{ sql }}
      ) as _subquery
      limit 0
    )
  {%- endcall %}

  {% call statement('main') -%}
    COPY INTO {{ target_relation }}
    FROM {{ stage }}
    FILE_FORMAT = {{ file_format }}
    {{ copy_options }}
  {%- endcall %}

  {% do apply_grants(target_relation, grant_config, should_revoke=False) %}

  {{ adapter.commit() }}
  {{ run_hooks(post_hooks, inside_transaction=False) }}

  {{ return({'relations': [target_relation]}) }}

{% endmaterialization %}
