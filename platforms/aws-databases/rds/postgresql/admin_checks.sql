-- AWS RDS PostgreSQL admin checks
SELECT now(), current_setting('server_version'), current_setting('rds.extensions');
SELECT * FROM pg_stat_replication;
SELECT datname, numbackends, blks_hit, blks_read FROM pg_stat_database;
SELECT pid, usename, wait_event_type, wait_event, query_start FROM pg_stat_activity WHERE state <> 'idle';
