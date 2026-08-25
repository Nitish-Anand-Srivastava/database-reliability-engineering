\set ON_ERROR_STOP on
\pset pager off

SET statement_timeout = '30s';

\echo Statement-level latency percentiles derived from normalized pg_stat_statements means
WITH normalized AS (
  SELECT
    queryid,
    calls,
    total_exec_time,
    mean_exec_time,
    min_exec_time,
    max_exec_time,
    stddev_exec_time,
    left(regexp_replace(query, '\s+', ' ', 'g'), 200) AS normalized_query
  FROM pg_stat_statements
  WHERE calls > 0
)
SELECT
  round(percentile_cont(0.50) WITHIN GROUP (ORDER BY mean_exec_time)::numeric, 2) AS p50_mean_exec_ms,
  round(percentile_cont(0.95) WITHIN GROUP (ORDER BY mean_exec_time)::numeric, 2) AS p95_mean_exec_ms,
  round(percentile_cont(0.99) WITHIN GROUP (ORDER BY mean_exec_time)::numeric, 2) AS p99_mean_exec_ms,
  round(sum(total_exec_time)::numeric, 2) AS total_exec_ms,
  sum(calls) AS total_calls
FROM normalized;

\echo Top normalized statements by total execution time
WITH ranked AS (
  SELECT
    queryid,
    calls,
    total_exec_time,
    mean_exec_time,
    min_exec_time,
    max_exec_time,
    stddev_exec_time,
    round(100.0 * total_exec_time / NULLIF(sum(total_exec_time) OVER (), 0), 2) AS total_exec_pct,
    left(regexp_replace(query, '\s+', ' ', 'g'), 200) AS normalized_query
  FROM pg_stat_statements
  WHERE calls > 0
)
SELECT
  queryid,
  calls,
  round(total_exec_time::numeric, 2) AS total_exec_ms,
  round(mean_exec_time::numeric, 2) AS mean_exec_ms,
  round(min_exec_time::numeric, 2) AS min_exec_ms,
  round(max_exec_time::numeric, 2) AS max_exec_ms,
  round(stddev_exec_time::numeric, 2) AS stddev_exec_ms,
  total_exec_pct,
  normalized_query
FROM ranked
ORDER BY total_exec_time DESC
LIMIT 20;
