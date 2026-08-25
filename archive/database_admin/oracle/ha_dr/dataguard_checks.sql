-- Oracle Data Guard checks
SELECT name, db_unique_name, open_mode, database_role, switchover_status FROM v$database;
SELECT process, status, thread#, sequence# FROM v$managed_standby;
SELECT thread#, MAX(sequence#) last_seq, MAX(applied) KEEP (DENSE_RANK LAST ORDER BY sequence#) applied_status FROM v$archived_log GROUP BY thread#;
