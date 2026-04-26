-- Azure Cosmos DB queries
SELECT * FROM c WHERE c._ts > GetCurrentTimestamp() - 3600