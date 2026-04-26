-- Azure SQL automatic tuning and index recommendations
SELECT * FROM sys.database_automatic_tuning_options;
SELECT reason, score, script FROM sys.dm_db_tuning_recommendations;
SELECT TOP (50) * FROM sys.query_store_wait_stats ORDER BY avg_query_wait_time_ms DESC;
