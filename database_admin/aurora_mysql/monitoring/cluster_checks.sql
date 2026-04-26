-- Aurora MySQL cluster checks
SHOW VARIABLES LIKE 'aurora_version';
SHOW GLOBAL STATUS LIKE 'Threads_running';
SHOW GLOBAL STATUS LIKE 'Innodb_row_lock_time%';
SHOW SLAVE STATUS;
-- Combine with CloudWatch: CPUUtilization, DatabaseConnections, ReplicaLag, FreeLocalStorage.
