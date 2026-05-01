-- Reconciliation checks for MySQL -> Azure MySQL Flexible Server
-- Author: Nitish Anand Srivastava

SELECT
  table_schema,
  table_name,
  table_rows
FROM information_schema.tables
WHERE table_schema = DATABASE()
ORDER BY table_rows DESC;

SELECT
  table_name,
  constraint_name,
  constraint_type
FROM information_schema.table_constraints
WHERE table_schema = DATABASE()
ORDER BY table_name;
