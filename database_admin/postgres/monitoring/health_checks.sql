-- PostgreSQL daily health checks
SELECT now() AS snapshot_time, version();
SELECT datname, numbackends, xact_commit, xact_rollback, blks_hit, blks_read FROM pg_stat_database ORDER BY numbackends DESC;
SELECT usename, state, wait_event_type, wait_event, query_start FROM pg_stat_activity WHERE state <> 'idle' ORDER BY query_start;
SELECT * FROM pg_stat_bgwriter;
SELECT schemaname, relname, n_dead_tup FROM pg_stat_user_tables ORDER BY n_dead_tup DESC LIMIT 50;
