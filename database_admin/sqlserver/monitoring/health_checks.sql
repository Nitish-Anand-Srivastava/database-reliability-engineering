-- SQL Server daily health checks
SELECT @@SERVERNAME AS server_name, @@VERSION AS version;
SELECT name, state_desc, recovery_model_desc FROM sys.databases;
SELECT DB_NAME(database_id) db_name, file_id, size/128.0 size_mb FROM sys.master_files ORDER BY size DESC;
SELECT wait_type, wait_time_ms, waiting_tasks_count FROM sys.dm_os_wait_stats ORDER BY wait_time_ms DESC OFFSET 0 ROWS FETCH NEXT 20 ROWS ONLY;
SELECT scheduler_id, runnable_tasks_count, current_tasks_count FROM sys.dm_os_schedulers WHERE status='VISIBLE ONLINE';
