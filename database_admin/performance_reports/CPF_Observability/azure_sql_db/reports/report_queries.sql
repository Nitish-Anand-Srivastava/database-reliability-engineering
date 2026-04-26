SELECT SYSUTCDATETIME() AS report_generated_at,
       (SELECT TOP 1 avg_cpu_percent FROM sys.dm_db_resource_stats ORDER BY end_time DESC) AS cpu_pct,
       (SELECT TOP 1 avg_data_io_percent FROM sys.dm_db_resource_stats ORDER BY end_time DESC) AS io_pct;
