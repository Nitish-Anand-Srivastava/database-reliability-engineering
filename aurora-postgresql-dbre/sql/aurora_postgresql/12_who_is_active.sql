\set ON_ERROR_STOP on
\pset pager off
\x auto

\echo Step 2: who is active right now
SELECT * FROM dbre.who_is_active(40);

\echo Client backend state mix
SELECT
  state,
  count(*) AS sessions,
  count(*) FILTER (WHERE wait_event_type IS NOT NULL) AS waiting_sessions
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY state
ORDER BY sessions DESC, state;
