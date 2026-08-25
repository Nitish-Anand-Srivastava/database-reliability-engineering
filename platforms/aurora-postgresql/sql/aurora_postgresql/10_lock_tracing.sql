\set ON_ERROR_STOP on
\pset pager off

SET statement_timeout = '30s';

\echo Blocking chains
WITH blocked AS (
  SELECT
    a.pid AS blocked_pid,
    unnest(pg_blocking_pids(a.pid)) AS blocker_pid,
    a.usename AS blocked_user,
    a.application_name AS blocked_app,
    a.client_addr AS blocked_client_addr,
    a.wait_event_type,
    a.wait_event,
    age(clock_timestamp(), a.query_start) AS blocked_query_age,
    age(clock_timestamp(), a.xact_start) AS blocked_xact_age,
    a.state AS blocked_state,
    a.query AS blocked_query
  FROM pg_stat_activity AS a
  WHERE cardinality(pg_blocking_pids(a.pid)) > 0
)
SELECT
  blocked.blocked_pid,
  blocker.pid AS blocker_pid,
  blocked.blocked_user,
  blocker.usename AS blocker_user,
  blocked.blocked_app,
  blocker.application_name AS blocker_app,
  blocked.wait_event_type,
  blocked.wait_event,
  blocked.blocked_query_age,
  age(clock_timestamp(), blocker.query_start) AS blocker_query_age,
  blocked.blocked_xact_age,
  age(clock_timestamp(), blocker.xact_start) AS blocker_xact_age,
  blocked.blocked_state,
  blocker.state AS blocker_state,
  left(regexp_replace(blocked.blocked_query, '\s+', ' ', 'g'), 200) AS blocked_query,
  left(regexp_replace(blocker.query, '\s+', ' ', 'g'), 200) AS blocker_query
FROM blocked
JOIN pg_stat_activity AS blocker
  ON blocker.pid = blocked.blocker_pid
ORDER BY blocked.blocked_query_age DESC, blocker_query_age DESC;

\echo Sessions holding locks while idle in transaction or otherwise old
SELECT
  pid,
  usename,
  application_name,
  client_addr,
  state,
  wait_event_type,
  wait_event,
  age(clock_timestamp(), xact_start) AS xact_age,
  age(clock_timestamp(), query_start) AS query_age,
  left(regexp_replace(query, '\s+', ' ', 'g'), 200) AS query
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
  AND age(clock_timestamp(), xact_start) > interval '1 minute'
ORDER BY xact_age DESC;
