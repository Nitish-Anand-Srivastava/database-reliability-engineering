-- Reconciliation checks for SQL Server -> Azure SQL Hyperscale
-- Author: Nitish Anand Srivastava
-- Run on target Azure SQL Database after seed and before cutover

SET NOCOUNT ON;

PRINT '=== Reconciliation: Object Inventory ===';

SELECT
    COUNT(*) AS table_count
FROM sys.tables;

SELECT
    COUNT(*) AS index_count
FROM sys.indexes
WHERE index_id > 0;

PRINT '=== Reconciliation: Row Counts (target snapshot) ===';

SELECT
    t.name AS table_name,
    SUM(p.rows) AS row_count_estimate
FROM sys.tables t
JOIN sys.partitions p
    ON t.object_id = p.object_id
    AND p.index_id IN (0, 1)
GROUP BY t.name
ORDER BY row_count_estimate DESC;

PRINT '=== Reconciliation: PK/FK Integrity ===';

SELECT
    COUNT(*) AS pk_constraints
FROM sys.key_constraints
WHERE type = 'PK';

SELECT
    COUNT(*) AS fk_constraints
FROM sys.foreign_keys;

PRINT '=== Reconciliation: CDC Replay Checkpoint (if table exists) ===';

IF OBJECT_ID('dbo.cdc_checkpoint', 'U') IS NOT NULL
BEGIN
    SELECT TOP 100
        table_name,
        last_lsn,
        last_applied_at,
        rows_applied,
        DATEDIFF(MINUTE, last_applied_at, SYSUTCDATETIME()) AS lag_minutes
    FROM dbo.cdc_checkpoint
    ORDER BY last_applied_at DESC;
END
ELSE
BEGIN
    PRINT 'dbo.cdc_checkpoint table not found.';
END

PRINT '=== Reconciliation Complete ===';
