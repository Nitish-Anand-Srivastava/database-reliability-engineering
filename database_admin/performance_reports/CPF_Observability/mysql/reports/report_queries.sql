-- MySQL report dataset (portable status extraction)
SELECT NOW() AS report_generated_at;
SHOW GLOBAL STATUS LIKE 'Threads_running';
SHOW GLOBAL STATUS LIKE 'Slow_queries';
