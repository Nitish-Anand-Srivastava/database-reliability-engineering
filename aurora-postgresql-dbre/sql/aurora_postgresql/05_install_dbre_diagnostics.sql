\set ON_ERROR_STOP on
\pset pager off

\echo Installing reusable dbre diagnostics helpers

CREATE SCHEMA IF NOT EXISTS dbre;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

CREATE OR REPLACE FUNCTION dbre.compact_query(query_text text, max_len integer DEFAULT 300)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT left(regexp_replace(coalesce(query_text, ''), '\s+', ' ', 'g'), greatest(max_len, 32));
$$;

CREATE OR REPLACE FUNCTION dbre.setting_value(setting_name text)
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT current_setting(setting_name, true);
$$;

CREATE OR REPLACE FUNCTION dbre.setting_numeric(setting_name text)
RETURNS numeric
LANGUAGE sql
STABLE
AS $$
  SELECT CASE unit
    WHEN '8kB' THEN setting::numeric * 8192
    WHEN 'kB' THEN setting::numeric * 1024
    WHEN 'MB' THEN setting::numeric * 1024 * 1024
    WHEN 'GB' THEN setting::numeric * 1024 * 1024 * 1024
    WHEN 'TB' THEN setting::numeric * 1024 * 1024 * 1024 * 1024
    WHEN 'ms' THEN setting::numeric
    WHEN 's' THEN setting::numeric * 1000
    WHEN 'min' THEN setting::numeric * 60000
    WHEN 'h' THEN setting::numeric * 3600000
    WHEN 'd' THEN setting::numeric * 86400000
    WHEN '' THEN setting::numeric
    ELSE NULL
  END
  FROM pg_settings
  WHERE name = setting_name;
$$;

CREATE OR REPLACE FUNCTION dbre.rel_fillfactor(rel_oid oid)
RETURNS integer
LANGUAGE sql
STABLE
AS $$
  SELECT coalesce(
    (
      SELECT substring(option FROM '[0-9]+')::integer
      FROM pg_class AS c
      CROSS JOIN LATERAL unnest(coalesce(c.reloptions, ARRAY[]::text[])) AS option
      WHERE c.oid = rel_oid
        AND option LIKE 'fillfactor=%'
      LIMIT 1
    ),
    100
  );
$$;

CREATE OR REPLACE FUNCTION dbre.instance_overview()
RETURNS TABLE (
  collected_at timestamptz,
  current_database name,
  server_version text,
  aurora_version text,
  postmaster_start_time timestamptz,
  instance_uptime interval,
  recovery_state boolean,
  max_connections integer,
  superuser_reserved_connections integer,
  shared_buffers text,
  effective_cache_size text,
  work_mem text,
  maintenance_work_mem text,
  max_worker_processes integer,
  max_parallel_workers integer,
  max_parallel_workers_per_gather integer,
  autovacuum_max_workers integer,
  track_io_timing text,
  shared_preload_libraries text,
  statement_timeout text,
  lock_timeout text,
  idle_in_transaction_session_timeout text
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    clock_timestamp(),
    current_database(),
    current_setting('server_version'),
    current_setting('aurora_version', true),
    pg_postmaster_start_time(),
    age(clock_timestamp(), pg_postmaster_start_time()),
    pg_is_in_recovery(),
    current_setting('max_connections')::integer,
    current_setting('superuser_reserved_connections')::integer,
    current_setting('shared_buffers'),
    current_setting('effective_cache_size'),
    current_setting('work_mem'),
    current_setting('maintenance_work_mem'),
    current_setting('max_worker_processes')::integer,
    current_setting('max_parallel_workers')::integer,
    current_setting('max_parallel_workers_per_gather')::integer,
    current_setting('autovacuum_max_workers')::integer,
    current_setting('track_io_timing'),
    current_setting('shared_preload_libraries'),
    current_setting('statement_timeout'),
    current_setting('lock_timeout'),
    current_setting('idle_in_transaction_session_timeout');
$$;

CREATE OR REPLACE FUNCTION dbre.who_is_active(p_limit integer DEFAULT 25)
RETURNS TABLE (
  pid integer,
  usename name,
  datname name,
  application_name text,
  client_addr text,
  backend_type text,
  state text,
  wait_event_type text,
  wait_event text,
  xact_age interval,
  query_age interval,
  session_age interval,
  blocker_count integer,
  query_text text
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    a.pid,
    a.usename,
    a.datname,
    coalesce(nullif(a.application_name, ''), '(unknown)'),
    coalesce(a.client_addr::text, 'local'),
    a.backend_type,
    a.state,
    a.wait_event_type,
    a.wait_event,
    coalesce(age(clock_timestamp(), a.xact_start), interval '0'),
    coalesce(age(clock_timestamp(), a.query_start), interval '0'),
    age(clock_timestamp(), a.backend_start),
    cardinality(pg_blocking_pids(a.pid)),
    dbre.compact_query(a.query, 320)
  FROM pg_stat_activity AS a
  WHERE a.pid <> pg_backend_pid()
  ORDER BY
    coalesce(age(clock_timestamp(), a.xact_start), interval '0') DESC,
    coalesce(age(clock_timestamp(), a.query_start), interval '0') DESC,
    a.pid
  LIMIT greatest(p_limit, 1);
$$;

CREATE OR REPLACE FUNCTION dbre.blocking_overview()
RETURNS TABLE (
  blocked_pid integer,
  blocker_pid integer,
  blocked_user name,
  blocker_user name,
  blocked_app text,
  blocker_app text,
  blocked_client text,
  blocker_client text,
  wait_event_type text,
  wait_event text,
  blocked_xact_age interval,
  blocker_xact_age interval,
  blocked_query_age interval,
  blocker_query_age interval,
  blocked_state text,
  blocker_state text,
  blocked_query text,
  blocker_query text
)
LANGUAGE sql
STABLE
AS $$
  WITH blocked AS (
    SELECT
      a.pid AS blocked_pid,
      unnest(pg_blocking_pids(a.pid)) AS blocker_pid,
      a.usename AS blocked_user,
      a.application_name AS blocked_app,
      coalesce(a.client_addr::text, 'local') AS blocked_client,
      a.wait_event_type,
      a.wait_event,
      coalesce(age(clock_timestamp(), a.xact_start), interval '0') AS blocked_xact_age,
      coalesce(age(clock_timestamp(), a.query_start), interval '0') AS blocked_query_age,
      a.state AS blocked_state,
      dbre.compact_query(a.query, 240) AS blocked_query
    FROM pg_stat_activity AS a
    WHERE cardinality(pg_blocking_pids(a.pid)) > 0
  )
  SELECT
    b.blocked_pid,
    blocker.pid,
    b.blocked_user,
    blocker.usename,
    coalesce(nullif(b.blocked_app, ''), '(unknown)'),
    coalesce(nullif(blocker.application_name, ''), '(unknown)'),
    b.blocked_client,
    coalesce(blocker.client_addr::text, 'local'),
    b.wait_event_type,
    b.wait_event,
    b.blocked_xact_age,
    coalesce(age(clock_timestamp(), blocker.xact_start), interval '0'),
    b.blocked_query_age,
    coalesce(age(clock_timestamp(), blocker.query_start), interval '0'),
    b.blocked_state,
    blocker.state,
    b.blocked_query,
    dbre.compact_query(blocker.query, 240)
  FROM blocked AS b
  JOIN pg_stat_activity AS blocker
    ON blocker.pid = b.blocker_pid
  ORDER BY b.blocked_query_age DESC, b.blocked_xact_age DESC, b.blocked_pid;
$$;

CREATE OR REPLACE FUNCTION dbre.wait_profile()
RETURNS TABLE (
  state text,
  wait_event_type text,
  wait_event text,
  sessions bigint,
  active_sessions bigint,
  longest_query_age interval,
  longest_xact_age interval
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    a.state,
    coalesce(a.wait_event_type, 'CPU/Client'),
    coalesce(a.wait_event, '(none)'),
    count(*) AS sessions,
    count(*) FILTER (WHERE a.state = 'active') AS active_sessions,
    max(coalesce(age(clock_timestamp(), a.query_start), interval '0')) AS longest_query_age,
    max(coalesce(age(clock_timestamp(), a.xact_start), interval '0')) AS longest_xact_age
  FROM pg_stat_activity AS a
  WHERE a.pid <> pg_backend_pid()
    AND a.backend_type = 'client backend'
  GROUP BY a.state, coalesce(a.wait_event_type, 'CPU/Client'), coalesce(a.wait_event, '(none)')
  ORDER BY sessions DESC, active_sessions DESC, longest_query_age DESC;
$$;

CREATE OR REPLACE FUNCTION dbre.database_pressure()
RETURNS TABLE (
  datname name,
  numbackends integer,
  xact_commit bigint,
  xact_rollback bigint,
  rollback_pct numeric,
  blks_hit_pct numeric,
  temp_written_mb numeric,
  deadlocks bigint,
  sessions bigint,
  sessions_abandoned bigint,
  sessions_fatal bigint,
  sessions_killed bigint,
  session_time interval,
  active_time interval,
  idle_in_transaction_time interval,
  tup_returned bigint,
  tup_fetched bigint,
  tup_inserted bigint,
  tup_updated bigint,
  tup_deleted bigint
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    d.datname,
    d.numbackends,
    d.xact_commit,
    d.xact_rollback,
    round(100.0 * d.xact_rollback / nullif(d.xact_commit + d.xact_rollback, 0), 2) AS rollback_pct,
    round(100.0 * d.blks_hit / nullif(d.blks_hit + d.blks_read, 0), 2) AS blks_hit_pct,
    round(d.temp_bytes::numeric / 1048576, 2) AS temp_written_mb,
    d.deadlocks,
    d.sessions,
    d.sessions_abandoned,
    d.sessions_fatal,
    d.sessions_killed,
    make_interval(secs => coalesce(d.session_time, 0) / 1000.0),
    make_interval(secs => coalesce(d.active_time, 0) / 1000.0),
    make_interval(secs => coalesce(d.idle_in_transaction_time, 0) / 1000.0),
    d.tup_returned,
    d.tup_fetched,
    d.tup_inserted,
    d.tup_updated,
    d.tup_deleted
  FROM pg_stat_database AS d
  WHERE d.datname IS NOT NULL
    AND d.datname NOT IN ('template0', 'template1')
  ORDER BY d.numbackends DESC, d.xact_commit DESC;
$$;

CREATE OR REPLACE FUNCTION dbre.top_statements(p_limit integer DEFAULT 20)
RETURNS TABLE (
  queryid bigint,
  calls bigint,
  plans bigint,
  total_exec_s numeric,
  mean_exec_ms numeric,
  min_exec_ms numeric,
  max_exec_ms numeric,
  stddev_exec_ms numeric,
  rows_per_call numeric,
  shared_hit_pct numeric,
  temp_written_mb numeric,
  wal_mb numeric,
  blk_read_ms numeric,
  blk_write_ms numeric,
  query_text text
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    s.queryid,
    s.calls,
    s.plans,
    round(s.total_exec_time::numeric / 1000, 2) AS total_exec_s,
    round(s.mean_exec_time::numeric, 2) AS mean_exec_ms,
    round(s.min_exec_time::numeric, 2) AS min_exec_ms,
    round(s.max_exec_time::numeric, 2) AS max_exec_ms,
    round(s.stddev_exec_time::numeric, 2) AS stddev_exec_ms,
    round(s.rows::numeric / nullif(s.calls, 0), 2) AS rows_per_call,
    round(100.0 * s.shared_blks_hit / nullif(s.shared_blks_hit + s.shared_blks_read, 0), 2) AS shared_hit_pct,
    round(s.temp_blks_written::numeric * current_setting('block_size')::numeric / 1048576, 2) AS temp_written_mb,
    round(s.wal_bytes::numeric / 1048576, 2) AS wal_mb,
    round(s.blk_read_time::numeric, 2) AS blk_read_ms,
    round(s.blk_write_time::numeric, 2) AS blk_write_ms,
    dbre.compact_query(s.query, 320)
  FROM pg_stat_statements AS s
  WHERE s.dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
  ORDER BY s.total_exec_time DESC
  LIMIT greatest(p_limit, 1);
$$;

CREATE OR REPLACE FUNCTION dbre.table_churn_review(p_limit integer DEFAULT 25)
RETURNS TABLE (
  schemaname name,
  relname name,
  table_size text,
  indexes_size text,
  n_live_tup bigint,
  n_dead_tup bigint,
  dead_tuple_pct numeric,
  writes bigint,
  n_tup_upd bigint,
  n_tup_hot_upd bigint,
  hot_update_pct numeric,
  n_mod_since_analyze bigint,
  fillfactor integer,
  last_autovacuum_age interval,
  last_autoanalyze_age interval,
  review_hint text
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    st.schemaname,
    st.relname,
    pg_size_pretty(pg_table_size(c.oid)) AS table_size,
    pg_size_pretty(pg_indexes_size(c.oid)) AS indexes_size,
    st.n_live_tup,
    st.n_dead_tup,
    round(100.0 * st.n_dead_tup / nullif(st.n_live_tup + st.n_dead_tup, 0), 2) AS dead_tuple_pct,
    st.n_tup_ins + st.n_tup_upd + st.n_tup_del AS writes,
    st.n_tup_upd,
    st.n_tup_hot_upd,
    round(100.0 * st.n_tup_hot_upd / nullif(st.n_tup_upd, 0), 2) AS hot_update_pct,
    st.n_mod_since_analyze,
    dbre.rel_fillfactor(c.oid),
    coalesce(age(clock_timestamp(), st.last_autovacuum), interval '100 years'),
    coalesce(age(clock_timestamp(), st.last_autoanalyze), interval '100 years'),
    CASE
      WHEN st.n_dead_tup > 1000000 OR round(100.0 * st.n_dead_tup / nullif(st.n_live_tup + st.n_dead_tup, 0), 2) >= 20
        THEN 'High dead tuple pressure; inspect vacuum pace, blockers, and long transactions.'
      WHEN st.n_tup_upd >= 10000 AND round(100.0 * st.n_tup_hot_upd / nullif(st.n_tup_upd, 0), 2) < 50
        THEN 'HOT rate is low for an update-heavy table; review fillfactor, row width, and indexed columns.'
      WHEN st.n_mod_since_analyze >= 100000
        THEN 'Statistics churn is high; review analyze cadence and planner stability.'
      ELSE 'Review write mix and maintenance cadence relative to size.'
    END
  FROM pg_stat_user_tables AS st
  JOIN pg_class AS c
    ON c.relname = st.relname
  JOIN pg_namespace AS n
    ON n.oid = c.relnamespace
   AND n.nspname = st.schemaname
  ORDER BY
    (st.n_tup_ins + st.n_tup_upd + st.n_tup_del) DESC,
    st.n_dead_tup DESC,
    pg_table_size(c.oid) DESC
  LIMIT greatest(p_limit, 1);
$$;

CREATE OR REPLACE FUNCTION dbre.vacuum_gap_review(p_limit integer DEFAULT 25)
RETURNS TABLE (
  schemaname name,
  relname name,
  table_size text,
  xid_age bigint,
  freeze_max_age integer,
  freeze_consumed_pct numeric,
  n_dead_tup bigint,
  n_mod_since_analyze bigint,
  last_vacuum_age interval,
  last_autovacuum_age interval,
  last_analyze_age interval,
  last_autoanalyze_age interval,
  maintenance_gap text
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    st.schemaname,
    st.relname,
    pg_size_pretty(pg_table_size(c.oid)) AS table_size,
    age(c.relfrozenxid) AS xid_age,
    current_setting('autovacuum_freeze_max_age')::integer AS freeze_max_age,
    round(100.0 * age(c.relfrozenxid) / current_setting('autovacuum_freeze_max_age')::numeric, 2) AS freeze_consumed_pct,
    st.n_dead_tup,
    st.n_mod_since_analyze,
    coalesce(age(clock_timestamp(), st.last_vacuum), interval '100 years'),
    coalesce(age(clock_timestamp(), st.last_autovacuum), interval '100 years'),
    coalesce(age(clock_timestamp(), st.last_analyze), interval '100 years'),
    coalesce(age(clock_timestamp(), st.last_autoanalyze), interval '100 years'),
    CASE
      WHEN age(c.relfrozenxid) >= current_setting('autovacuum_freeze_max_age')::bigint * 0.80
        THEN 'Freeze age is consuming more than 80% of the budget; prioritize vacuum.'
      WHEN st.last_autovacuum IS NULL
        THEN 'Never autovacuumed; validate table scale, thresholds, and blockers.'
      WHEN st.last_autoanalyze IS NULL
        THEN 'Never autoanalyzed; planner statistics may be stale.'
      WHEN st.n_mod_since_analyze >= 100000
        THEN 'High modification count since analyze; review statistics freshness.'
      ELSE 'Review in context of workload and table size.'
    END
  FROM pg_stat_user_tables AS st
  JOIN pg_class AS c
    ON c.relname = st.relname
  JOIN pg_namespace AS n
    ON n.oid = c.relnamespace
   AND n.nspname = st.schemaname
  ORDER BY
    round(100.0 * age(c.relfrozenxid) / current_setting('autovacuum_freeze_max_age')::numeric, 2) DESC,
    st.n_dead_tup DESC
  LIMIT greatest(p_limit, 1);
$$;

CREATE OR REPLACE FUNCTION dbre.index_efficiency_review(p_limit integer DEFAULT 25)
RETURNS TABLE (
  schemaname name,
  table_name name,
  index_name name,
  is_unique boolean,
  index_size text,
  idx_scan bigint,
  idx_tup_read bigint,
  idx_tup_fetch bigint,
  cache_hit_pct numeric,
  review_hint text
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    ui.schemaname,
    ui.relname,
    ui.indexrelname,
    i.indisunique,
    pg_size_pretty(pg_relation_size(ui.indexrelid)) AS index_size,
    ui.idx_scan,
    ui.idx_tup_read,
    ui.idx_tup_fetch,
    round(100.0 * si.idx_blks_hit / nullif(si.idx_blks_hit + si.idx_blks_read, 0), 2) AS cache_hit_pct,
    CASE
      WHEN ui.idx_scan = 0 AND pg_relation_size(ui.indexrelid) >= 134217728
        THEN 'Large index with zero scans; validate whether it still earns its write and storage cost.'
      WHEN ui.idx_scan < 100 AND pg_relation_size(ui.indexrelid) >= 536870912
        THEN 'Large low-scan index; review with workload owners before keeping it.'
      WHEN round(100.0 * si.idx_blks_hit / nullif(si.idx_blks_hit + si.idx_blks_read, 0), 2) < 99
        THEN 'Index cache hit ratio is low; correlate with working set and memory posture.'
      ELSE 'Index appears active; review alongside table churn and query plans.'
    END
  FROM pg_stat_user_indexes AS ui
  JOIN pg_statio_user_indexes AS si
    ON si.indexrelid = ui.indexrelid
  JOIN pg_index AS i
    ON i.indexrelid = ui.indexrelid
  ORDER BY
    pg_relation_size(ui.indexrelid) DESC,
    ui.idx_scan ASC
  LIMIT greatest(p_limit, 1);
$$;

CREATE OR REPLACE FUNCTION dbre.io_overview()
RETURNS TABLE (
  backend_type text,
  object text,
  context text,
  reads bigint,
  read_ms numeric,
  writes bigint,
  write_ms numeric,
  writebacks bigint,
  extends bigint,
  hits bigint,
  evictions bigint,
  fsyncs bigint,
  stats_reset timestamptz
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    backend_type,
    object,
    context,
    reads,
    round(read_time::numeric, 2),
    writes,
    round(write_time::numeric, 2),
    writebacks,
    extends,
    hits,
    evictions,
    fsyncs,
    stats_reset
  FROM pg_stat_io
  ORDER BY (reads + writes + writebacks + fsyncs) DESC, backend_type, object, context;
$$;

CREATE OR REPLACE FUNCTION dbre.replica_status()
RETURNS TABLE (
  application_name text,
  client_addr text,
  state text,
  sync_state text,
  sent_lsn pg_lsn,
  write_lsn pg_lsn,
  flush_lsn pg_lsn,
  replay_lsn pg_lsn,
  write_lag interval,
  flush_lag interval,
  replay_lag interval
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    application_name,
    coalesce(client_addr::text, 'local'),
    state,
    sync_state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    write_lag,
    flush_lag,
    replay_lag
  FROM pg_stat_replication
  ORDER BY application_name;
$$;

CREATE OR REPLACE FUNCTION dbre.replication_slots_review()
RETURNS TABLE (
  slot_name text,
  slot_type text,
  active boolean,
  wal_status text,
  safe_wal_size text,
  restart_lsn pg_lsn,
  confirmed_flush_lsn pg_lsn,
  inactive_since timestamptz
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    slot_name,
    slot_type,
    active,
    wal_status,
    pg_size_pretty(safe_wal_size),
    restart_lsn,
    confirmed_flush_lsn,
    inactive_since
  FROM pg_replication_slots
  ORDER BY active ASC, slot_name;
$$;

CREATE OR REPLACE FUNCTION dbre.config_gap_review()
RETURNS TABLE (
  section text,
  setting_name text,
  current_value text,
  expected_state text,
  severity text,
  observation text
)
LANGUAGE sql
STABLE
AS $$
  SELECT * FROM (
    VALUES
      (
        'extensions',
        'shared_preload_libraries',
        current_setting('shared_preload_libraries'),
        'must include pg_stat_statements',
        CASE WHEN current_setting('shared_preload_libraries') LIKE '%pg_stat_statements%' THEN 'ok' ELSE 'critical' END,
        CASE WHEN current_setting('shared_preload_libraries') LIKE '%pg_stat_statements%' THEN 'pg_stat_statements preload is enabled.' ELSE 'Add pg_stat_statements to shared_preload_libraries and reboot the cluster.' END
      ),
      (
        'instrumentation',
        'track_io_timing',
        current_setting('track_io_timing'),
        'on',
        CASE WHEN current_setting('track_io_timing') = 'on' THEN 'ok' ELSE 'critical' END,
        CASE WHEN current_setting('track_io_timing') = 'on' THEN 'IO timing is available for tuning and statement analysis.' ELSE 'Turn on track_io_timing to attribute latency to physical reads and writes.' END
      ),
      (
        'instrumentation',
        'pg_stat_statements.track',
        current_setting('pg_stat_statements.track', true),
        'all or top',
        CASE WHEN coalesce(current_setting('pg_stat_statements.track', true), '') IN ('all', 'top') THEN 'ok' ELSE 'warning' END,
        CASE WHEN coalesce(current_setting('pg_stat_statements.track', true), '') IN ('all', 'top') THEN 'Statement capture scope is acceptable.' ELSE 'Review pg_stat_statements.track so operational SQL and utility activity are visible enough for investigations.' END
      ),
      (
        'logging',
        'log_lock_waits',
        current_setting('log_lock_waits'),
        'on',
        CASE WHEN current_setting('log_lock_waits') = 'on' THEN 'ok' ELSE 'warning' END,
        CASE WHEN current_setting('log_lock_waits') = 'on' THEN 'Lock wait logging is enabled.' ELSE 'Enable log_lock_waits so transient blockers leave evidence in the logs.' END
      ),
      (
        'logging',
        'log_autovacuum_min_duration',
        current_setting('log_autovacuum_min_duration'),
        'not -1',
        CASE WHEN current_setting('log_autovacuum_min_duration') <> '-1' THEN 'ok' ELSE 'warning' END,
        CASE WHEN current_setting('log_autovacuum_min_duration') <> '-1' THEN 'Autovacuum activity will be visible in logs.' ELSE 'Set log_autovacuum_min_duration so vacuum stalls and wraparound risk leave breadcrumbs.' END
      ),
      (
        'timeouts',
        'idle_in_transaction_session_timeout',
        current_setting('idle_in_transaction_session_timeout'),
        'greater than 0',
        CASE WHEN dbre.setting_numeric('idle_in_transaction_session_timeout') > 0 THEN 'ok' ELSE 'warning' END,
        CASE WHEN dbre.setting_numeric('idle_in_transaction_session_timeout') > 0 THEN 'Idle-in-transaction sessions are bounded.' ELSE 'Set idle_in_transaction_session_timeout to cap application stalls that pin vacuum and locks.' END
      ),
      (
        'timeouts',
        'lock_timeout',
        current_setting('lock_timeout'),
        'greater than 0 for DDL-heavy estates',
        CASE WHEN dbre.setting_numeric('lock_timeout') > 0 THEN 'ok' ELSE 'warning' END,
        CASE WHEN dbre.setting_numeric('lock_timeout') > 0 THEN 'Lock waits are bounded for this session default.' ELSE 'Consider a non-zero lock_timeout to avoid silent pileups during operational changes.' END
      ),
      (
        'security',
        'rds.force_ssl',
        coalesce(current_setting('rds.force_ssl', true), '(not exposed)'),
        '1',
        CASE WHEN coalesce(current_setting('rds.force_ssl', true), '1') = '1' THEN 'ok' ELSE 'critical' END,
        CASE WHEN coalesce(current_setting('rds.force_ssl', true), '1') = '1' THEN 'SSL enforcement is enabled or managed outside visible settings.' ELSE 'Enable rds.force_ssl for production Aurora clusters.' END
      ),
      (
        'security',
        'password_encryption',
        current_setting('password_encryption'),
        'scram-sha-256',
        CASE WHEN current_setting('password_encryption') = 'scram-sha-256' THEN 'ok' ELSE 'warning' END,
        CASE WHEN current_setting('password_encryption') = 'scram-sha-256' THEN 'SCRAM is in use for new password hashes.' ELSE 'Move password_encryption to scram-sha-256 unless application constraints prevent it.' END
      ),
      (
        'autovacuum',
        'autovacuum',
        current_setting('autovacuum'),
        'on',
        CASE WHEN current_setting('autovacuum') = 'on' THEN 'ok' ELSE 'critical' END,
        CASE WHEN current_setting('autovacuum') = 'on' THEN 'Autovacuum is enabled.' ELSE 'Autovacuum must stay enabled on Aurora PostgreSQL.' END
      ),
      (
        'autovacuum',
        'track_counts',
        current_setting('track_counts'),
        'on',
        CASE WHEN current_setting('track_counts') = 'on' THEN 'ok' ELSE 'critical' END,
        CASE WHEN current_setting('track_counts') = 'on' THEN 'Statistics collection needed by autovacuum is enabled.' ELSE 'Enable track_counts; without it autovacuum cannot target tables correctly.' END
      ),
      (
        'capacity',
        'max_connections',
        current_setting('max_connections'),
        'review with connection poolers and workload profile',
        CASE WHEN current_setting('max_connections')::integer > 1000 THEN 'warning' ELSE 'ok' END,
        CASE WHEN current_setting('max_connections')::integer > 1000 THEN 'High max_connections can hide connection churn and increase memory pressure; validate against RDS Proxy and PgBouncer design.' ELSE 'Connection cap is not obviously excessive; still validate against real concurrency and pool sizing.' END
      )
  ) AS review(section, setting_name, current_value, expected_state, severity, observation)
  ORDER BY
    CASE severity
      WHEN 'critical' THEN 1
      WHEN 'warning' THEN 2
      ELSE 3
    END,
    section,
    setting_name;
$$;
