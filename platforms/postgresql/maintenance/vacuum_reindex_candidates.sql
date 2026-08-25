-- Postgres maintenance candidates
SELECT schemaname, relname, n_live_tup, n_dead_tup,
       ROUND(100.0*n_dead_tup/NULLIF(n_live_tup+n_dead_tup,0),2) AS dead_pct
FROM pg_stat_user_tables
WHERE n_dead_tup > 10000
ORDER BY n_dead_tup DESC;

SELECT schemaname, relname, idx_scan, seq_scan
FROM pg_stat_user_tables
ORDER BY seq_scan DESC
LIMIT 50;
