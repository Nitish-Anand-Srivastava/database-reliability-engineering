\set ON_ERROR_STOP on
\pset pager off

CREATE SCHEMA IF NOT EXISTS dbre_rds_pg;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

CREATE OR REPLACE FUNCTION dbre_rds_pg.compact_query(query_text text, max_len integer DEFAULT 280)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT left(regexp_replace(coalesce(query_text, ''), '\s+', ' ', 'g'), greatest(max_len, 32));
$$;

CREATE OR REPLACE FUNCTION dbre_rds_pg.instance_overview()
RETURNS TABLE (
  collected_at timestamptz,
  database_name name,
  server_version text,
  rds_extensions text,
  uptime interval,
  max_connections integer,
  shared_buffers text,
  work_mem text,
  maintenance_work_mem text,
  effective_cache_size text,
  autovacuum text,
  autovacuum_max_workers integer,
  track_io_timing text,
  log_lock_waits text,
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
    current_setting('rds.extensions', true),
    age(clock_timestamp(), pg_postmaster_start_time()),
    current_setting('max_connections')::integer,
    current_setting('shared_buffers'),
    current_setting('work_mem'),
    current_setting('maintenance_work_mem'),
    current_setting('effective_cache_size'),
    current_setting('autovacuum'),
    current_setting('autovacuum_max_workers')::integer,
    current_setting('track_io_timing'),
    current_setting('log_lock_waits'),
    current_setting('statement_timeout'),
    current_setting('lock_timeout'),
    current_setting('idle_in_transaction_session_timeout');
$$;

CREATE OR REPLACE FUNCTION dbre_rds_pg.who_is_active(p_limit integer DEFAULT 30)
RETURNS TABLE (
  pid integer,
  usename name,
  datname name,
  application_name text,
  client_addr text,
  state text,
  wait_event_type text,
  wait_event text,
  xact_age interval,
  query_age interval,
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
    a.state,
    a.wait_event_type,
    a.wait_event,
    coalesce(age(clock_timestamp(), a.xact_start), interval '0'),
    coalesce(age(clock_timestamp(), a.query_start), interval '0'),
    cardinality(pg_blocking_pids(a.pid)),
    dbre_rds_pg.compact_query(a.query, 320)
  FROM pg_stat_activity AS a
  WHERE a.pid <> pg_backend_pid()
    AND a.backend_type = 'client backend'
  ORDER BY
    coalesce(age(clock_timestamp(), a.xact_start), interval '0') DESC,
    coalesce(age(clock_timestamp(), a.query_start), interval '0') DESC,
    a.pid
  LIMIT greatest(p_limit, 1);
$$;

CREATE OR REPLACE FUNCTION dbre_rds_pg.blocking_overview()
RETURNS TABLE (
  blocked_pid integer,
  blocker_pid integer,
  blocked_user name,
  blocker_user name,
  blocked_app text,
  blocker_app text,
  blocked_state text,
  blocker_state text,
  wait_event_type text,
  wait_event text,
  blocked_xact_age interval,
  blocker_xact_age interval,
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
      a.state AS blocked_state,
      a.wait_event_type,
      a.wait_event,
      coalesce(age(clock_timestamp(), a.xact_start), interval '0') AS blocked_xact_age,
      dbre_rds_pg.compact_query(a.query, 240) AS blocked_query
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
    b.blocked_state,
    blocker.state,
    b.wait_event_type,
    b.wait_event,
    b.blocked_xact_age,
    coalesce(age(clock_timestamp(), blocker.xact_start), interval '0'),
    b.blocked_query,
    dbre_rds_pg.compact_query(blocker.query, 240)
  FROM blocked AS b
  JOIN pg_stat_activity AS blocker
    ON blocker.pid = b.blocker_pid
  ORDER BY b.blocked_xact_age DESC, b.blocked_pid;
$$;

CREATE OR REPLACE FUNCTION dbre_rds_pg.wait_profile()
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

CREATE OR REPLACE FUNCTION dbre_rds_pg.database_pressure()
RETURNS TABLE (
  datname name,
  numbackends integer,
  xact_commit bigint,
  xact_rollback bigint,
  rollback_pct numeric,
  blks_hit_pct numeric,
  temp_written_mb numeric,
  deadlocks bigint,
  session_time interval,
  active_time interval,
  idle_in_transaction_time interval,
  sessions bigint,
  sessions_fatal bigint,
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
    round(100.0 * d.xact_rollback / nullif(d.xact_commit + d.xact_rollback, 0), 2),
    round(100.0 * d.blks_hit / nullif(d.blks_hit + d.blks_read, 0), 2),
    round(d.temp_bytes::numeric / 1048576, 2),
    d.deadlocks,
    make_interval(secs => coalesce(d.session_time, 0) / 1000.0),
    make_interval(secs => coalesce(d.active_time, 0) / 1000.0),
    make_interval(secs => coalesce(d.idle_in_transaction_time, 0) / 1000.0),
    d.sessions,
    d.sessions_fatal,
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

CREATE OR REPLACE FUNCTION dbre_rds_pg.top_statements(p_limit integer DEFAULT 20)
RETURNS TABLE (
  queryid bigint,
  calls bigint,
  total_exec_ms double precision,
  mean_exec_ms double precision,
  rows bigint,
  shared_hit_pct numeric,
  temp_written_mb numeric,
  blk_read_ms double precision,
  blk_write_ms double precision,
  wal_mb numeric,
  query_text text
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_has_blk_read_time boolean;
  v_has_blk_write_time boolean;
  v_has_wal_bytes boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM pg_attribute
    WHERE attrelid = 'public.pg_stat_statements'::regclass
      AND attname = 'blk_read_time'
      AND NOT attisdropped
  )
  INTO v_has_blk_read_time;

  SELECT EXISTS (
    SELECT 1
    FROM pg_attribute
    WHERE attrelid = 'public.pg_stat_statements'::regclass
      AND attname = 'blk_write_time'
      AND NOT attisdropped
  )
  INTO v_has_blk_write_time;

  SELECT EXISTS (
    SELECT 1
    FROM pg_attribute
    WHERE attrelid = 'public.pg_stat_statements'::regclass
      AND attname = 'wal_bytes'
      AND NOT attisdropped
  )
  INTO v_has_wal_bytes;

  IF v_has_blk_read_time AND v_has_blk_write_time AND v_has_wal_bytes THEN
    RETURN QUERY
    SELECT
      pss.queryid,
      pss.calls,
      pss.total_exec_time,
      pss.mean_exec_time,
      pss.rows,
      round(100.0 * pss.shared_blks_hit / nullif(pss.shared_blks_hit + pss.shared_blks_read, 0), 2),
      round(pss.temp_blks_written::numeric * current_setting('block_size')::numeric / 1048576, 2),
      pss.blk_read_time,
      pss.blk_write_time,
      round(pss.wal_bytes::numeric / 1048576, 2),
      dbre_rds_pg.compact_query(pss.query, 320)
    FROM pg_stat_statements AS pss
    ORDER BY pss.total_exec_time DESC
    LIMIT greatest(p_limit, 1);
  ELSE
    RETURN QUERY
    SELECT
      pss.queryid,
      pss.calls,
      pss.total_exec_time,
      pss.mean_exec_time,
      pss.rows,
      round(100.0 * pss.shared_blks_hit / nullif(pss.shared_blks_hit + pss.shared_blks_read, 0), 2),
      round(pss.temp_blks_written::numeric * current_setting('block_size')::numeric / 1048576, 2),
      NULL::double precision,
      NULL::double precision,
      NULL::numeric,
      dbre_rds_pg.compact_query(pss.query, 320)
    FROM pg_stat_statements AS pss
    ORDER BY pss.total_exec_time DESC
    LIMIT greatest(p_limit, 1);
  END IF;
EXCEPTION
  WHEN undefined_table OR object_not_in_prerequisite_state THEN
    RETURN;
END;
$$;

CREATE OR REPLACE FUNCTION dbre_rds_pg.table_churn_review(p_limit integer DEFAULT 25)
RETURNS TABLE (
  schemaname name,
  relname name,
  table_size text,
  indexes_size text,
  n_live_tup bigint,
  n_dead_tup bigint,
  dead_tuple_pct numeric,
  writes bigint,
  hot_update_pct numeric,
  n_mod_since_analyze bigint,
  since_last_autovacuum interval,
  since_last_autoanalyze interval,
  review_hint text
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    st.schemaname,
    st.relname,
    pg_size_pretty(pg_table_size(format('%I.%I', st.schemaname, st.relname)::regclass)),
    pg_size_pretty(pg_indexes_size(format('%I.%I', st.schemaname, st.relname)::regclass)),
    st.n_live_tup,
    st.n_dead_tup,
    round(100.0 * st.n_dead_tup / nullif(st.n_live_tup + st.n_dead_tup, 0), 2),
    st.n_tup_ins + st.n_tup_upd + st.n_tup_del,
    round(100.0 * st.n_tup_hot_upd / nullif(st.n_tup_upd, 0), 2),
    st.n_mod_since_analyze,
    coalesce(age(clock_timestamp(), st.last_autovacuum), interval '100 years'),
    coalesce(age(clock_timestamp(), st.last_autoanalyze), interval '100 years'),
    CASE
      WHEN st.n_dead_tup > 1000000 THEN 'High dead tuple count; inspect autovacuum pace and long transactions.'
      WHEN st.n_tup_upd >= 10000 AND round(100.0 * st.n_tup_hot_upd / nullif(st.n_tup_upd, 0), 2) < 50 THEN 'Update-heavy table with poor HOT rate; review fillfactor and indexed columns.'
      WHEN st.n_mod_since_analyze > 100000 THEN 'Planner statistics may be stale for this write-heavy table.'
      ELSE 'Review in context of workload, plans, and vacuum cadence.'
    END
  FROM pg_stat_user_tables AS st
  ORDER BY (st.n_tup_ins + st.n_tup_upd + st.n_tup_del) DESC, st.n_dead_tup DESC
  LIMIT greatest(p_limit, 1);
$$;

CREATE OR REPLACE FUNCTION dbre_rds_pg.checkpointer_overview()
RETURNS TABLE (
  stats_source text,
  checkpoints_timed bigint,
  checkpoints_req bigint,
  checkpoint_write_time_ms double precision,
  checkpoint_sync_time_ms double precision,
  buffers_checkpoint bigint,
  buffers_clean bigint,
  maxwritten_clean bigint,
  buffers_alloc bigint,
  stats_reset timestamptz
)
LANGUAGE plpgsql
AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_attribute
    WHERE attrelid = 'pg_catalog.pg_stat_bgwriter'::regclass
      AND attname = 'checkpoints_timed'
      AND NOT attisdropped
  ) THEN
    RETURN QUERY
    SELECT
      'pg_stat_bgwriter',
      bg.checkpoints_timed,
      bg.checkpoints_req,
      bg.checkpoint_write_time,
      bg.checkpoint_sync_time,
      bg.buffers_checkpoint,
      bg.buffers_clean,
      bg.maxwritten_clean,
      bg.buffers_alloc,
      bg.stats_reset
    FROM pg_stat_bgwriter AS bg;
  ELSIF to_regclass('pg_catalog.pg_stat_checkpointer') IS NOT NULL THEN
    RETURN QUERY
    SELECT
      'pg_stat_checkpointer + pg_stat_bgwriter',
      cp.num_timed,
      cp.num_requested,
      cp.write_time,
      cp.sync_time,
      cp.buffers_written,
      bg.buffers_clean,
      bg.maxwritten_clean,
      bg.buffers_alloc,
      coalesce(cp.stats_reset, bg.stats_reset)
    FROM pg_stat_checkpointer AS cp
    CROSS JOIN pg_stat_bgwriter AS bg;
  ELSE
    RETURN QUERY
    SELECT
      'unavailable',
      NULL::bigint,
      NULL::bigint,
      NULL::double precision,
      NULL::double precision,
      NULL::bigint,
      NULL::bigint,
      NULL::bigint,
      NULL::bigint,
      NULL::timestamptz;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION dbre_rds_pg.replication_overview()
RETURNS TABLE (
  application_name text,
  client_addr text,
  state text,
  sync_state text,
  write_lag interval,
  flush_lag interval,
  replay_lag interval,
  sent_lsn pg_lsn,
  write_lsn pg_lsn,
  flush_lsn pg_lsn,
  replay_lsn pg_lsn
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    application_name,
    coalesce(client_addr::text, 'local'),
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
$$;

CREATE OR REPLACE FUNCTION dbre_rds_pg.rds_parameter_review()
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
        CASE WHEN current_setting('shared_preload_libraries') LIKE '%pg_stat_statements%' THEN 'pg_stat_statements preload is enabled.' ELSE 'Add pg_stat_statements to shared_preload_libraries and reboot the instance.' END
      ),
      (
        'instrumentation',
        'track_io_timing',
        current_setting('track_io_timing'),
        'on',
        CASE WHEN current_setting('track_io_timing') = 'on' THEN 'ok' ELSE 'warning' END,
        CASE WHEN current_setting('track_io_timing') = 'on' THEN 'IO timing data is available for query diagnosis.' ELSE 'Turn on track_io_timing to improve latency attribution.' END
      ),
      (
        'timeouts',
        'idle_in_transaction_session_timeout',
        current_setting('idle_in_transaction_session_timeout'),
        'greater than 0',
        CASE WHEN current_setting('idle_in_transaction_session_timeout') <> '0' THEN 'ok' ELSE 'warning' END,
        CASE WHEN current_setting('idle_in_transaction_session_timeout') <> '0' THEN 'Idle transactions are bounded.' ELSE 'Set idle_in_transaction_session_timeout to cap vacuum and lock damage from application stalls.' END
      ),
      (
        'timeouts',
        'lock_timeout',
        current_setting('lock_timeout'),
        'greater than 0 for operational sessions',
        CASE WHEN current_setting('lock_timeout') <> '0' THEN 'ok' ELSE 'warning' END,
        CASE WHEN current_setting('lock_timeout') <> '0' THEN 'Lock waits are bounded.' ELSE 'Consider non-zero lock_timeout for operational change sessions.' END
      ),
      (
        'logging',
        'log_lock_waits',
        current_setting('log_lock_waits'),
        'on',
        CASE WHEN current_setting('log_lock_waits') = 'on' THEN 'ok' ELSE 'warning' END,
        CASE WHEN current_setting('log_lock_waits') = 'on' THEN 'Lock wait logging is enabled.' ELSE 'Enable log_lock_waits to leave evidence for transient blockers.' END
      ),
      (
        'logging',
        'log_min_duration_statement',
        current_setting('log_min_duration_statement'),
        'set to an operational threshold',
        CASE WHEN current_setting('log_min_duration_statement') <> '-1' THEN 'ok' ELSE 'warning' END,
        CASE WHEN current_setting('log_min_duration_statement') <> '-1' THEN 'Slow statement logging is active.' ELSE 'Consider enabling duration-based statement logging for production investigations.' END
      ),
      (
        'security',
        'rds.force_ssl',
        coalesce(current_setting('rds.force_ssl', true), '(not exposed)'),
        '1',
        CASE WHEN coalesce(current_setting('rds.force_ssl', true), '1') = '1' THEN 'ok' ELSE 'critical' END,
        CASE WHEN coalesce(current_setting('rds.force_ssl', true), '1') = '1' THEN 'SSL enforcement is enabled or managed outside visible settings.' ELSE 'Enable rds.force_ssl for production RDS PostgreSQL estates.' END
      ),
      (
        'autovacuum',
        'autovacuum',
        current_setting('autovacuum'),
        'on',
        CASE WHEN current_setting('autovacuum') = 'on' THEN 'ok' ELSE 'critical' END,
        CASE WHEN current_setting('autovacuum') = 'on' THEN 'Autovacuum is enabled.' ELSE 'Autovacuum must remain enabled in production.' END
      )
  ) AS review(section, setting_name, current_value, expected_state, severity, observation)
  ORDER BY CASE severity WHEN 'critical' THEN 1 WHEN 'warning' THEN 2 ELSE 3 END, section, setting_name;
$$;
