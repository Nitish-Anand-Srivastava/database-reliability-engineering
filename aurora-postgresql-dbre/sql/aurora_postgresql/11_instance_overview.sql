\set ON_ERROR_STOP on
\pset pager off
\x auto

\echo Step 1: instance and parameter posture
SELECT * FROM dbre.instance_overview();

\echo Parameter spotlight
SELECT
  name,
  setting,
  unit,
  vartype,
  source
FROM pg_settings
WHERE name IN (
  'max_connections',
  'shared_buffers',
  'effective_cache_size',
  'work_mem',
  'maintenance_work_mem',
  'autovacuum_max_workers',
  'max_parallel_workers',
  'max_parallel_workers_per_gather',
  'track_io_timing',
  'shared_preload_libraries',
  'log_lock_waits',
  'log_autovacuum_min_duration',
  'statement_timeout',
  'lock_timeout',
  'idle_in_transaction_session_timeout'
)
ORDER BY name;
