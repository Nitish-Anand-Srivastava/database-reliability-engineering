-- Azure SQL DB health checks
SELECT @@VERSION AS version;
SELECT TOP (20) wait_type, wait_time_ms, waiting_tasks_count FROM sys.dm_db_wait_stats ORDER BY wait_time_ms DESC;
SELECT TOP (20) total_worker_time, total_elapsed_time, execution_count, SUBSTRING(text,1,200) sql_text
FROM sys.dm_exec_query_stats CROSS APPLY sys.dm_exec_sql_text(sql_handle)
ORDER BY total_worker_time DESC;
SELECT * FROM sys.dm_db_resource_stats ORDER BY end_time DESC;
