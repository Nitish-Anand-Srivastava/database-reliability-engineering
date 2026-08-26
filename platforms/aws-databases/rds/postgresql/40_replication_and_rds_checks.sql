\set ON_ERROR_STOP on
\pset pager off
\x auto

\echo Step 13: replication overview
SELECT * FROM dbre_rds_pg.replication_overview();

\echo Step 14: replication slots
SELECT
  slot_name,
  slot_type,
  active,
  wal_status,
  pg_size_pretty(safe_wal_size) AS safe_wal_size,
  restart_lsn,
  confirmed_flush_lsn,
  inactive_since
FROM pg_replication_slots
ORDER BY active ASC, slot_name;

\echo Step 15: RDS parameter review
SELECT * FROM dbre_rds_pg.rds_parameter_review();

\echo Step 16: extension and parameter spotlight
SELECT
  name,
  setting,
  unit,
  source
FROM pg_settings
WHERE name IN (
  'max_connections',
  'shared_buffers',
  'effective_cache_size',
  'work_mem',
  'maintenance_work_mem',
  'autovacuum',
  'autovacuum_max_workers',
  'track_io_timing',
  'log_lock_waits',
  'log_min_duration_statement',
  'statement_timeout',
  'lock_timeout',
  'idle_in_transaction_session_timeout'
)
ORDER BY name;
