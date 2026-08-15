import streamlit as st
import altair as alt
import pandas as pd
from snowflake.snowpark.context import get_active_session

st.set_page_config(page_title="Trade Dashboard", layout="wide")
st.markdown("## 📊 Trade Data Dashboard")

session = get_active_session()


@st.cache_data(ttl=300)
def fetch_metrics():
    """Fetch active, expired, and rejected trade counts."""
    row = session.sql("""
        SELECT
            SUM(CASE WHEN TRADE_STATUS = 'ACTIVE' THEN 1 ELSE 0 END) AS active_trades,
            SUM(CASE WHEN TRADE_STATUS = 'EXPIRED' THEN 1 ELSE 0 END) AS expired_trades
        FROM DATAWAREHOUSE_DB.DATAWAREHOUSE_SCHEMA.VALID_TRADES
    """).collect()[0]

    rejected = session.sql("""
        SELECT COUNT(*) AS cnt
        FROM COMPLIANCE_DB.COMPLIANCE_SCHEMA.REJECTED_TRADES
    """).collect()[0]["CNT"] or 0

    active = row["ACTIVE_TRADES"] or 0
    expired = row["EXPIRED_TRADES"] or 0
    return active, expired, rejected


active, expired, rejected = fetch_metrics()
total = active + expired + rejected

# --- Metrics ---
col1, col2, col3, col4 = st.columns(4)
col1.metric("Total Trades", f"{total:,}")
col2.metric("Active Trades", f"{active:,}")
col3.metric("Expired Trades", f"{expired:,}")
col4.metric("Rejected Trades", f"{rejected:,}")

st.markdown("---")

# --- Bar Chart ---
df = pd.DataFrame({
    "Status": ["Active", "Expired", "Rejected"],
    "Count": [active, expired, rejected],
    "Color": ["#06D6A0", "#FFD166", "#E71D36"],
})

chart = (
    alt.Chart(df)
    .mark_bar(cornerRadiusTopLeft=6, cornerRadiusTopRight=6)
    .encode(
        x=alt.X("Status:N", axis=alt.Axis(labelFontSize=14, title=None), sort=None),
        y=alt.Y("Count:Q", axis=alt.Axis(title="Number of Trades")),
        color=alt.Color("Color:N", scale=None, legend=None),
        tooltip=["Status", "Count"],
    )
    .properties(height=400)
)

text = chart.mark_text(dy=-12, fontSize=16, fontWeight="bold").encode(
    text=alt.Text("Count:Q", format=",")
)

st.altair_chart(chart + text, use_container_width=True)
