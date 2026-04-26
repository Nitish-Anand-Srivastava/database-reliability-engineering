-- SQL Server index maintenance candidates
SELECT OBJECT_SCHEMA_NAME(ps.object_id) schema_name, OBJECT_NAME(ps.object_id) table_name,
       i.name index_name, ps.index_id, ps.avg_fragmentation_in_percent, ps.page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ps
JOIN sys.indexes i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
WHERE ps.page_count > 1000 AND ps.avg_fragmentation_in_percent > 20
ORDER BY ps.avg_fragmentation_in_percent DESC;
