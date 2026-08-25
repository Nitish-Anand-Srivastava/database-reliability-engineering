-- Azure SQL DB snapshot dataset
SELECT SYSUTCDATETIME() AS captured_at, @@VERSION AS version;
SELECT TOP (20) end_time, avg_cpu_percent, avg_data_io_percent, avg_log_write_percent
FROM sys.dm_db_resource_stats ORDER BY end_time DESC;
SELECT TOP (50) qs.total_worker_time, qs.total_elapsed_time, qs.execution_count,
       SUBSTRING(st.text,1,300) AS sql_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
ORDER BY qs.total_worker_time DESC;
SELECT TOP (20) wait_type, wait_time_ms, waiting_tasks_count
FROM sys.dm_db_wait_stats ORDER BY wait_time_ms DESC;
