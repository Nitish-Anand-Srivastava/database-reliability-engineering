\set ON_ERROR_STOP on
\pset pager off
\x auto

\echo Step 5A: top SQL by total execution time
SELECT * FROM dbre.top_statements(25);

\echo Step 5B: latency percentile snapshot from statement means
WITH means AS (
  SELECT mean_exec_time
  FROM pg_stat_statements
  WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
    AND calls > 0
)
SELECT
  round(percentile_cont(0.50) WITHIN GROUP (ORDER BY mean_exec_time)::numeric, 2) AS p50_mean_exec_ms,
  round(percentile_cont(0.90) WITHIN GROUP (ORDER BY mean_exec_time)::numeric, 2) AS p90_mean_exec_ms,
  round(percentile_cont(0.95) WITHIN GROUP (ORDER BY mean_exec_time)::numeric, 2) AS p95_mean_exec_ms,
  round(percentile_cont(0.99) WITHIN GROUP (ORDER BY mean_exec_time)::numeric, 2) AS p99_mean_exec_ms
FROM means;

\echo Planning-heavy statements
SELECT
  queryid,
  calls,
  plans,
  round(total_plan_time::numeric / 1000, 2) AS total_plan_s,
  round(mean_plan_time::numeric, 2) AS mean_plan_ms,
  round(total_exec_time::numeric / 1000, 2) AS total_exec_s,
  dbre.compact_query(query, 240) AS query_text
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
  AND plans > 0
ORDER BY total_plan_time DESC
LIMIT 15;
