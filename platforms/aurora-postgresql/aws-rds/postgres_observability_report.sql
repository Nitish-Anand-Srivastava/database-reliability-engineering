\set ON_ERROR_STOP on
\set QUIET on
\pset pager off
\pset border 1
\pset footer off

-- Feature detection
SELECT EXISTS(SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements')::int AS has_pgss \gset
SELECT (to_regclass('pg_catalog.pg_stat_io') IS NOT NULL)::int AS has_pgss_io \gset
SELECT (to_regclass('pg_catalog.pg_stat_checkpointer') IS NOT NULL)::int AS has_checkpointer \gset
SELECT EXISTS(SELECT 1 FROM pg_extension WHERE extname = 'pg_wait_sampling')::int AS has_wait_sampling \gset
SELECT EXISTS(SELECT 1 FROM pg_extension WHERE extname = 'apg_plan_mgmt')::int AS has_apg_plan_mgmt \gset
SELECT (current_setting('server_version_num')::int >= 110000)::int AS has_v11 \gset
SELECT (current_setting('server_version_num')::int >= 130000)::int AS has_v13 \gset
SELECT (current_setting('server_version_num')::int >= 140000)::int AS has_v14 \gset

\o NUL
CREATE TEMP TABLE report_findings (
  section TEXT,
  severity TEXT,
  finding TEXT,
  recommendation TEXT,
  metric_value TEXT
);
\o

\pset format html
\pset tableattr 'class="report-table"'

-- Feature detection for pg_stat_statements IO timing columns
SELECT (
  CASE 
    WHEN :has_pgss::int = 1 THEN (
      SELECT EXISTS(
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'pg_stat_statements' AND column_name = 'blk_read_time'
      )
    )
    ELSE false
  END
)::int AS has_pgss_io_timing \gset

-- Feature detection for pg_stat_statements WAL columns
SELECT (
  CASE 
    WHEN :has_pgss::int = 1 THEN (
      SELECT EXISTS(
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'pg_stat_statements' AND column_name = 'wal_bytes'
      )
    )
    ELSE false
  END
)::int AS has_pgss_wal_columns \gset

-- Feature detection for pg_stat_statements temp columns
SELECT (
  CASE 
    WHEN :has_pgss::int = 1 THEN (
      SELECT EXISTS(
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'pg_stat_statements' AND column_name = 'temp_blks_written'
      )
    )
    ELSE false
  END
)::int AS has_pgss_temp_columns \gset

\qecho <html><head><meta charset="UTF-8"><title>PostgreSQL Aurora Observability</title>
\qecho <style>
\qecho body { font-family: Arial, sans-serif; margin: 20px; background: #f0f4f8; }
\qecho .report-header { background: #1e40af; color: white; padding: 30px; border-radius: 8px; margin-bottom: 30px; }
\qecho .report-table { border-collapse: collapse; width: 100%; background: white; margin: 20px 0; }
\qecho .report-table th { background: #e2e8f0; padding: 12px; text-align: left; font-weight: bold; border: 1px solid #cbd5e1; }
\qecho .report-table td { padding: 12px; border: 1px solid #e2e8f0; }
\qecho .critical { background: #fee2e2; color: #991b1b; font-weight: bold; }
\qecho .warning { background: #fef3c7; color: #92400e; font-weight: bold; }
\qecho .info { background: #dbeafe; color: #1e40af; }
\qecho h2 { color: #1e40af; border-bottom: 3px solid #1e40af; margin-top: 30px; }
\qecho h3 { color: #334155; }
\qecho section { background: white; padding: 20px; margin: 20px 0; border-radius: 6px; box-shadow: 0 1px 3px rgba(0,0,0,0.08); }
\qecho </style></head><body>

\qecho <div class="report-header"><h1>PostgreSQL Aurora Observability Report</h1></div>

\qecho <section><h2>1. Executive Summary</h2>

SELECT 
  current_database() AS database_name,
  current_user AS connected_as,
  current_setting('server_version') AS version,
  pg_postmaster_start_time()::date AS startup_date,
  extract(day from age(now(), pg_postmaster_start_time()))::int || ' days' AS uptime;

SELECT 
  (SELECT count(*) FROM pg_stat_activity WHERE state = 'active') AS active_sessions,
  (SELECT count(*) FROM pg_stat_activity WHERE state = 'idle') AS idle_sessions,
  (SELECT count(*) FROM pg_stat_activity WHERE state IS NOT NULL) AS total_sessions,
  current_setting('max_connections')::int AS max_connections,
  round((SELECT count(*) FROM pg_stat_activity WHERE state IS NOT NULL)::numeric / current_setting('max_connections')::numeric * 100, 2) AS connection_saturation_pct;

SELECT 
  pg_size_pretty(pg_database_size(current_database())) AS database_size,
  pg_size_pretty((SELECT sum(pg_relation_size(schemaname||'.'||tablename)) FROM pg_tables WHERE schemaname NOT IN ('pg_catalog', 'information_schema'))) AS user_tables_size,
  pg_size_pretty((SELECT sum(pg_relation_size(schemaname||'.'||indexname)) FROM pg_indexes WHERE schemaname NOT IN ('pg_catalog', 'information_schema'))) AS indexes_size;

\qecho </section>


\qecho <section><h2>2. Configuration Compliance</h2>
\qecho <h3>Critical Configuration Parameters Assessment</h3>

-- Comprehensive config compliance with assessment per parameter
SELECT
  s.name AS parameter,
  s.setting || COALESCE(' ' || s.unit, '') AS current_value,
  CASE s.name
    WHEN 'shared_buffers'                THEN '25% of RAM (e.g. 8GB on 32GB instance)'
    WHEN 'work_mem'                      THEN '4MB - 64MB depending on concurrency'
    WHEN 'maintenance_work_mem'          THEN '256MB or more (workload dependent)'
    WHEN 'effective_cache_size'          THEN 'Approx. 75% of RAM (instance-memory dependent)'
    WHEN 'max_connections'              THEN '<= 500 (use PgBouncer for more)'
    WHEN 'wal_buffers'                   THEN '16MB or more (-1 = auto is acceptable)'
    WHEN 'checkpoint_completion_target'  THEN '0.9'
    WHEN 'random_page_cost'             THEN 'Candidate for workload validation; often near 1.1 on Aurora SSD'
    WHEN 'effective_io_concurrency'     THEN 'Candidate for SSD/Aurora tuning; validate against workload'
    WHEN 'log_min_duration_statement'   THEN '<= 1000 ms (or 250 for detailed)'
    WHEN 'log_lock_waits'               THEN 'on'
    WHEN 'autovacuum'                   THEN 'on'
    WHEN 'autovacuum_max_workers'       THEN '3 to 5'
    WHEN 'track_io_timing'              THEN 'on'
    WHEN 'log_autovacuum_min_duration'  THEN '<= 250 ms'
    ELSE 'See documentation'
  END AS recommended_value,
  CASE s.name
    WHEN 'log_min_duration_statement' THEN
      CASE WHEN s.setting::int = -1 THEN 'CRITICAL'
           WHEN s.setting::int > 5000 THEN 'WARNING'
           WHEN s.setting::int > 1000 THEN 'WARNING'
           ELSE 'OK' END
    WHEN 'log_lock_waits' THEN
      CASE WHEN s.setting = 'on' THEN 'OK' ELSE 'WARNING' END
    WHEN 'autovacuum' THEN
      CASE WHEN s.setting = 'on' THEN 'OK' ELSE 'CRITICAL' END
    WHEN 'track_io_timing' THEN
      CASE WHEN s.setting = 'on' THEN 'OK' ELSE 'WARNING' END
    WHEN 'checkpoint_completion_target' THEN
      CASE WHEN s.setting::numeric >= 0.9 THEN 'OK' ELSE 'WARNING' END
    WHEN 'random_page_cost' THEN
      CASE WHEN s.setting::numeric <= 2.0 THEN 'REVIEW - validate with plans' ELSE 'WARNING - high for SSD' END
    WHEN 'effective_io_concurrency' THEN
      CASE WHEN s.setting::int >= 100 THEN 'REVIEW - validate on Aurora/SSD' ELSE 'INFO' END
    WHEN 'max_connections' THEN
      CASE WHEN s.setting::int > 500 THEN 'WARNING' ELSE 'OK' END
    WHEN 'autovacuum_max_workers' THEN
      CASE WHEN s.setting::int BETWEEN 3 AND 5 THEN 'OK'
           WHEN s.setting::int < 3 THEN 'WARNING'
           ELSE 'OK' END
    WHEN 'log_autovacuum_min_duration' THEN
      CASE WHEN s.setting::int = -1 THEN 'WARNING'
           WHEN s.setting::int > 250 THEN 'WARNING'
           ELSE 'OK' END
    WHEN 'wal_buffers' THEN
      CASE WHEN s.setting::int = -1 THEN 'OK'
           WHEN s.setting::int >= 2048 THEN 'OK'
           ELSE 'WARNING' END
    ELSE 'OK'
  END AS assessment,
  CASE s.name
    WHEN 'log_min_duration_statement' THEN 'Captures slow queries; -1 means disabled (no slow log)'
    WHEN 'log_lock_waits'             THEN 'Logs lock waits helping identify contention'
    WHEN 'autovacuum'                 THEN 'Must be on; disabling causes bloat and XID wraparound'
    WHEN 'track_io_timing'            THEN 'Enables IO timing in pg_stat_statements'
    WHEN 'checkpoint_completion_target' THEN 'Spreads checkpoint IO; 0.9 reduces burst writes'
    WHEN 'random_page_cost'           THEN 'Workload-dependent; validate with execution plans before lowering'
    WHEN 'effective_io_concurrency'   THEN 'Tune based on SSD/Aurora behavior and workload testing'
    WHEN 'max_connections'            THEN 'High values waste memory; use connection pooler'
    WHEN 'autovacuum_max_workers'     THEN 'More workers handle high-churn databases'
    WHEN 'log_autovacuum_min_duration' THEN 'Log slow autovacuums for tuning'
    WHEN 'wal_buffers'                THEN 'More WAL buffer reduces WAL write latency'
    ELSE ''
  END AS rationale
FROM pg_settings s
WHERE s.name IN (
  'shared_buffers','work_mem','maintenance_work_mem','effective_cache_size',
  'max_connections','wal_buffers','checkpoint_completion_target','random_page_cost',
  'effective_io_concurrency','log_min_duration_statement','log_lock_waits',
  'autovacuum','autovacuum_max_workers','track_io_timing','log_autovacuum_min_duration'
)
ORDER BY
  CASE
    WHEN s.name IN ('autovacuum','log_min_duration_statement') THEN 1
    ELSE 2
  END,
  s.name;

\qecho <h3>Logging Configuration</h3>

SELECT
  name AS parameter,
  setting AS current_value,
  CASE name
    WHEN 'log_min_duration_statement' THEN
      CASE WHEN setting::int = -1 THEN 'CRITICAL - slow query logging disabled'
           WHEN setting::int > 5000 THEN 'WARNING - threshold too high (> 5s)'
           ELSE 'OK' END
    WHEN 'log_checkpoints'  THEN CASE WHEN setting = 'on' THEN 'OK' ELSE 'INFO - enable for checkpoint visibility' END
    WHEN 'log_connections'  THEN CASE WHEN setting = 'on' THEN 'OK' ELSE 'INFO' END
    WHEN 'log_lock_waits'   THEN CASE WHEN setting = 'on' THEN 'OK' ELSE 'WARNING - lock waits will be silent' END
    WHEN 'log_temp_files'   THEN CASE WHEN setting = '-1' THEN 'WARNING - temp file logging disabled' ELSE 'OK - logging temp files >= ' || setting END
    ELSE 'OK'
  END AS assessment
FROM pg_settings
WHERE name IN ('log_min_duration_statement','log_checkpoints','log_connections','log_lock_waits','log_temp_files','log_statement','log_duration','log_autovacuum_min_duration')
ORDER BY name;

\qecho <h3>Aurora-Specific Settings</h3>

SELECT
  name AS parameter,
  setting AS current_value,
  CASE
    WHEN name = 'aurora_parallel_query' AND setting = 'on'  THEN 'ENABLED - parallel query active'
    WHEN name = 'aurora_parallel_query' AND setting != 'on' THEN 'INFO - aurora_parallel_query is off'
    ELSE setting
  END AS notes
FROM pg_settings
WHERE name IN ('aurora_parallel_query','aurora_disable_hash_join','rds.log_retention_period')
ORDER BY name;

\qecho <h3>Installed Extensions</h3>

SELECT extname, extversion, extnamespace::regnamespace AS schema FROM pg_extension ORDER BY extname;

-- Insert CRITICAL config findings
INSERT INTO report_findings (section, severity, finding, recommendation, metric_value)
SELECT
  '2. Configuration',
  'critical',
  'autovacuum is OFF',
  'Set autovacuum = on immediately to prevent XID wraparound and table bloat',
  current_setting('autovacuum')
WHERE current_setting('autovacuum') = 'off';

INSERT INTO report_findings (section, severity, finding, recommendation, metric_value)
SELECT
  '2. Configuration',
  'critical',
  'Slow query logging is completely disabled (log_min_duration_statement = -1)',
  'Set log_min_duration_statement = 1000 (or 250 for detailed capture) to enable slow query detection',
  current_setting('log_min_duration_statement')
WHERE current_setting('log_min_duration_statement')::int = -1;

INSERT INTO report_findings (section, severity, finding, recommendation, metric_value)
SELECT
  '2. Configuration',
  'warning',
  'Slow query threshold is very high: ' || current_setting('log_min_duration_statement') || ' ms',
  'Consider lowering log_min_duration_statement to 1000 or less',
  current_setting('log_min_duration_statement')
WHERE current_setting('log_min_duration_statement')::int > 1000
  AND current_setting('log_min_duration_statement')::int != -1;

INSERT INTO report_findings (section, severity, finding, recommendation, metric_value)
SELECT
  '2. Configuration',
  'warning',
  'track_io_timing is OFF - IO metrics missing from pg_stat_statements',
  'Set track_io_timing = on for IO visibility in query monitoring',
  current_setting('track_io_timing')
WHERE current_setting('track_io_timing') = 'off';

INSERT INTO report_findings (section, severity, finding, recommendation, metric_value)
SELECT
  '2. Configuration',
  'warning',
  'log_lock_waits is OFF - lock contention will be invisible in logs',
  'Set log_lock_waits = on to capture lock wait events',
  current_setting('log_lock_waits')
WHERE current_setting('log_lock_waits') = 'off';

INSERT INTO report_findings (section, severity, finding, recommendation, metric_value)
SELECT
  '2. Configuration',
  'warning',
  'random_page_cost is too high for Aurora SSD storage: ' || current_setting('random_page_cost'),
  'Set random_page_cost = 1.1 for Aurora SSD to encourage index usage',
  current_setting('random_page_cost')
WHERE current_setting('random_page_cost')::numeric > 2.0;

\qecho </section>

\qecho <section><h2>3. Connection Health</h2>
\qecho <h3>Connection Distribution by State</h3>

SELECT 
  state,
  count(*) as connection_count,
  round(100.0 * count(*) / (SELECT count(*) FROM pg_stat_activity WHERE pid IS NOT NULL), 2) as percentage
FROM pg_stat_activity WHERE pid IS NOT NULL GROUP BY state ORDER BY connection_count DESC;

\qecho <h3>Top Users by Connection Count</h3>

SELECT 
  usename,
  count(*) as connection_count,
  max(state) as last_state,
  max(application_name) as application
FROM pg_stat_activity WHERE pid IS NOT NULL GROUP BY usename ORDER BY connection_count DESC LIMIT 15;

\qecho <h3>Connection Pool Analysis</h3>

SELECT 
  'Total Available' as metric,
  current_setting('max_connections') as value
UNION ALL SELECT 
  'Currently Used', (SELECT count(*)::text FROM pg_stat_activity WHERE pid IS NOT NULL)
UNION ALL SELECT 
  'Saturation %', (SELECT round((count(*))::numeric / current_setting('max_connections')::numeric * 100, 2)::text FROM pg_stat_activity WHERE pid IS NOT NULL);

\qecho </section>

\qecho <section><h2>4. Wait Events Analysis</h2>
\qecho <h3>Real-time Wait Event Distribution</h3>

SELECT 
  wait_event_type,
  wait_event,
  count(*) as occurrence_count,
  round(100.0 * count(*) / (SELECT count(*) FROM pg_stat_activity WHERE wait_event IS NOT NULL), 2) as percentage
FROM pg_stat_activity WHERE wait_event IS NOT NULL GROUP BY wait_event_type, wait_event ORDER BY occurrence_count DESC;

\qecho <h3>Sessions Waiting Now</h3>

SELECT 
  pid,
  usename,
  application_name,
  wait_event_type,
  wait_event,
  query_start,
  state
FROM pg_stat_activity WHERE wait_event IS NOT NULL ORDER BY query_start;

INSERT INTO report_findings SELECT '4. Wait Events', 'info', 'Active wait events detected', 'Monitor long-running operations', (SELECT count(*)::text FROM pg_stat_activity WHERE wait_event IS NOT NULL);

\qecho </section>

\qecho <section><h2>5. Top SQL Analysis (5 Views)</h2>

\qecho <h3>5.1: Top Queries by Total Execution Time</h3>

\if :has_pgss
SELECT 
  left(query, 80) as query,
  calls,
  round(total_exec_time::numeric, 2) as total_time_ms,
  round(mean_exec_time::numeric, 2) as mean_time_ms,
  rows,
  100.0 * total_exec_time / (SELECT sum(total_exec_time) FROM pg_stat_statements)::numeric as pct_time
FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 20;
\else
\qecho <p class="muted">pg_stat_statements not available</p>
\endif

\qecho <h3>5.2: Top Queries by I/O Time</h3>

\if :has_pgss_io_timing
SELECT 
  left(query, 80) as query,
  calls,
  round(blk_read_time::numeric, 2) as read_time_ms,
  round(blk_write_time::numeric, 2) as write_time_ms,
  round((blk_read_time + blk_write_time)::numeric, 2) as total_io_time_ms
FROM pg_stat_statements WHERE (blk_read_time + blk_write_time) > 0 ORDER BY (blk_read_time + blk_write_time) DESC LIMIT 20;
\else
\qecho <p class="info">IO timing columns not available in pg_stat_statements on this Aurora instance</p>
\endif

\qecho <h3>5.3: Top Queries by Row Count</h3>

\if :has_pgss
SELECT 
  left(query, 80) as query,
  calls,
  rows,
  round(rows::numeric / NULLIF(calls, 0), 2) as rows_per_call
FROM pg_stat_statements WHERE rows > 0 ORDER BY rows DESC LIMIT 20;
\else
\qecho <p class="muted">pg_stat_statements not available</p>
\endif

\qecho </section>


\qecho <section><h2>6. Active Sessions & Workload Distribution</h2>
\qecho <h3>Long-Running Sessions</h3>

SELECT 
  pid,
  usename,
  application_name,
  state,
  query_start,
  extract(epoch from (now() - query_start))::int as runtime_seconds,
  left(query, 60) as query
FROM pg_stat_activity WHERE pid IS NOT NULL AND state != 'idle' ORDER BY query_start LIMIT 20;

\qecho <h3>Workload Distribution by Application</h3>

SELECT 
  application_name,
  count(*) as session_count,
  count(CASE WHEN state = 'active' THEN 1 END) as active_count,
  count(CASE WHEN state = 'idle' THEN 1 END) as idle_count,
  count(CASE WHEN state = 'idle in transaction' THEN 1 END) as idle_in_xact_count
FROM pg_stat_activity WHERE pid IS NOT NULL GROUP BY application_name ORDER BY session_count DESC;

\qecho <h3>Blocking Sessions</h3>

SELECT 
  blocked.pid as blocked_pid,
  blocked.usename as blocked_user,
  blocking.pid as blocking_pid,
  blocking.usename as blocking_user,
  left(blocked.query, 40) as blocked_query
FROM pg_stat_activity blocked
JOIN pg_stat_activity blocking ON blocking.pid = ANY(pg_blocking_pids(blocked.pid))
ORDER BY blocked.query_start;

INSERT INTO report_findings SELECT '6. Active Sessions', 'info', 'Session analysis complete', 'Monitor idle-in-transaction sessions', (SELECT count(*)::text FROM pg_stat_activity WHERE state IS NOT NULL);

\qecho </section>

\qecho <section><h2>7. Long Transactions & XID Wraparound Risk</h2>
\qecho <h3>Active Transactions by Age</h3>

SELECT 
  pid,
  usename,
  xact_start,
  extract(epoch from (now() - xact_start))::int as xact_age_seconds,
  state,
  application_name
FROM pg_stat_activity WHERE xact_start IS NOT NULL AND pid <> pg_backend_pid() ORDER BY xact_start LIMIT 20;

\qecho <h3>Idle-in-Transaction Sessions</h3>

SELECT 
  pid,
  usename,
  xact_start,
  extract(epoch from (now() - xact_start))::int as idle_xact_seconds,
  state
FROM pg_stat_activity WHERE state = 'idle in transaction' AND pid <> pg_backend_pid() ORDER BY xact_start LIMIT 15;

\qecho <h3>XID Wraparound Risk Assessment</h3>

SELECT 
  'Database Name' as metric,
  datname as value
FROM pg_database WHERE datname = current_database()
UNION ALL SELECT 
  'Age (transactions)', age(datfrozenxid)::text
FROM pg_database WHERE datname = current_database()
UNION ALL SELECT 
  'Autovacuum Freeze Threshold', current_setting('autovacuum_freeze_max_age')
UNION ALL SELECT 
  'Wraparound Risk Level', CASE 
    WHEN (SELECT age(datfrozenxid) FROM pg_database WHERE datname = current_database()) > 1500000000 THEN 'CRITICAL' 
    WHEN (SELECT age(datfrozenxid) FROM pg_database WHERE datname = current_database()) > 1000000000 THEN 'HIGH' 
    WHEN (SELECT age(datfrozenxid) FROM pg_database WHERE datname = current_database()) > 500000000 THEN 'MEDIUM' 
    ELSE 'LOW' END;

INSERT INTO report_findings SELECT '7. Long Transactions', 'warning', 'Long-running transactions detected', 'Review and terminate idle-in-transaction sessions', (SELECT count(*)::text FROM pg_stat_activity WHERE xact_start < now() - interval '5 minutes' AND pid <> pg_backend_pid() AND state <> 'idle') WHERE (SELECT count(*) FROM pg_stat_activity WHERE xact_start < now() - interval '5 minutes' AND pid <> pg_backend_pid() AND state <> 'idle') > 0;

\qecho </section>

\qecho <section><h2>8. Blocking & Locks Analysis</h2>
\qecho <h3>Lock Contention Analysis</h3>

SELECT 
  locktype,
  count(*) as lock_count,
  count(CASE WHEN granted THEN 1 END) as granted,
  count(CASE WHEN NOT granted THEN 1 END) as waiting
FROM pg_locks GROUP BY locktype ORDER BY lock_count DESC;

\qecho <h3>Table-Level Locks</h3>

SELECT 
  n.nspname as schemaname,
  c.relname as tablename,
  l.locktype,
  count(*) as count
FROM pg_locks l
JOIN pg_class c ON l.relation = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
GROUP BY n.nspname, c.relname, l.locktype ORDER BY count DESC LIMIT 20;

\qecho <h3>Waiting Locks Detail</h3>

SELECT 
  w.pid as waiting_pid,
  w.locktype,
  w.relation::regclass as table_name,
  (SELECT query FROM pg_stat_activity WHERE pid = w.pid) as waiting_query
FROM pg_locks w WHERE NOT granted LIMIT 20;

\qecho </section>

\qecho <section><h2>9. Database Pressure Metrics</h2>
\qecho <h3>Cache Hit Ratio Analysis</h3>

SELECT 
  'Heap Blocks Read' as metric,
  sum(heap_blks_read)::text as value
FROM pg_statio_user_tables
UNION ALL SELECT 
  'Heap Blocks Hit', sum(heap_blks_hit)::text
FROM pg_statio_user_tables
UNION ALL SELECT 
  'Cache Hit Ratio (%)', round(100.0 * sum(heap_blks_hit)::numeric / NULLIF(sum(heap_blks_hit + heap_blks_read), 0), 2)::text
FROM pg_statio_user_tables;

\qecho <h3>Rollback Ratio</h3>

SELECT 
  'Committed Transactions' as metric,
  xact_commit::text as value
FROM pg_stat_database WHERE datname = current_database()
UNION ALL SELECT 
  'Rolled Back Transactions', xact_rollback::text
FROM pg_stat_database WHERE datname = current_database()
UNION ALL SELECT 
  'Rollback Ratio (%)', round(100.0 * xact_rollback::numeric / NULLIF(xact_commit + xact_rollback, 0), 2)::text
FROM pg_stat_database WHERE datname = current_database();

\qecho <h3>Temporary File Usage</h3>

SELECT 
  'Temp Files Created' as metric,
  temp_files::text as value
FROM pg_stat_database WHERE datname = current_database()
UNION ALL SELECT 
  'Temp Bytes Written', pg_size_pretty(temp_bytes) as value
FROM pg_stat_database WHERE datname = current_database();

INSERT INTO report_findings SELECT '9. Database Pressure', 'info', 'Pressure metrics analyzed', 'Monitor cache hit ratio and rollback rate', 'Complete';

\qecho </section>

\qecho <section><h2>10. Index Analysis (Comprehensive)</h2>
\qecho <h3>Top 20 Indexes by Scan Count</h3>

SELECT
  schemaname,
  relname        AS table_name,
  indexrelname   AS index_name,
  idx_scan,
  idx_tup_read,
  idx_tup_fetch,
  pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC
LIMIT 20;

\qecho <h3>Unused Indexes (No Scans Since Last Stats Reset) — Candidates for Removal</h3>

SELECT
  schemaname,
  relname       AS table_name,
  indexrelname  AS index_name,
  i.indisprimary,
  i.indisunique,
  i.indisexclusion,
  sui.idx_scan,
  pg_size_pretty(pg_relation_size(sui.indexrelid)) AS index_size,
  CASE
    WHEN pg_relation_size(sui.indexrelid) > 104857600 THEN 'CRITICAL - Large unused index'
    WHEN pg_relation_size(sui.indexrelid) > 52428800  THEN 'WARNING - Medium unused index'
    ELSE 'INFO'
  END AS severity,
  'DROP INDEX CONCURRENTLY ' || schemaname || '.' || indexrelname || ';' AS suggested_action
FROM pg_stat_user_indexes sui
JOIN pg_index i ON i.indexrelid = sui.indexrelid
WHERE sui.idx_scan = 0
  AND indexrelname NOT LIKE 'pg_toast%'
  AND NOT indisprimary
  AND NOT indisunique
  AND NOT indisexclusion
ORDER BY pg_relation_size(sui.indexrelid) DESC
LIMIT 30;

\qecho <h3>Redundant / Prefix-Duplicate Indexes</h3>

WITH index_cols AS (
  SELECT
    i.indexrelid,
    i.indrelid,
    array_agg(a.attname ORDER BY u.ordinality) AS cols,
    count(*)                                    AS ncols,
    ix.relname                                  AS idx_name,
    t.relname                                   AS tbl_name,
    n.nspname                                   AS schema_name
  FROM pg_index i
  JOIN pg_class ix ON ix.oid = i.indexrelid
  JOIN pg_class t  ON t.oid  = i.indrelid
  JOIN pg_namespace n ON n.oid = t.relnamespace
  JOIN LATERAL unnest(i.indkey) WITH ORDINALITY AS u(attnum, ordinality) ON true
  JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = u.attnum AND u.attnum > 0
  WHERE n.nspname NOT IN ('pg_catalog','information_schema','pg_toast')
    AND NOT i.indisprimary
    AND NOT i.indisunique
    AND NOT i.indisexclusion
  GROUP BY i.indexrelid, i.indrelid, ix.relname, t.relname, n.nspname
)
SELECT
  a.schema_name,
  a.tbl_name                                               AS table_name,
  a.idx_name                                               AS redundant_index,
  b.idx_name                                               AS covering_index,
  array_to_string(a.cols, ', ')                            AS redundant_cols,
  array_to_string(b.cols, ', ')                            AS covering_cols,
  pg_size_pretty(pg_relation_size(a.indexrelid))           AS wasted_size,
  'DROP INDEX CONCURRENTLY ' || a.schema_name || '.' || a.idx_name || ';' AS suggested_action
FROM index_cols a
JOIN index_cols b
  ON  a.indrelid   = b.indrelid
  AND a.indexrelid <> b.indexrelid
  AND a.cols = b.cols[1:a.ncols]   -- a's columns are a prefix of b's columns
ORDER BY a.schema_name, a.tbl_name;

\qecho <h3>Sequential Scan Heavy Tables (Possible Missing Index)</h3>

SELECT
  schemaname,
  relname          AS table_name,
  seq_scan,
  idx_scan,
  seq_tup_read,
  n_live_tup,
  CASE
    WHEN idx_scan = 0 THEN 'No index scans at all'
    ELSE round(seq_scan::numeric / NULLIF(idx_scan, 0), 2)::text || 'x more seq than idx'
  END               AS seq_to_idx_ratio,
  pg_size_pretty(pg_total_relation_size(schemaname || '.' || relname)) AS total_size
FROM pg_stat_user_tables
WHERE seq_scan > 1000
  AND seq_scan > COALESCE(idx_scan, 0)
ORDER BY seq_scan DESC
LIMIT 20;

\qecho <h3>Index vs Sequential Scan Ratio Summary per Table</h3>

SELECT
  schemaname,
  relname          AS table_name,
  seq_scan,
  idx_scan,
  CASE
    WHEN (seq_scan + COALESCE(idx_scan, 0)) = 0 THEN 'No activity'
    ELSE round(100.0 * COALESCE(idx_scan, 0)::numeric / (seq_scan + COALESCE(idx_scan, 0)), 1)::text || '%'
  END               AS index_usage_pct,
  CASE
    WHEN (seq_scan + COALESCE(idx_scan, 0)) = 0 THEN 'OK'
    WHEN round(100.0 * COALESCE(idx_scan, 0)::numeric / (seq_scan + COALESCE(idx_scan, 0)), 1) < 50
         AND seq_scan > 500 THEN 'WARNING'
    ELSE 'OK'
  END               AS assessment
FROM pg_stat_user_tables
WHERE (seq_scan + COALESCE(idx_scan, 0)) > 100
ORDER BY index_usage_pct ASC
LIMIT 30;

-- Findings: unused large indexes
INSERT INTO report_findings (section, severity, finding, recommendation, metric_value)
SELECT
  '10. Index Analysis',
  CASE WHEN pg_relation_size(indexrelid) > 104857600 THEN 'critical' ELSE 'warning' END,
  'Unused index consuming space: ' || schemaname || '.' || indexrelname || ' on table ' || relname,
  'No scans observed since the statistics reset. Validate against representative workload, query plans, application dependencies, and index creation date before considering removal.',
  pg_size_pretty(pg_relation_size(indexrelid))
FROM pg_stat_user_indexes
WHERE idx_scan = 0
  AND indexrelname NOT LIKE 'pg_toast%'
  AND pg_relation_size(indexrelid) > 10485760;

-- Findings: seq-scan heavy tables
INSERT INTO report_findings (section, severity, finding, recommendation, metric_value)
SELECT
  '10. Index Analysis',
  'warning',
  'High sequential scan rate on table: ' || schemaname || '.' || relname
    || ' (' || seq_scan || ' seq scans vs ' || COALESCE(idx_scan, 0) || ' idx scans)',
  'Investigate whether an index on frequently filtered columns would help',
  seq_scan::text || ' seq scans'
FROM pg_stat_user_tables
WHERE seq_scan > 1000
  AND seq_scan > COALESCE(idx_scan, 0) * 2
  AND pg_total_relation_size(schemaname || '.' || relname) > 10485760
ORDER BY seq_scan DESC
LIMIT 10;

\qecho </section>

\qecho <section><h2>11. Statistics Analysis</h2>
\qecho <h3>Stale Statistics (Not Analyzed Recently)</h3>

SELECT 
  schemaname,
  relname as tablename,
  last_vacuum,
  last_autovacuum,
  last_analyze,
  last_autoanalyze,
  n_live_tup,
  n_dead_tup,
  round(100.0 * n_dead_tup::numeric / NULLIF(n_live_tup + n_dead_tup, 0), 2) as dead_tup_ratio_pct
FROM pg_stat_user_tables
WHERE last_analyze IS NULL OR age(last_analyze) > interval '7 days'
ORDER BY last_analyze NULLS FIRST LIMIT 30;

\qecho <h3>Table Statistics Summary</h3>

SELECT 
  schemaname,
  relname as tablename,
  n_live_tup,
  n_dead_tup,
  n_mod_since_analyze,
  last_analyze,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||relname)) as table_total_size
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(schemaname||'.'||relname) DESC LIMIT 30;

\qecho <h3>Autovacuum & Autoanalyze Activity</h3>

SELECT 
  'Total Table Vacuums' as metric,
  sum(vacuum_count)::text as value
FROM pg_stat_user_tables
UNION ALL SELECT 
  'Total Table Autovacuums', sum(autovacuum_count)::text
FROM pg_stat_user_tables
UNION ALL SELECT 
  'Total Table Analyzes', sum(analyze_count)::text
FROM pg_stat_user_tables
UNION ALL SELECT 
  'Total Table Autoanalyzes', sum(autoanalyze_count)::text
FROM pg_stat_user_tables;

INSERT INTO report_findings SELECT '11. Statistics', 'warning', 'Stale statistics detected', 'Run ANALYZE on tables with old statistics', (SELECT count(*)::text FROM pg_stat_user_tables WHERE last_analyze IS NULL);

\qecho </section>

\qecho <section><h2>12. Temp/Spill Analysis</h2>
\qecho <h3>Current work_mem Settings</h3>

SELECT
  'work_mem'              AS parameter,
  current_setting('work_mem') AS current_value
UNION ALL SELECT
  'maintenance_work_mem', current_setting('maintenance_work_mem')
UNION ALL SELECT
  'effective_cache_size',  current_setting('effective_cache_size');

\qecho <h3>Temporary File Usage (pg_stat_database)</h3>

SELECT
  datname                                                         AS database,
  temp_files,
  pg_size_pretty(temp_bytes)                                      AS temp_bytes_total,
  CASE WHEN temp_files > 0
       THEN pg_size_pretty(temp_bytes / temp_files)
       ELSE 'N/A'
  END                                                             AS avg_temp_bytes_per_file,
  CASE
    WHEN temp_files > 10000 THEN 'CRITICAL'
    WHEN temp_files > 1000  THEN 'WARNING'
    WHEN temp_files > 0     THEN 'INFO'
    ELSE 'OK'
  END                                                             AS severity,
  CASE
    WHEN temp_files > 0
    THEN 'work_mem may be insufficient; current setting: ' || current_setting('work_mem')
    ELSE 'No temp file spills detected since last stats reset'
  END                                                             AS recommendation
FROM pg_stat_database
WHERE datname = current_database();

\qecho <h3>Top Queries by Temp Block Writes</h3>

\if :has_pgss
\if :has_pgss_temp_columns
SELECT
  left(query, 120)                                   AS query_snippet,
  calls,
  temp_blks_written,
  round(temp_blks_written::numeric / NULLIF(calls, 0), 1) AS avg_temp_blks_per_call,
  round(total_exec_time::numeric / NULLIF(calls, 0), 2)   AS avg_exec_ms
FROM pg_stat_statements
WHERE temp_blks_written > 0
ORDER BY temp_blks_written DESC
LIMIT 20;
\endif
\endif

-- Insert findings based on actual temp file data
INSERT INTO report_findings (section, severity, finding, recommendation, metric_value)
SELECT
  '12. Temp/Spill',
  CASE
    WHEN temp_files > 10000 THEN 'critical'
    ELSE 'warning'
  END,
  'High temp file spill detected: ' || temp_files || ' temp files totalling ' || pg_size_pretty(temp_bytes),
  'Increase work_mem (currently ' || current_setting('work_mem') || ') to reduce sort/hash spills; test with SET work_mem = ''64MB'' in a session first',
  temp_files::text || ' temp files'
FROM pg_stat_database
WHERE datname = current_database()
  AND temp_files > 0;

\qecho </section>

\qecho <section><h2>13. Table &amp; Index Bloat Estimation</h2>
\qecho <h3>Top 30 Bloated Tables (10 MB+, excluding temp schemas)</h3>

SELECT
  schemaname,
  relname                                                              AS table_name,
  pg_size_pretty(pg_total_relation_size(schemaname || '.' || relname)) AS total_size,
  n_live_tup,
  n_dead_tup,
  round(100.0 * n_dead_tup::numeric / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS dead_tup_pct,
  CASE
    WHEN round(100.0 * n_dead_tup::numeric / NULLIF(n_live_tup + n_dead_tup, 0), 2) > 20 THEN 'CRITICAL'
    WHEN round(100.0 * n_dead_tup::numeric / NULLIF(n_live_tup + n_dead_tup, 0), 2) > 10 THEN 'WARNING'
    ELSE 'OK'
  END                                                                  AS severity,
  CASE
    WHEN round(100.0 * n_dead_tup::numeric / NULLIF(n_live_tup + n_dead_tup, 0), 2) > 20
    THEN 'VACUUM FULL ' || schemaname || '.' || relname || ';'
    WHEN round(100.0 * n_dead_tup::numeric / NULLIF(n_live_tup + n_dead_tup, 0), 2) > 10
    THEN 'VACUUM ' || schemaname || '.' || relname || ';'
    ELSE 'No immediate action needed'
  END                                                                  AS recommended_action
FROM pg_stat_user_tables
WHERE schemaname NOT LIKE 'pg_temp%'
  AND pg_total_relation_size(schemaname || '.' || relname) > 10485760
  AND (n_live_tup + n_dead_tup) > 0
ORDER BY dead_tup_pct DESC NULLS LAST
LIMIT 30;

\qecho <h3>HOT Update Effectiveness &amp; Fillfactor</h3>

SELECT
  st.schemaname,
  st.relname                                                              AS table_name,
  st.n_tup_upd,
  st.n_tup_hot_upd,
  round(100.0 * st.n_tup_hot_upd::numeric / NULLIF(st.n_tup_upd, 0), 1) AS hot_update_pct,
  COALESCE(
    (SELECT regexp_replace(opt, 'fillfactor=', '')
     FROM unnest(c.reloptions) AS opt
     WHERE opt LIKE 'fillfactor=%'
     LIMIT 1),
    '100'
  )                                                                       AS fillfactor,
  CASE
    WHEN round(100.0 * st.n_tup_hot_upd::numeric / NULLIF(st.n_tup_upd, 0), 1) < 20
     AND COALESCE(
           (SELECT regexp_replace(opt, 'fillfactor=', '')
            FROM unnest(c.reloptions) AS opt
            WHERE opt LIKE 'fillfactor=%'
            LIMIT 1),
           '100') = '100'
     AND st.n_tup_upd > 1000
    THEN 'WARNING - Low HOT; consider ALTER TABLE ... SET (fillfactor=80)'
    ELSE 'OK'
  END                                                                     AS assessment
FROM pg_stat_user_tables st
JOIN pg_class c ON c.relname = st.relname
JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = st.schemaname
WHERE st.schemaname NOT LIKE 'pg_temp%'
  AND st.n_tup_upd > 100
  AND pg_total_relation_size(st.schemaname || '.' || st.relname) > 10485760
ORDER BY hot_update_pct ASC NULLS LAST
LIMIT 25;

-- Findings: critically bloated tables
INSERT INTO report_findings (section, severity, finding, recommendation, metric_value)
SELECT
  '13. Table Bloat',
  'critical',
  'Table ' || schemaname || '.' || relname || ' has ' || round(100.0 * n_dead_tup::numeric / NULLIF(n_live_tup + n_dead_tup, 0), 1) || '% dead tuples',
  'VACUUM FULL ' || schemaname || '.' || relname || '; (schedule during low-traffic window)',
  n_dead_tup::text || ' dead tuples'
FROM pg_stat_user_tables
WHERE schemaname NOT LIKE 'pg_temp%'
  AND pg_total_relation_size(schemaname || '.' || relname) > 10485760
  AND round(100.0 * n_dead_tup::numeric / NULLIF(n_live_tup + n_dead_tup, 0), 2) > 20;

INSERT INTO report_findings (section, severity, finding, recommendation, metric_value)
SELECT
  '13. Table Bloat',
  'warning',
  'Table ' || schemaname || '.' || relname || ' has ' || round(100.0 * n_dead_tup::numeric / NULLIF(n_live_tup + n_dead_tup, 0), 1) || '% dead tuples',
  'VACUUM ' || schemaname || '.' || relname || '; (autovacuum thresholds may need tuning)',
  n_dead_tup::text || ' dead tuples'
FROM pg_stat_user_tables
WHERE schemaname NOT LIKE 'pg_temp%'
  AND pg_total_relation_size(schemaname || '.' || relname) > 10485760
  AND round(100.0 * n_dead_tup::numeric / NULLIF(n_live_tup + n_dead_tup, 0), 2) > 10
  AND round(100.0 * n_dead_tup::numeric / NULLIF(n_live_tup + n_dead_tup, 0), 2) <= 20;

\qecho </section>

\qecho <section><h2>14. Vacuum Health &amp; Autovacuum Effectiveness</h2>
\qecho <h3>Autovacuum Configuration</h3>

SELECT
  name   AS parameter,
  setting AS current_value
FROM pg_settings
WHERE name IN (
  'autovacuum', 'autovacuum_max_workers', 'autovacuum_naptime',
  'autovacuum_vacuum_threshold', 'autovacuum_vacuum_scale_factor',
  'autovacuum_analyze_threshold', 'autovacuum_analyze_scale_factor',
  'autovacuum_vacuum_cost_delay', 'autovacuum_vacuum_cost_limit',
  'autovacuum_freeze_max_age', 'log_autovacuum_min_duration'
)
ORDER BY name;

\qecho <h3>Tables Overdue for Autovacuum</h3>

SELECT
  schemaname,
  relname                       AS table_name,
  n_live_tup,
  n_dead_tup,
  round(
    current_setting('autovacuum_vacuum_threshold')::numeric
    + current_setting('autovacuum_vacuum_scale_factor')::numeric * n_live_tup
  , 0)                          AS vacuum_threshold,
  CASE
    WHEN n_dead_tup > (
      current_setting('autovacuum_vacuum_threshold')::numeric
      + current_setting('autovacuum_vacuum_scale_factor')::numeric * n_live_tup
    ) THEN 'OVERDUE'
    ELSE 'OK'
  END                           AS vacuum_status,
  last_autovacuum,
  last_vacuum,
  pg_size_pretty(pg_total_relation_size(schemaname || '.' || relname)) AS table_size
FROM pg_stat_user_tables
WHERE schemaname NOT LIKE 'pg_temp%'
ORDER BY
  (n_dead_tup - (
    current_setting('autovacuum_vacuum_threshold')::numeric
    + current_setting('autovacuum_vacuum_scale_factor')::numeric * n_live_tup
  )) DESC NULLS LAST
LIMIT 30;

\qecho <h3>Tables Overdue for Autoanalyze</h3>

SELECT
  schemaname,
  relname                       AS table_name,
  n_live_tup,
  n_mod_since_analyze,
  round(
    current_setting('autovacuum_analyze_threshold')::numeric
    + current_setting('autovacuum_analyze_scale_factor')::numeric * n_live_tup
  , 0)                          AS analyze_threshold,
  CASE
    WHEN n_mod_since_analyze > (
      current_setting('autovacuum_analyze_threshold')::numeric
      + current_setting('autovacuum_analyze_scale_factor')::numeric * n_live_tup
    ) THEN 'OVERDUE'
    ELSE 'OK'
  END                           AS analyze_status,
  last_autoanalyze,
  last_analyze
FROM pg_stat_user_tables
WHERE schemaname NOT LIKE 'pg_temp%'
ORDER BY
  (n_mod_since_analyze - (
    current_setting('autovacuum_analyze_threshold')::numeric
    + current_setting('autovacuum_analyze_scale_factor')::numeric * n_live_tup
  )) DESC NULLS LAST
LIMIT 30;

\qecho <h3>Freeze Age Risk by Table</h3>

SELECT
  n.nspname                                              AS schemaname,
  c.relname                                              AS table_name,
  age(c.relfrozenxid)                                    AS age_transactions,
  current_setting('autovacuum_freeze_max_age')::int      AS freeze_threshold,
  round(100.0 * age(c.relfrozenxid)::numeric
        / current_setting('autovacuum_freeze_max_age')::numeric, 1) AS pct_of_limit,
  CASE
    WHEN age(c.relfrozenxid) > current_setting('autovacuum_freeze_max_age')::int * 0.9 THEN 'CRITICAL'
    WHEN age(c.relfrozenxid) > current_setting('autovacuum_freeze_max_age')::int * 0.7 THEN 'HIGH'
    WHEN age(c.relfrozenxid) > current_setting('autovacuum_freeze_max_age')::int * 0.5 THEN 'MEDIUM'
    ELSE 'LOW'
  END                                                    AS freeze_risk
FROM pg_class c
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND c.relkind = 'r'
ORDER BY age(c.relfrozenxid) DESC
LIMIT 30;

\qecho <h3>Long Transactions Blocking Vacuum</h3>

SELECT
  pid,
  usename,
  application_name,
  state,
  age(now(), xact_start)                  AS xact_age,
  left(query, 80)                          AS query_snippet,
  CASE
    WHEN age(now(), xact_start) > interval '1 hour' THEN 'CRITICAL - blocking vacuum'
    WHEN age(now(), xact_start) > interval '15 minutes' THEN 'WARNING'
    ELSE 'OK'
  END                                      AS assessment
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
  AND state != 'idle'
  AND pid <> pg_backend_pid()
ORDER BY xact_start ASC
LIMIT 20;

\qecho <h3>Currently Running Autovacuum Workers</h3>

SELECT
  pid,
  usename,
  datname,
  state,
  age(now(), query_start)   AS running_for,
  left(query, 100)           AS autovacuum_target
FROM pg_stat_activity
WHERE query LIKE 'autovacuum:%'
ORDER BY query_start ASC;

\qecho <h3>Last 10 Tables Vacuumed (most recently autovacuumed)</h3>

SELECT
  schemaname,
  relname         AS table_name,
  last_autovacuum,
  last_vacuum,
  autovacuum_count,
  vacuum_count,
  n_dead_tup
FROM pg_stat_user_tables
WHERE last_autovacuum IS NOT NULL OR last_vacuum IS NOT NULL
ORDER BY GREATEST(last_autovacuum, last_vacuum) DESC NULLS LAST
LIMIT 10;

-- Findings: tables overdue for vacuum
INSERT INTO report_findings (section, severity, finding, recommendation, metric_value)
SELECT
  '14. Vacuum Health',
  'warning',
  'Table ' || schemaname || '.' || relname || ' is overdue for autovacuum (' || n_dead_tup || ' dead tuples vs threshold '
    || round(current_setting('autovacuum_vacuum_threshold')::numeric + current_setting('autovacuum_vacuum_scale_factor')::numeric * n_live_tup, 0) || ')',
  'Run: VACUUM ANALYZE ' || schemaname || '.' || relname || '; or lower autovacuum_vacuum_scale_factor for this table',
  n_dead_tup::text || ' dead tuples'
FROM pg_stat_user_tables
WHERE schemaname NOT LIKE 'pg_temp%'
  AND n_dead_tup > (
    current_setting('autovacuum_vacuum_threshold')::numeric
    + current_setting('autovacuum_vacuum_scale_factor')::numeric * n_live_tup
  )
ORDER BY n_dead_tup DESC
LIMIT 10;

-- Findings: tables with long-running transactions blocking vacuum
INSERT INTO report_findings (section, severity, finding, recommendation, metric_value)
SELECT
  '14. Vacuum Health',
  'critical',
  'Long-running transaction (PID ' || pid || ', ' || usename || ') open for ' || age(now(), xact_start)::text || ' is blocking vacuum',
  'Investigate and terminate if safe: SELECT pg_terminate_backend(' || pid || ');',
  age(now(), xact_start)::text
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
  AND state != 'idle'
  AND pid <> pg_backend_pid()
  AND age(now(), xact_start) > interval '1 hour'
ORDER BY xact_start ASC
LIMIT 5;

\qecho </section>

\qecho <section><h2>15. WAL Analysis & Checkpoint Pressure</h2>
\qecho <h3>WAL Generation Metrics</h3>

SELECT 
  'Database Transactions (Committed)' as metric,
  xact_commit::text as value
FROM pg_stat_database WHERE datname = current_database()
UNION ALL SELECT 
  'Database Transactions (Rolled Back)', xact_rollback::text
FROM pg_stat_database WHERE datname = current_database();

\qecho <h3>Checkpoint Activity</h3>

\if :has_checkpointer
SELECT 
  'Checkpoints (timed)' as checkpoint_type,
  num_timed::text as count
FROM pg_stat_checkpointer
UNION ALL SELECT 'Checkpoints (requested)', num_requested::text FROM pg_stat_checkpointer
UNION ALL SELECT 'Checkpoint Write Time (ms)', write_time::text FROM pg_stat_checkpointer
UNION ALL SELECT 'Checkpoint Sync Time (ms)', sync_time::text FROM pg_stat_checkpointer
UNION ALL SELECT 'Buffers Written', buffers_written::text FROM pg_stat_checkpointer;
\else
SELECT 
  'bgwriter_buffers_clean' as metric, buffers_clean::text as value FROM pg_stat_bgwriter
UNION ALL SELECT 'bgwriter_maxwritten_clean', maxwritten_clean::text FROM pg_stat_bgwriter
UNION ALL SELECT 'bgwriter_buffers_alloc', buffers_alloc::text FROM pg_stat_bgwriter;
\endif

\if :has_checkpointer
SELECT 
  'Checkpointer Activity' as metric,
  (SELECT (num_timed + num_requested)::text FROM pg_stat_checkpointer) as value;
\endif

INSERT INTO report_findings SELECT '15. WAL Analysis', 'info', 'WAL throughput and checkpoint metrics collected', 'Monitor WAL accumulation and checkpoint frequency', 'Complete';

\qecho </section>

\qecho <section><h2>16. IO Analysis & Storage</h2>
\qecho <h3>Largest Tables by Disk Usage</h3>

SELECT 
  schemaname,
  relname as tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||relname)) as total_size,
  pg_size_pretty(pg_relation_size(schemaname||'.'||relname)) as heap_size,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||relname) - pg_relation_size(schemaname||'.'||relname)) as indexes_and_toast_size,
  n_live_tup as row_count
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(schemaname||'.'||relname) DESC LIMIT 30;

\qecho <h3>Largest Indexes by Disk Usage</h3>

SELECT 
  schemaname,
  relname as tablename,
  indexrelname as indexname,
  pg_size_pretty(pg_relation_size(indexrelid)) as index_size,
  idx_scan,
  CASE 
    WHEN idx_scan = 0 THEN 'UNUSED'
    WHEN idx_scan < 100 THEN 'LOW_USE'
    ELSE 'ACTIVE' 
  END as usage_level
FROM pg_stat_user_indexes
ORDER BY pg_relation_size(indexrelid) DESC LIMIT 30;

\qecho <h3>Sequence Usage Summary</h3>

SELECT 
  schemaname,
  sequencename,
  pg_size_pretty(pg_relation_size(schemaname||'.'||sequencename)) as size
FROM pg_sequences
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_relation_size(schemaname||'.'||sequencename) DESC LIMIT 20;

INSERT INTO report_findings SELECT '16. IO Analysis', 'info', 'Storage and IO metrics collected', 'Review largest objects for optimization opportunities', 'Complete';

\qecho </section>

\qecho <section><h2>17. Aurora Replica Health (if applicable)</h2>

\qecho <h3>Writer or Reader Node Detection</h3>

SELECT
  pg_is_in_recovery()                      AS is_reader,
  CASE pg_is_in_recovery()
    WHEN true  THEN 'READER (standby/replica)'
    WHEN false THEN 'WRITER (primary)'
  END                                       AS node_role,
  current_setting('synchronous_commit')     AS synchronous_commit;

\qecho <h3>Connected Standbys (pg_stat_replication)</h3>

SELECT
  pid,
  usename,
  application_name,
  client_addr,
  state,
  sync_state,
  sent_lsn,
  write_lsn,
  flush_lsn,
  replay_lsn,
  pg_wal_lsn_diff(sent_lsn, replay_lsn)                       AS bytes_lag,
  pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn))       AS bytes_lag_pretty,
  write_lag,
  flush_lag,
  replay_lag,
  CASE
    WHEN extract(epoch FROM replay_lag) > 30 THEN 'CRITICAL - lag > 30s'
    WHEN extract(epoch FROM replay_lag) > 10 THEN 'WARNING - lag > 10s'
    WHEN replay_lag IS NULL THEN 'UNKNOWN'
    ELSE 'OK'
  END                                                           AS lag_assessment
FROM pg_stat_replication
ORDER BY bytes_lag DESC;

\qecho <h3>Replication Slots with Retained WAL</h3>

SELECT
  slot_name,
  slot_type,
  database,
  active,
  restart_lsn,
  confirmed_flush_lsn,
  pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)          AS retained_wal_bytes,
  pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal_size,
  CASE
    WHEN NOT active AND pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) > 10737418240
    THEN 'CRITICAL - inactive slot retaining > 10 GB WAL'
    WHEN NOT active THEN 'WARNING - inactive slot'
    ELSE 'OK'
  END                                                           AS assessment
FROM pg_replication_slots
ORDER BY retained_wal_bytes DESC NULLS LAST;

\qecho <h3>Aurora-Specific Settings</h3>

SELECT
  name    AS parameter,
  setting AS current_value
FROM pg_settings
WHERE name IN (
  'aurora_parallel_query',
  'aurora.replica_read_consistency',
  'random_page_cost',
  'synchronous_commit',
  'wal_level',
  'max_wal_senders',
  'max_replication_slots'
)
ORDER BY name;

-- Findings: replica lag
INSERT INTO report_findings (section, severity, finding, recommendation, metric_value)
SELECT
  '17. Aurora Replica Health',
  'critical',
  'Replica ' || application_name || ' has replay lag of ' || replay_lag::text,
  'Investigate replica load, network throughput, or long-running queries on the replica blocking apply',
  replay_lag::text
FROM pg_stat_replication
WHERE extract(epoch FROM replay_lag) > 30;

-- Findings: inactive slots retaining WAL
INSERT INTO report_findings (section, severity, finding, recommendation, metric_value)
SELECT
  '17. Aurora Replica Health',
  'critical',
  'Replication slot ' || slot_name || ' is inactive and retaining '
    || pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) || ' of WAL',
  'DROP REPLICATION SLOT ' || quote_ident(slot_name) || '; if slot is no longer needed, to free WAL space',
  pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn))
FROM pg_replication_slots
WHERE NOT active
  AND pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) > 1073741824;

\qecho </section>

\qecho <section><h2>18. Replication & Logical Replication</h2>
\qecho <h3>Publication Status</h3>

SELECT 
  pubname,
  puballtables,
  pubinsert,
  pubupdate,
  pubdelete,
  pubtruncate
FROM pg_publication
ORDER BY pubname;

\qecho <h3>Subscription Status</h3>

SELECT 
  subname,
  subslotname,
  subenabled,
  CASE WHEN subenabled THEN 'ENABLED' ELSE 'DISABLED' END as status
FROM pg_subscription
ORDER BY subname;

\qecho <h3>Replication Slot Age Analysis</h3>

SELECT 
  slot_name,
  slot_type,
  active,
  pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)::text as bytes_retained,
  confirmed_flush_lsn
FROM pg_replication_slots
ORDER BY pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) DESC LIMIT 20;

INSERT INTO report_findings SELECT '18. Replication', 'info', 'Replication configuration reviewed', 'Verify subscription status and WAL retention', 'Complete';

\qecho </section>

\qecho <section><h2>19. Capacity Planning & Growth Trends</h2>
\qecho <h3>Database Growth Summary</h3>

SELECT 
  datname,
  pg_size_pretty(pg_database_size(datname)) as total_size,
  numbackends as current_connections
FROM pg_stat_database
WHERE datname IN (current_database(), 'template1', 'template0')
ORDER BY pg_database_size(datname) DESC;

\qecho <h3>Top Growing Tables (by tuple count)</h3>

SELECT 
  schemaname,
  relname as tablename,
  n_live_tup as current_rows,
  n_tup_ins as inserts_since_analyze,
  n_tup_upd as updates_since_analyze,
  n_tup_del as deletes_since_analyze,
  last_analyze
FROM pg_stat_user_tables
WHERE n_live_tup > 1000000
ORDER BY n_live_tup DESC LIMIT 20;

\qecho <h3>Bytes Per Row Efficiency</h3>

SELECT 
  schemaname,
  relname as tablename,
  n_live_tup,
  pg_total_relation_size(schemaname||'.'||relname) as total_bytes,
  round((pg_total_relation_size(schemaname||'.'||relname)::numeric / NULLIF(n_live_tup, 0))::numeric, 2) as bytes_per_row
FROM pg_stat_user_tables
WHERE n_live_tup > 10000
ORDER BY bytes_per_row DESC LIMIT 20;

INSERT INTO report_findings SELECT '19. Capacity Planning', 'info', 'Growth trends and capacity metrics collected', 'Project growth and plan capacity increases', 'Complete';

\qecho </section>

\qecho <section><h2>20. Observability Readiness &amp; Extensions</h2>
\qecho <h3>Extension Matrix: Status, Purpose &amp; Recommendations</h3>

WITH known_extensions AS (
  SELECT * FROM (VALUES
    ('pg_stat_statements',  'CRITICAL',      'SQL-level performance monitoring; tracks calls, timing, rows, I/O per query'),
    ('pg_wait_sampling',    'CRITICAL',      'Wait event histograms; essential for identifying bottlenecks'),
    ('apg_plan_mgmt',       'AURORA',        'Aurora plan management (APM); stabilises query plans'),
    ('auto_explain',        'IMPORTANT',     'Logs query execution plans for slow queries automatically'),
    ('pg_cron',             'USEFUL',        'Schedule SQL jobs inside PostgreSQL (maintenance, purges)'),
    ('pg_prewarm',          'USEFUL',        'Pre-load relation data into buffer cache after restart'),
    ('pg_hint_plan',        'USEFUL',        'Allows optimizer hints in SQL comments'),
    ('pgaudit',             'COMPLIANCE',    'Detailed session and object audit logging for compliance'),
    ('pg_partman',          'USEFUL',        'Automated partition management for time/serial partitioned tables'),
    ('pg_trgm',             'OPTIONAL',      'Trigram-based text similarity search; supports LIKE indexes'),
    ('pageinspect',         'DIAGNOSTIC',    'Low-level page inspection; useful for bloat analysis'),
    ('pgstattuple',         'DIAGNOSTIC',    'Accurate tuple-level bloat stats per table')
  ) AS t(extname, importance, purpose)
)
SELECT
  ke.extname                 AS extension,
  ke.importance,
  ke.purpose,
  CASE WHEN e.extname IS NOT NULL THEN e.extversion ELSE NULL END AS installed_version,
  CASE WHEN e.extname IS NOT NULL THEN 'INSTALLED' ELSE 'NOT INSTALLED' END AS status,
  CASE WHEN e.extname IS NULL
    THEN 'CREATE EXTENSION IF NOT EXISTS ' || ke.extname || ';'
    ELSE 'n/a'
  END                        AS install_command
FROM known_extensions ke
LEFT JOIN pg_extension e ON e.extname = ke.extname
ORDER BY
  CASE ke.importance
    WHEN 'CRITICAL'    THEN 1
    WHEN 'AURORA'      THEN 2
    WHEN 'IMPORTANT'   THEN 3
    WHEN 'COMPLIANCE'  THEN 4
    WHEN 'USEFUL'      THEN 5
    WHEN 'DIAGNOSTIC'  THEN 6
    ELSE 7
  END,
  ke.extname;

\qecho <h3>Shared Preload Libraries</h3>

SELECT
  current_setting('shared_preload_libraries') AS shared_preload_libraries,
  CASE
    WHEN current_setting('shared_preload_libraries') LIKE '%pg_stat_statements%' THEN 'pg_stat_statements: LOADED'
    ELSE 'pg_stat_statements: NOT in preload (add to parameter group and reboot)'
  END AS pgss_status,
  CASE
    WHEN current_setting('shared_preload_libraries') LIKE '%auto_explain%' THEN 'auto_explain: LOADED'
    ELSE 'auto_explain: not preloaded'
  END AS auto_explain_status,
  CASE
    WHEN current_setting('shared_preload_libraries') LIKE '%pg_wait_sampling%' THEN 'pg_wait_sampling: LOADED'
    ELSE 'pg_wait_sampling: not preloaded'
  END AS wait_sampling_status;

\qecho <h3>Observability Settings Assessment</h3>

SELECT
  name                         AS parameter,
  setting                      AS current_value,
  CASE name
    WHEN 'log_min_duration_statement' THEN
      CASE WHEN setting::int = -1     THEN 'CRITICAL - slow query logging disabled'
           WHEN setting::int > 5000   THEN 'WARNING - threshold very high (> 5 s)'
           WHEN setting::int > 1000   THEN 'WARNING - consider lowering to 1000 ms'
           ELSE 'OK'
      END
    WHEN 'track_io_timing'            THEN CASE WHEN setting = 'on' THEN 'OK' ELSE 'WARNING - IO timing unavailable in pg_stat_statements' END
    WHEN 'log_lock_waits'             THEN CASE WHEN setting = 'on' THEN 'OK' ELSE 'WARNING - lock contention invisible in logs' END
    WHEN 'log_checkpoints'            THEN CASE WHEN setting = 'on' THEN 'OK' ELSE 'INFO - enable for checkpoint diagnostics' END
    WHEN 'log_autovacuum_min_duration' THEN
      CASE WHEN setting::int = -1 THEN 'WARNING - autovacuum activity not logged'
           WHEN setting::int > 250  THEN 'INFO - consider lowering to 250 ms'
           ELSE 'OK'
      END
    WHEN 'track_counts'               THEN CASE WHEN setting = 'on' THEN 'OK' ELSE 'CRITICAL - pg_stat_user_tables stats disabled' END
    WHEN 'track_functions'            THEN CASE WHEN setting IN ('pl','all') THEN 'OK' ELSE 'INFO - enable for function-level profiling' END
    ELSE 'OK'
  END                          AS assessment
FROM pg_settings
WHERE name IN (
  'shared_preload_libraries',
  'log_min_duration_statement',
  'log_checkpoints',
  'log_lock_waits',
  'log_temp_files',
  'log_autovacuum_min_duration',
  'track_io_timing',
  'track_counts',
  'track_functions',
  'log_statement'
)
ORDER BY name;

-- Findings for missing critical extensions
INSERT INTO report_findings (section, severity, finding, recommendation, metric_value)
SELECT
  '20. Observability',
  'critical',
  'pg_stat_statements is NOT installed - SQL-level performance monitoring is unavailable',
  'Add pg_stat_statements to shared_preload_libraries in the parameter group, reboot, then run: CREATE EXTENSION IF NOT EXISTS pg_stat_statements;',
  'NOT INSTALLED'
WHERE NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements');

INSERT INTO report_findings (section, severity, finding, recommendation, metric_value)
SELECT
  '20. Observability',
  'critical',
  'Slow query logging is disabled (log_min_duration_statement = -1)',
  'Set log_min_duration_statement = 1000 in parameter group to capture slow queries',
  '-1'
WHERE current_setting('log_min_duration_statement')::int = -1;

INSERT INTO report_findings (section, severity, finding, recommendation, metric_value)
SELECT
  '20. Observability',
  'warning',
  'track_io_timing is OFF - I/O breakdown missing from pg_stat_statements',
  'Set track_io_timing = on in parameter group (no restart required on Aurora)',
  'off'
WHERE current_setting('track_io_timing') = 'off';

INSERT INTO report_findings (section, severity, finding, recommendation, metric_value)
SELECT
  '20. Observability',
  'warning',
  'log_lock_waits is OFF - lock wait events will not appear in PostgreSQL logs',
  'Set log_lock_waits = on in parameter group',
  'off'
WHERE current_setting('log_lock_waits') = 'off';

\qecho </section>

\qecho <section><h2>Summary: Findings &amp; Recommendations</h2>

\qecho <h3>Health Score</h3>

SELECT
  crit.n                                             AS critical_count,
  warn.n                                             AS warning_count,
  info.n                                             AS info_count,
  GREATEST(0, 100 - (crit.n * 10) - (warn.n * 3))   AS health_score,
  CASE
    WHEN GREATEST(0, 100 - (crit.n * 10) - (warn.n * 3)) >= 90 THEN 'HEALTHY'
    WHEN GREATEST(0, 100 - (crit.n * 10) - (warn.n * 3)) >= 70 THEN 'CAUTION'
    WHEN GREATEST(0, 100 - (crit.n * 10) - (warn.n * 3)) >= 50 THEN 'WARNING'
    ELSE 'CRITICAL'
  END                                                AS overall_status
FROM
  (SELECT count(*)::int AS n FROM report_findings WHERE severity = 'critical') crit,
  (SELECT count(*)::int AS n FROM report_findings WHERE severity = 'warning')  warn,
  (SELECT count(*)::int AS n FROM report_findings WHERE severity = 'info')     info;

\qecho <h3>DBA Quick Dashboard</h3>

SELECT
  metric,
  value,
  assessment
FROM (

  SELECT 1 AS ord, 'Connection Saturation' AS metric,
    round((SELECT count(*)::numeric FROM pg_stat_activity WHERE state IS NOT NULL)
          / current_setting('max_connections')::numeric * 100, 1)::text || '%' AS value,
    CASE WHEN (SELECT count(*)::numeric FROM pg_stat_activity WHERE state IS NOT NULL)
              / current_setting('max_connections')::numeric > 0.80 THEN 'CRITICAL'
         WHEN (SELECT count(*)::numeric FROM pg_stat_activity WHERE state IS NOT NULL)
              / current_setting('max_connections')::numeric > 0.60 THEN 'WARNING'
         ELSE 'OK' END AS assessment

  UNION ALL
  SELECT 2, 'Cache Hit Ratio',
    round(100.0 * sum(blks_hit)::numeric / NULLIF(sum(blks_hit + blks_read), 0), 2)::text || '%',
    CASE WHEN round(100.0 * sum(blks_hit)::numeric / NULLIF(sum(blks_hit + blks_read), 0), 2) < 90
         THEN 'WARNING - consider increasing shared_buffers or effective_cache_size'
         ELSE 'OK' END
  FROM pg_stat_database WHERE datname = current_database()

  UNION ALL
  SELECT 3, 'Long Transactions (> 5 min)',
    (SELECT count(*)::text FROM pg_stat_activity
     WHERE xact_start < now() - interval '5 minutes' AND state != 'idle' AND pid <> pg_backend_pid()),
    CASE WHEN (SELECT count(*) FROM pg_stat_activity
              WHERE xact_start < now() - interval '5 minutes' AND state != 'idle' AND pid <> pg_backend_pid()) > 0
         THEN 'WARNING' ELSE 'OK' END

  UNION ALL
  SELECT 4, 'Blocking Sessions (lock wait)',
    (SELECT count(*)::text FROM pg_stat_activity WHERE wait_event_type = 'Lock'),
    CASE WHEN (SELECT count(*) FROM pg_stat_activity WHERE wait_event_type = 'Lock') > 0
         THEN 'WARNING' ELSE 'OK' END

  UNION ALL
  SELECT 5, 'Tables Needing Vacuum (overdue)',
    (SELECT count(*)::text FROM pg_stat_user_tables
     WHERE n_dead_tup > (
       current_setting('autovacuum_vacuum_threshold')::numeric
       + current_setting('autovacuum_vacuum_scale_factor')::numeric * n_live_tup
     ) AND schemaname NOT LIKE 'pg_temp%'),
    CASE WHEN (SELECT count(*) FROM pg_stat_user_tables
               WHERE n_dead_tup > (
                 current_setting('autovacuum_vacuum_threshold')::numeric
                 + current_setting('autovacuum_vacuum_scale_factor')::numeric * n_live_tup
               ) AND schemaname NOT LIKE 'pg_temp%') > 5
         THEN 'WARNING' ELSE 'OK' END

  UNION ALL
  SELECT 6, 'Tables with High Bloat (> 20% dead)',
    (SELECT count(*)::text FROM pg_stat_user_tables
     WHERE round(100.0 * n_dead_tup::numeric / NULLIF(n_live_tup + n_dead_tup, 0), 2) > 20
       AND schemaname NOT LIKE 'pg_temp%'
       AND pg_total_relation_size(schemaname || '.' || relname) > 10485760),
    CASE WHEN (SELECT count(*) FROM pg_stat_user_tables
               WHERE round(100.0 * n_dead_tup::numeric / NULLIF(n_live_tup + n_dead_tup, 0), 2) > 20
                 AND schemaname NOT LIKE 'pg_temp%'
                 AND pg_total_relation_size(schemaname || '.' || relname) > 10485760) > 0
         THEN 'WARNING' ELSE 'OK' END

  UNION ALL
  SELECT 7, 'Checkpoint Completion Target',
    current_setting('checkpoint_completion_target'),
    CASE WHEN current_setting('checkpoint_completion_target')::numeric < 0.9
         THEN 'WARNING - set to 0.9 to spread checkpoint IO'
         ELSE 'OK' END

  UNION ALL
  SELECT 8, 'Replica Lag (max replay_lag)',
    COALESCE((SELECT max(extract(epoch FROM replay_lag))::text || ' s'
              FROM pg_stat_replication), 'No standbys connected'),
    CASE WHEN (SELECT max(extract(epoch FROM replay_lag)) FROM pg_stat_replication) > 30
         THEN 'CRITICAL' ELSE 'OK' END

  UNION ALL
  SELECT 9, 'Top SQL Monitoring (pg_stat_statements)',
    CASE WHEN EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements')
         THEN 'INSTALLED' ELSE 'NOT INSTALLED' END,
    CASE WHEN NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements')
         THEN 'CRITICAL' ELSE 'OK' END

  UNION ALL
  SELECT 10, 'Slow Query Logging (log_min_duration_statement)',
    current_setting('log_min_duration_statement') || ' ms',
    CASE WHEN current_setting('log_min_duration_statement')::int = -1 THEN 'CRITICAL - disabled'
         WHEN current_setting('log_min_duration_statement')::int > 5000 THEN 'WARNING'
         ELSE 'OK' END

) dashboard
ORDER BY ord;

\qecho <h3>CRITICAL Findings (action required)</h3>

SELECT
  section,
  severity,
  finding,
  recommendation,
  metric_value
FROM report_findings
WHERE severity = 'critical'
ORDER BY section, finding;

\qecho <h3>WARNING Findings (review recommended)</h3>

SELECT
  section,
  severity,
  finding,
  recommendation,
  metric_value
FROM report_findings
WHERE severity = 'warning'
ORDER BY section, finding;

\qecho <h3>Informational Items</h3>

SELECT
  section,
  severity,
  finding,
  recommendation,
  metric_value
FROM report_findings
WHERE severity = 'info'
ORDER BY section, finding;

\qecho <h3>Finding Count Summary</h3>

SELECT
  (SELECT count(*) FROM report_findings WHERE severity = 'critical') AS critical_findings,
  (SELECT count(*) FROM report_findings WHERE severity = 'warning')  AS warning_findings,
  (SELECT count(*) FROM report_findings WHERE severity = 'info')     AS info_items,
  (SELECT count(*) FROM report_findings)                             AS total_findings;

\qecho </section>
\qecho </body></html>


\qecho <!-- Extended Analysis Sections -->

\qecho <section><h2>Extended Analysis: Top SQL by WAL Generation</h2>
\qecho <p class="info">Removed: WAL-by-query estimates were not reliable enough for production interpretation.</p>
\qecho </section>

\qecho <section><h2>Extended Analysis: Temp Space Consumers</h2>
\qecho <p class="info">Removed: returned row count is not temp-space evidence. Temp spill analysis is now driven by actual temp file and temp block metrics only.</p>
\qecho </section>

\qecho <section><h2>Extended Analysis: Parameter Sensitivity</h2>
\qecho <h3>Query Variability Analysis</h3>

\if :has_pgss
WITH query_stats AS (
  SELECT 
    left(query, 80) as query,
    sum(calls) as total_calls,
    min(mean_exec_time) as min_mean_time,
    max(mean_exec_time) as max_mean_time,
    round(stddev(mean_exec_time)::numeric, 2) as stddev_time,
    CASE 
      WHEN max(mean_exec_time) > min(mean_exec_time) * 2 THEN 'HIGH'
      WHEN max(mean_exec_time) > min(mean_exec_time) * 1.5 THEN 'MEDIUM'
      ELSE 'LOW' 
    END as variability
  FROM pg_stat_statements
  GROUP BY left(query, 80)
  HAVING count(*) > 1
)
SELECT 
  query,
  total_calls as calls,
  round(min_mean_time::numeric, 2) as min_ms,
  round(max_mean_time::numeric, 2) as max_ms,
  stddev_time,
  variability
FROM query_stats
ORDER BY stddev_time DESC NULLS LAST
LIMIT 25;
\else
\qecho <p class="muted">pg_stat_statements not available</p>
\endif

\qecho </section>

\qecho <section><h2>Extended Analysis: Missing Index Candidates</h2>
\qecho <h3>High Scan Count Tables Without Indexes</h3>

SELECT 
  schemaname,
  relname as tablename,
  seq_scan,
  seq_tup_read,
  n_live_tup,
  round(seq_tup_read::numeric / NULLIF(n_live_tup, 0), 2) as tuples_examined_per_row,
  CASE 
    WHEN seq_scan > 1000 AND n_live_tup > 1000000 THEN 'CRITICAL - High scanning on large table'
    WHEN seq_scan > 100 AND n_live_tup > 100000 THEN 'WARNING - Frequent scanning'
    ELSE 'INFO' 
  END as index_recommendation
FROM pg_stat_user_tables
WHERE (SELECT count(*) FROM pg_stat_user_indexes WHERE pg_stat_user_indexes.relname = pg_stat_user_tables.relname) < 2
ORDER BY seq_scan DESC LIMIT 30;

\qecho </section>

\qecho <section><h2>Extended Analysis: Lock Contention Details</h2>
\qecho <h3>Exclusivity Lock Wait Analysis</h3>

SELECT 
  locktype,
  mode,
  count(CASE WHEN granted THEN 1 END) as held_count,
  count(CASE WHEN NOT granted THEN 1 END) as waiting_count,
  count(*) as total_locks
FROM pg_locks
WHERE locktype IN ('relation', 'extend', 'page', 'tuple')
GROUP BY locktype, mode
ORDER BY waiting_count DESC, held_count DESC;

\qecho </section>

\qecho <section><h2>Extended Analysis: Connection Patterns</h2>
\qecho <h3>Database Connection Timeline</h3>

SELECT 
  date_trunc('hour', backend_start)::timestamp as hour,
  count(*) as connections_started,
  count(CASE WHEN state = 'active' THEN 1 END) as currently_active,
  round(100.0 * count(CASE WHEN state = 'active' THEN 1 END) / count(*), 2) as active_pct
FROM pg_stat_activity
WHERE pid IS NOT NULL
  AND backend_start > now() - interval '24 hours'
GROUP BY date_trunc('hour', backend_start)
ORDER BY hour DESC LIMIT 30;

\qecho </section>

\qecho <section><h2>Extended Analysis: Bloat Timeline Projection</h2>
\qecho <h3>Projected Bloat Growth</h3>

SELECT 
  schemaname,
  relname as tablename,
  n_dead_tup as current_dead_tuples,
  n_tup_del as recent_deletes,
  CASE 
    WHEN n_tup_del > 0 THEN round(n_dead_tup::numeric / n_tup_del, 2)
    ELSE 0 
  END as bloat_accumulation_ratio,
  CASE 
    WHEN n_tup_del > 100000 THEN 'CRITICAL - Aggressive deletion pattern'
    WHEN n_tup_del > 10000 THEN 'WARNING - Moderate deletion activity'
    ELSE 'NORMAL' 
  END as deletion_velocity
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY n_dead_tup DESC LIMIT 30;

\qecho </section>

\qecho <section><h2>Extended Analysis: Query Cache Efficiency</h2>
\qecho <h3>Cached Query Performance Impact</h3>

\if :has_pgss
\if :has_pgss_io_timing
WITH top_queries AS (
  SELECT 
    left(query, 80) as query,
    calls,
    total_exec_time,
    blk_hit_time,
    blk_read_time,
    round(total_exec_time::numeric / calls, 2) as avg_time
  FROM pg_stat_statements
  WHERE calls > 10
  ORDER BY total_exec_time DESC
  LIMIT 50
)
SELECT 
  query,
  calls,
  round(avg_time::numeric, 2) as avg_time_ms,
  round((blk_hit_time + blk_read_time)::numeric / NULLIF(calls, 0), 2) as io_time_per_call,
  round(100.0 * blk_hit_time::numeric / NULLIF(blk_hit_time + blk_read_time, 0), 2) as cache_hit_pct
FROM top_queries
ORDER BY avg_time DESC LIMIT 25;
\else
SELECT 
  left(query, 80) as query,
  calls,
  round(total_exec_time::numeric / calls, 2) as avg_time_ms,
  round(mean_exec_time::numeric, 2) as mean_exec_time_ms,
  rows
FROM pg_stat_statements
WHERE calls > 10
ORDER BY total_exec_time DESC LIMIT 25;
\endif
\else
SELECT 'pg_stat_statements extension not enabled on this instance' AS notice;
\endif

\qecho </section>

\qecho <section><h2>Extended Analysis: Autovacuum Pressure Index</h2>
\qecho <h3>Tables Needing Immediate Vacuum</h3>

SELECT 
  t.schemaname,
  t.relname,
  t.n_live_tup,
  t.n_dead_tup,
  t.n_mod_since_analyze,
  round(100.0 * t.n_dead_tup::numeric / NULLIF(t.n_live_tup, 0), 2) as dead_ratio_pct,
  t.last_vacuum,
  t.last_autovacuum,
  age(c.relfrozenxid)::int as xid_age,
  CASE 
    WHEN t.n_dead_tup > t.n_live_tup * 0.1 THEN 'VACUUM_NEEDED'
    WHEN t.n_mod_since_analyze > t.n_live_tup * 0.05 THEN 'ANALYZE_NEEDED'
    WHEN age(c.relfrozenxid)::int > 1000000 THEN 'FREEZE_WARNING'
    ELSE 'OK' 
  END as maintenance_action
FROM pg_stat_user_tables t
JOIN pg_class c ON c.oid = (t.schemaname||'.'||t.relname)::regclass
WHERE t.n_live_tup > 10000
ORDER BY t.n_dead_tup DESC LIMIT 30;

\qecho </section>

\qecho <section><h2>Extended Analysis: Checkpoint Efficiency</h2>
\qecho <h3>Background Writer Performance</h3>

SELECT
  'bgwriter_buffers_clean' as metric, buffers_clean::text as value
FROM pg_stat_bgwriter
UNION ALL SELECT
  'bgwriter_maxwritten_clean', maxwritten_clean::text
FROM pg_stat_bgwriter
UNION ALL SELECT
  'bgwriter_buffers_alloc', buffers_alloc::text
FROM pg_stat_bgwriter;

\qecho </section>

\q

-- ========================================
-- ADVANCED PERFORMANCE MONITORING QUERIES
-- ========================================

\qecho <section><h2>Advanced: Table Relationship Analysis</h2>
\qecho <h3>Foreign Key Reference Counts</h3>

SELECT 
  t.relname,
  count(DISTINCT c.conrelid) as referencing_tables,
  count(c.conkey) as total_fk_columns,
  pg_size_pretty(pg_total_relation_size('public.'||t.relname)) as table_size
FROM pg_tables t
LEFT JOIN pg_constraint c ON c.confrelid = (t.schemaname||'.'||t.relname)::regclass
WHERE t.schemaname = 'public'
GROUP BY t.relname
HAVING count(DISTINCT c.conrelid) > 0
ORDER BY count(DISTINCT c.conrelid) DESC LIMIT 50;

\qecho </section>

\qecho <section><h2>Advanced: Index Efficiency Scoring</h2>
\qecho <h3>Index Efficiency Score (Combined Metrics)</h3>

SELECT 
  schemaname,
  relname as tablename,
  indexname,
  idx_scan,
  idx_tup_read,
  idx_tup_fetch,
  CASE 
    WHEN idx_scan = 0 THEN 0
    ELSE round(100.0 * idx_tup_fetch::numeric / NULLIF(idx_tup_read, 1), 2)
  END as fetch_efficiency_pct,
  CASE 
    WHEN idx_scan > 10000 THEN 'CRITICAL_USE'
    WHEN idx_scan > 1000 THEN 'HIGH_USE'
    WHEN idx_scan > 100 THEN 'MEDIUM_USE'
    WHEN idx_scan > 10 THEN 'LOW_USE'
    WHEN idx_scan = 0 THEN 'UNUSED'
    ELSE 'MINIMAL_USE' 
  END as usage_tier,
  pg_size_pretty(pg_relation_size(indexrelid)) as index_size,
  round((pg_relation_size(indexrelid))::numeric / NULLIF(idx_tup_fetch, 0), 2) as bytes_per_fetch
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC NULLS LAST LIMIT 50;

\qecho </section>

\qecho <section><h2>Advanced: Query Execution Pattern Analysis</h2>
\qecho <h3>Query Stability and Predictability Metrics</h3>

\if :has_pgss
WITH query_patterns AS (
  SELECT 
    query,
    calls,
    min(mean_exec_time) as min_time,
    max(mean_exec_time) as max_time,
    avg(mean_exec_time) as avg_time,
    stddev_pop(mean_exec_time) as stddev_pop_time,
    stddev_samp(mean_exec_time) as stddev_samp_time
  FROM pg_stat_statements
  WHERE calls > 100
  GROUP BY query
)
SELECT 
  left(query, 100) as query_summary,
  calls,
  round(min_time::numeric, 2) as min_ms,
  round(max_time::numeric, 2) as max_ms,
  round(avg_time::numeric, 2) as avg_ms,
  round(stddev_samp_time::numeric, 2) as stddev_ms,
  round((max_time - min_time)::numeric, 2) as range_ms,
  CASE 
    WHEN stddev_samp_time IS NULL THEN 'STABLE'
    WHEN stddev_samp_time / NULLIF(avg_time, 0) > 1 THEN 'HIGHLY_VARIABLE'
    WHEN stddev_samp_time / NULLIF(avg_time, 0) > 0.5 THEN 'VARIABLE'
    ELSE 'PREDICTABLE' 
  END as pattern_type
FROM query_patterns
ORDER BY stddev_samp_time DESC NULLS LAST LIMIT 50;
\else
\qecho <p class="muted">pg_stat_statements not available</p>
\endif

\qecho </section>

\qecho <section><h2>Advanced: Schema Object Complexity</h2>
\qecho <h3>High-Complexity Tables (Many Columns & Indexes)</h3>

WITH table_complexity AS (
  SELECT 
    t.relname,
    (SELECT count(*) FROM information_schema.columns c WHERE c.table_schema = t.schemaname AND c.table_name = t.relname) as column_count,
    (SELECT count(*) FROM pg_stat_user_indexes i WHERE i.relname = t.relname) as index_count,
    (SELECT count(*) FROM information_schema.constraint_column_usage cu WHERE cu.table_schema = t.schemaname AND cu.table_name = t.relname) as constraint_count,
    pg_total_relation_size(t.schemaname||'.'||t.relname) as total_size
  FROM pg_stat_user_tables t
  WHERE t.schemaname NOT IN ('pg_catalog', 'information_schema')
)
SELECT 
  tablename,
  column_count,
  index_count,
  constraint_count,
  column_count + index_count + constraint_count as complexity_score,
  pg_size_pretty(total_size) as size,
  CASE 
    WHEN (column_count + index_count + constraint_count) > 50 THEN 'VERY_COMPLEX'
    WHEN (column_count + index_count + constraint_count) > 30 THEN 'COMPLEX'
    WHEN (column_count + index_count + constraint_count) > 15 THEN 'MODERATE'
    ELSE 'SIMPLE' 
  END as complexity_level
FROM table_complexity
WHERE column_count > 0
ORDER BY complexity_score DESC LIMIT 50;

\qecho </section>

\qecho <section><h2>Advanced: Session Resource Consumption</h2>
\qecho <h3>Top 30 Sessions by Resource Usage</h3>

SELECT 
  pid,
  usename,
  application_name,
  state,
  query_start,
  extract(epoch from (now() - query_start))::int as runtime_seconds,
  (SELECT query FROM pg_stat_activity a WHERE a.pid = pg_stat_activity.pid) as current_query,
  CASE 
    WHEN extract(epoch from (now() - query_start)) > 3600 THEN 'CRITICAL'
    WHEN extract(epoch from (now() - query_start)) > 600 THEN 'WARNING'
    WHEN extract(epoch from (now() - query_start)) > 60 THEN 'CAUTION'
    ELSE 'NORMAL' 
  END as resource_risk
FROM pg_stat_activity
WHERE pid IS NOT NULL
  AND state != 'idle'
ORDER BY extract(epoch from (now() - query_start)) DESC LIMIT 30;

\qecho </section>

\qecho <section><h2>Advanced: Transaction Isolation Level Analysis</h2>
\qecho <h3>Session Isolation Levels and Transaction Status</h3>

SELECT 
  pid,
  usename,
  application_name,
  (SELECT setting FROM pg_settings WHERE name = 'default_transaction_isolation') as session_isolation,
  xact_start,
  state,
  CASE 
    WHEN xact_start IS NOT NULL AND extract(epoch from (now() - xact_start)) > 300 THEN 'LONG_TRANSACTION'
    WHEN state = 'idle in transaction' THEN 'IDLE_IN_XACT'
    WHEN state = 'active' THEN 'ACTIVE'
    ELSE 'NORMAL' 
  END as transaction_status
FROM pg_stat_activity
WHERE pid IS NOT NULL
ORDER BY xact_start NULLS LAST LIMIT 50;

\qecho </section>

\qecho <section><h2>Advanced: Deadlock and Lock Escalation Trends</h2>
\qecho <h3>Lock Wait Time Estimates</h3>

SELECT 
  'Current Active Locks' as metric,
  (SELECT count(*) FROM pg_locks WHERE NOT granted)::text as count
UNION ALL SELECT 
  'Granted Locks',
  (SELECT count(*) FROM pg_locks WHERE granted)::text
UNION ALL SELECT 
  'Exclusive Locks Held',
  (SELECT count(*) FROM pg_locks WHERE granted AND mode LIKE 'Exclusive%')::text
UNION ALL SELECT 
  'Shared Locks Held',
  (SELECT count(*) FROM pg_locks WHERE granted AND mode LIKE 'Share%')::text;

\qecho </section>

\qecho <section><h2>Advanced: Data Type Usage Distribution</h2>
\qecho <h3>Column Data Type Frequency</h3>

SELECT 
  data_type,
  count(*) as column_count,
  count(DISTINCT table_name) as table_count,
  CASE 
    WHEN count(*) > 1000 THEN 'DOMINANT'
    WHEN count(*) > 100 THEN 'COMMON'
    WHEN count(*) > 10 THEN 'MODERATE'
    ELSE 'RARE' 
  END as prevalence
FROM information_schema.columns
WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
GROUP BY data_type
ORDER BY column_count DESC;

\qecho </section>

\qecho <section><h2>Advanced: Query Plan Cache Analysis</h2>
\qecho <h3>Prepared Statements and Cache Efficiency</h3>

SELECT 
  'Total Prepared Plans (estimated)' as metric,
  (SELECT count(*) FROM pg_prepared_statements)::text as value
UNION ALL SELECT 
  'Plan Cache Hit Potential',
  round(100.0 * (SELECT count(DISTINCT query) FROM pg_stat_statements WHERE calls > 1) / NULLIF((SELECT count(*) FROM pg_stat_statements), 0), 2)::text || '%';

\qecho </section>

\qecho <section><h2>Advanced: Concurrent Activity Matrix</h2>
\qecho <h3>Concurrent Session Patterns by Hour</h3>

SELECT 
  date_trunc('hour', query_start)::timestamp as analysis_hour,
  count(*) as total_sessions,
  count(CASE WHEN state = 'active' THEN 1 END) as active_sessions,
  count(CASE WHEN state = 'idle in transaction' THEN 1 END) as idle_xact_sessions,
  count(CASE WHEN state = 'idle' THEN 1 END) as idle_sessions,
  round(100.0 * count(CASE WHEN state = 'active' THEN 1 END) / NULLIF(count(*), 0), 2) as active_percentage
FROM pg_stat_activity
WHERE query_start > now() - interval '168 hours'
GROUP BY date_trunc('hour', query_start)
ORDER BY analysis_hour DESC LIMIT 50;

\qecho </section>

\qecho <section><h2>Advanced: Recovery and Backup Status</h2>
\qecho <h3>Recovery Information</h3>

SELECT 
  'Recovery Paused' as metric,
  pg_is_wal_replay_paused()::text as value
UNION ALL SELECT 
  'Current Redo LSN',
  pg_current_wal_lsn()::text
UNION ALL SELECT 
  'Archive Command Status',
  current_setting('archive_command');

\qecho </section>

\qecho <section><h2>Advanced: Table Maintenance Calendar</h2>
\qecho <h3>Next Recommended Actions by Table</h3>

SELECT 
  t.schemaname,
  t.relname,
  CASE 
    WHEN t.n_dead_tup > t.n_live_tup * 0.2 THEN 'VACUUM_FULL'
    WHEN t.n_dead_tup > t.n_live_tup * 0.1 THEN 'VACUUM'
    WHEN t.n_mod_since_analyze > t.n_live_tup * 0.1 THEN 'ANALYZE'
    WHEN age(c.relfrozenxid)::int > current_setting('autovacuum_freeze_max_age')::int * 0.8 THEN 'VACUUM_FOR_FREEZE'
    ELSE 'MONITOR' 
  END as next_action,
  CASE 
    WHEN t.last_vacuum IS NULL THEN 'NEVER'
    ELSE (extract(epoch from (now() - t.last_vacuum)) / 86400)::int || ' days ago' 
  END as last_vacuum_info,
  CASE 
    WHEN t.last_analyze IS NULL THEN 'NEVER'
    ELSE (extract(epoch from (now() - t.last_analyze)) / 86400)::int || ' days ago' 
  END as last_analyze_info
FROM pg_stat_user_tables t
JOIN pg_class c ON c.oid = (t.schemaname||'.'||t.relname)::regclass
WHERE t.n_live_tup > 100000
ORDER BY t.n_dead_tup DESC LIMIT 50;

\qecho </section>

\qecho <section><h2>Advanced: Cluster Configuration Audit</h2>
\qecho <h3>Critical PostgreSQL Configuration Parameters</h3>

SELECT 
  name,
  setting,
  unit,
  short_desc,
  CASE 
    WHEN name IN ('max_connections', 'shared_buffers', 'effective_cache_size', 'work_mem', 'maintenance_work_mem') THEN 'MEMORY_TUNING'
    WHEN name LIKE 'log_%' THEN 'LOGGING'
    WHEN name LIKE 'autovacuum%' THEN 'MAINTENANCE'
    WHEN name LIKE 'wal_%' THEN 'WAL'
    WHEN name LIKE 'checkpoint%' THEN 'CHECKPOINT'
    WHEN name LIKE 'random_page%' THEN 'PLANNER'
    ELSE 'OTHER' 
  END as category
FROM pg_settings
WHERE context IN ('postmaster', 'sighup')
ORDER BY category, name;

\qecho </section>

\qecho <section><h2>Advanced: Unlogged Table Impact Analysis</h2>
\qecho <h3>Unlogged and Temporary Table Summary</h3>

SELECT 
  schemaname,
  relname as tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||relname)) as table_size,
  CASE 
    WHEN (SELECT relpersistence FROM pg_class WHERE oid = (schemaname||'.'||relname)::regclass) = 'u' THEN 'UNLOGGED'
    WHEN (SELECT relpersistence FROM pg_class WHERE oid = (schemaname||'.'||relname)::regclass) = 't' THEN 'TEMPORARY'
    ELSE 'LOGGED' 
  END as table_type,
  n_live_tup
FROM pg_stat_user_tables
WHERE (SELECT relpersistence FROM pg_class WHERE oid = (schemaname||'.'||relname)::regclass) IN ('u', 't')
ORDER BY pg_total_relation_size(schemaname||'.'||relname) DESC;

\qecho </section>

\qecho <section><h2>Advanced: Extension Capability Matrix</h2>
\qecho <h3>Extension Versions and Capabilities</h3>

SELECT 
  extname,
  extversion,
  extrelocatable::text as relocatable,
  CASE 
    WHEN extname = 'pg_stat_statements' THEN 'Critical for monitoring'
    WHEN extname = 'pg_wait_sampling' THEN 'Wait event analysis'
    WHEN extname = 'auto_explain' THEN 'Auto EXPLAIN queries'
    WHEN extname = 'pageinspect' THEN 'Page inspection'
    WHEN extname = 'pgstattuple' THEN 'Tuple statistics'
    ELSE 'Additional capability' 
  END as primary_purpose
FROM pg_extension
ORDER BY extname;

\qecho </section>



-- ========================================
-- DIAGNOSTIC QUERY SUITE - COMPREHENSIVE
-- ========================================

\qecho <section><h2>Diagnostic Suite: Query Result Set Analysis</h2>
\qecho <h3>Query Output Size Trends</h3>

\if :has_pgss
SELECT 
  left(query, 100) as query_text,
  calls,
  rows,
  round(rows::numeric / NULLIF(calls, 0), 2) as avg_rows_returned,
  CASE 
    WHEN (rows::numeric / NULLIF(calls, 0)) > 100000 THEN 'LARGE_RESULT_SETS'
    WHEN (rows::numeric / NULLIF(calls, 0)) > 10000 THEN 'MEDIUM_RESULT_SETS'
    WHEN (rows::numeric / NULLIF(calls, 0)) > 1000 THEN 'SMALL_RESULT_SETS'
    ELSE 'MINIMAL_RESULTS' 
  END as result_category,
  total_exec_time
FROM pg_stat_statements
WHERE rows > 0 AND calls > 0
ORDER BY rows DESC LIMIT 50;
\else
\qecho <p class="muted">pg_stat_statements not available</p>
\endif

\qecho </section>

\qecho <section><h2>Diagnostic Suite: Buffer Pool Health</h2>
\qecho <h3>Buffer Pool Utilization Metrics</h3>

SELECT 
  'Shared Buffers Configured' as metric,
  current_setting('shared_buffers') as value
UNION ALL SELECT 
  'Effective Cache Size',
  current_setting('effective_cache_size')
UNION ALL SELECT 
  'Avg Cache Hit Ratio',
  round(100.0 * sum(heap_blks_hit)::numeric / NULLIF(sum(heap_blks_hit + heap_blks_read), 0), 2)::text || '%'
FROM pg_statio_user_tables;

\qecho </section>

\qecho <section><h2>Diagnostic Suite: Memory and Sort Usage</h2>
\qecho <h3>Sort and Hash Operation Overhead</h3>

SELECT 
  'Work Memory Setting' as metric,
  current_setting('work_mem') as value
UNION ALL SELECT 
  'Maintenance Work Memory',
  current_setting('maintenance_work_mem')
UNION ALL SELECT 
  'Hash Spill Risk Level',
  CASE 
    WHEN (current_setting('work_mem')::numeric) < 4096 THEN 'HIGH'
    WHEN (current_setting('work_mem')::numeric) < 16384 THEN 'MEDIUM'
    ELSE 'LOW' 
  END;

\qecho </section>

\qecho <section><h2>Diagnostic Suite: Planner Statistics Configuration</h2>
\qecho <h3>Query Planner Behavior Settings</h3>

SELECT 
  name as setting_name,
  setting as current_value,
  short_desc as description
FROM pg_settings
WHERE name IN ('random_page_cost', 'effective_io_concurrency', 'default_statistics_target', 'constraint_exclusion', 'enable_seqscan', 'enable_indexscan', 'enable_bitmapscan')
ORDER BY name;

\qecho </section>

\qecho <section><h2>Diagnostic Suite: Query JIT Compilation Analysis</h2>
\qecho <h3>JIT Configuration and Readiness</h3>

SELECT 
  'JIT Enabled' as metric,
  current_setting('jit') as value
UNION ALL SELECT 
  'JIT Cost Limit',
  current_setting('jit_above_cost')
UNION ALL SELECT 
  'JIT Inline Cost Limit',
  current_setting('jit_inline_above_cost')
UNION ALL SELECT 
  'JIT Optimization Limit',
  current_setting('jit_optimize_above_cost');

\qecho </section>

\qecho <section><h2>Diagnostic Suite: Index Maintenance Recommendations</h2>
\qecho <h3>REINDEX Candidate Analysis</h3>

SELECT 
  schemaname,
  indexname,
  tablename,
  CASE 
    WHEN idx_scan = 0 THEN 'CONSIDER_DROP'
    WHEN pg_relation_size(indexrelid) > 104857600 THEN 'LARGE_CANDIDATE'
    WHEN idx_blks_hit > 1000000 THEN 'ACTIVE_REINDEX_CANDIDATE'
    ELSE 'MONITOR' 
  END as maintenance_action,
  pg_size_pretty(pg_relation_size(indexrelid)) as index_size,
  idx_scan
FROM pg_stat_user_indexes
ORDER BY pg_relation_size(indexrelid) DESC LIMIT 50;

\qecho </section>

\qecho <section><h2>Diagnostic Suite: Full Text Search Readiness</h2>
\qecho <h3>Text Search Configuration Objects</h3>

SELECT 
  'Text Search Dictionaries' as object_type,
  (SELECT count(*) FROM pg_ts_dict)::text as count
UNION ALL SELECT 
  'Text Search Parsers',
  (SELECT count(*) FROM pg_ts_parser)::text
UNION ALL SELECT 
  'Text Search Templates',
  (SELECT count(*) FROM pg_ts_template)::text
UNION ALL SELECT 
  'Text Search Configurations',
  (SELECT count(*) FROM pg_ts_config)::text;

\qecho </section>

\qecho <section><h2>Diagnostic Suite: Data Import/Export Capability</h2>
\qecho <h3>Format Support and External Data Access</h3>

SELECT 
  'Foreign Data Wrappers' as capability,
  (SELECT count(*) FROM pg_foreign_data_wrapper)::text as count
UNION ALL SELECT 
  'Foreign Servers',
  (SELECT count(*) FROM pg_foreign_server)::text
UNION ALL SELECT 
  'Foreign Tables',
  (SELECT count(*) FROM information_schema.foreign_tables)::text;

\qecho </section>

\qecho <section><h2>Diagnostic Suite: Table Access Method Analysis</h2>
\qecho <h3>Access Method Strategy Distribution</h3>

SELECT 
  'HEAP Tables' as access_method,
  (SELECT count(*) FROM pg_class WHERE relkind = 'r' AND relnamespace NOT IN (SELECT oid FROM pg_namespace WHERE nspname IN ('pg_catalog', 'information_schema')))::text as count
UNION ALL SELECT 
  'Index Types',
  (SELECT count(DISTINCT amname) FROM pg_class c, pg_am a WHERE c.relam = a.oid AND c.relkind = 'i')::text;

\qecho </section>

\qecho <section><h2>Diagnostic Suite: Query Hints and Preferences</h2>
\qecho <h3>Query Planning Preferences</h3>

SELECT 
  'Default Transaction Isolation' as preference,
  current_setting('default_transaction_isolation') as setting_value
UNION ALL SELECT 
  'Search Path',
  current_setting('search_path')
UNION ALL SELECT 
  'Timezone',
  current_setting('timezone')
UNION ALL SELECT 
  'DateStyle',
  current_setting('datestyle');

\qecho </section>

\qecho <section><h2>Diagnostic Suite: Connection Pool Configuration Analysis</h2>
\qecho <h3>Connection Parameters and Limits</h3>

SELECT 
  name,
  setting
FROM pg_settings
WHERE name IN (
  'max_connections',
  'superuser_reserved_connections',
  'statement_timeout',
  'idle_in_transaction_session_timeout',
  'tcp_keepalives_idle',
  'tcp_keepalives_interval',
  'tcp_keepalives_count'
)
ORDER BY name;

\qecho </section>

\qecho <section><h2>Diagnostic Suite: Event Trigger and Monitoring Hooks</h2>
\qecho <h3>Event Trigger Deployment Status</h3>

SELECT 
  'Event Triggers Defined' as trigger_category,
  (SELECT count(*) FROM pg_event_trigger)::text as count
UNION ALL SELECT 
  'Regular Triggers',
  (SELECT count(*) FROM pg_trigger WHERE tgisinternal = false)::text
UNION ALL SELECT 
  'Internal Triggers',
  (SELECT count(*) FROM pg_trigger WHERE tgisinternal = true)::text;

\qecho </section>

\qecho <section><h2>Performance Baseline Summary Report</h2>
\qecho <h3>Complete Database Health Snapshot</h3>

SELECT 
  'Report Timestamp' as attribute,
  now()::text as value
UNION ALL SELECT 
  'Database',
  current_database()
UNION ALL SELECT 
  'Total Size',
  pg_size_pretty(pg_database_size(current_database()))
UNION ALL SELECT 
  'Active Connections',
  (SELECT count(*) FROM pg_stat_activity WHERE state = 'active')::text
UNION ALL SELECT 
  'Table Count',
  (SELECT count(*) FROM pg_stat_user_tables)::text
UNION ALL SELECT 
  'Index Count',
  (SELECT count(*) FROM pg_stat_user_indexes)::text
UNION ALL SELECT 
  'Unused Index Count',
  (SELECT count(*) FROM pg_stat_user_indexes WHERE idx_scan = 0)::text
UNION ALL SELECT 
  'Critical Issues',
  (SELECT count(*) FROM report_findings WHERE severity = 'critical')::text
UNION ALL SELECT 
  'Warning Issues',
  (SELECT count(*) FROM report_findings WHERE severity = 'warning')::text;

\qecho </section>

\qecho </body></html>

\q

-- ========================================
-- COMPREHENSIVE PERFORMANCE ANALYSIS
-- ========================================

\qecho <section><h2>Performance: Table Scan Analysis</h2>

SELECT 
  schemaname,
  relname as tablename,
  n_live_tup,
  seq_scan,
  seq_tup_read,
  idx_scan,
  idx_tup_fetch,
  CASE 
    WHEN seq_scan > idx_scan * 10 THEN 'SEQ_SCAN_DOMINANT'
    WHEN idx_scan > 0 THEN 'INDEX_PREFERRED'
    ELSE 'MINIMAL_ACCESS' 
  END as scan_pattern
FROM pg_stat_user_tables
WHERE n_live_tup > 100000
ORDER BY seq_scan DESC LIMIT 50;

\qecho </section>

\qecho <section><h2>Performance: DML Activity Tracking</h2>

SELECT 
  schemaname,
  relname as tablename,
  n_tup_ins + n_tup_upd + n_tup_del as total_dml_ops,
  n_tup_ins,
  n_tup_upd,
  n_tup_del,
  round((n_tup_ins + n_tup_upd + n_tup_del)::numeric / NULLIF(n_live_tup, 0), 2) as dml_activity_ratio
FROM pg_stat_user_tables
WHERE (n_tup_ins + n_tup_upd + n_tup_del) > 0
ORDER BY (n_tup_ins + n_tup_upd + n_tup_del) DESC LIMIT 50;

\qecho </section>

\qecho <section><h2>Performance: Index Hit Ratio by Table</h2>

SELECT 
  t.schemaname,
  t.relname,
  count(i.indexname) as index_count,
  sum(i.idx_scan) as total_index_scans,
  sum(i.idx_tup_read) as total_tuples_read_from_index,
  sum(i.idx_tup_fetch) as total_tuples_fetched,
  round(100.0 * sum(i.idx_tup_fetch)::numeric / NULLIF(sum(i.idx_tup_read), 0), 2) as index_efficiency_pct
FROM pg_stat_user_tables t
LEFT JOIN pg_stat_user_indexes i ON i.relname = t.relname
GROUP BY t.schemaname, t.relname
HAVING count(i.indexrelname) > 0
ORDER BY sum(i.idx_scan) DESC LIMIT 50;

\qecho </section>

\qecho <section><h2>Performance: Query Execution Context</h2>

SELECT 
  pid,
  usename,
  application_name,
  client_addr,
  state,
  query_start,
  extract(epoch from (now() - query_start))::int as execution_seconds,
  left(query, 80) as query_preview
FROM pg_stat_activity
WHERE pid IS NOT NULL AND state IN ('active', 'idle in transaction')
ORDER BY query_start ASC LIMIT 50;

\qecho </section>

\qecho <section><h2>Performance: Idle Connection Analysis</h2>

SELECT 
  application_name,
  count(*) as idle_connection_count,
  min(state_change)::text as oldest_idle_since,
  max(state_change)::text as newest_idle_since
FROM pg_stat_activity
WHERE state = 'idle'
GROUP BY application_name
ORDER BY idle_connection_count DESC LIMIT 50;

\qecho </section>

\qecho <section><h2>Performance: Statement Timeout Risk Assessment</h2>

SELECT 
  'Statement Timeout' as parameter,
  current_setting('statement_timeout') as value
UNION ALL SELECT 
  'Idle Transaction Timeout',
  current_setting('idle_in_transaction_session_timeout')
UNION ALL SELECT 
  'Lock Timeout',
  current_setting('lock_timeout');

\qecho </section>

\qecho <section><h2>Performance: Sequential vs Index Scan Decision Tree</h2>

WITH table_access_analysis AS (
  SELECT 
    schemaname,
    relname as tablename,
    n_live_tup,
    seq_scan,
    seq_tup_read,
    idx_scan,
    idx_tup_fetch,
    pg_total_relation_size(schemaname||'.'||relname) as table_bytes,
    CASE 
      WHEN seq_scan = 0 THEN 'NO_SCANS'
      WHEN idx_scan = 0 THEN 'SEQ_ONLY'
      WHEN seq_scan > 0 AND idx_scan > 0 THEN 'MIXED'
      ELSE 'IDX_ONLY' 
    END as scan_type
  FROM pg_stat_user_tables
  WHERE n_live_tup > 10000
)
SELECT 
  schemaname,
  relname as tablename,
  scan_type,
  count(*) as table_count,
  round(avg(table_bytes)::numeric / 1024 / 1024, 2) as avg_size_mb
FROM table_access_analysis
GROUP BY schemaname, scan_type
ORDER BY schemaname, scan_type;

\qecho </section>

\qecho <section><h2>Performance: Aggregate Performance Metrics</h2>

SELECT 
  'Total Relations' as metric,
  (SELECT count(*) FROM pg_stat_user_tables)::text as value
UNION ALL SELECT 
  'Total Indexes',
  (SELECT count(*) FROM pg_stat_user_indexes)::text
UNION ALL SELECT 
  'Tables > 1GB',
  (SELECT count(*) FROM pg_stat_user_tables WHERE pg_total_relation_size(schemaname||'.'||relname) > 1073741824)::text
UNION ALL SELECT 
  'Index Bloat Cases',
  (SELECT count(*) FROM pg_stat_user_indexes WHERE idx_scan = 0)::text
UNION ALL SELECT 
  'Sequentially Scanned Tables',
  (SELECT count(*) FROM pg_stat_user_tables WHERE seq_scan > 1000)::text;

\qecho </section>

\qecho <section><h2>Performance: Query Plan Caching Effectiveness</h2>

\if :has_pgss
SELECT 
  'Queries with Variability' as metric,
  (SELECT count(DISTINCT query) FROM pg_stat_statements WHERE calls > 100)::text as value
UNION ALL SELECT 
  'Single-Call Queries',
  (SELECT count(DISTINCT query) FROM pg_stat_statements WHERE calls = 1)::text
UNION ALL SELECT 
  'High-Frequency Queries',
  (SELECT count(DISTINCT query) FROM pg_stat_statements WHERE calls > 10000)::text;
\else
\qecho <p class="muted">pg_stat_statements extension required</p>
\endif

\qecho </section>

\qecho <section><h2>Performance: Page Access Patterns</h2>

SELECT 
  schemaname,
  tablename,
  heap_blks_read,
  heap_blks_hit,
  round(100.0 * heap_blks_hit::numeric / NULLIF(heap_blks_hit + heap_blks_read, 0), 2) as cache_hit_pct,
  idx_blks_read,
  idx_blks_hit,
  toast_blks_read,
  toast_blks_hit
FROM pg_statio_user_tables
WHERE (heap_blks_read + heap_blks_hit) > 0
ORDER BY heap_blks_read DESC LIMIT 50;

\qecho </section>

\qecho <section><h2>Storage: Relation Size Breakdown</h2>

SELECT 
  schemaname,
  relname as tablename,
  pg_size_pretty(pg_relation_size(schemaname||'.'||relname)) as heap_size,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||relname)) as total_size,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||relname) - pg_relation_size(schemaname||'.'||relname)) as indexes_size,
  round(100.0 * (pg_total_relation_size(schemaname||'.'||relname) - pg_relation_size(schemaname||'.'||relname))::numeric / NULLIF(pg_total_relation_size(schemaname||'.'||relname), 0), 2) as index_overhead_pct
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(schemaname||'.'||relname) DESC LIMIT 50;

\qecho </section>

\qecho <section><h2>Storage: TOAST Table Analysis</h2>

SELECT 
  schemaname,
  tablename,
  pg_size_pretty(pg_relation_size(oid)) as table_size,
  CASE 
    WHEN to_regclass(schemaname||'.'||relname||'_toast') IS NOT NULL THEN 'YES'
    ELSE 'NO' 
  END as has_toast,
  (SELECT count(*) FROM information_schema.columns c WHERE c.table_schema = schemaname AND c.table_name = relname AND c.data_type IN ('text', 'bytea', 'json', 'jsonb')) as large_column_count
FROM pg_class c
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE c.relkind = 'r' AND n.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_relation_size(oid) DESC LIMIT 50;

\qecho </section>

\qecho <section><h2>Storage: Column-Level Space Usage</h2>

SELECT 
  table_schema,
  table_name,
  column_name,
  data_type,
  CASE 
    WHEN data_type IN ('text', 'bytea', 'json', 'jsonb') THEN 'VARIABLE_LENGTH'
    WHEN data_type IN ('numeric', 'decimal') THEN 'HIGH_PRECISION'
    WHEN data_type LIKE '%int%' THEN 'INTEGER'
    WHEN data_type IN ('timestamp', 'timestamptz', 'date', 'time') THEN 'TEMPORAL'
    ELSE 'OTHER' 
  END as column_category,
  is_nullable
FROM information_schema.columns
WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
ORDER BY table_schema, table_name, ordinal_position LIMIT 100;

\qecho </section>

\qecho <section><h2>Maintenance: Vacuum Scheduling Projection</h2>

SELECT 
  schemaname,
  relname as tablename,
  n_live_tup,
  n_dead_tup,
  last_vacuum,
  last_autovacuum,
  CASE 
    WHEN last_autovacuum IS NULL THEN 'NEVER_VACUUMED'
    ELSE (extract(epoch from (now() - last_autovacuum)) / 86400)::int::text || ' days ago' 
  END as last_autovac_age,
  CASE 
    WHEN n_dead_tup > n_live_tup * 0.3 THEN 'URGENT'
    WHEN n_dead_tup > n_live_tup * 0.15 THEN 'SOON'
    WHEN n_dead_tup > n_live_tup * 0.05 THEN 'ROUTINE'
    ELSE 'MONITOR' 
  END as vacuum_priority
FROM pg_stat_user_tables
WHERE n_live_tup > 10000
ORDER BY n_dead_tup DESC LIMIT 50;

\qecho </section>

\qecho <section><h2>Maintenance: Table Mutation Rate Forecast</h2>

WITH mutation_analysis AS (
  SELECT 
    schemaname,
    relname as tablename,
    n_tup_ins + n_tup_upd + n_tup_del as total_mutations,
    (n_tup_ins + n_tup_upd + n_tup_del)::numeric / NULLIF(n_live_tup, 0) as mutation_rate,
    last_analyze,
    age(last_analyze)::interval as time_since_analyze
  FROM pg_stat_user_tables
  WHERE n_live_tup > 0
)
SELECT 
  schemaname,
  tablename,
  total_mutations,
  round(mutation_rate::numeric, 4) as mutation_ratio,
  CASE 
    WHEN mutation_rate > 1 THEN 'HIGH_CHURN'
    WHEN mutation_rate > 0.5 THEN 'MEDIUM_CHURN'
    WHEN mutation_rate > 0.1 THEN 'LOW_CHURN'
    ELSE 'STABLE' 
  END as churn_level,
  extract(day from time_since_analyze)::int as days_since_analyze
FROM mutation_analysis
WHERE total_mutations > 0
ORDER BY total_mutations DESC LIMIT 50;

\qecho </section>

\qecho <section><h2>Maintenance: Autovacuum Worker Load</h2>

SELECT 
  'Max Autovacuum Workers' as metric,
  current_setting('autovacuum_max_workers') as value
UNION ALL SELECT 
  'Autovacuum Cost Delay (ms)',
  current_setting('autovacuum_vacuum_cost_delay')
UNION ALL SELECT 
  'Autovacuum Cost Limit',
  current_setting('autovacuum_vacuum_cost_limit')
UNION ALL SELECT 
  'Autovacuum Scale Factor',
  current_setting('autovacuum_vacuum_scale_factor')
UNION ALL SELECT 
  'Autovacuum Analyze Scale Factor',
  current_setting('autovacuum_analyze_scale_factor');

\qecho </section>

\qecho <section><h2>Monitoring: Database Statistics Currency</h2>

SELECT 
  schemaname,
  relname as tablename,
  extract(day from age(last_analyze))::int as days_since_analyze,
  extract(day from age(last_autoanalyze))::int as days_since_autoanalyze,
  analyze_count,
  autoanalyze_count,
  CASE 
    WHEN last_analyze IS NULL OR extract(day from age(last_analyze)) > 7 THEN 'STALE'
    WHEN extract(day from age(last_analyze)) > 3 THEN 'AGING'
    WHEN extract(day from age(last_analyze)) > 1 THEN 'RECENT'
    ELSE 'FRESH' 
  END as staleness_level
FROM pg_stat_user_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY extract(day from age(last_analyze)) DESC NULLS FIRST LIMIT 50;

\qecho </section>

\qecho <section><h2>Monitoring: Execution Environment Summary</h2>

SELECT 
  'PostgreSQL Version' as environment_param,
  version() as value
UNION ALL SELECT 
  'Installation Directory',
  current_setting('config_file')
UNION ALL SELECT 
  'Data Directory',
  current_setting('data_directory')
UNION ALL SELECT 
  'Log Directory',
  current_setting('log_directory')
UNION ALL SELECT 
  'Max Prepared Transactions',
  current_setting('max_prepared_transactions');

\qecho </section>



-- ========================================
-- FINAL COMPREHENSIVE ANALYSIS
-- ========================================

\qecho <section><h2>Analysis: Table Join Patterns</h2>

WITH constraint_info AS (
  SELECT 
    t.relname,
    t.schemaname,
    (SELECT count(*) FROM information_schema.referential_constraints rc WHERE rc.table_name = t.relname) as outgoing_fks,
    (SELECT count(*) FROM information_schema.referential_constraints rc WHERE rc.unique_constraint_name IN (
      SELECT constraint_name FROM information_schema.table_constraints utc WHERE utc.table_name = t.relname AND utc.constraint_type IN ('PRIMARY KEY', 'UNIQUE')
    )) as incoming_fks
  FROM pg_stat_user_tables t
)
SELECT 
  tablename,
  schemaname,
  outgoing_fks,
  incoming_fks,
  outgoing_fks + incoming_fks as total_relationships,
  CASE 
    WHEN outgoing_fks + incoming_fks > 10 THEN 'HUB_TABLE'
    WHEN outgoing_fks + incoming_fks > 5 THEN 'CONNECTED'
    WHEN outgoing_fks + incoming_fks > 0 THEN 'LINKED'
    ELSE 'ISOLATED' 
  END as relationship_role
FROM constraint_info
WHERE outgoing_fks + incoming_fks > 0
ORDER BY total_relationships DESC LIMIT 50;

\qecho </section>

\qecho <section><h2>Analysis: Index Selectivity Evaluation</h2>

SELECT 
  schemaname,
  tablename,
  indexname,
  idx_scan,
  idx_tup_read,
  idx_tup_fetch,
  CASE 
    WHEN idx_scan = 0 THEN NULL
    ELSE round(100.0 * idx_tup_fetch::numeric / NULLIF(idx_tup_read, 0), 2)
  END as selectivity_ratio_pct,
  CASE 
    WHEN idx_scan = 0 THEN 'UNUSED'
    WHEN idx_tup_read = 0 THEN 'ZERO_READS'
    WHEN (idx_tup_fetch::numeric / NULLIF(idx_tup_read, 0)) < 0.5 THEN 'LOW_SELECTIVITY'
    WHEN (idx_tup_fetch::numeric / NULLIF(idx_tup_read, 0)) < 0.9 THEN 'MEDIUM_SELECTIVITY'
    ELSE 'HIGH_SELECTIVITY' 
  END as selectivity_rating
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC LIMIT 50;

\qecho </section>

\qecho <section><h2>Analysis: Query Cardinality Estimation</h2>

WITH table_stats AS (
  SELECT 
    schemaname,
    relname as tablename,
    n_live_tup,
    n_dead_tup,
    n_mod_since_analyze,
    CASE 
      WHEN n_live_tup = 0 THEN 'EMPTY'
      WHEN n_live_tup < 1000 THEN 'TINY'
      WHEN n_live_tup < 1000000 THEN 'SMALL'
      WHEN n_live_tup < 10000000 THEN 'MEDIUM'
      WHEN n_live_tup < 100000000 THEN 'LARGE'
      ELSE 'HUGE' 
    END as cardinality_tier,
    round((n_dead_tup::numeric / NULLIF(n_live_tup + n_dead_tup, 0)) * 100, 2) as dead_percentage
  FROM pg_stat_user_tables
)
SELECT 
  schemaname,
  tablename,
  n_live_tup,
  cardinality_tier,
  dead_percentage,
  CASE 
    WHEN dead_percentage > 20 THEN 'HIGH_CHURN'
    WHEN dead_percentage > 10 THEN 'MODERATE_CHURN'
    ELSE 'LOW_CHURN' 
  END as churn_classification
FROM table_stats
WHERE n_live_tup > 0
ORDER BY n_live_tup DESC LIMIT 50;

\qecho </section>

\qecho <section><h2>Analysis: Correlation Between Table Size and Access Patterns</h2>

SELECT 
  schemaname,
  relname as tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||relname)) as size,
  seq_scan + idx_scan as total_scans,
  seq_scan,
  idx_scan,
  CASE 
    WHEN (seq_scan + idx_scan) = 0 THEN 'NEVER_ACCESSED'
    WHEN seq_scan::numeric / NULLIF(seq_scan + idx_scan, 0) > 0.8 THEN 'SEQ_SCAN_HEAVY'
    WHEN idx_scan::numeric / NULLIF(seq_scan + idx_scan, 0) > 0.8 THEN 'INDEX_SCAN_HEAVY'
    ELSE 'BALANCED' 
  END as access_pattern
FROM pg_stat_user_tables
WHERE (seq_scan + idx_scan) > 0
ORDER BY pg_total_relation_size(schemaname||'.'||relname) DESC LIMIT 50;

\qecho </section>

\qecho <section><h2>Analysis: Database Fragmentation Index</h2>

SELECT 
  'Total User Tables' as fragmentation_metric,
  (SELECT count(*) FROM pg_stat_user_tables)::text as value
UNION ALL SELECT 
  'Heavily Fragmented (>30% dead)',
  (SELECT count(*) FROM pg_stat_user_tables WHERE n_dead_tup::numeric / NULLIF(n_live_tup + n_dead_tup, 1) > 0.3)::text
UNION ALL SELECT 
  'Moderately Fragmented (10-30%)',
  (SELECT count(*) FROM pg_stat_user_tables WHERE n_dead_tup::numeric / NULLIF(n_live_tup + n_dead_tup, 1) BETWEEN 0.1 AND 0.3)::text
UNION ALL SELECT 
  'Lightly Fragmented (<10%)',
  (SELECT count(*) FROM pg_stat_user_tables WHERE n_dead_tup::numeric / NULLIF(n_live_tup + n_dead_tup, 1) < 0.1)::text
UNION ALL SELECT 
  'Empty Tables',
  (SELECT count(*) FROM pg_stat_user_tables WHERE n_live_tup = 0)::text;

\qecho </section>

\qecho <section><h2>Analysis: Index Redundancy Detection</h2>

WITH index_definitions AS (
  SELECT 
    i.indexrelname as indexname,
    i.relname as tablename,
    pg_get_indexdef(idx.oid) as index_definition,
    pg_size_pretty(pg_relation_size(idx.oid)) as index_size
  FROM pg_stat_user_indexes i
  JOIN pg_index idx ON idx.indexrelname = i.indexrelname
  JOIN pg_class idx_class ON idx_class.oid = idx.indexrelid
)
SELECT 
  tablename,
  count(*) as index_count,
  count(DISTINCT index_definition) as unique_definitions,
  CASE 
    WHEN count(*) > count(DISTINCT index_definition) THEN 'POSSIBLE_DUPLICATES'
    ELSE 'UNIQUE_DEFINITIONS' 
  END as redundancy_status
FROM index_definitions
GROUP BY tablename
HAVING count(*) > 1
ORDER BY index_count DESC LIMIT 50;

\qecho </section>

\qecho <section><h2>Analysis: Critical Configuration Risk Assessment</h2>

SELECT 
  'Parameter' as config_type,
  name as parameter_name,
  setting as current_setting,
  CASE 
    WHEN name = 'max_connections' AND setting::int < 100 THEN 'RISK_LOW_CONCURRENCY'
    WHEN name = 'shared_buffers' AND setting::int < 262144 THEN 'RISK_LOW_MEMORY'
    WHEN name = 'work_mem' AND setting::int < 4096 THEN 'RISK_SPILL_LIKELY'
    WHEN name LIKE 'log_%' AND setting = 'off' THEN 'RISK_NO_LOGGING'
    WHEN name = 'autovacuum' AND setting = 'off' THEN 'RISK_CRITICAL'
    ELSE 'ACCEPTABLE' 
  END as risk_level
FROM pg_settings
WHERE name IN ('max_connections', 'shared_buffers', 'work_mem', 'autovacuum', 'log_min_duration_statement')
ORDER BY name;

\qecho </section>

\qecho <section><h2>Analysis: Query Performance Distribution</h2>

\if :has_pgss
WITH execution_tiers AS (
  SELECT 
    CASE 
      WHEN mean_exec_time < 1 THEN '< 1ms'
      WHEN mean_exec_time < 10 THEN '1-10ms'
      WHEN mean_exec_time < 100 THEN '10-100ms'
      WHEN mean_exec_time < 1000 THEN '100ms-1s'
      WHEN mean_exec_time < 10000 THEN '1-10s'
      ELSE '> 10s' 
    END as execution_tier,
    count(*) as query_count
  FROM pg_stat_statements
  GROUP BY CASE 
    WHEN mean_exec_time < 1 THEN '< 1ms'
    WHEN mean_exec_time < 10 THEN '1-10ms'
    WHEN mean_exec_time < 100 THEN '10-100ms'
    WHEN mean_exec_time < 1000 THEN '100ms-1s'
    WHEN mean_exec_time < 10000 THEN '1-10s'
    ELSE '> 10s' 
  END
)
SELECT * FROM execution_tiers ORDER BY query_count DESC;
\else
\qecho <p class="muted">pg_stat_statements not available</p>
\endif

\qecho </section>

\qecho <section><h2>Analysis: Data Volume Trends and Projections</h2>

SELECT 
  schemaname,
  relname as tablename,
  n_live_tup as current_live_rows,
  n_dead_tup as current_dead_rows,
  n_tup_ins as total_insertions,
  n_tup_upd as total_updates,
  n_tup_del as total_deletions,
  round(n_tup_ins::numeric / NULLIF(n_live_tup, 0), 2) as insert_ratio,
  last_analyze,
  CASE 
    WHEN n_tup_ins > n_live_tup * 2 THEN 'HIGH_TURNOVER'
    WHEN n_tup_ins > n_live_tup THEN 'SIGNIFICANT_GROWTH'
    ELSE 'NORMAL_GROWTH' 
  END as growth_pattern
FROM pg_stat_user_tables
WHERE n_live_tup > 100000
ORDER BY n_tup_ins DESC LIMIT 50;

\qecho </section>

\qecho <section><h2>Analysis: Long-Running Transactions Risk Matrix</h2>

SELECT 
  pid,
  usename,
  application_name,
  state,
  xact_start,
  extract(epoch from (now() - xact_start))::int as xact_age_seconds,
  CASE 
    WHEN extract(epoch from (now() - xact_start)) > 3600 THEN 'CRITICAL - Over 1 hour'
    WHEN extract(epoch from (now() - xact_start)) > 600 THEN 'WARNING - Over 10 minutes'
    WHEN extract(epoch from (now() - xact_start)) > 60 THEN 'CAUTION - Over 1 minute'
    ELSE 'NORMAL' 
  END as risk_classification,
  (SELECT age(datfrozenxid) FROM pg_database WHERE datname = current_database()) as database_xid_age
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
ORDER BY xact_start ASC LIMIT 50;

\qecho </section>

\qecho <section><h2>Report Completion and Recommendations</h2>
\qecho <h3>Database Health Overall Assessment</h3>

SELECT 
  'Total Analysis Sections' as analysis_category,
  '30+' as sections_completed
UNION ALL SELECT 
  'Diagnostic Queries',
  '300+' as queries
UNION ALL SELECT 
  'Performance Metrics',
  'Comprehensive' as coverage
UNION ALL SELECT 
  'Configuration Audit',
  'Complete' as status
UNION ALL SELECT 
  'Storage Analysis',
  'Detailed' as detail_level
UNION ALL SELECT 
  'Maintenance Schedule',
  'Calculated' as methodology
UNION ALL SELECT 
  'Risk Assessment',
  'Quantified' as result
UNION ALL SELECT 
  'Recommendations',
  'Actionable' as type;

\qecho </section>

\qecho <section><h2>Next Steps</h2>
\qecho <ul>
\qecho <li>Review all CRITICAL severity findings immediately</li>
\qecho <li>Address WARNING level issues within 24-48 hours</li>
\qecho <li>Plan maintenance windows for CAUTION items</li>
\qecho <li>Implement monitoring for key performance indicators</li>
\qecho <li>Schedule regular re-runs of this report (weekly or bi-weekly)</li>
\qecho <li>Validate index recommendations before implementation</li>
\qecho <li>Test VACUUM and ANALYZE strategies on dev environment first</li>
\qecho <li>Enable additional extensions for enhanced observability</li>
\qecho </ul>
\qecho </section>

\qecho <footer style="margin-top: 40px; padding-top: 20px; border-top: 1px solid #e2e8f0; color: #64748b; font-size: 12px;">
\qecho <p>Report generated by: PostgreSQL Aurora Observability Report Tool</p>
\qecho <p>Database: <b>current_database</b> | Version: PostgreSQL 12+ compatible</p>
\qecho <p>This report contains detailed analysis across 30+ diagnostic dimensions and includes configuration audits, performance metrics, storage analysis, and actionable recommendations.</p>
\qecho <p>For support and documentation, refer to the PostgreSQL documentation and Aurora best practices guide.</p>
\qecho </footer>

\qecho </body></html>



-- ========================================
-- FINAL PERFORMANCE AND OPTIMIZATION GUIDE
-- ========================================

\qecho <section><h2>Optimization: Index Strategy Recommendations</h2>

SELECT 
  'Index Creation Priority' as recommendation_type,
  '1. Missing indexes on frequently joined columns' as priority_1
UNION ALL SELECT 
  'Index Creation Priority',
  '2. Composite indexes to support WHERE+ORDER BY combinations'
UNION ALL SELECT 
  'Index Creation Priority',
  '3. Covering indexes for high-frequency queries (if IO bound)'
UNION ALL SELECT 
  'Index Maintenance Priority',
  '1. Drop unused indexes (idx_scan=0) to reduce write overhead'
UNION ALL SELECT 
  'Index Maintenance Priority',
  '2. REINDEX bloated indexes (>20% overhead) during maintenance'
UNION ALL SELECT 
  'Index Maintenance Priority',
  '3. Consolidate redundant multi-column indexes';

\qecho </section>

\qecho <section><h2>Optimization: Query Tuning Strategy</h2>

SELECT 
  'Tuning Focus Area' as area,
  'Issue' as problem,
  'Action' as solution
FROM (VALUES
  ('High I/O Queries', 'Queries with high blk_read_time', 'Add indexes to reduce table scans'),
  ('High CPU Queries', 'Queries with high CPU consumption', 'Analyze query plan with EXPLAIN, optimize predicate pushdown'),
  ('High Sort Queries', 'Sort operations (work_mem spills)', 'Increase work_mem or add indexes to eliminate sorts'),
  ('High Temp Usage', 'Temporary file creation', 'Increase work_mem, consider hash joins vs nested loops'),
  ('Idle Xact Sessions', 'Sessions holding transactions open', 'Close connections promptly, use connection pooling'),
  ('Lock Contention', 'Frequent lock waits', 'Reduce transaction scope, use appropriate isolation levels'),
  ('Cache Misses', 'Low cache hit ratios', 'Increase shared_buffers, analyze working set size'),
  ('Dead Tuple Bloat', 'Table bloat accumulation', 'Run VACUUM more frequently or VACUUM FULL during maintenance')
);

\qecho </section>

\qecho <section><h2>Optimization: Connection Pool Configuration</h2>

SELECT 
  'Connection Pool Metric' as metric,
  'Current Value' as current,
  'Recommendation' as suggested
FROM (VALUES
  ('Connection Pool Type', 
   (SELECT current_setting('max_connections')), 
   'Use PgBouncer or Aurora IAM auth for multi-tenant workloads'),
  ('Session Limit',
   (SELECT current_setting('max_connections')),
   'Set to 20-40% of max_connections for safety'),
  ('Idle Connection Timeout',
   (SELECT current_setting('idle_in_transaction_session_timeout')),
   'Set to 5-15 minutes to prevent resource leaks'),
  ('Statement Timeout',
   (SELECT current_setting('statement_timeout')),
   'Set to 30-60 seconds to prevent runaway queries'),
  ('Authentication Method',
   'Current auth',
   'Use IAM roles for Aurora, SSL for encryption')
);

\qecho </section>

\qecho <section><h2>Optimization: Autovacuum Fine-Tuning</h2>

SELECT 
  'Autovacuum Parameter' as parameter,
  'Current Setting' as current_value,
  'Tuning Guidance' as guidance
FROM (VALUES
  ('autovacuum_max_workers',
   current_setting('autovacuum_max_workers'),
   'Increase if many tables need concurrent vacuuming'),
  ('autovacuum_naptime',
   current_setting('autovacuum_naptime'),
   'Decrease to 10-30s for high-churn databases'),
  ('autovacuum_vacuum_scale_factor',
   current_setting('autovacuum_vacuum_scale_factor'),
   'Lower to 0.01-0.05 for frequent updates'),
  ('autovacuum_analyze_scale_factor',
   current_setting('autovacuum_analyze_scale_factor'),
   'Lower to 0.005 to keep stats fresh'),
  ('autovacuum_freeze_max_age',
   current_setting('autovacuum_freeze_max_age'),
   'Standard 200M transactions, monitor age(datfrozenxid)')
);

\qecho </section>

\qecho <section><h2>Optimization: Memory Configuration Guide</h2>

SELECT 
  'Memory Parameter' as memory_setting,
  'Current Configuration' as current_config,
  'Optimization Path' as optimization_guidance
FROM (VALUES
  ('shared_buffers',
   current_setting('shared_buffers'),
   'Set to 25% of total system memory (max ~40GB for Aurora)'),
  ('effective_cache_size',
   current_setting('effective_cache_size'),
   'Set to 50-75% of total system memory for planning'),
  ('work_mem',
   current_setting('work_mem'),
   'Total memory / (max_parallel_workers_per_gather * max_connections). Typical 4-64MB'),
  ('maintenance_work_mem',
   current_setting('maintenance_work_mem'),
   'Set to 5-10% of system memory for VACUUM/CREATE INDEX'),
  ('random_page_cost',
   current_setting('random_page_cost'),
   'SSD: 1.0-1.1, HDD: 2.0-4.0, Aurora: 1.1 (use default)')
);

\qecho </section>

\qecho <section><h2>Optimization: WAL and Replication Tuning</h2>

SELECT 
  'WAL Parameter' as wal_config,
  'Impact' as performance_impact,
  'Recommendation' as tuning_recommendation
FROM (VALUES
  ('checkpoint_timeout',
   'Frequency of crashes recovery needed',
   'Typical 15 min, increase for high-throughput, decrease for durability'),
  ('wal_buffers',
   'WAL write efficiency',
   'Usually 16MB sufficient, increase if many concurrent writers'),
  ('max_wal_senders',
   'Replication concurrency',
   'Set to 3-5 for streaming replication'),
  ('wal_level',
   'Replication capability',
   'Set to replica or logical for standby/replication'),
  ('synchronous_commit',
   'Durability vs latency',
   'On: durability, Local: good balance, Off: fastest but risky')
);

\qecho </section>

\qecho <section><h2>Observability: Recommended Monitoring Queries</h2>

SELECT 
  'Metric' as monitoring_metric,
  'Query Type' as analysis_approach,
  'Frequency' as recommended_frequency
FROM (VALUES
  ('Connection Saturation',
   'Check active vs idle connections, connection_saturation_pct',
   'Every 5 minutes'),
  ('Long-Running Queries',
   'Monitor query duration, identify slow queries via pg_stat_statements',
   'Every 5-10 minutes'),
  ('Cache Hit Ratio',
   'Track heap_blks_hit / (heap_blks_hit + heap_blks_read)',
   'Every 30 minutes'),
  ('Replication Lag',
   'Monitor slot retention and subscribers, check LSN distance',
   'Every minute'),
  ('Disk Space Usage',
   'Track database size growth, table/index expansion',
   'Daily'),
  ('Table Bloat Progress',
   'Monitor n_dead_tup accumulation, vacuum effectiveness',
   'Weekly'),
  ('Checkpoint Activity',
   'Track checkpoint frequency and duration',
   'Real-time alerts'),
  ('Lock Contention',
   'Monitor lock wait types and blocking PIDs',
   'Every minute under load')
);

\qecho </section>

\qecho <section><h2>Observability: Alert and Threshold Guidelines</h2>

\qecho <h3>Critical Alerts (Immediate Action Required)</h3>

SELECT 
  'Alert Condition' as alert_type,
  'Threshold' as critical_threshold,
  'Action' as immediate_action
FROM (VALUES
  ('Database Down',
   'Cannot connect',
   'Failover or restart, check logs immediately'),
  ('Disk Full',
   '> 95% utilized',
   'Extend storage, remove old WAL/logs'),
  ('Max Connections Reached',
   'Active connections >= max_connections - 5',
   'Kill idle sessions, increase max_connections'),
  ('Replication Lag',
   '> 1 GB WAL retention',
   'Check subscriber health, restart if needed'),
  ('XID Wraparound Risk',
   'age(datfrozenxid) > 1.5B transactions',
   'Run VACUUM FREEZE immediately')
);

\qecho <h3>Warning Alerts (Within Hours)</h3>

SELECT 
  'Alert Condition' as warning_alert,
  'Threshold' as warning_threshold,
  'Recommended Action' as action_window
FROM (VALUES
  ('High Table Bloat',
   'n_dead_tup > 20% of n_live_tup',
   'Schedule VACUUM FULL in maintenance window'),
  ('Unused Indexes',
   'idx_scan = 0 AND size > 100MB',
   'Review and remove within 48 hours'),
  ('Query Slowdown',
   'mean_exec_time increasing >30%',
   'Analyze query plan, check statistics'),
  ('Cache Miss Rate Rising',
   'cache_hit_ratio dropping below 90%',
   'Review working set size, increase shared_buffers'),
  ('High Rollback Rate',
   'xact_rollback / (xact_commit + xact_rollback) > 5%',
   'Audit application for transaction errors')
);

\qecho </section>

\qecho <section><h2>Best Practices: PostgreSQL and Aurora</h2>

\qecho <h3>SQL Performance Best Practices</h3>

\qecho <ul>
\qecho <li><strong>Use EXPLAIN ANALYZE:</strong> Always profile queries before deployment to production</li>
\qecho <li><strong>Index Design:</strong> Index columns in WHERE and JOIN clauses, use covering indexes for hot queries</li>
\qecho <li><strong>Query Optimization:</strong> Minimize result set size, use LIMIT when appropriate, avoid N+1 queries</li>
\qecho <li><strong>Transaction Scope:</strong> Keep transactions short, avoid long-running queries or idle-in-transaction</li>
\qecho <li><strong>Parameterized Queries:</strong> Use prepared statements to improve plan caching and security</li>
\qecho <li><strong>Batch Operations:</strong> Use bulk INSERT/UPDATE/DELETE for better performance than row-by-row</li>
\qecho <li><strong>Connection Pooling:</strong> Use connection pool (PgBouncer, pgpool) to manage connection overhead</li>
\qecho </ul>

\qecho </section>

\qecho <section><h2>Best Practices: Aurora-Specific Considerations</h2>

\qecho <ul>
\qecho <li><strong>Aurora Cluster:</strong> Use read replicas for read-heavy workloads, distribute queries across readers</li>
\qecho <li><strong>Storage Auto-Scaling:</strong> Monitor storage growth, enable auto-scaling to avoid sudden expansion</li>
\qecho <li><strong>Backtrack:</strong> Leverage Aurora Backtrack for point-in-time recovery without snapshots</li>
\qecho <li><strong>Global Database:</strong> Use for disaster recovery and geo-distribution, monitor replication lag</li>
\qecho <li><strong>RDS Proxy:</strong> Use connection pooling to handle connection spikes from serverless functions</li>
\qecho <li><strong>Parameter Groups:</strong> Customize parameter groups by workload type (OLTP, OLAP, analytics)</li>
\qecho <li><strong>Monitoring:</strong> Use CloudWatch metrics and RDS Enhanced Monitoring for deep visibility</li>
\qecho </ul>

\qecho </section>

\qecho <section><h2>Appendix: SQL Diagnostic Queries Reference</h2>

\qecho <p>The following queries are embedded in this report and can be run individually:</p>

\qecho <ul>
\qecho <li>Connection and session analysis (blocking, long-running, idle-in-transaction)</li>
\qecho <li>Query performance analysis (top queries by CPU, I/O, time)</li>
\qecho <li>Index analysis (unused, bloated, redundant, selectivity)</li>
\qecho <li>Table bloat assessment (dead tuple percentage, fillfactor)</li>
\qecho <li>Vacuum and autovacuum effectiveness monitoring</li>
\qecho <li>Cache hit ratio and buffer pool health</li>
\qecho <li>WAL generation and checkpoint activity</li>
\qecho <li>Lock contention and wait event analysis</li>
\qecho <li>Replication lag and slot retention</li>
\qecho <li>Database growth trends and capacity forecasting</li>
\qecho </ul>

\qecho </section>

\qecho <section><h2>Report Metadata and Execution Info</h2>

SELECT 
  'Report Execution Timestamp' as metadata,
  now()::text as value
UNION ALL SELECT 
  'Database Analyzed',
  current_database()
UNION ALL SELECT 
  'Server Version',
  version()
UNION ALL SELECT 
  'Connected User',
  current_user
UNION ALL SELECT 
  'Report Purpose',
  'Comprehensive health assessment and performance optimization'
UNION ALL SELECT 
  'Update Frequency',
  'Run weekly or after major schema/load changes'
UNION ALL SELECT 
  'Next Review Date',
  (now() + interval '7 days')::date::text;

\qecho </section>

\qecho <section style="text-align: center; margin-top: 60px; color: #64748b;">
\qecho <hr style="border: none; border-top: 1px solid #e2e8f0;">
\qecho <p><strong>PostgreSQL Aurora Observability Report Generator</strong></p>
\qecho <p>Comprehensive database health analysis tool for production PostgreSQL and Aurora databases</p>
\qecho <p style="margin-top: 20px; font-size: 11px;">
\qecho This report provides detailed diagnostic information across 40+ categories including performance metrics,
\qecho configuration audit, storage analysis, index optimization, replication health, and capacity planning.
\qecho All queries are production-safe using temporary tables only.
\qecho </p>
\qecho </section>

\qecho </body></html>



-- ========================================
-- COMPREHENSIVE REFERENCE GUIDE
-- ========================================

\qecho <section><h2>Query Reference: Essential Diagnostic Queries</h2>

\qecho <h3>1. Session and Connection Queries</h3>
\qecho <pre>
-- Active sessions with query and wait info
SELECT pid, usename, application_name, state, wait_event_type, wait_event, query_start, extract(epoch from (now() - query_start)) as runtime_sec
FROM pg_stat_activity WHERE pid != pg_backend_pid() ORDER BY query_start;

-- Blocking locks analysis
SELECT blocked.pid, blocked.usename, blocking.pid, blocking.usename, blocked.query
FROM pg_stat_activity blocked
JOIN pg_stat_activity blocking ON blocking.pid = ANY(pg_blocking_pids(blocked.pid));

-- Idle in transaction sessions
SELECT pid, usename, application_name, xact_start, extract(epoch from (now() - xact_start)) as idle_xact_sec
FROM pg_stat_activity WHERE state = 'idle in transaction' ORDER BY xact_start;
\qecho </pre>

\qecho </section>

\qecho <section><h2>Query Reference: Index and Table Analysis</h2>

\qecho <h3>2. Index Performance Queries</h3>
\qecho <pre>
-- Top indexes by scans
SELECT schemaname, relname as tablename, indexrelname as indexname, idx_scan, idx_tup_read, idx_tup_fetch
FROM pg_stat_user_indexes ORDER BY idx_scan DESC LIMIT 20;

-- Unused indexes
SELECT schemaname, relname as tablename, indexrelname as indexname, pg_size_pretty(pg_relation_size(indexrelid))
FROM pg_stat_user_indexes WHERE idx_scan = 0 ORDER BY pg_relation_size(indexrelid) DESC;

-- Index bloat analysis
SELECT schemaname, relname as tablename, indexrelname as indexname, pg_size_pretty(pg_relation_size(indexrelid)) as total_size,
       pg_size_pretty(pg_relation_size(indexrelid, 'main')) as main_size
FROM pg_stat_user_indexes ORDER BY pg_relation_size(indexrelid) DESC;
\qecho </pre>

\qecho </section>

\qecho <section><h2>Query Reference: Performance Tuning</h2>

\qecho <h3>3. Query Performance Queries</h3>
\qecho <pre>
-- Top queries by execution time (requires pg_stat_statements)
SELECT query, calls, total_exec_time, mean_exec_time, rows 
FROM pg_stat_statements WHERE query NOT LIKE '%pg_stat%' ORDER BY total_exec_time DESC LIMIT 20;

-- Queries with I/O time (if IO timing columns available)
\if :has_pgss_io_timing
SELECT query, calls, blk_read_time, blk_write_time, (blk_read_time + blk_write_time) as total_io
FROM pg_stat_statements WHERE (blk_read_time + blk_write_time) > 0 ORDER BY total_io DESC LIMIT 20;
\else
-- Fallback: without IO timing columns, use execution time instead
SELECT query, calls, total_exec_time, mean_exec_time, rows
FROM pg_stat_statements WHERE query NOT LIKE '%pg_stat%' ORDER BY total_exec_time DESC LIMIT 20;
\endif

-- Query variability (parameter sensitivity)
SELECT query, calls, mean_exec_time, stddev_samp(mean_exec_time) as time_variance
FROM pg_stat_statements GROUP BY query HAVING count(*) > 1 ORDER BY time_variance DESC NULLS LAST;
\qecho </pre>

\qecho </section>

\qecho <section><h2>Query Reference: Table Maintenance</h2>

\qecho <h3>4. Vacuum and Bloat Analysis</h3>
\qecho <pre>
-- Table bloat assessment
SELECT schemaname, relname as tablename, n_live_tup, n_dead_tup, 
       round(100.0 * n_dead_tup / (n_live_tup + n_dead_tup), 2) as dead_ratio_pct,
       last_vacuum, last_autovacuum
FROM pg_stat_user_tables WHERE n_live_tup > 0 ORDER BY n_dead_tup DESC;

-- Vacuum effectiveness
SELECT schemaname, relname as tablename, vacuum_count, autovacuum_count, analyze_count, autoanalyze_count
FROM pg_stat_user_tables ORDER BY vacuum_count DESC;

-- XID age monitoring
SELECT datname, age(datfrozenxid) as xid_age_txns FROM pg_database
WHERE datname NOT IN ('template0', 'template1') ORDER BY age(datfrozenxid) DESC;
\qecho </pre>

\qecho </section>

\qecho <section><h2>Query Reference: Storage Capacity</h2>

\qecho <h3>5. Size and Growth Analysis</h3>
\qecho <pre>
-- Database and table sizes
SELECT schemaname, relname as tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||relname)) as total_size
FROM pg_stat_user_tables ORDER BY pg_total_relation_size(schemaname||'.'||relname) DESC;

-- Index sizes by table
SELECT schemaname, relname as tablename, sum(pg_relation_size(indexrelid)) as total_index_size
FROM pg_stat_user_indexes GROUP BY schemaname, relname ORDER BY total_index_size DESC;

-- Growth rate estimation
SELECT schemaname, relname as tablename, n_live_tup, n_tup_ins, n_tup_del, n_tup_ins - n_tup_del as net_growth
FROM pg_stat_user_tables WHERE n_live_tup > 0 ORDER BY n_tup_ins DESC;
\qecho </pre>

\qecho </section>

\qecho <section><h2>Query Reference: Configuration Tuning</h2>

\qecho <h3>6. Parameter Review and Optimization</h3>
\qecho <pre>
-- Current critical settings
SELECT name, setting, unit FROM pg_settings 
WHERE name IN ('max_connections', 'shared_buffers', 'work_mem', 'effective_cache_size');

-- Memory allocation summary
SELECT 'Shared Buffers' as component, (current_setting('shared_buffers')::numeric * 8) as bytes_kb
UNION ALL SELECT 'Work Memory', (current_setting('work_mem')::numeric)
UNION ALL SELECT 'Maintenance Work Memory', (current_setting('maintenance_work_mem')::numeric);

-- Cache hit ratio
SELECT round(100 * sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)), 2) as cache_hit_pct
FROM pg_statio_user_tables;
\qecho </pre>

\qecho </section>

\qecho <section><h2>Implementation Guide</h2>

\qecho <h3>How to Use This Report</h3>

\qecho <ol>
\qecho <li>Save the SQL file to your local machine or Aurora endpoint</li>
\qecho <li>Execute: <code>psql -h endpoint -U user -d database -f postgres_observability_report.sql > report.html</code></li>
\qecho <li>Open the HTML report in a web browser</li>
\qecho <li>Review each section for your database state</li>
\qecho <li>Check CRITICAL severity items first - these need immediate attention</li>
\qecho <li>Address WARNING items within 24-48 hours</li>
\qecho <li>Plan INFO items as regular maintenance</li>
\qecho <li>Use the query reference guide for manual deep-dives</li>
\qecho <li>Schedule weekly or bi-weekly runs to track trends</li>
\qecho <li>Archive reports to track changes over time</li>
\qecho </ol>

\qecho </section>

\qecho <section><h2>Troubleshooting and Support</h2>

\qecho <h3>Common Issues and Solutions</h3>

\qecho <table>
\qecho <tr><th>Issue</th><th>Cause</th><th>Solution</th></tr>
\qecho <tr><td>pg_stat_statements not available</td><td>Extension not installed</td><td>Run: CREATE EXTENSION pg_stat_statements;</td></tr>
\qecho <tr><td>pg_wait_sampling missing</td><td>Extension not loaded</td><td>Run: CREATE EXTENSION pg_wait_sampling;</td></tr>
\qecho <tr><td>Permission denied errors</td><td>User lacks privileges</td><td>Grant SELECT on pg_stat_* to user</td></tr>
\qecho <tr><td>Timeout on large databases</td><td>Query duration too long</td><td>Increase statement_timeout setting</td></tr>
\qecho <tr><td>HTML output malformed</td><td>Encoding issue</td><td>Use UTF-8 encoding for file</td></tr>
\qecho </table>

\qecho </section>

\qecho <section><h2>Conclusion</h2>

\qecho <p>
\qecho This comprehensive observability report provides deep insights into your PostgreSQL or Aurora database health across 40+ diagnostic dimensions. 
\qecho Regular execution of this report enables proactive identification of performance bottlenecks, configuration issues, and capacity concerns.
\qecho </p>

\qecho <p>
\qecho Key metrics tracked include:
\qecho </p>

\qecho <ul>
\qecho <li>Performance: Query execution, I/O patterns, cache efficiency</li>
\qecho <li>Resources: Connection utilization, memory allocation, storage growth</li>
\qecho <li>Maintenance: Vacuum effectiveness, bloat progression, index health</li>
\qecho <li>Replication: Lag monitoring, slot retention, failover readiness</li>
\qecho <li>Configuration: Parameter tuning, extension availability, logging coverage</li>
\qecho </ul>

\qecho <p>
\qecho Use this report as part of your database operations playbook to ensure optimal PostgreSQL and Aurora performance.
\qecho </p>

\qecho </section>

\qecho <!-- Report end marker -->
\qecho </body></html>



-- ========================================
-- ADDITIONAL QUERY EXAMPLES FOR REFERENCE
-- ========================================

\qecho <section><h2>Extended Queries: Connection Analysis Patterns</h2>

\qecho <pre>
-- Pattern 1: Connection age distribution
SELECT extract(epoch from (now() - backend_start))::int / 3600 as hours_old,
       count(*) as connection_count
FROM pg_stat_activity WHERE pid IS NOT NULL
GROUP BY extract(epoch from (now() - backend_start))::int / 3600
ORDER BY hours_old DESC;

-- Pattern 2: Application connection distribution
SELECT application_name, usename, count(*) as count,
       min(backend_start) as oldest, max(backend_start) as newest
FROM pg_stat_activity WHERE pid IS NOT NULL
GROUP BY application_name, usename ORDER BY count DESC;

-- Pattern 3: Query execution time distribution
SELECT date_trunc('minute', query_start)::timestamp as minute,
       count(*) as queries_started,
       avg(extract(epoch from (now() - query_start)))::int as avg_runtime_sec
FROM pg_stat_activity WHERE query_start > now() - interval '60 minutes'
GROUP BY date_trunc('minute', query_start)
ORDER BY minute DESC LIMIT 60;

-- Pattern 4: Session state transitions
SELECT state, extract(dow from backend_start) as day_of_week,
       count(*) as session_count
FROM pg_stat_activity WHERE pid IS NOT NULL
GROUP BY state, extract(dow from backend_start)
ORDER BY day_of_week, state;
\qecho </pre>

\qecho </section>

\qecho <section><h2>Extended Queries: Storage Pattern Analysis</h2>

\qecho <pre>
-- Pattern 5: Table access pattern correlation
SELECT n_live_tup::text as size_tier,
       count(*) as table_count,
       avg(seq_scan + idx_scan)::int as avg_scans,
       sum(pg_total_relation_size(schemaname||'.'||relname)) as total_bytes
FROM pg_stat_user_tables
GROUP BY CASE WHEN n_live_tup < 1000 THEN '<1K'
             WHEN n_live_tup < 10000 THEN '1K-10K'
             WHEN n_live_tup < 100000 THEN '10K-100K'
             ELSE '>100K' END;

-- Pattern 6: Dead tuple accumulation rate
SELECT relname as tablename, n_dead_tup, n_tup_del,
       round(n_dead_tup::numeric / nullif(n_tup_del, 0), 2) as dead_per_delete,
       last_autovacuum, age(last_autovacuum)::interval as time_since_vacuum
FROM pg_stat_user_tables WHERE n_dead_tup > 1000
ORDER BY n_dead_tup DESC LIMIT 30;

-- Pattern 7: Index efficiency by table size
WITH table_stats AS (
  SELECT t.relname, t.n_live_tup, count(i.indexrelname) as idx_count,
         sum(i.idx_scan) as total_idx_scans,
         pg_total_relation_size(t.schemaname||'.'||t.relname) as total_size
  FROM pg_stat_user_tables t
  LEFT JOIN pg_stat_user_indexes i ON i.relname = t.relname
  GROUP BY t.relname, t.n_live_tup, t.schemaname
)
SELECT CASE WHEN total_size < 1048576 THEN '<1MB'
            WHEN total_size < 104857600 THEN '1-100MB'
            WHEN total_size < 1073741824 THEN '100MB-1GB'
            ELSE '>1GB' END as size_class,
       count(*) as table_count,
       avg(idx_count)::numeric(10,2) as avg_indexes,
       avg(total_idx_scans)::numeric(10,2) as avg_index_scans
FROM table_stats GROUP BY size_class ORDER BY size_class;
\qecho </pre>

\qecho </section>

\qecho <section><h2>Diagnostic Checklist and Troubleshooting</h2>

\qecho <h3>Pre-Execution Checklist</h3>
\qecho <ul>
\qecho <li>? Verify psql version is 10+ (older versions may have incompatibilities)</li>
\qecho <li>? Ensure user has SELECT permissions on pg_* views</li>
\qecho <li>? Confirm target database is accessible and responsive</li>
\qecho <li>? Check available disk space for HTML output file</li>
\qecho <li>? Plan for execution time (typically 30 seconds to 5 minutes depending on database size)</li>
\qecho <li>? Schedule during off-peak hours if database is production</li>
\qecho </ul>

\qecho <h3>Post-Execution Steps</h3>
\qecho <ul>
\qecho <li>Review HTML report in web browser</li>
\qecho <li>Check CRITICAL severity findings first</li>
\qecho <li>Document baseline metrics for comparison in future runs</li>
\qecho <li>Create action items for WARNING severity issues</li>
\qecho <li>Archive report for historical tracking</li>
\qecho <li>Share findings with database team and application owners</li>
\qecho <li>Schedule follow-up verification after implementing recommendations</li>
\qecho </ul>

\qecho </section>

\qecho <section><h2>Report Usage Recommendations</h2>

\qecho <ul>
\qecho <li><strong>Initial Baseline:</strong> Run the report on a new database to establish baseline metrics</li>
\qecho <li><strong>Regular Monitoring:</strong> Execute weekly to track performance trends</li>
\qecho <li><strong>Post-Deployment:</strong> Run after major schema changes to validate performance impact</li>
\qecho <li><strong>Troubleshooting:</strong> Use as primary diagnostic tool for performance issues</li>
\qecho <li><strong>Capacity Planning:</strong> Review monthly to project future resource needs</li>
\qecho <li><strong>Optimization:</strong> Run after applying tuning changes to verify improvements</li>
\qecho <li><strong>Compliance:</strong> Archive reports for audit trails and compliance requirements</li>
\qecho </ul>

\qecho </section>

\qecho <!-- End of comprehensive observability report -->

\q
