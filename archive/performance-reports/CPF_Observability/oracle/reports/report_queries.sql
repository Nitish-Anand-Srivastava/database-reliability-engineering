-- Oracle report dataset
SELECT SYSTIMESTAMP AS report_generated_at,
       (SELECT COUNT(*) FROM v$session WHERE status='ACTIVE') AS active_sessions,
       (SELECT COUNT(*) FROM v$session WHERE blocking_session IS NOT NULL) AS blocked_sessions
FROM dual;
