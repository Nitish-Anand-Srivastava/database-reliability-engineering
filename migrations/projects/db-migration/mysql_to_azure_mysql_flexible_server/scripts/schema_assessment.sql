-- MySQL schema and compatibility assessment
-- Author: Nitish Anand Srivastava

SELECT DATABASE() AS current_database;

SELECT
  table_schema,
  table_name,
  table_rows,
  ROUND((data_length + index_length) / 1024 / 1024, 2) AS size_mb
FROM information_schema.tables
WHERE table_schema NOT IN ('mysql', 'sys', 'performance_schema', 'information_schema')
ORDER BY size_mb DESC;

SELECT
  table_schema,
  table_name,
  engine,
  table_collation
FROM information_schema.tables
WHERE table_schema NOT IN ('mysql', 'sys', 'performance_schema', 'information_schema')
ORDER BY table_schema, table_name;
