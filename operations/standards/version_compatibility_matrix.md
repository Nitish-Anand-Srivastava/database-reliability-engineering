# Version Compatibility Matrix (Maintain Quarterly)

> Purpose: track currently supported **vendor-recommended/LTS** versions across the DB estate.

## RDBMS
- Oracle Database (19c LTS / 23ai track)
- SQL Server (2022 current enterprise baseline)
- PostgreSQL (17 current, 16/15 still common estate baselines)
- MySQL (8.4 LTS / 8.0 legacy transition)
- MariaDB (11.x where applicable)

## Cloud Managed
- Azure SQL DB (evergreen)
- Azure Cosmos DB (service-managed)
- AWS RDS (engine-specific support windows)
- Aurora PostgreSQL / Aurora MySQL (cluster family specific)

## NoSQL
- MongoDB (7.x/8.x rollout by workload)
- Cassandra (4.1+)
- Redis (7.x+)

## Operating Rule
- Review and refresh this matrix every quarter.
- Tie patch windows to CVE severity, vendor support dates, and application certification.
- Block production deployments on unsupported engine versions.
