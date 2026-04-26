SELECT query, calls, total_time
FROM pg_stat_statements
ORDER BY calls DESC
LIMIT 20;
