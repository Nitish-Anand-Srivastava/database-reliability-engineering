-- MySQL maintenance/index review
SELECT object_schema, object_name, count_read, count_write
FROM performance_schema.table_io_waits_summary_by_table
WHERE object_schema NOT IN ('mysql','sys','performance_schema','information_schema')
ORDER BY count_read DESC LIMIT 50;

SELECT table_schema, table_name, index_name, cardinality
FROM information_schema.statistics
WHERE table_schema NOT IN ('mysql','sys','performance_schema','information_schema')
ORDER BY table_schema, table_name, index_name;
