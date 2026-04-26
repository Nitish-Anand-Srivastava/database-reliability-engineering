-- MySQL report dataset (last 30 mins)
SELECT NOW() AS report_generated_at,
       (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME='Threads_running') AS threads_running,
       (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME='Slow_queries') AS slow_queries_total;
