SELECT name, count, type
FROM information_schema.innodb_metrics
WHERE status = 'enabled';