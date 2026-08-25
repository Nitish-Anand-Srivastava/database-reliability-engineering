\set ON_ERROR_STOP on
\pset pager off

SET statement_timeout = '30s';

\echo Table bloat proxies from dead tuple accumulation
SELECT
  st.schemaname,
  st.relname,
  pg_size_pretty(pg_table_size(format('%I.%I', st.schemaname, st.relname)::regclass)) AS table_size,
  st.n_live_tup,
  st.n_dead_tup,
  round(100.0 * st.n_dead_tup / GREATEST(st.n_live_tup + st.n_dead_tup, 1), 2) AS dead_tuple_pct,
  age(clock_timestamp(), st.last_vacuum) AS since_last_vacuum,
  age(clock_timestamp(), st.last_autovacuum) AS since_last_autovacuum,
  age(clock_timestamp(), st.last_analyze) AS since_last_analyze,
  age(clock_timestamp(), st.last_autoanalyze) AS since_last_autoanalyze
FROM pg_stat_user_tables AS st
ORDER BY dead_tuple_pct DESC, pg_table_size(format('%I.%I', st.schemaname, st.relname)::regclass) DESC
LIMIT 25;

\echo HOT update effectiveness and fillfactor posture
SELECT
  st.schemaname,
  st.relname,
  st.n_tup_upd,
  st.n_tup_hot_upd,
  round(100.0 * st.n_tup_hot_upd / GREATEST(st.n_tup_upd, 1), 2) AS hot_update_pct,
  coalesce(
    (
      SELECT substring(option from '[0-9]+')::int
      FROM unnest(c.reloptions) AS option
      WHERE option LIKE 'fillfactor=%'
      LIMIT 1
    ),
    100
  ) AS fillfactor
FROM pg_stat_user_tables AS st
JOIN pg_class AS c
  ON c.relname = st.relname
JOIN pg_namespace AS n
  ON n.oid = c.relnamespace
 AND n.nspname = st.schemaname
WHERE st.n_tup_upd > 0
ORDER BY hot_update_pct ASC, st.n_tup_upd DESC
LIMIT 25;

\echo Large indexes with low scan counts as a practical index-bloat proxy
SELECT
  s.schemaname,
  s.relname AS table_name,
  s.indexrelname AS index_name,
  pg_size_pretty(pg_relation_size(s.indexrelid)) AS index_size,
  s.idx_scan,
  s.idx_tup_read,
  s.idx_tup_fetch
FROM pg_stat_user_indexes AS s
WHERE pg_relation_size(s.indexrelid) > 268435456
ORDER BY s.idx_scan ASC, pg_relation_size(s.indexrelid) DESC
LIMIT 25;
