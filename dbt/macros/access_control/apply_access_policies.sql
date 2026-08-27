{% macro apply_access_policies() %}
{% if execute and this is not none %}
{% set policy_db = 'COMPLIANCE_DB' %}
{% set policy_schema = 'ACCESS_CONTROL' %}

{% set col_set = {} %}
{% for c in adapter.get_columns_in_relation(this) %}
  {% do col_set.update({(c.name | upper): true}) %}
{% endfor %}

{% set policy_refs_sql %}
SELECT POLICY_KIND, REF_COLUMN_NAME
FROM TABLE({{ this.database }}.INFORMATION_SCHEMA.POLICY_REFERENCES(
  REF_ENTITY_DOMAIN => 'TABLE',
  REF_DATABASE_NAME => '{{ this.database }}',
  REF_SCHEMA_NAME => '{{ this.schema }}',
  REF_ENTITY_NAME => '{{ this.identifier }}'
))
{% endset %}

{% set policy_refs = run_query(policy_refs_sql) %}

{% set masked_set = {} %}
{% set has_row_policy = [] %}
{% for row in policy_refs %}
  {% if (row['POLICY_KIND'] | upper) == 'MASKING_POLICY' %}
    {% do masked_set.update({(row['REF_COLUMN_NAME'] | upper): true}) %}
  {% elif (row['POLICY_KIND'] | upper) == 'ROW_ACCESS_POLICY' %}
    {% do has_row_policy.append(1) %}
  {% endif %}
{% endfor %}

{% if 'COUNTERPARTY' in col_set and 'COUNTERPARTY' not in masked_set %}
  {% do run_query("ALTER TABLE " ~ this.render() ~ " MODIFY COLUMN COUNTERPARTY SET MASKING POLICY " ~ policy_db ~ "." ~ policy_schema ~ ".counterparty_mask") %}
{% endif %}

{% if 'NOTIONAL' in col_set and 'NOTIONAL' not in masked_set %}
  {% do run_query("ALTER TABLE " ~ this.render() ~ " MODIFY COLUMN NOTIONAL SET MASKING POLICY " ~ policy_db ~ "." ~ policy_schema ~ ".notional_mask") %}
{% endif %}

{% if 'CURRENCY' in col_set and not has_row_policy %}
  {% do run_query("ALTER TABLE " ~ this.render() ~ " ADD ROW ACCESS POLICY " ~ policy_db ~ "." ~ policy_schema ~ ".currency_row_policy ON (CURRENCY)") %}
{% endif %}

{% endif %}
{% endmacro %}
