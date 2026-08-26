-- Reconciliation data test: every source record in the batch must be either
-- accepted as a candidate or assigned to a distinct quarantined source record.
-- Any non-zero unaccounted_rows is a zero-loss failure that blocks publication.

select etl_date, source_rows, candidate_valid_rows, quarantined_distinct_records, unaccounted_rows
from {{ ref('reconciliation') }}
where unaccounted_rows <> 0
