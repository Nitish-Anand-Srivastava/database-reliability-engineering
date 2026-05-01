-- Schema and feature assessment for SQL Server to Azure SQL Database Hyperscale
-- Author: Nitish Anand Srivastava
-- Run on source SQL Server

SET NOCOUNT ON;

PRINT '=== SQL Server to Hyperscale Assessment ===';

-- Database size overview
SELECT
    DB_NAME(database_id) AS database_name,
    SUM(size) * 8.0 / 1024 / 1024 AS size_tb
FROM sys.master_files
WHERE DB_NAME(database_id) = DB_NAME()
GROUP BY database_id;

-- Compatibility level
SELECT name, compatibility_level
FROM sys.databases
WHERE name = DB_NAME();

-- Deprecated or unsupported patterns to review
SELECT 'Cross Database References' AS check_name, COUNT(*) AS findings
FROM sys.sql_expression_dependencies
WHERE referenced_database_name IS NOT NULL
UNION ALL
SELECT 'CLR Assemblies', COUNT(*)
FROM sys.assemblies
WHERE is_user_defined = 1
UNION ALL
SELECT 'SQL Agent Jobs (server scoped)', COUNT(*)
FROM msdb.dbo.sysjobs
UNION ALL
SELECT 'Linked Servers', COUNT(*)
FROM sys.servers
WHERE is_linked = 1;

-- CDC eligibility and PK coverage
SELECT
    t.name AS table_name,
    CASE WHEN i.index_id IS NULL THEN 'NO_PK' ELSE 'PK_PRESENT' END AS pk_status,
    SUM(p.rows) AS row_count_estimate
FROM sys.tables t
LEFT JOIN sys.indexes i
    ON t.object_id = i.object_id
    AND i.is_primary_key = 1
LEFT JOIN sys.partitions p
    ON t.object_id = p.object_id
    AND p.index_id IN (0,1)
GROUP BY t.name, i.index_id
ORDER BY row_count_estimate DESC;

-- High-level index distribution
SELECT
    OBJECT_NAME(i.object_id) AS table_name,
    COUNT(*) AS index_count
FROM sys.indexes i
JOIN sys.tables t ON i.object_id = t.object_id
WHERE i.index_id > 0
GROUP BY i.object_id
ORDER BY index_count DESC;

PRINT '=== Assessment Complete ===';
