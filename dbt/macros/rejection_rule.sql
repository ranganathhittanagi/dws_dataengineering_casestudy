{% macro rejection_base_columns(rule_id, rule_name, rejection_reason) %}
        '{{ rule_id }}' as RULE_ID,
        '{{ rule_name }}' as RULE_NAME,
        SOURCE_TYPE,
        '{{ rejection_reason }}' as REJECTION_REASON,
        TRADE_ID,
        VERSION,
        COUNTERPARTY,
        NOTIONAL,
        CURRENCY,
        MATURITY_DATE,
        EXECUTION_DATE,
        ETL_DATE,
        ROW_ID,
        CURRENT_TIMESTAMP()::TIMESTAMP_NTZ as LAST_UPDATED_DATE
{%- endmacro %}
