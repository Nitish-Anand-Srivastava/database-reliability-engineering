-- Oracle CPF_Observability snapshot dataset
SELECT SYSTIMESTAMP AS captured_at, instance_name, status FROM v$instance;

SELECT * FROM (
  SELECT sql_id, executions, elapsed_time/1e6 elapsed_s, cpu_time/1e6 cpu_s,
         buffer_gets, disk_reads, SUBSTR(sql_text,1,300) sql_text
  FROM v$sql
  ORDER BY elapsed_time DESC
) WHERE ROWNUM <= 50;

SELECT event, wait_class, total_waits, time_waited_micro/1e6 time_waited_s
FROM v$system_event
WHERE wait_class <> 'Idle'
ORDER BY time_waited_micro DESC FETCH FIRST 30 ROWS ONLY;

SELECT s.sid blocked_sid, s.blocking_session blocker_sid, s.seconds_in_wait, s.event
FROM v$session s
WHERE s.blocking_session IS NOT NULL
ORDER BY s.seconds_in_wait DESC;
