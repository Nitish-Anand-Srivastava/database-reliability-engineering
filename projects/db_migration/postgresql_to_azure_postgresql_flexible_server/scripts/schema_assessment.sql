-- PostgreSQL schema and compatibility assessment
-- Author: Nitish Anand Srivastava

SELECT current_database() AS database_name;

SELECT
  n.nspname AS schema_name,
  c.relname AS table_name,
  pg_total_relation_size(c.oid) / 1024 / 1024 AS size_mb
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'r'
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY size_mb DESC;

SELECT extname, extversion
FROM pg_extension
ORDER BY extname;
