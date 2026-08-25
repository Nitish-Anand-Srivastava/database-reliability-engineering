\set ON_ERROR_STOP on
\pset pager off
\x auto

\echo Step 4: database-level pressure
SELECT * FROM dbre.database_pressure();

\echo Background writer and checkpoint signals
SELECT
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
FROM pg_stat_bgwriter;
