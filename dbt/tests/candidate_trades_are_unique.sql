-- Warehouse data test: exactly one current row per TRADE_ID.

select TRADE_ID, count(*) as cnt
from {{ ref('valid_trades') }}
group by TRADE_ID
having count(*) > 1
