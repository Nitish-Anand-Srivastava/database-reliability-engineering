-- Reconciliation checks for PostgreSQL -> Azure PostgreSQL Flexible Server
-- Author: Nitish Anand Srivastava

SELECT
  n.nspname AS schema_name,
  c.relname AS table_name,
  COALESCE(s.n_live_tup, 0) AS row_estimate
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_stat_user_tables s ON s.relid = c.oid
WHERE c.relkind = 'r'
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY row_estimate DESC;

SELECT conname, contype
FROM pg_constraint
ORDER BY conname;
