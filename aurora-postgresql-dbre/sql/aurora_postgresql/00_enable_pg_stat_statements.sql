\set ON_ERROR_STOP on
\pset pager off

\echo Ensuring pg_stat_statements is available in this database
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

\echo Current settings that influence DBRE diagnostics
SELECT name, setting
FROM pg_settings
WHERE name IN (
  'shared_preload_libraries',
  'track_io_timing',
  'log_connections',
  'log_disconnections',
  'idle_in_transaction_session_timeout',
  'lock_timeout'
)
ORDER BY name;

\echo Extension status
SELECT extname, extversion
FROM pg_extension
WHERE extname = 'pg_stat_statements';
