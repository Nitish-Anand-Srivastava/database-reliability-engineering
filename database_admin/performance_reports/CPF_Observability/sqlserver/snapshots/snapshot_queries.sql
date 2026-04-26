-- SQL Server CPF_Observability snapshot dataset
SELECT SYSUTCDATETIME() AS captured_at, @@SERVERNAME AS server_name, @@VERSION AS version;

SELECT TOP (50) qs.execution_count,
       qs.total_worker_time/1000.0 total_cpu_ms,
       qs.total_elapsed_time/1000.0 total_elapsed_ms,
       qs.total_logical_reads,
       SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
         ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text) ELSE qs.statement_end_offset END - qs.statement_start_offset)/2)+1) AS sql_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
ORDER BY qs.total_worker_time DESC;

SELECT TOP (30) wait_type, waiting_tasks_count, wait_time_ms, signal_wait_time_ms
FROM sys.dm_os_wait_stats
ORDER BY wait_time_ms DESC;

SELECT wt.session_id blocked_session, wt.blocking_session_id blocker_session, wt.wait_duration_ms, wt.wait_type
FROM sys.dm_os_waiting_tasks wt
WHERE wt.blocking_session_id IS NOT NULL AND wt.blocking_session_id <> 0
ORDER BY wt.wait_duration_ms DESC;
