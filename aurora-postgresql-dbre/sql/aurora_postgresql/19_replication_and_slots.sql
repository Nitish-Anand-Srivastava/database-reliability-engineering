\set ON_ERROR_STOP on
\pset pager off
\x auto

\echo Step 9A: replica status
SELECT * FROM dbre.replica_status();

\echo Step 9B: replication slots
SELECT * FROM dbre.replication_slots_review();

\echo Step 9C: WAL posture
SELECT
  wal_records,
  wal_fpi,
  wal_bytes,
  wal_buffers_full,
  wal_write,
  wal_sync,
  wal_write_time,
  wal_sync_time,
  stats_reset
FROM pg_stat_wal;
