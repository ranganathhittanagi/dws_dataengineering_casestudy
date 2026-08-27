{% macro create_row_access_policy() %}
{% if execute %}
{% set mapping_table = 'COMPLIANCE_DB.ACCESS_CONTROL.CURRENCY_ENTITLEMENTS' %}
{% set policy_schema = 'COMPLIANCE_DB.ACCESS_CONTROL' %}

{% set check_table_sql %}
  SELECT COUNT(*) AS cnt
  FROM COMPLIANCE_DB.INFORMATION_SCHEMA.TABLES
  WHERE TABLE_SCHEMA = 'ACCESS_CONTROL'
    AND TABLE_NAME = 'CURRENCY_ENTITLEMENTS'
{% endset %}
{% set table_exists = run_query(check_table_sql)[0][0] > 0 %}

{% if table_exists %}
  {% set create_policy_sql %}
  CREATE OR ALTER ROW ACCESS POLICY {{ policy_schema }}.currency_row_policy AS (currency_code STRING)
  RETURNS BOOLEAN ->
    IS_ROLE_IN_SESSION('DWS_SERVICE_ROLE') OR IS_ROLE_IN_SESSION('ACCOUNTADMIN')
    OR EXISTS (
      SELECT 1
      FROM {{ mapping_table }}
      WHERE ROLE_NAME = CURRENT_ROLE()
        AND CURRENCY = currency_code
    )
  {% endset %}
  {% do run_query(create_policy_sql) %}
{% endif %}
{% endif %}
{% endmacro %}
