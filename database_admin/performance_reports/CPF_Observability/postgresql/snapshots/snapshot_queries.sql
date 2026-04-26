-- PostgreSQL CPF_Observability snapshot dataset
CREATE SCHEMA IF NOT EXISTS cpf;
CREATE TABLE IF NOT EXISTS cpf.snapshot_meta (
  snapshot_id bigserial PRIMARY KEY,
  captured_at timestamptz NOT NULL DEFAULT now(),
  source text NOT NULL DEFAULT 'postgresql'
);

-- Capture top waits / active sessions
INSERT INTO cpf.snapshot_meta DEFAULT VALUES;

-- Use query outputs and persist externally as JSON/CSV for HTML rendering
SELECT now() AS captured_at, datname, numbackends, xact_commit, xact_rollback, blks_hit, blks_read
FROM pg_stat_database;

SELECT pid, usename, state, wait_event_type, wait_event, now()-query_start AS query_age, LEFT(query, 300) AS query
FROM pg_stat_activity
WHERE state <> 'idle'
ORDER BY query_start;

SELECT queryid, calls, total_exec_time, mean_exec_time, shared_blks_read, temp_blks_written, LEFT(query, 300) query
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 50;

SELECT blocked_locks.pid AS blocked_pid, blocking_locks.pid AS blocking_pid
FROM pg_locks blocked_locks
JOIN pg_locks blocking_locks
  ON blocked_locks.locktype = blocking_locks.locktype
 AND blocked_locks.database IS NOT DISTINCT FROM blocking_locks.database
 AND blocked_locks.relation IS NOT DISTINCT FROM blocking_locks.relation
 AND blocked_locks.page IS NOT DISTINCT FROM blocking_locks.page
 AND blocked_locks.tuple IS NOT DISTINCT FROM blocking_locks.tuple
 AND blocked_locks.virtualxid IS NOT DISTINCT FROM blocking_locks.virtualxid
 AND blocked_locks.transactionid IS NOT DISTINCT FROM blocking_locks.transactionid
 AND blocked_locks.classid IS NOT DISTINCT FROM blocking_locks.classid
 AND blocked_locks.objid IS NOT DISTINCT FROM blocking_locks.objid
 AND blocked_locks.objsubid IS NOT DISTINCT FROM blocking_locks.objsubid
 AND blocked_locks.pid <> blocking_locks.pid
WHERE NOT blocked_locks.granted AND blocking_locks.granted;
