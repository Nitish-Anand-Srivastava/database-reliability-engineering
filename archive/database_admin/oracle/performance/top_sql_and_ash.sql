-- Oracle performance triage
SELECT * FROM (
  SELECT sql_id, executions, elapsed_time/1e6 elapsed_s, cpu_time/1e6 cpu_s, buffer_gets, disk_reads, SUBSTR(sql_text,1,120) sql_text
  FROM v$sql ORDER BY elapsed_time DESC
) WHERE ROWNUM <= 25;

SELECT sample_time, session_state, wait_class, COUNT(*) active_sessions
FROM v$active_session_history
WHERE sample_time >= SYSTIMESTAMP - INTERVAL '15' MINUTE
GROUP BY sample_time, session_state, wait_class
ORDER BY sample_time DESC;
