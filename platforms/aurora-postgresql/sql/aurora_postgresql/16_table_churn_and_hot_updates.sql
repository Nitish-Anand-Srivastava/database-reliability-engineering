\set ON_ERROR_STOP on
\pset pager off
\x auto

\echo Step 6A: churn-heavy tables
SELECT * FROM dbre.table_churn_review(30);

\echo Step 6B: sequential-scan-heavy tables
SELECT
  schemaname,
  relname,
  seq_scan,
  idx_scan,
  round(seq_tup_read::numeric / nullif(seq_scan, 0), 2) AS avg_rows_per_seq_scan,
  n_live_tup,
  n_dead_tup,
  pg_size_pretty(pg_table_size(format('%I.%I', schemaname, relname)::regclass)) AS table_size
FROM pg_stat_user_tables
ORDER BY seq_tup_read DESC, seq_scan DESC
LIMIT 20;
