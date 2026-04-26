-- Aurora PostgreSQL cluster checks
SELECT now(), current_setting('server_version');
SELECT * FROM pg_stat_replication;
SELECT datname, numbackends, xact_commit, xact_rollback FROM pg_stat_database;
SELECT * FROM pg_stat_wal;
-- Combine with CloudWatch: CPUUtilization, FreeableMemory, Read/WriteLatency, ReplicaLag.
