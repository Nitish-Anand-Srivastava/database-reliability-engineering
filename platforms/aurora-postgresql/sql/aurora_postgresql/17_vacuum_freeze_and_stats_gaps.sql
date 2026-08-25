\set ON_ERROR_STOP on
\pset pager off
\x auto

\echo Step 7A: vacuum, freeze age, and stale stats review
SELECT * FROM dbre.vacuum_gap_review(30);

\echo Step 7B: currently running vacuums and analyze tasks
SELECT
  pid,
  datname,
  relid::regclass AS relation_name,
  phase,
  heap_blks_total,
  heap_blks_scanned,
  heap_blks_vacuumed,
  index_vacuum_count,
  max_dead_tuples,
  num_dead_tuples
FROM pg_stat_progress_vacuum
ORDER BY pid;

\echo Tables never vacuumed or analyzed
SELECT
  schemaname,
  relname,
  n_live_tup,
  n_dead_tup,
  last_vacuum,
  last_autovacuum,
  last_analyze,
  last_autoanalyze
FROM pg_stat_user_tables
WHERE last_vacuum IS NULL
   OR last_autovacuum IS NULL
   OR last_analyze IS NULL
   OR last_autoanalyze IS NULL
ORDER BY n_live_tup DESC, relname;
