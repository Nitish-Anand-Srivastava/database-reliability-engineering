\set ON_ERROR_STOP on
\pset pager off
\pset border 1
\pset footer off
\pset format html
\pset tableattr 'class="report-table"'

\if :{?report_file}
\else
\set report_file or_postgres_configuration_gap_report.html
\endif

\if :{?top_tables}
\else
\set top_tables 30
\endif

\qecho <!DOCTYPE html>
\o :report_file
\qecho <html lang="en">
\qecho <head>
\qecho <meta charset="utf-8">
\qecho <title>Postgres Configuration Gap Report</title>
\qecho <style>
\qecho body { font-family: Arial, Helvetica, sans-serif; margin: 24px; background: #0b1020; color: #e5e7eb; }
\qecho h1, h2, h3 { color: #f8fafc; }
\qecho section { margin-bottom: 28px; padding: 16px; background: #111827; border: 1px solid #1f2937; border-radius: 10px; }
\qecho .report-table { width: 100%; border-collapse: collapse; font-size: 13px; margin-top: 12px; }
\qecho .report-table th, .report-table td { border: 1px solid #334155; padding: 8px 10px; text-align: left; vertical-align: top; }
\qecho .report-table th { background: #1e293b; }
\qecho .muted { color: #cbd5e1; }
\qecho </style>
\qecho </head>
\qecho <body>
\qecho <h1>Postgres Configuration Gap Report</h1>
\qecho <p class="muted">This report highlights configuration anomalies and table-level maintenance risks for Aurora PostgreSQL / RDS PostgreSQL without creating persistent objects.</p>

\qecho <section><h2>1. Environment overview</h2>
SELECT
  now() AS generated_at,
  current_database() AS database_name,
  current_setting('server_version') AS server_version,
  current_setting('rds.extensions', true) AS rds_extensions,
  age(clock_timestamp(), pg_postmaster_start_time()) AS uptime,
  current_setting('max_connections') AS max_connections,
  current_setting('shared_buffers') AS shared_buffers,
  current_setting('work_mem') AS work_mem,
  current_setting('effective_cache_size') AS effective_cache_size,
  current_setting('autovacuum') AS autovacuum,
  current_setting('track_io_timing') AS track_io_timing,
  current_setting('default_statistics_target') AS default_statistics_target;
\qecho </section>

\qecho <section><h2>2. Parameter gap review</h2>
SELECT * FROM (
  VALUES
    ('critical', 'shared_preload_libraries', current_setting('shared_preload_libraries'), 'must include pg_stat_statements', CASE WHEN current_setting('shared_preload_libraries') LIKE '%pg_stat_statements%' THEN 'pg_stat_statements preload is enabled.' ELSE 'Add pg_stat_statements to shared_preload_libraries and reboot the instance.' END),
    ('warning', 'track_io_timing', current_setting('track_io_timing'), 'on', CASE WHEN current_setting('track_io_timing') = 'on' THEN 'IO timing is enabled.' ELSE 'Turn on track_io_timing so query and IO latency can be attributed correctly.' END),
    ('warning', 'log_temp_files', current_setting('log_temp_files'), '0 or a practical threshold during investigations', CASE WHEN current_setting('log_temp_files') <> '-1' THEN 'Temporary file logging is active.' ELSE 'Enable log_temp_files when investigating work_mem spills and temp-heavy queries.' END),
    ('warning', 'log_lock_waits', current_setting('log_lock_waits'), 'on', CASE WHEN current_setting('log_lock_waits') = 'on' THEN 'Lock wait logging is enabled.' ELSE 'Enable log_lock_waits so transient blockers leave evidence in logs.' END),
    ('warning', 'log_autovacuum_min_duration', current_setting('log_autovacuum_min_duration'), 'not -1', CASE WHEN current_setting('log_autovacuum_min_duration') <> '-1' THEN 'Autovacuum logging is active.' ELSE 'Enable log_autovacuum_min_duration so maintenance stalls and wraparound risk are visible.' END),
    ('warning', 'idle_in_transaction_session_timeout', current_setting('idle_in_transaction_session_timeout'), 'greater than 0', CASE WHEN current_setting('idle_in_transaction_session_timeout') <> '0' THEN 'Idle transactions are bounded.' ELSE 'Set idle_in_transaction_session_timeout to reduce vacuum and lock damage from stalled sessions.' END),
    ('warning', 'statement_timeout', current_setting('statement_timeout'), 'set intentionally per workload', CASE WHEN current_setting('statement_timeout') <> '0' THEN 'A statement timeout is configured.' ELSE 'No global statement timeout is configured; make sure this is an intentional design choice.' END),
    ('warning', 'lock_timeout', current_setting('lock_timeout'), 'greater than 0 for operational sessions', CASE WHEN current_setting('lock_timeout') <> '0' THEN 'Lock waits are bounded.' ELSE 'Consider non-zero lock_timeout for operational change sessions and maintenance tooling.' END),
    ('warning', 'default_statistics_target', current_setting('default_statistics_target'), '100 or higher for complex workloads', CASE WHEN current_setting('default_statistics_target')::integer >= 100 THEN 'Statistics target is at or above the common baseline.' ELSE 'Default statistics target is low; complex skewed workloads may benefit from a higher baseline or per-column tuning.' END),
    ('warning', 'autovacuum_vacuum_scale_factor', current_setting('autovacuum_vacuum_scale_factor'), 'review for large write-heavy tables', CASE WHEN current_setting('autovacuum_vacuum_scale_factor')::numeric <= 0.10 THEN 'Global vacuum scale factor is already tighter than the common default.' ELSE 'Default-style scale factors can be too lax for large write-heavy tables; validate large-table reloptions.' END),
    ('warning', 'autovacuum_analyze_scale_factor', current_setting('autovacuum_analyze_scale_factor'), 'review for large write-heavy tables', CASE WHEN current_setting('autovacuum_analyze_scale_factor')::numeric <= 0.05 THEN 'Analyze scale factor is relatively aggressive.' ELSE 'Large write-heavy tables may need lower analyze thresholds to keep planner stats fresh.' END),
    ('critical', 'autovacuum', current_setting('autovacuum'), 'on', CASE WHEN current_setting('autovacuum') = 'on' THEN 'Autovacuum is enabled.' ELSE 'Autovacuum must remain enabled in production PostgreSQL estates.' END),
    ('critical', 'track_counts', current_setting('track_counts'), 'on', CASE WHEN current_setting('track_counts') = 'on' THEN 'Statistics collection for autovacuum is enabled.' ELSE 'track_counts must be enabled or autovacuum cannot target tables correctly.' END),
    ('critical', 'rds.force_ssl', coalesce(current_setting('rds.force_ssl', true), '(not exposed)'), '1', CASE WHEN coalesce(current_setting('rds.force_ssl', true), '1') = '1' THEN 'SSL enforcement is enabled or managed outside visible settings.' ELSE 'Enable rds.force_ssl for production RDS/Aurora PostgreSQL estates.' END),
    ('warning', 'password_encryption', current_setting('password_encryption'), 'scram-sha-256', CASE WHEN current_setting('password_encryption') = 'scram-sha-256' THEN 'SCRAM is configured for new password hashes.' ELSE 'Move password_encryption to scram-sha-256 unless compatibility constraints prevent it.' END)
) AS review(severity, setting_name, current_value, expected_state, observation)
ORDER BY CASE severity WHEN 'critical' THEN 1 WHEN 'warning' THEN 2 ELSE 3 END, setting_name;
\qecho </section>

\qecho <section><h2>3. Tables with autovacuum disabled or risky reloptions</h2>
WITH table_options AS (
  SELECT
    c.oid,
    n.nspname AS schemaname,
    c.relname,
    pg_table_size(c.oid) AS table_bytes,
    st.n_live_tup,
    st.n_dead_tup,
    st.n_mod_since_analyze,
    st.last_autovacuum,
    st.last_autoanalyze,
    coalesce(max(CASE WHEN opt.option_name = 'autovacuum_enabled' THEN opt.option_value END), 'true') AS autovacuum_enabled,
    coalesce(max(CASE WHEN opt.option_name = 'toast.autovacuum_enabled' THEN opt.option_value END), 'true') AS toast_autovacuum_enabled,
    max(CASE WHEN opt.option_name = 'autovacuum_vacuum_scale_factor' THEN opt.option_value END) AS table_vacuum_scale_factor,
    max(CASE WHEN opt.option_name = 'autovacuum_analyze_scale_factor' THEN opt.option_value END) AS table_analyze_scale_factor,
    coalesce(max(CASE WHEN opt.option_name = 'fillfactor' THEN opt.option_value END), '100') AS fillfactor
  FROM pg_class AS c
  JOIN pg_namespace AS n
    ON n.oid = c.relnamespace
  JOIN pg_stat_user_tables AS st
    ON st.relid = c.oid
  LEFT JOIN LATERAL pg_options_to_table(c.reloptions) AS opt
    ON true
  WHERE c.relkind = 'r'
  GROUP BY c.oid, n.nspname, c.relname, st.n_live_tup, st.n_dead_tup, st.n_mod_since_analyze, st.last_autovacuum, st.last_autoanalyze
)
SELECT
  CASE
    WHEN autovacuum_enabled = 'false' THEN 'critical'
    WHEN toast_autovacuum_enabled = 'false' THEN 'warning'
    WHEN table_bytes >= 10737418240 AND coalesce(table_vacuum_scale_factor, current_setting('autovacuum_vacuum_scale_factor'))::numeric > 0.10 THEN 'warning'
    WHEN table_bytes >= 10737418240 AND coalesce(table_analyze_scale_factor, current_setting('autovacuum_analyze_scale_factor'))::numeric > 0.05 THEN 'warning'
    ELSE 'info'
  END AS severity,
  schemaname,
  relname,
  pg_size_pretty(table_bytes) AS table_size,
  autovacuum_enabled,
  toast_autovacuum_enabled,
  coalesce(table_vacuum_scale_factor, '(cluster default)') AS vacuum_scale_factor,
  coalesce(table_analyze_scale_factor, '(cluster default)') AS analyze_scale_factor,
  fillfactor,
  n_live_tup,
  n_dead_tup,
  n_mod_since_analyze,
  last_autovacuum,
  last_autoanalyze
FROM table_options
WHERE autovacuum_enabled = 'false'
   OR toast_autovacuum_enabled = 'false'
   OR (table_bytes >= 10737418240 AND coalesce(table_vacuum_scale_factor, current_setting('autovacuum_vacuum_scale_factor'))::numeric > 0.10)
   OR (table_bytes >= 10737418240 AND coalesce(table_analyze_scale_factor, current_setting('autovacuum_analyze_scale_factor'))::numeric > 0.05)
ORDER BY
  CASE
    WHEN autovacuum_enabled = 'false' THEN 1
    WHEN toast_autovacuum_enabled = 'false' THEN 2
    ELSE 3
  END,
  table_bytes DESC
LIMIT :top_tables;
\qecho </section>

\qecho <section><h2>4. HOT / fillfactor anomalies</h2>
WITH table_options AS (
  SELECT
    st.relid,
    st.schemaname,
    st.relname,
    pg_table_size(st.relid) AS table_bytes,
    st.n_tup_upd,
    st.n_tup_hot_upd,
    st.n_dead_tup,
    coalesce(max(CASE WHEN opt.option_name = 'fillfactor' THEN opt.option_value END), '100')::integer AS fillfactor
  FROM pg_stat_user_tables AS st
  LEFT JOIN pg_class AS c
    ON c.oid = st.relid
  LEFT JOIN LATERAL pg_options_to_table(c.reloptions) AS opt
    ON true
  GROUP BY st.relid, st.schemaname, st.relname, st.n_tup_upd, st.n_tup_hot_upd, st.n_dead_tup
)
SELECT
  CASE
    WHEN n_tup_upd >= 100000 AND fillfactor >= 100 THEN 'warning'
    WHEN n_tup_upd >= 100000 AND round(100.0 * n_tup_hot_upd / nullif(n_tup_upd, 0), 2) < 50 THEN 'warning'
    ELSE 'info'
  END AS severity,
  schemaname,
  relname,
  pg_size_pretty(table_bytes) AS table_size,
  n_tup_upd,
  n_tup_hot_upd,
  round(100.0 * n_tup_hot_upd / nullif(n_tup_upd, 0), 2) AS hot_update_pct,
  fillfactor,
  n_dead_tup,
  CASE
    WHEN n_tup_upd >= 100000 AND fillfactor >= 100 THEN 'High update volume with fillfactor 100 reduces headroom for HOT updates.'
    WHEN n_tup_upd >= 100000 AND round(100.0 * n_tup_hot_upd / nullif(n_tup_upd, 0), 2) < 50 THEN 'Update-heavy table has poor HOT ratio; review fillfactor and indexed columns touched by updates.'
    ELSE 'Review in workload context.'
  END AS observation
FROM table_options
WHERE n_tup_upd >= 10000
ORDER BY n_tup_upd DESC, table_bytes DESC
LIMIT :top_tables;
\qecho </section>

\qecho <section><h2>5. Dead tuple and autovacuum lag anomalies</h2>
SELECT
  CASE
    WHEN n_dead_tup >= 1000000 AND last_autovacuum IS NULL THEN 'critical'
    WHEN n_dead_tup >= 1000000 THEN 'warning'
    WHEN round(100.0 * n_dead_tup / nullif(n_live_tup + n_dead_tup, 0), 2) >= 20 THEN 'warning'
    ELSE 'info'
  END AS severity,
  schemaname,
  relname,
  pg_size_pretty(pg_table_size(relid)) AS table_size,
  n_live_tup,
  n_dead_tup,
  round(100.0 * n_dead_tup / nullif(n_live_tup + n_dead_tup, 0), 2) AS dead_tuple_pct,
  n_mod_since_analyze,
  last_autovacuum,
  last_autoanalyze,
  CASE
    WHEN n_dead_tup >= 1000000 AND last_autovacuum IS NULL THEN 'Heavy dead-tuple buildup with no recorded autovacuum.'
    WHEN n_dead_tup >= 1000000 THEN 'Heavy dead-tuple buildup; inspect blockers, autovacuum throughput, and storage pressure.'
    WHEN round(100.0 * n_dead_tup / nullif(n_live_tup + n_dead_tup, 0), 2) >= 20 THEN 'Dead tuples exceed 20% of visible rows; review update/delete patterns and vacuum cadence.'
    ELSE 'Review in workload context.'
  END AS observation
FROM pg_stat_user_tables
WHERE n_dead_tup > 100000
ORDER BY n_dead_tup DESC, n_mod_since_analyze DESC
LIMIT :top_tables;
\qecho </section>

\qecho <section><h2>6. Stale statistics and analyze gaps</h2>
SELECT
  CASE
    WHEN last_autoanalyze IS NULL AND n_mod_since_analyze > 100000 THEN 'critical'
    WHEN n_mod_since_analyze > 100000 THEN 'warning'
    ELSE 'info'
  END AS severity,
  schemaname,
  relname,
  pg_size_pretty(pg_table_size(relid)) AS table_size,
  n_live_tup,
  n_mod_since_analyze,
  last_analyze,
  last_autoanalyze,
  CASE
    WHEN last_autoanalyze IS NULL AND n_mod_since_analyze > 100000 THEN 'Large modification count with no recorded autoanalyze.'
    WHEN n_mod_since_analyze > 100000 THEN 'Planner stats may be stale for this table.'
    ELSE 'Review in workload context.'
  END AS observation
FROM pg_stat_user_tables
WHERE n_mod_since_analyze > 10000
ORDER BY n_mod_since_analyze DESC, pg_table_size(relid) DESC
LIMIT :top_tables;
\qecho </section>

\qecho <section><h2>7. Freeze age and wraparound risk</h2>
SELECT
  CASE
    WHEN age(c.relfrozenxid) >= current_setting('autovacuum_freeze_max_age')::bigint * 0.80 THEN 'critical'
    WHEN age(c.relfrozenxid) >= current_setting('autovacuum_freeze_max_age')::bigint * 0.60 THEN 'warning'
    ELSE 'info'
  END AS severity,
  n.nspname AS schemaname,
  c.relname,
  pg_size_pretty(pg_table_size(c.oid)) AS table_size,
  age(c.relfrozenxid) AS relfrozenxid_age,
  current_setting('autovacuum_freeze_max_age') AS freeze_max_age,
  round(100.0 * age(c.relfrozenxid) / current_setting('autovacuum_freeze_max_age')::numeric, 2) AS freeze_consumed_pct
FROM pg_class AS c
JOIN pg_namespace AS n
  ON n.oid = c.relnamespace
WHERE c.relkind = 'r'
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY freeze_consumed_pct DESC, pg_table_size(c.oid) DESC
LIMIT :top_tables;
\qecho </section>

\qecho <section><h2>8. Large tables still using default-style vacuum/analyze thresholds</h2>
WITH table_options AS (
  SELECT
    c.oid,
    n.nspname AS schemaname,
    c.relname,
    pg_table_size(c.oid) AS table_bytes,
    st.n_tup_ins,
    st.n_tup_upd,
    st.n_tup_del,
    coalesce(max(CASE WHEN opt.option_name = 'autovacuum_vacuum_scale_factor' THEN opt.option_value END), current_setting('autovacuum_vacuum_scale_factor'))::numeric AS vacuum_scale_factor,
    coalesce(max(CASE WHEN opt.option_name = 'autovacuum_analyze_scale_factor' THEN opt.option_value END), current_setting('autovacuum_analyze_scale_factor'))::numeric AS analyze_scale_factor
  FROM pg_class AS c
  JOIN pg_namespace AS n
    ON n.oid = c.relnamespace
  JOIN pg_stat_user_tables AS st
    ON st.relid = c.oid
  LEFT JOIN LATERAL pg_options_to_table(c.reloptions) AS opt
    ON true
  WHERE c.relkind = 'r'
  GROUP BY c.oid, n.nspname, c.relname, st.n_tup_ins, st.n_tup_upd, st.n_tup_del
)
SELECT
  CASE
    WHEN table_bytes >= 21474836480 AND (n_tup_ins + n_tup_upd + n_tup_del) >= 100000 AND vacuum_scale_factor > 0.10 THEN 'warning'
    WHEN table_bytes >= 21474836480 AND (n_tup_ins + n_tup_upd + n_tup_del) >= 100000 AND analyze_scale_factor > 0.05 THEN 'warning'
    ELSE 'info'
  END AS severity,
  schemaname,
  relname,
  pg_size_pretty(table_bytes) AS table_size,
  (n_tup_ins + n_tup_upd + n_tup_del) AS writes,
  vacuum_scale_factor,
  analyze_scale_factor,
  'Large write-heavy tables often need tighter per-table thresholds than cluster defaults.' AS observation
FROM table_options
WHERE table_bytes >= 5368709120
ORDER BY table_bytes DESC, writes DESC
LIMIT :top_tables;
\qecho </section>

\qecho <section><h2>9. Interpreting anomalies</h2>
\qecho <p class="muted">Treat critical rows as immediate action items. Warning rows indicate settings or table posture that commonly drive poor performance, bloat, stale plans, or maintenance lag in Aurora PostgreSQL environments. Always correlate these findings with CloudWatch, Performance Insights, and RDS events before changing parameters.</p>
\qecho </section>
\qecho </body>
\qecho </html>
\o
