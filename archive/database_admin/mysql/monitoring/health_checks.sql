-- MySQL daily health checks
SELECT @@hostname host, @@version version;
SHOW GLOBAL STATUS LIKE 'Threads_running';
SHOW GLOBAL STATUS LIKE 'Slow_queries';
SHOW GLOBAL STATUS LIKE 'Innodb_row_lock%';
SELECT table_schema, ROUND(SUM(data_length+index_length)/1024/1024,2) size_mb
FROM information_schema.tables GROUP BY table_schema ORDER BY size_mb DESC;
