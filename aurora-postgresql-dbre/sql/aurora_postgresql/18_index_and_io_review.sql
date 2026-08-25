\set ON_ERROR_STOP on
\pset pager off
\x auto

\echo Step 8A: index efficiency review
SELECT * FROM dbre.index_efficiency_review(30);

\echo Step 8B: IO overview (PostgreSQL 16+)
SELECT * FROM dbre.io_overview();

\echo Step 8C: table and index cache ratios
SELECT
  relname,
  heap_blks_read,
  heap_blks_hit,
  idx_blks_read,
  idx_blks_hit,
  round(100.0 * heap_blks_hit / nullif(heap_blks_hit + heap_blks_read, 0), 2) AS heap_hit_pct,
  round(100.0 * idx_blks_hit / nullif(idx_blks_hit + idx_blks_read, 0), 2) AS index_hit_pct
FROM pg_statio_user_tables
ORDER BY (heap_blks_read + idx_blks_read) DESC
LIMIT 25;
