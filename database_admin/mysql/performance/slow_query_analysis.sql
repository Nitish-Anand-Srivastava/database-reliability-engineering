SELECT db, count(*) AS exec_count, sum(query_time) AS total_time
FROM mysql.slow_log
GROUP BY db
ORDER BY total_time DESC;