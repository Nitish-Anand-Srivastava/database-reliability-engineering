-- SQL Server top queries (Query Store)
SELECT TOP (25)
  DB_NAME() AS db_name,
  q.query_id,
  rs.count_executions,
  rs.avg_duration/1000.0 avg_duration_ms,
  rs.avg_cpu_time/1000.0 avg_cpu_ms,
  rs.avg_logical_io_reads,
  qt.query_sql_text
FROM sys.query_store_query q
JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_plan p ON p.query_id = q.query_id
JOIN sys.query_store_runtime_stats rs ON rs.plan_id = p.plan_id
ORDER BY rs.avg_duration DESC;
