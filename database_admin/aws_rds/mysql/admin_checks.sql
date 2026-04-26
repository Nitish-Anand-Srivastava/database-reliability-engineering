-- AWS RDS MySQL admin checks
SHOW VARIABLES LIKE 'version%';
SHOW GLOBAL STATUS LIKE 'Threads_running';
SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_reads';
SHOW SLAVE STATUS;
SELECT user, host, account_locked FROM mysql.user ORDER BY user, host;
