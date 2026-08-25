-- Azure Cosmos DB (SQL API) diagnostics queries
SELECT VALUE COUNT(1) FROM c;
SELECT TOP 100 c.id, c._ts FROM c ORDER BY c._ts DESC;
SELECT c.partitionKey, COUNT(1) AS item_count FROM c GROUP BY c.partitionKey;
-- Operational checks to monitor externally: RU consumption, throttled requests (429), p95 latency, hot partitions.
