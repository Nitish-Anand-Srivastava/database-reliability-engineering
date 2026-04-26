-- MySQL CPF_Observability snapshot dataset
SELECT NOW() AS captured_at, @@hostname AS host, @@version AS version;
SHOW GLOBAL STATUS LIKE 'Threads_running';
SHOW GLOBAL STATUS LIKE 'Slow_queries';
SHOW GLOBAL STATUS LIKE 'Innodb_row_lock%';

SELECT DIGEST, LEFT(DIGEST_TEXT, 300) AS sql_text, COUNT_STAR,
       SUM_TIMER_WAIT/1000000000000 AS total_s,
       AVG_TIMER_WAIT/1000000000 AS avg_ms,
       SUM_ROWS_EXAMINED, SUM_NO_INDEX_USED
FROM performance_schema.events_statements_summary_by_digest
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 50;

SELECT r.trx_id waiting_trx_id, b.trx_id blocking_trx_id,
       TIMESTAMPDIFF(SECOND,r.trx_started,NOW()) waiting_seconds,
       LEFT(r.trx_query,300) waiting_query, LEFT(b.trx_query,300) blocking_query
FROM information_schema.innodb_lock_waits w
JOIN information_schema.innodb_trx b ON b.trx_id = w.blocking_trx_id
JOIN information_schema.innodb_trx r ON r.trx_id = w.requesting_trx_id;
