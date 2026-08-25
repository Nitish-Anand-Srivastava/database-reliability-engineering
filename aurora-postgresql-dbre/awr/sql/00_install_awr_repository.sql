\set ON_ERROR_STOP on
\pset pager off

CREATE SCHEMA IF NOT EXISTS dbre_awr;

CREATE TABLE IF NOT EXISTS dbre_awr.snapshots (
  snapshot_id bigserial PRIMARY KEY,
  captured_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  label text,
  snapshot_type text NOT NULL,
  database_name name NOT NULL DEFAULT current_database(),
  server_version text NOT NULL DEFAULT current_setting('server_version'),
  aurora_version text,
  top_sql_limit integer NOT NULL,
  statement_text_length integer NOT NULL
);

CREATE TABLE IF NOT EXISTS dbre_awr.settings_snapshot (
  snapshot_id bigint NOT NULL REFERENCES dbre_awr.snapshots(snapshot_id) ON DELETE CASCADE,
  setting_name text NOT NULL,
  setting_value text,
  unit text,
  source text,
  PRIMARY KEY (snapshot_id, setting_name)
);

CREATE TABLE IF NOT EXISTS dbre_awr.activity_snapshot (
  snapshot_id bigint NOT NULL REFERENCES dbre_awr.snapshots(snapshot_id) ON DELETE CASCADE,
  state text,
  wait_event_type text,
  wait_event text,
  sessions bigint NOT NULL,
  active_sessions bigint NOT NULL,
  longest_query_age_seconds numeric,
  longest_xact_age_seconds numeric
);

CREATE TABLE IF NOT EXISTS dbre_awr.session_snapshot (
  snapshot_id bigint NOT NULL REFERENCES dbre_awr.snapshots(snapshot_id) ON DELETE CASCADE,
  pid integer NOT NULL,
  usename name,
  datname name,
  application_name text,
  client_addr text,
  backend_type text,
  state text,
  wait_event_type text,
  wait_event text,
  xact_age_seconds numeric,
  query_age_seconds numeric,
  session_age_seconds numeric,
  blocker_count integer,
  query_text text
);

CREATE TABLE IF NOT EXISTS dbre_awr.database_stats (
  snapshot_id bigint NOT NULL REFERENCES dbre_awr.snapshots(snapshot_id) ON DELETE CASCADE,
  datid oid,
  datname name,
  numbackends integer,
  xact_commit bigint,
  xact_rollback bigint,
  blks_read bigint,
  blks_hit bigint,
  tup_returned bigint,
  tup_fetched bigint,
  tup_inserted bigint,
  tup_updated bigint,
  tup_deleted bigint,
  temp_files bigint,
  temp_bytes bigint,
  deadlocks bigint,
  checksum_failures bigint,
  blk_read_time double precision,
  blk_write_time double precision,
  session_time double precision,
  active_time double precision,
  idle_in_transaction_time double precision,
  sessions bigint,
  sessions_abandoned bigint,
  sessions_fatal bigint,
  sessions_killed bigint,
  PRIMARY KEY (snapshot_id, datid)
);

CREATE TABLE IF NOT EXISTS dbre_awr.bgwriter_stats (
  snapshot_id bigint PRIMARY KEY REFERENCES dbre_awr.snapshots(snapshot_id) ON DELETE CASCADE,
  checkpoints_timed bigint,
  checkpoints_req bigint,
  checkpoint_write_time double precision,
  checkpoint_sync_time double precision,
  buffers_checkpoint bigint,
  buffers_clean bigint,
  maxwritten_clean bigint,
  buffers_backend bigint,
  buffers_backend_fsync bigint,
  buffers_alloc bigint,
  stats_reset timestamptz
);

CREATE TABLE IF NOT EXISTS dbre_awr.wal_stats (
  snapshot_id bigint PRIMARY KEY REFERENCES dbre_awr.snapshots(snapshot_id) ON DELETE CASCADE,
  wal_records bigint,
  wal_fpi bigint,
  wal_bytes numeric,
  wal_buffers_full bigint,
  wal_write bigint,
  wal_sync bigint,
  wal_write_time double precision,
  wal_sync_time double precision,
  stats_reset timestamptz
);

CREATE TABLE IF NOT EXISTS dbre_awr.table_stats (
  snapshot_id bigint NOT NULL REFERENCES dbre_awr.snapshots(snapshot_id) ON DELETE CASCADE,
  relid oid NOT NULL,
  schemaname name NOT NULL,
  relname name NOT NULL,
  table_bytes bigint NOT NULL,
  indexes_bytes bigint NOT NULL,
  seq_scan bigint,
  seq_tup_read bigint,
  idx_scan bigint,
  idx_tup_fetch bigint,
  n_live_tup bigint,
  n_dead_tup bigint,
  n_tup_ins bigint,
  n_tup_upd bigint,
  n_tup_del bigint,
  n_tup_hot_upd bigint,
  n_mod_since_analyze bigint,
  relfrozenxid_age bigint,
  fillfactor integer,
  last_vacuum timestamptz,
  last_autovacuum timestamptz,
  last_analyze timestamptz,
  last_autoanalyze timestamptz,
  PRIMARY KEY (snapshot_id, relid)
);

CREATE TABLE IF NOT EXISTS dbre_awr.index_stats (
  snapshot_id bigint NOT NULL REFERENCES dbre_awr.snapshots(snapshot_id) ON DELETE CASCADE,
  indexrelid oid NOT NULL,
  relid oid NOT NULL,
  schemaname name NOT NULL,
  relname name NOT NULL,
  indexrelname name NOT NULL,
  is_unique boolean NOT NULL,
  index_bytes bigint NOT NULL,
  idx_scan bigint,
  idx_tup_read bigint,
  idx_tup_fetch bigint,
  idx_blks_read bigint,
  idx_blks_hit bigint,
  PRIMARY KEY (snapshot_id, indexrelid)
);

CREATE TABLE IF NOT EXISTS dbre_awr.statement_stats (
  snapshot_id bigint NOT NULL REFERENCES dbre_awr.snapshots(snapshot_id) ON DELETE CASCADE,
  dbid oid NOT NULL,
  userid oid,
  queryid bigint NOT NULL,
  calls bigint,
  plans bigint,
  total_plan_time double precision,
  total_exec_time double precision,
  rows bigint,
  shared_blks_hit bigint,
  shared_blks_read bigint,
  temp_blks_written bigint,
  blk_read_time double precision,
  blk_write_time double precision,
  wal_bytes numeric,
  query_text text,
  PRIMARY KEY (snapshot_id, dbid, queryid)
);

CREATE TABLE IF NOT EXISTS dbre_awr.replication_stats (
  snapshot_id bigint NOT NULL REFERENCES dbre_awr.snapshots(snapshot_id) ON DELETE CASCADE,
  application_name text NOT NULL,
  client_addr text,
  state text,
  sync_state text,
  write_lag interval,
  flush_lag interval,
  replay_lag interval,
  sent_lsn pg_lsn,
  write_lsn pg_lsn,
  flush_lsn pg_lsn,
  replay_lsn pg_lsn,
  PRIMARY KEY (snapshot_id, application_name)
);

CREATE TABLE IF NOT EXISTS dbre_awr.replication_slots (
  snapshot_id bigint NOT NULL REFERENCES dbre_awr.snapshots(snapshot_id) ON DELETE CASCADE,
  slot_name text NOT NULL,
  slot_type text,
  active boolean,
  wal_status text,
  safe_wal_size bigint,
  restart_lsn pg_lsn,
  confirmed_flush_lsn pg_lsn,
  inactive_since timestamptz,
  PRIMARY KEY (snapshot_id, slot_name)
);

CREATE TABLE IF NOT EXISTS dbre_awr.io_stats (
  snapshot_id bigint NOT NULL REFERENCES dbre_awr.snapshots(snapshot_id) ON DELETE CASCADE,
  backend_type text NOT NULL,
  object text NOT NULL,
  context text NOT NULL,
  reads bigint,
  read_time double precision,
  writes bigint,
  write_time double precision,
  writebacks bigint,
  extends bigint,
  hits bigint,
  evictions bigint,
  reuses bigint,
  fsyncs bigint,
  stats_reset timestamptz,
  PRIMARY KEY (snapshot_id, backend_type, object, context)
);

CREATE INDEX IF NOT EXISTS idx_dbre_awr_snapshots_type_time
  ON dbre_awr.snapshots (snapshot_type, captured_at DESC);

CREATE INDEX IF NOT EXISTS idx_dbre_awr_table_stats_snapshot
  ON dbre_awr.table_stats (snapshot_id, relid);

CREATE INDEX IF NOT EXISTS idx_dbre_awr_index_stats_snapshot
  ON dbre_awr.index_stats (snapshot_id, indexrelid);

CREATE INDEX IF NOT EXISTS idx_dbre_awr_statement_stats_snapshot
  ON dbre_awr.statement_stats (snapshot_id, dbid, queryid);

CREATE OR REPLACE FUNCTION dbre_awr.rel_fillfactor(rel_oid oid)
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

CREATE OR REPLACE FUNCTION dbre_awr.take_snapshot(
  p_label text DEFAULT NULL,
  p_snapshot_type text DEFAULT 'auto',
  p_top_sql_limit integer DEFAULT 100,
  p_statement_text_length integer DEFAULT 400
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
  v_snapshot_id bigint;
  v_lock_key bigint := 84742317;
BEGIN
  IF NOT pg_try_advisory_lock(v_lock_key) THEN
    RAISE EXCEPTION 'dbre_awr snapshot already running';
  END IF;

  INSERT INTO dbre_awr.snapshots (
    label,
    snapshot_type,
    aurora_version,
    top_sql_limit,
    statement_text_length
  )
  VALUES (
    p_label,
    p_snapshot_type,
    current_setting('aurora_version', true),
    greatest(p_top_sql_limit, 1),
    greatest(p_statement_text_length, 120)
  )
  RETURNING snapshot_id INTO v_snapshot_id;

  INSERT INTO dbre_awr.settings_snapshot (snapshot_id, setting_name, setting_value, unit, source)
  SELECT
    v_snapshot_id,
    name,
    setting,
    unit,
    source
  FROM pg_settings
  WHERE name IN (
    'max_connections',
    'shared_buffers',
    'effective_cache_size',
    'work_mem',
    'maintenance_work_mem',
    'max_worker_processes',
    'max_parallel_workers',
    'max_parallel_workers_per_gather',
    'autovacuum',
    'autovacuum_max_workers',
    'autovacuum_freeze_max_age',
    'track_counts',
    'track_io_timing',
    'shared_preload_libraries',
    'log_lock_waits',
    'log_autovacuum_min_duration',
    'statement_timeout',
    'lock_timeout',
    'idle_in_transaction_session_timeout',
    'password_encryption',
    'rds.force_ssl',
    'pg_stat_statements.track'
  );

  INSERT INTO dbre_awr.activity_snapshot (
    snapshot_id,
    state,
    wait_event_type,
    wait_event,
    sessions,
    active_sessions,
    longest_query_age_seconds,
    longest_xact_age_seconds
  )
  SELECT
    v_snapshot_id,
    state,
    coalesce(wait_event_type, 'CPU/Client'),
    coalesce(wait_event, '(none)'),
    count(*) AS sessions,
    count(*) FILTER (WHERE state = 'active') AS active_sessions,
    max(extract(epoch FROM age(clock_timestamp(), query_start))),
    max(extract(epoch FROM age(clock_timestamp(), xact_start)))
  FROM pg_stat_activity
  WHERE backend_type = 'client backend'
    AND pid <> pg_backend_pid()
  GROUP BY state, coalesce(wait_event_type, 'CPU/Client'), coalesce(wait_event, '(none)');

  INSERT INTO dbre_awr.session_snapshot (
    snapshot_id,
    pid,
    usename,
    datname,
    application_name,
    client_addr,
    backend_type,
    state,
    wait_event_type,
    wait_event,
    xact_age_seconds,
    query_age_seconds,
    session_age_seconds,
    blocker_count,
    query_text
  )
  SELECT
    v_snapshot_id,
    a.pid,
    a.usename,
    a.datname,
    a.application_name,
    coalesce(a.client_addr::text, 'local'),
    a.backend_type,
    a.state,
    a.wait_event_type,
    a.wait_event,
    extract(epoch FROM age(clock_timestamp(), a.xact_start)),
    extract(epoch FROM age(clock_timestamp(), a.query_start)),
    extract(epoch FROM age(clock_timestamp(), a.backend_start)),
    cardinality(pg_blocking_pids(a.pid)),
    left(regexp_replace(coalesce(a.query, ''), '\s+', ' ', 'g'), greatest(p_statement_text_length, 120))
  FROM pg_stat_activity AS a
  WHERE a.pid <> pg_backend_pid();

  INSERT INTO dbre_awr.database_stats (
    snapshot_id,
    datid,
    datname,
    numbackends,
    xact_commit,
    xact_rollback,
    blks_read,
    blks_hit,
    tup_returned,
    tup_fetched,
    tup_inserted,
    tup_updated,
    tup_deleted,
    temp_files,
    temp_bytes,
    deadlocks,
    checksum_failures,
    blk_read_time,
    blk_write_time,
    session_time,
    active_time,
    idle_in_transaction_time,
    sessions,
    sessions_abandoned,
    sessions_fatal,
    sessions_killed
  )
  SELECT
    v_snapshot_id,
    datid,
    datname,
    numbackends,
    xact_commit,
    xact_rollback,
    blks_read,
    blks_hit,
    tup_returned,
    tup_fetched,
    tup_inserted,
    tup_updated,
    tup_deleted,
    temp_files,
    temp_bytes,
    deadlocks,
    checksum_failures,
    blk_read_time,
    blk_write_time,
    session_time,
    active_time,
    idle_in_transaction_time,
    sessions,
    sessions_abandoned,
    sessions_fatal,
    sessions_killed
  FROM pg_stat_database
  WHERE datname IS NOT NULL
    AND datname NOT IN ('template0', 'template1');

  IF EXISTS (
    SELECT 1
    FROM pg_attribute
    WHERE attrelid = 'pg_catalog.pg_stat_bgwriter'::regclass
      AND attname = 'checkpoints_timed'
      AND NOT attisdropped
  ) THEN
    INSERT INTO dbre_awr.bgwriter_stats (
      snapshot_id,
      checkpoints_timed,
      checkpoints_req,
      checkpoint_write_time,
      checkpoint_sync_time,
      buffers_checkpoint,
      buffers_clean,
      maxwritten_clean,
      buffers_backend,
      buffers_backend_fsync,
      buffers_alloc,
      stats_reset
    )
    SELECT
      v_snapshot_id,
      bg.checkpoints_timed,
      bg.checkpoints_req,
      bg.checkpoint_write_time,
      bg.checkpoint_sync_time,
      bg.buffers_checkpoint,
      bg.buffers_clean,
      bg.maxwritten_clean,
      bg.buffers_backend,
      bg.buffers_backend_fsync,
      bg.buffers_alloc,
      bg.stats_reset
    FROM pg_stat_bgwriter AS bg;
  ELSIF to_regclass('pg_catalog.pg_stat_checkpointer') IS NOT NULL THEN
    INSERT INTO dbre_awr.bgwriter_stats (
      snapshot_id,
      checkpoints_timed,
      checkpoints_req,
      checkpoint_write_time,
      checkpoint_sync_time,
      buffers_checkpoint,
      buffers_clean,
      maxwritten_clean,
      buffers_backend,
      buffers_backend_fsync,
      buffers_alloc,
      stats_reset
    )
    SELECT
      v_snapshot_id,
      cp.num_timed,
      cp.num_requested,
      cp.write_time,
      cp.sync_time,
      cp.buffers_written,
      bg.buffers_clean,
      bg.maxwritten_clean,
      NULL::bigint,
      NULL::bigint,
      bg.buffers_alloc,
      coalesce(cp.stats_reset, bg.stats_reset)
    FROM pg_stat_checkpointer AS cp
    CROSS JOIN pg_stat_bgwriter AS bg;
  ELSE
    INSERT INTO dbre_awr.bgwriter_stats (
      snapshot_id,
      checkpoints_timed,
      checkpoints_req,
      checkpoint_write_time,
      checkpoint_sync_time,
      buffers_checkpoint,
      buffers_clean,
      maxwritten_clean,
      buffers_backend,
      buffers_backend_fsync,
      buffers_alloc,
      stats_reset
    )
    SELECT
      v_snapshot_id,
      NULL::bigint,
      NULL::bigint,
      NULL::double precision,
      NULL::double precision,
      NULL::bigint,
      NULL::bigint,
      NULL::bigint,
      NULL::bigint,
      NULL::bigint,
      NULL::bigint,
      NULL::timestamptz;
  END IF;

  INSERT INTO dbre_awr.wal_stats (
    snapshot_id,
    wal_records,
    wal_fpi,
    wal_bytes,
    wal_buffers_full,
    wal_write,
    wal_sync,
    wal_write_time,
    wal_sync_time,
    stats_reset
  )
  SELECT
    v_snapshot_id,
    wal.wal_records,
    wal.wal_fpi,
    wal.wal_bytes,
    wal.wal_buffers_full,
    wal.wal_write,
    wal.wal_sync,
    wal.wal_write_time,
    wal.wal_sync_time,
    wal.stats_reset
  FROM pg_stat_wal AS wal;

  INSERT INTO dbre_awr.table_stats (
    snapshot_id,
    relid,
    schemaname,
    relname,
    table_bytes,
    indexes_bytes,
    seq_scan,
    seq_tup_read,
    idx_scan,
    idx_tup_fetch,
    n_live_tup,
    n_dead_tup,
    n_tup_ins,
    n_tup_upd,
    n_tup_del,
    n_tup_hot_upd,
    n_mod_since_analyze,
    relfrozenxid_age,
    fillfactor,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze
  )
  SELECT
    v_snapshot_id,
    c.oid,
    st.schemaname,
    st.relname,
    pg_table_size(c.oid),
    pg_indexes_size(c.oid),
    st.seq_scan,
    st.seq_tup_read,
    st.idx_scan,
    st.idx_tup_fetch,
    st.n_live_tup,
    st.n_dead_tup,
    st.n_tup_ins,
    st.n_tup_upd,
    st.n_tup_del,
    st.n_tup_hot_upd,
    st.n_mod_since_analyze,
    age(c.relfrozenxid),
    dbre_awr.rel_fillfactor(c.oid),
    st.last_vacuum,
    st.last_autovacuum,
    st.last_analyze,
    st.last_autoanalyze
  FROM pg_stat_user_tables AS st
  JOIN pg_class AS c
    ON c.relname = st.relname
  JOIN pg_namespace AS n
    ON n.oid = c.relnamespace
   AND n.nspname = st.schemaname;

  INSERT INTO dbre_awr.index_stats (
    snapshot_id,
    indexrelid,
    relid,
    schemaname,
    relname,
    indexrelname,
    is_unique,
    index_bytes,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch,
    idx_blks_read,
    idx_blks_hit
  )
  SELECT
    v_snapshot_id,
    ui.indexrelid,
    ui.relid,
    ui.schemaname,
    ui.relname,
    ui.indexrelname,
    i.indisunique,
    pg_relation_size(ui.indexrelid),
    ui.idx_scan,
    ui.idx_tup_read,
    ui.idx_tup_fetch,
    si.idx_blks_read,
    si.idx_blks_hit
  FROM pg_stat_user_indexes AS ui
  JOIN pg_statio_user_indexes AS si
    ON si.indexrelid = ui.indexrelid
  JOIN pg_index AS i
    ON i.indexrelid = ui.indexrelid;

  BEGIN
    INSERT INTO dbre_awr.statement_stats (
      snapshot_id,
      dbid,
      userid,
      queryid,
      calls,
      plans,
      total_plan_time,
      total_exec_time,
      rows,
      shared_blks_hit,
      shared_blks_read,
      temp_blks_written,
      blk_read_time,
      blk_write_time,
      wal_bytes,
      query_text
    )
    SELECT
      v_snapshot_id,
      pss.dbid,
      pss.userid,
      pss.queryid,
      pss.calls,
      pss.plans,
      pss.total_plan_time,
      pss.total_exec_time,
      pss.rows,
      pss.shared_blks_hit,
      pss.shared_blks_read,
      pss.temp_blks_written,
      pss.blk_read_time,
      pss.blk_write_time,
      pss.wal_bytes,
      left(regexp_replace(pss.query, '\s+', ' ', 'g'), greatest(p_statement_text_length, 120))
    FROM pg_stat_statements AS pss
    ORDER BY pss.total_exec_time DESC
    LIMIT greatest(p_top_sql_limit, 1);
  EXCEPTION
    WHEN undefined_table OR object_not_in_prerequisite_state THEN
      RAISE NOTICE 'pg_stat_statements snapshot skipped: %', SQLERRM;
  END;

  INSERT INTO dbre_awr.replication_stats (
    snapshot_id,
    application_name,
    client_addr,
    state,
    sync_state,
    write_lag,
    flush_lag,
    replay_lag,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn
  )
  SELECT
    v_snapshot_id,
    rep.application_name,
    coalesce(rep.client_addr::text, 'local'),
    rep.state,
    rep.sync_state,
    rep.write_lag,
    rep.flush_lag,
    rep.replay_lag,
    rep.sent_lsn,
    rep.write_lsn,
    rep.flush_lsn,
    rep.replay_lsn
  FROM pg_stat_replication AS rep;

  INSERT INTO dbre_awr.replication_slots (
    snapshot_id,
    slot_name,
    slot_type,
    active,
    wal_status,
    safe_wal_size,
    restart_lsn,
    confirmed_flush_lsn,
    inactive_since
  )
  SELECT
    v_snapshot_id,
    slot.slot_name,
    slot.slot_type,
    slot.active,
    slot.wal_status,
    slot.safe_wal_size,
    slot.restart_lsn,
    slot.confirmed_flush_lsn,
    slot.inactive_since
  FROM pg_replication_slots AS slot;

  BEGIN
    INSERT INTO dbre_awr.io_stats (
      snapshot_id,
      backend_type,
      object,
      context,
      reads,
      read_time,
      writes,
      write_time,
      writebacks,
      extends,
      hits,
      evictions,
      reuses,
      fsyncs,
      stats_reset
    )
    SELECT
      v_snapshot_id,
      io.backend_type,
      io.object,
      io.context,
      io.reads,
      io.read_time,
      io.writes,
      io.write_time,
      io.writebacks,
      io.extends,
      io.hits,
      io.evictions,
      io.reuses,
      io.fsyncs,
      io.stats_reset
    FROM pg_stat_io AS io;
  EXCEPTION
    WHEN undefined_table THEN
      RAISE NOTICE 'pg_stat_io snapshot skipped: %', SQLERRM;
  END;

  PERFORM pg_advisory_unlock(v_lock_key);
  RETURN v_snapshot_id;
EXCEPTION
  WHEN OTHERS THEN
    PERFORM pg_advisory_unlock(v_lock_key);
    RAISE;
END;
$$;
