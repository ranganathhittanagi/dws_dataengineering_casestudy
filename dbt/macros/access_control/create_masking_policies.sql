{% macro create_masking_policies() %}
{% if execute %}
{% set privileged_roles = ['DWS_SERVICE_ROLE', 'ACCOUNTADMIN', 'DATA_ANALYSTS'] %}
{% set policy_schema = 'COMPLIANCE_DB.ACCESS_CONTROL' %}

{% set create_counterparty_sql %}
CREATE OR ALTER MASKING POLICY {{ policy_schema }}.counterparty_mask AS (val STRING)
RETURNS STRING ->
  CASE
    WHEN IS_ROLE_IN_SESSION('{{ privileged_roles | join("') OR IS_ROLE_IN_SESSION('") }}') THEN val
    ELSE '***'
  END
{% endset %}
{% do run_query(create_counterparty_sql) %}

{% set create_notional_sql %}
CREATE OR ALTER MASKING POLICY {{ policy_schema }}.notional_mask AS (val NUMBER(18,2))
RETURNS NUMBER(18,2) ->
  CASE
    WHEN IS_ROLE_IN_SESSION('{{ privileged_roles | join("') OR IS_ROLE_IN_SESSION('") }}') THEN val
    ELSE 0
  END
{% endset %}
{% do run_query(create_notional_sql) %}
{% endif %}
{% endmacro %}
