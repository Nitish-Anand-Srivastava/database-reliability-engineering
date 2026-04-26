-- AWS RDS SQL Server admin checks
SELECT @@VERSION AS version;
SELECT TOP (20) wait_type, wait_time_ms, waiting_tasks_count FROM sys.dm_os_wait_stats ORDER BY wait_time_ms DESC;
SELECT DB_NAME(database_id) db_name, log_send_queue_size, redo_queue_size FROM sys.dm_hadr_database_replica_states;
SELECT name, state_desc, recovery_model_desc FROM sys.databases;
