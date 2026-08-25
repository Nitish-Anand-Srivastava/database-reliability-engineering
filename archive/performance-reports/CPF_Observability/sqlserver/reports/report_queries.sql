-- SQL Server report dataset
SELECT SYSUTCDATETIME() AS report_generated_at,
       (SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE status='running') AS running_sessions,
       (SELECT COUNT(*) FROM sys.dm_exec_requests WHERE blocking_session_id <> 0) AS blocked_requests;
