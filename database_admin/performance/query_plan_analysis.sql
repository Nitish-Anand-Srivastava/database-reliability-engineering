/*
Performance Troubleshooting Query Pack (Advanced)
Scope: Oracle, SQL Server, PostgreSQL, MySQL
Goal: self-sufficient detection queries that return only suspicious/problematic signals.
How to use: run only the section for your engine.
*/

/* =====================================================================
   ORACLE (needs access to V$ views; DBA role recommended)
   ===================================================================== */

-- O-0) Fast health detector: returns only active issues
WITH cpu AS (
    SELECT value AS cpu_count FROM v$parameter WHERE name = 'cpu_count'
),
aas AS (
    SELECT COUNT(*) AS aas
    FROM v$active_session_history
    WHERE sample_time >= SYSTIMESTAMP - INTERVAL '5' MINUTE
),
blocked AS (
    SELECT COUNT(*) AS blocked_sessions
    FROM v$session
    WHERE blocking_session IS NOT NULL
),
long_tx AS (
    SELECT COUNT(*) AS long_tx_over_10m
    FROM v$session
    WHERE status = 'ACTIVE'
      AND last_call_et > 600
      AND type = 'USER'
)
SELECT 'AAS_CPU_PRESSURE' AS issue, a.aas AS observed, c.cpu_count AS threshold
FROM aas a CROSS JOIN cpu c
WHERE a.aas > c.cpu_count
UNION ALL
SELECT 'BLOCKING_SESSIONS', b.blocked_sessions, 0
FROM blocked b
WHERE b.blocked_sessions > 0
UNION ALL
SELECT 'LONG_ACTIVE_SESSIONS_OVER_10M', l.long_tx_over_10m, 0
FROM long_tx l
WHERE l.long_tx_over_10m > 0;

-- O-1) Top wait events (non-idle)
SELECT event,
       wait_class,
       total_waits,
       ROUND(time_waited_micro / 1e6, 2) AS time_waited_s,
       ROUND(average_wait / 100, 2) AS avg_wait_ms
FROM v$system_event
WHERE wait_class <> 'Idle'
ORDER BY time_waited_micro DESC
FETCH FIRST 25 ROWS ONLY;

-- O-2) Top SQL by elapsed/exec with heavy logical+physical IO
SELECT *
FROM (
    SELECT s.sql_id,
           SUBSTR(s.sql_text, 1, 140) AS sql_text,
           s.executions,
           ROUND(s.elapsed_time / 1e6, 2) AS elapsed_s,
           ROUND((s.elapsed_time / NULLIF(s.executions, 0)) / 1e3, 2) AS avg_elapsed_ms,
           ROUND((s.buffer_gets / NULLIF(s.executions, 0)), 2) AS lio_per_exec,
           ROUND((s.disk_reads / NULLIF(s.executions, 0)), 2) AS pio_per_exec,
           s.plan_hash_value
    FROM v$sql s
    WHERE s.executions > 0
    ORDER BY s.elapsed_time DESC
)
WHERE ROWNUM <= 25;

-- O-3) Blocking sessions with victim + blocker SQL
SELECT b.sid AS blocked_sid,
       b.username AS blocked_user,
       b.seconds_in_wait,
       bl.sid AS blocker_sid,
       bl.username AS blocker_user,
       SUBSTR(b.sql_id, 1, 13) AS blocked_sql_id,
       SUBSTR(bl.sql_id, 1, 13) AS blocker_sql_id
FROM v$session b
JOIN v$session bl ON b.blocking_session = bl.sid
WHERE b.blocking_session IS NOT NULL
ORDER BY b.seconds_in_wait DESC;

-- O-4) Segment hotspots by physical reads
SELECT owner,
       object_name,
       object_type,
       value AS physical_reads
FROM v$segment_statistics
WHERE statistic_name = 'physical reads'
ORDER BY value DESC
FETCH FIRST 25 ROWS ONLY;


/* =====================================================================
   SQL SERVER (VIEW SERVER STATE recommended)
   ===================================================================== */

-- S-0) Fast health detector: returns only active issues
WITH cpu_pressure AS (
    SELECT COUNT(*) AS runnable_tasks
    FROM sys.dm_os_schedulers
    WHERE status = 'VISIBLE ONLINE' AND runnable_tasks_count > 0
),
blocking AS (
    SELECT COUNT(*) AS blocked_requests
    FROM sys.dm_exec_requests
    WHERE blocking_session_id <> 0
),
long_req AS (
    SELECT COUNT(*) AS long_requests_over_30s
    FROM sys.dm_exec_requests
    WHERE total_elapsed_time > 30000
)
SELECT 'CPU_RUNNABLE_TASKS' AS issue, runnable_tasks AS observed, 0 AS threshold
FROM cpu_pressure
WHERE runnable_tasks > 0
UNION ALL
SELECT 'BLOCKED_REQUESTS', blocked_requests, 0
FROM blocking
WHERE blocked_requests > 0
UNION ALL
SELECT 'LONG_REQUESTS_OVER_30S', long_requests_over_30s, 0
FROM long_req
WHERE long_requests_over_30s > 0;

-- S-1) Top expensive statements in cache
SELECT TOP (25)
    DB_NAME(st.dbid) AS database_name,
    qs.execution_count,
    qs.total_worker_time / 1000.0 AS total_cpu_ms,
    (qs.total_elapsed_time / NULLIF(qs.execution_count, 0)) / 1000.0 AS avg_elapsed_ms,
    qs.total_logical_reads,
    qs.total_logical_writes,
    SUBSTRING(st.text,
              (qs.statement_start_offset / 2) + 1,
              ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text)
                                             ELSE qs.statement_end_offset END
                - qs.statement_start_offset) / 2) + 1) AS statement_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
ORDER BY qs.total_worker_time DESC;

-- S-2) Wait hotspots (filtered)
SELECT TOP (30)
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    signal_wait_time_ms,
    CAST(100.0 * wait_time_ms / NULLIF(SUM(wait_time_ms) OVER (), 0) AS DECIMAL(8,2)) AS pct_total_wait
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN (
    'CLR_SEMAPHORE','LAZYWRITER_SLEEP','RESOURCE_QUEUE','SLEEP_TASK','SLEEP_SYSTEMTASK',
    'SQLTRACE_BUFFER_FLUSH','WAITFOR','LOGMGR_QUEUE','CHECKPOINT_QUEUE','REQUEST_FOR_DEADLOCK_SEARCH',
    'XE_TIMER_EVENT','BROKER_TO_FLUSH','BROKER_TASK_STOP','CLR_MANUAL_EVENT','CLR_AUTO_EVENT',
    'DISPATCHER_QUEUE_SEMAPHORE','FT_IFTS_SCHEDULER_IDLE_WAIT','XE_DISPATCHER_WAIT','XE_DISPATCHER_JOIN'
)
ORDER BY wait_time_ms DESC;

-- S-3) Blocking chain + SQL text
SELECT wt.session_id AS blocked_session,
       wt.blocking_session_id AS blocker_session,
       wt.wait_duration_ms,
       wt.wait_type,
       LEFT(txt.text, 220) AS blocked_sql_text
FROM sys.dm_os_waiting_tasks wt
LEFT JOIN sys.dm_exec_requests r ON r.session_id = wt.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) txt
WHERE wt.blocking_session_id IS NOT NULL
  AND wt.blocking_session_id <> 0
ORDER BY wt.wait_duration_ms DESC;

-- S-4) File latency hotspot report
SELECT DB_NAME(vfs.database_id) AS database_name,
       mf.name AS logical_name,
       mf.type_desc,
       CASE WHEN vfs.num_of_reads = 0 THEN 0 ELSE vfs.io_stall_read_ms * 1.0 / vfs.num_of_reads END AS avg_read_stall_ms,
       CASE WHEN vfs.num_of_writes = 0 THEN 0 ELSE vfs.io_stall_write_ms * 1.0 / vfs.num_of_writes END AS avg_write_stall_ms
FROM sys.dm_io_virtual_file_stats(NULL, NULL) vfs
JOIN sys.master_files mf ON mf.database_id = vfs.database_id AND mf.file_id = vfs.file_id
WHERE (CASE WHEN vfs.num_of_reads = 0 THEN 0 ELSE vfs.io_stall_read_ms * 1.0 / vfs.num_of_reads END) > 20
   OR (CASE WHEN vfs.num_of_writes = 0 THEN 0 ELSE vfs.io_stall_write_ms * 1.0 / vfs.num_of_writes END) > 20
ORDER BY avg_read_stall_ms DESC, avg_write_stall_ms DESC;


/* =====================================================================
   POSTGRESQL (requires pg_stat_statements extension)
   ===================================================================== */

-- P-0) Fast health detector: returns only active issues
WITH blocked AS (
    SELECT COUNT(*) AS blocked_sessions
    FROM pg_stat_activity
    WHERE cardinality(pg_blocking_pids(pid)) > 0
),
long_xact AS (
    SELECT COUNT(*) AS xacts_over_10m
    FROM pg_stat_activity
    WHERE xact_start IS NOT NULL
      AND now() - xact_start > interval '10 minutes'
),
slow_q AS (
    SELECT COUNT(*) AS statements_over_250ms
    FROM pg_stat_statements
    WHERE mean_exec_time > 250
)
SELECT 'BLOCKED_SESSIONS' AS issue, blocked_sessions AS observed, 0 AS threshold
FROM blocked WHERE blocked_sessions > 0
UNION ALL
SELECT 'LONG_XACTS_OVER_10M', xacts_over_10m, 0
FROM long_xact WHERE xacts_over_10m > 0
UNION ALL
SELECT 'MEAN_QUERY_TIME_OVER_250MS', statements_over_250ms, 0
FROM slow_q WHERE statements_over_250ms > 0;

-- P-1) Query bottlenecks by total and mean exec time
SELECT queryid,
       calls,
       ROUND(total_exec_time::numeric, 2) AS total_exec_ms,
       ROUND(mean_exec_time::numeric, 2) AS mean_exec_ms,
       shared_blks_read,
       temp_blks_written,
       LEFT(query, 180) AS query_sample
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 25;

-- P-2) Blocking chains with blocker + blocked query text
WITH blocked AS (
    SELECT a.pid AS blocked_pid,
           unnest(pg_blocking_pids(a.pid)) AS blocker_pid,
           a.query AS blocked_query,
           a.query_start
    FROM pg_stat_activity a
    WHERE cardinality(pg_blocking_pids(a.pid)) > 0
)
SELECT b.blocked_pid,
       sa.usename AS blocked_user,
       age(clock_timestamp(), sa.query_start) AS blocked_for,
       b.blocker_pid,
       sb.usename AS blocker_user,
       age(clock_timestamp(), sb.query_start) AS blocker_running_for,
       LEFT(sa.query, 180) AS blocked_query,
       LEFT(sb.query, 180) AS blocker_query
FROM blocked b
JOIN pg_stat_activity sa ON sa.pid = b.blocked_pid
JOIN pg_stat_activity sb ON sb.pid = b.blocker_pid
ORDER BY blocked_for DESC;

-- P-3) Dead tuple pressure (bloat risk)
SELECT schemaname,
       relname,
       n_live_tup,
       n_dead_tup,
       ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS dead_tuple_pct,
       last_autovacuum,
       last_autoanalyze
FROM pg_stat_user_tables
WHERE n_dead_tup > 10000
   OR (100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0)) > 10
ORDER BY n_dead_tup DESC
LIMIT 25;

-- P-4) IO-heavy relations + low heap hit ratio
SELECT schemaname,
       relname,
       heap_blks_read,
       heap_blks_hit,
       ROUND(100.0 * heap_blks_hit / NULLIF(heap_blks_hit + heap_blks_read, 0), 2) AS heap_hit_pct
FROM pg_statio_user_tables
WHERE heap_blks_read > 10000
  AND (100.0 * heap_blks_hit / NULLIF(heap_blks_hit + heap_blks_read, 0)) < 95
ORDER BY heap_blks_read DESC
LIMIT 25;


/* =====================================================================
   MYSQL 8.0+ (performance_schema should be enabled)
   ===================================================================== */

-- M-0) Fast health detector: returns only active issues
WITH lock_waits AS (
    SELECT COUNT(*) AS lock_wait_count
    FROM information_schema.innodb_lock_waits
),
slow_digest AS (
    SELECT COUNT(*) AS digests_over_200ms
    FROM performance_schema.events_statements_summary_by_digest
    WHERE AVG_TIMER_WAIT / 1000000000 > 200
),
full_scan AS (
    SELECT COUNT(*) AS no_index_statements
    FROM performance_schema.events_statements_summary_by_digest
    WHERE SUM_NO_INDEX_USED > 0
)
SELECT 'LOCK_WAITS' AS issue, lock_wait_count AS observed, 0 AS threshold
FROM lock_waits WHERE lock_wait_count > 0
UNION ALL
SELECT 'DIGESTS_AVG_OVER_200MS', digests_over_200ms, 0
FROM slow_digest WHERE digests_over_200ms > 0
UNION ALL
SELECT 'STATEMENTS_WITH_NO_INDEX', no_index_statements, 0
FROM full_scan WHERE no_index_statements > 0;

-- M-1) Top statement digests by total and avg latency
SELECT DIGEST,
       LEFT(DIGEST_TEXT, 180) AS digest_text,
       COUNT_STAR,
       ROUND(SUM_TIMER_WAIT / 1000000000000, 2) AS total_time_s,
       ROUND(AVG_TIMER_WAIT / 1000000000, 2) AS avg_time_ms,
       SUM_ROWS_EXAMINED,
       SUM_ROWS_SENT,
       SUM_NO_INDEX_USED
FROM performance_schema.events_statements_summary_by_digest
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 25;

-- M-2) InnoDB lock waits with blocker/waiter SQL
SELECT r.trx_id AS waiting_trx_id,
       TIMESTAMPDIFF(SECOND, r.trx_started, NOW()) AS waiting_seconds,
       LEFT(r.trx_query, 180) AS waiting_query,
       b.trx_id AS blocking_trx_id,
       LEFT(b.trx_query, 180) AS blocking_query
FROM information_schema.innodb_lock_waits w
JOIN information_schema.innodb_trx b ON b.trx_id = w.blocking_trx_id
JOIN information_schema.innodb_trx r ON r.trx_id = w.requesting_trx_id
ORDER BY waiting_seconds DESC;

-- M-3) Wait-event hotspots
SELECT EVENT_NAME,
       COUNT_STAR,
       ROUND(SUM_TIMER_WAIT / 1000000000000, 2) AS total_wait_s,
       ROUND(AVG_TIMER_WAIT / 1000000000, 2) AS avg_wait_ms
FROM performance_schema.events_waits_summary_global_by_event_name
WHERE COUNT_STAR > 0
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 30;

-- M-4) Read-heavy tables that likely need indexing review
SELECT object_schema,
       object_name,
       count_read,
       count_fetch,
       count_write
FROM performance_schema.table_io_waits_summary_by_table
WHERE object_schema NOT IN ('mysql', 'performance_schema', 'information_schema', 'sys')
  AND count_read > (count_write * 10)
ORDER BY count_read DESC
LIMIT 25;
