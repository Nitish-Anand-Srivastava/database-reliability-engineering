\set ON_ERROR_STOP on
\pset pager off
\pset border 1
\pset footer off
\pset format html
\pset tableattr 'class="report-table"'

\if :{?report_file}
\else
\set report_file or_postgres_observability_report.html
\endif

\if :{?top_sessions}
\else
\set top_sessions 25
\endif

\if :{?top_sql}
\else
\set top_sql 30
\endif

\if :{?top_tables}
\else
\set top_tables 25
\endif

SELECT (to_regclass('public.pg_stat_statements') IS NOT NULL)::int AS has_pgss \gset
SELECT (to_regclass('pg_catalog.pg_stat_checkpointer') IS NOT NULL)::int AS has_checkpointer \gset

\o :report_file
\qecho <!DOCTYPE html>
\qecho <html lang="en">
\qecho <head>
\qecho <meta charset="utf-8">
\qecho <title>Postgres Observability Report</title>
\qecho <style>
\qecho body { font-family: Arial, Helvetica, sans-serif; margin: 24px; background: #0b1020; color: #e5e7eb; }
\qecho h1, h2, h3 { color: #f8fafc; }
\qecho section { margin-bottom: 28px; padding: 16px; background: #111827; border: 1px solid #1f2937; border-radius: 10px; }
\qecho .report-table { width: 100%; border-collapse: collapse; font-size: 13px; margin-top: 12px; }
\qecho .report-table th, .report-table td { border: 1px solid #334155; padding: 8px 10px; text-align: left; vertical-align: top; }
\qecho .report-table th { background: #1e293b; }
\qecho .muted { color: #cbd5e1; }
\qecho code { color: #93c5fd; }
\qecho </style>
\qecho </head>
\qecho <body>
\qecho <h1>Postgres Observability Report</h1>
\qecho <p class="muted">This report is intended for production-safe review. It captures top resource-consuming sessions and the highest-value operational signals without creating persistent schemas or helper functions.</p>

\qecho <section><h2>1. Instance overview</h2>
SELECT
  now() AS generated_at,
  current_database() AS database_name,
  current_setting('server_version') AS server_version,
  current_setting('rds.extensions', true) AS rds_extensions,
  age(clock_timestamp(), pg_postmaster_start_time()) AS uptime,
  current_setting('max_connections') AS max_connections,
  current_setting('shared_buffers') AS shared_buffers,
  current_setting('work_mem') AS work_mem,
  current_setting('maintenance_work_mem') AS maintenance_work_mem,
  current_setting('effective_cache_size') AS effective_cache_size,
  current_setting('autovacuum') AS autovacuum,
  current_setting('autovacuum_max_workers') AS autovacuum_max_workers,
  current_setting('track_io_timing') AS track_io_timing,
  current_setting('log_lock_waits') AS log_lock_waits,
  current_setting('log_min_duration_statement') AS log_min_duration_statement,
  current_setting('statement_timeout') AS statement_timeout,
  current_setting('lock_timeout') AS lock_timeout,
  current_setting('idle_in_transaction_session_timeout') AS idle_in_transaction_session_timeout;
\qecho </section>

\qecho <section><h2>2. Connection and wait posture</h2>
SELECT
  state,
  coalesce(wait_event_type, 'CPU/Client') AS wait_event_type,
  coalesce(wait_event, '(none)') AS wait_event,
  count(*) AS sessions,
  count(*) FILTER (WHERE state = 'active') AS active_sessions,
  max(coalesce(age(clock_timestamp(), query_start), interval '0')) AS longest_query_age,
  max(coalesce(age(clock_timestamp(), xact_start), interval '0')) AS longest_xact_age
FROM pg_stat_activity
WHERE backend_type = 'client backend'
  AND pid <> pg_backend_pid()
GROUP BY state, coalesce(wait_event_type, 'CPU/Client'), coalesce(wait_event, '(none)')
ORDER BY sessions DESC, active_sessions DESC, longest_query_age DESC;
\qecho </section>

\qecho <section><h2>3. Top active and costly sessions</h2>
SELECT
  pid,
  usename,
  datname,
  coalesce(nullif(application_name, ''), '(unknown)') AS application_name,
  coalesce(client_addr::text, 'local') AS client_addr,
  state,
  wait_event_type,
  wait_event,
  coalesce(age(clock_timestamp(), xact_start), interval '0') AS xact_age,
  coalesce(age(clock_timestamp(), query_start), interval '0') AS query_age,
  cardinality(pg_blocking_pids(pid)) AS blocker_count,
  left(regexp_replace(coalesce(query, ''), '\s+', ' ', 'g'), 320) AS query_text
FROM pg_stat_activity
WHERE backend_type = 'client backend'
  AND pid <> pg_backend_pid()
ORDER BY
  CASE WHEN state = 'active' THEN 0 ELSE 1 END,
  coalesce(age(clock_timestamp(), xact_start), interval '0') DESC,
  coalesce(age(clock_timestamp(), query_start), interval '0') DESC
LIMIT :top_sessions;
\qecho </section>

\qecho <section><h2>4. Blocking chains</h2>
WITH blocked AS (
  SELECT
    a.pid AS blocked_pid,
    unnest(pg_blocking_pids(a.pid)) AS blocker_pid,
    a.usename AS blocked_user,
    a.application_name AS blocked_app,
    a.state AS blocked_state,
    a.wait_event_type,
    a.wait_event,
    coalesce(age(clock_timestamp(), a.xact_start), interval '0') AS blocked_xact_age,
    left(regexp_replace(coalesce(a.query, ''), '\s+', ' ', 'g'), 240) AS blocked_query
  FROM pg_stat_activity AS a
  WHERE cardinality(pg_blocking_pids(a.pid)) > 0
)
SELECT
  b.blocked_pid,
  blocker.pid AS blocker_pid,
  b.blocked_user,
  blocker.usename AS blocker_user,
  coalesce(nullif(b.blocked_app, ''), '(unknown)') AS blocked_app,
  coalesce(nullif(blocker.application_name, ''), '(unknown)') AS blocker_app,
  b.blocked_state,
  blocker.state AS blocker_state,
  b.wait_event_type,
  b.wait_event,
  b.blocked_xact_age,
  coalesce(age(clock_timestamp(), blocker.xact_start), interval '0') AS blocker_xact_age,
  b.blocked_query,
  left(regexp_replace(coalesce(blocker.query, ''), '\s+', ' ', 'g'), 240) AS blocker_query
FROM blocked AS b
JOIN pg_stat_activity AS blocker
  ON blocker.pid = b.blocker_pid
ORDER BY b.blocked_xact_age DESC, b.blocked_pid;
\qecho </section>

\qecho <section><h2>5. Database pressure</h2>
SELECT
  datname,
  numbackends,
  xact_commit,
  xact_rollback,
  round(100.0 * xact_rollback / nullif(xact_commit + xact_rollback, 0), 2) AS rollback_pct,
  round(100.0 * blks_hit / nullif(blks_hit + blks_read, 0), 2) AS buffer_hit_pct,
  round(temp_bytes::numeric / 1048576, 2) AS temp_written_mb,
  deadlocks,
  make_interval(secs => coalesce(session_time, 0) / 1000.0) AS session_time,
  make_interval(secs => coalesce(active_time, 0) / 1000.0) AS active_time,
  make_interval(secs => coalesce(idle_in_transaction_time, 0) / 1000.0) AS idle_in_transaction_time,
  sessions,
  sessions_fatal,
  tup_returned,
  tup_fetched,
  tup_inserted,
  tup_updated,
  tup_deleted
FROM pg_stat_database
WHERE datname IS NOT NULL
  AND datname NOT IN ('template0', 'template1')
ORDER BY numbackends DESC, xact_commit DESC;
\qecho </section>

\if :has_pgss
\qecho <section><h2>6. Top SQL from pg_stat_statements</h2>
SELECT
  queryid,
  calls,
  round(total_exec_time::numeric, 2) AS total_exec_ms,
  round(mean_exec_time::numeric, 2) AS mean_exec_ms,
  rows,
  round(100.0 * shared_blks_hit / nullif(shared_blks_hit + shared_blks_read, 0), 2) AS shared_hit_pct,
  round(temp_blks_written::numeric * current_setting('block_size')::numeric / 1048576, 2) AS temp_written_mb,
  left(regexp_replace(coalesce(query, ''), '\s+', ' ', 'g'), 320) AS query_text
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT :top_sql;
\qecho </section>
\else
\qecho <section><h2>6. Top SQL from pg_stat_statements</h2><p class="muted">pg_stat_statements is not installed in this database, so statement-level aggregation is unavailable in this report.</p></section>
\endif

\qecho <section><h2>7. Table churn, bloat proxies, and stale stats</h2>
SELECT
  schemaname,
  relname,
  pg_size_pretty(pg_table_size(format('%I.%I', schemaname, relname)::regclass)) AS table_size,
  pg_size_pretty(pg_indexes_size(format('%I.%I', schemaname, relname)::regclass)) AS indexes_size,
  n_live_tup,
  n_dead_tup,
  round(100.0 * n_dead_tup / nullif(n_live_tup + n_dead_tup, 0), 2) AS dead_tuple_pct,
  (n_tup_ins + n_tup_upd + n_tup_del) AS writes,
  round(100.0 * n_tup_hot_upd / nullif(n_tup_upd, 0), 2) AS hot_update_pct,
  n_mod_since_analyze,
  last_autovacuum,
  last_autoanalyze
FROM pg_stat_user_tables
ORDER BY (n_tup_ins + n_tup_upd + n_tup_del) DESC, n_dead_tup DESC
LIMIT :top_tables;
\qecho </section>

\qecho <section><h2>8. Vacuum progress and maintenance gaps</h2>
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

SELECT
  schemaname,
  relname,
  n_live_tup,
  n_dead_tup,
  n_mod_since_analyze,
  last_vacuum,
  last_autovacuum,
  last_analyze,
  last_autoanalyze
FROM pg_stat_user_tables
WHERE last_autovacuum IS NULL
   OR last_autoanalyze IS NULL
   OR n_mod_since_analyze > 100000
ORDER BY n_mod_since_analyze DESC, n_dead_tup DESC
LIMIT :top_tables;
\qecho </section>

\qecho <section><h2>9. Checkpointer and background writer</h2>
\if :has_checkpointer
SELECT
  cp.num_timed AS checkpoints_timed,
  cp.num_requested AS checkpoints_requested,
  cp.write_time AS checkpoint_write_time_ms,
  cp.sync_time AS checkpoint_sync_time_ms,
  cp.buffers_written AS buffers_checkpoint,
  bg.buffers_clean,
  bg.maxwritten_clean,
  bg.buffers_alloc,
  coalesce(cp.stats_reset, bg.stats_reset) AS stats_reset
FROM pg_stat_checkpointer AS cp
CROSS JOIN pg_stat_bgwriter AS bg;
\else
SELECT
  checkpoints_timed,
  checkpoints_req AS checkpoints_requested,
  checkpoint_write_time AS checkpoint_write_time_ms,
  checkpoint_sync_time AS checkpoint_sync_time_ms,
  buffers_checkpoint,
  buffers_clean,
  maxwritten_clean,
  buffers_alloc,
  stats_reset
FROM pg_stat_bgwriter;
\endif
\qecho </section>

\qecho <section><h2>10. Replication posture</h2>
SELECT
  application_name,
  coalesce(client_addr::text, 'local') AS client_addr,
  state,
  sync_state,
  write_lag,
  flush_lag,
  replay_lag,
  sent_lsn,
  write_lsn,
  flush_lsn,
  replay_lsn
FROM pg_stat_replication
ORDER BY application_name;

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
\qecho </section>

\qecho <section><h2>11. Parameter review</h2>
SELECT * FROM (
  VALUES
    ('shared_preload_libraries', current_setting('shared_preload_libraries'), 'must include pg_stat_statements', CASE WHEN current_setting('shared_preload_libraries') LIKE '%pg_stat_statements%' THEN 'ok' ELSE 'critical' END),
    ('track_io_timing', current_setting('track_io_timing'), 'on', CASE WHEN current_setting('track_io_timing') = 'on' THEN 'ok' ELSE 'warning' END),
    ('autovacuum', current_setting('autovacuum'), 'on', CASE WHEN current_setting('autovacuum') = 'on' THEN 'ok' ELSE 'critical' END),
    ('idle_in_transaction_session_timeout', current_setting('idle_in_transaction_session_timeout'), 'greater than 0', CASE WHEN current_setting('idle_in_transaction_session_timeout') <> '0' THEN 'ok' ELSE 'warning' END),
    ('lock_timeout', current_setting('lock_timeout'), 'greater than 0 for ops sessions', CASE WHEN current_setting('lock_timeout') <> '0' THEN 'ok' ELSE 'warning' END),
    ('log_lock_waits', current_setting('log_lock_waits'), 'on', CASE WHEN current_setting('log_lock_waits') = 'on' THEN 'ok' ELSE 'warning' END),
    ('log_min_duration_statement', current_setting('log_min_duration_statement'), 'set to a real threshold', CASE WHEN current_setting('log_min_duration_statement') <> '-1' THEN 'ok' ELSE 'warning' END),
    ('rds.force_ssl', coalesce(current_setting('rds.force_ssl', true), '(not exposed)'), '1', CASE WHEN coalesce(current_setting('rds.force_ssl', true), '1') = '1' THEN 'ok' ELSE 'critical' END)
) AS review(setting_name, current_value, expected_state, severity)
ORDER BY CASE severity WHEN 'critical' THEN 1 WHEN 'warning' THEN 2 ELSE 3 END, setting_name;
\qecho </section>

\qecho <section><h2>12. How to read this report</h2>
\qecho <p class="muted">Start with sections 2, 3, and 4 for live pressure and blockers. Use section 6 for top SQL if <code>pg_stat_statements</code> is available. Use sections 7 and 8 to identify churn-heavy tables, dead-tuple buildup, and stale stats. Correlate the findings with CloudWatch, RDS events, and Performance Insights for host-level and instance-level signals.</p>
\qecho </section>
\qecho </body>
\qecho </html>
\o
