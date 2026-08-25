SELECT wait_event_type, wait_event, count(*)
FROM pg_stat_activity
GROUP BY wait_event_type, wait_event
ORDER BY count DESC;