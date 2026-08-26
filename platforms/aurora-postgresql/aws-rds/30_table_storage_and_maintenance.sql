\set ON_ERROR_STOP on
\pset pager off
\x auto

\echo Step 9: churn-heavy tables
SELECT * FROM dbre_rds_pg.table_churn_review(30);

\echo Step 10: active vacuum progress
SELECT
  pid,
  datname,
  relid::regclass AS relation_name,
  phase,
  heap_blks_total,
  heap_blks_scanned,
  heap_blks_vacuumed,
  index_vacuum_count,
  num_dead_tuples
FROM pg_stat_progress_vacuum
ORDER BY pid;

\echo Step 11: stale statistics and vacuum gaps
SELECT
  schemaname,
  relname,
  n_live_tup,
  n_dead_tup,
  n_mod_since_analyze,
  last_autovacuum,
  last_autoanalyze,
  last_vacuum,
  last_analyze
FROM pg_stat_user_tables
ORDER BY n_mod_since_analyze DESC, n_dead_tup DESC
LIMIT 30;

\echo Step 12: sequential-scan-heavy tables
SELECT
  schemaname,
  relname,
  seq_scan,
  idx_scan,
  seq_tup_read,
  idx_tup_fetch,
  pg_size_pretty(pg_table_size(format('%I.%I', schemaname, relname)::regclass)) AS table_size
FROM pg_stat_user_tables
ORDER BY seq_tup_read DESC, seq_scan DESC
LIMIT 20;
