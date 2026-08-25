-- PostgreSQL report dataset (last 30 mins)
SELECT now() AS report_generated_at,
       interval '30 minutes' AS report_window,
       (SELECT COUNT(*) FROM pg_stat_activity WHERE state <> 'idle') AS active_sessions,
       (SELECT COUNT(*) FROM pg_stat_activity WHERE now()-query_start > interval '5 minutes') AS long_running_queries,
       (SELECT COUNT(*) FROM pg_stat_activity WHERE cardinality(pg_blocking_pids(pid)) > 0) AS blocked_sessions;
