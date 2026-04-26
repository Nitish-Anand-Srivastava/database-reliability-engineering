-- AWS RDS Oracle admin checks
SELECT * FROM v$instance;
SELECT name, open_mode, database_role FROM v$database;
SELECT event, total_waits, time_waited_micro/1e6 time_waited_s FROM v$system_event WHERE wait_class <> 'Idle' ORDER BY time_waited_micro DESC FETCH FIRST 20 ROWS ONLY;
SELECT owner, segment_name, bytes/1024/1024 size_mb FROM dba_segments ORDER BY bytes DESC FETCH FIRST 20 ROWS ONLY;
