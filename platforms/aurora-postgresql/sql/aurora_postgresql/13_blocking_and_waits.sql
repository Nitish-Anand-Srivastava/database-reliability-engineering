\set ON_ERROR_STOP on
\pset pager off
\x auto

\echo Step 3A: blocking chains
SELECT * FROM dbre.blocking_overview();

\echo Step 3B: wait profile
SELECT * FROM dbre.wait_profile();

\echo Lock inventory by lock type and mode
SELECT
  locktype,
  mode,
  granted,
  count(*) AS lock_count
FROM pg_locks
GROUP BY locktype, mode, granted
ORDER BY granted, lock_count DESC, locktype, mode;
