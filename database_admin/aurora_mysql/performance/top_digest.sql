SELECT DIGEST, DIGEST_TEXT, COUNT_STAR,
       SUM_TIMER_WAIT/1000000000000 total_s,
       AVG_TIMER_WAIT/1000000000 avg_ms
FROM performance_schema.events_statements_summary_by_digest
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 25;
