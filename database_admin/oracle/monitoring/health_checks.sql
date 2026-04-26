-- Oracle daily health checks
SELECT instance_name, status, database_status FROM v$instance;
SELECT name, open_mode, log_mode FROM v$database;
SELECT tablespace_name, ROUND((used_space/tablespace_size)*100,2) pct_used FROM dba_tablespace_usage_metrics ORDER BY pct_used DESC;
SELECT resource_name, current_utilization, limit_value FROM v$resource_limit WHERE resource_name IN ('processes','sessions');
SELECT event, total_waits, time_waited_micro/1e6 time_waited_s FROM v$system_event WHERE wait_class <> 'Idle' ORDER BY time_waited_micro DESC FETCH FIRST 20 ROWS ONLY;
