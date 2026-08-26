import streamlit as st
import altair as alt
import pandas as pd
from snowflake.snowpark.context import get_active_session

st.set_page_config(page_title="Data Quality Dashboard", layout="wide")
st.markdown("## 📈 Trade Data Quality Dashboard")

session = get_active_session()


def _to_pandas(rows):
    """Convert a Snowpark result to a pandas DataFrame with uppercase column names."""
    if not rows:
        return pd.DataFrame()
    columns = [k.upper() for k in rows[0].asDict().keys()]
    return pd.DataFrame([r.asDict().values() for r in rows], columns=columns)


@st.cache_data(ttl=300)
def fetch_quality_summary():
    """Fetch latest batch quality score, reconciliation, and rule failures."""
    latest = session.sql("""
        SELECT MAX(ETL_DATE) AS latest_batch
        FROM COMPLIANCE_DB.DQ_OBSERVABILITY.QUALITY_SCORECARD
    """).collect()[0]["LATEST_BATCH"]

    if not latest:
        return None, pd.DataFrame(), pd.DataFrame(), pd.DataFrame()

    scorecard = _to_pandas(session.sql("""
        SELECT RULE_NAME, DIMENSION, FAILURE_COUNT, TOTAL_ROWS, SCORE
        FROM COMPLIANCE_DB.DQ_OBSERVABILITY.QUALITY_SCORECARD
        WHERE ETL_DATE = %(batch)s
        ORDER BY FAILURE_COUNT DESC
    """ % {"batch": repr(latest)}).collect())

    reconciliation = _to_pandas(session.sql("""
        SELECT SOURCE_ROWS, CANDIDATE_VALID_ROWS, QUARANTINED_DISTINCT_RECORDS, UNACCOUNTED_ROWS
        FROM COMPLIANCE_DB.DQ_OBSERVABILITY.RECONCILIATION
        WHERE ETL_DATE = %(batch)s
    """ % {"batch": repr(latest)}).collect())

    rejected = _to_pandas(session.sql("""
        SELECT RULE_NAME, RULE_ID, COUNT(*) AS COUNT
        FROM COMPLIANCE_DB.COMPLIANCE_SCHEMA.REJECTED_TRADES
        WHERE ETL_DATE = %(batch)s
        GROUP BY RULE_NAME, RULE_ID
        ORDER BY COUNT DESC
    """ % {"batch": repr(latest)}).collect())

    overall_score = float(scorecard["SCORE"].mean()) if not scorecard.empty else 100.0
    return latest, scorecard, reconciliation, rejected, overall_score


result = fetch_quality_summary()

if result[0] is None:
    st.info("No quality scorecard data available yet.")
else:
    latest, scorecard, reconciliation, rejected, overall_score = result

    st.markdown(f"### Latest Batch: {latest}")

    q1, q2, q3 = st.columns(3)
    q1.metric("Overall Quality Score", f"{overall_score:.1f}%")
    if not reconciliation.empty:
        q2.metric("Source Rows", f"{int(reconciliation['SOURCE_ROWS'].iloc[0]):,}")
        q3.metric("Unaccounted Rows", f"{int(reconciliation['UNACCOUNTED_ROWS'].iloc[0]):,}")
    else:
        q2.metric("Source Rows", "-")
        q3.metric("Unaccounted Rows", "-")

    st.markdown("---")

    st.markdown("#### Reconciliation")
    if not reconciliation.empty:
        st.dataframe(reconciliation, use_container_width=True, hide_index=True)
    else:
        st.write("No reconciliation record for this batch.")

    st.markdown("#### Rejections by Rule")
    if not rejected.empty:
        st.dataframe(rejected, use_container_width=True, hide_index=True)
        chart = (
            alt.Chart(rejected)
            .mark_bar(cornerRadiusTopLeft=6, cornerRadiusTopRight=6)
            .encode(
                x=alt.X("RULE_NAME:N", axis=alt.Axis(title=None), sort=alt.EncodingSortField(field="COUNT", order="descending")),
                y=alt.Y("COUNT:Q", axis=alt.Axis(title="Rejected Records")),
                color=alt.Color("RULE_NAME:N", legend=None),
                tooltip=["RULE_NAME", "COUNT"],
            )
            .properties(height=300)
        )
        st.altair_chart(chart, use_container_width=True)
    else:
        st.write("No rejected records for this batch.")

    st.markdown("#### Quality Scorecard")
    if not scorecard.empty:
        st.dataframe(scorecard, use_container_width=True, hide_index=True)
    else:
        st.write("No scorecard details for this batch.")
