\set ON_ERROR_STOP on
\pset pager off
\x auto

\echo Step 1: instance posture
SELECT * FROM dbre_rds_pg.instance_overview();

\echo Step 2: active sessions
SELECT * FROM dbre_rds_pg.who_is_active(40);

\echo Step 3: wait profile
SELECT * FROM dbre_rds_pg.wait_profile();

\echo Step 4: connection state mix
SELECT
  state,
  count(*) AS sessions,
  count(*) FILTER (WHERE wait_event_type IS NOT NULL) AS waiting_sessions
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY state
ORDER BY sessions DESC, state;
