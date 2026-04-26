-- SQL Server Always On AG checks
SELECT ag.name, ar.replica_server_name, rs.role_desc, rs.synchronization_health_desc
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
JOIN sys.dm_hadr_availability_replica_states rs ON ar.replica_id = rs.replica_id;

SELECT DB_NAME(database_id) db_name, synchronization_state_desc, log_send_queue_size, redo_queue_size
FROM sys.dm_hadr_database_replica_states;
