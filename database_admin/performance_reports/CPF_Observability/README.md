# CPF_Observability (Cross-Platform Forensics)

CPF_Observability is a common performance observability framework that produces **AWR-style HTML reports** across multiple DB platforms.

## Default behavior
- Snapshot interval: **30 minutes**
- Snapshot retention: **7 days**
- Supports **scheduled mode** and **one-off mode**

## Supported database types
- Oracle
- SQL Server
- PostgreSQL
- MySQL
- MongoDB
- Azure Cosmos DB
- Azure SQL DB
- Aurora PostgreSQL
- Aurora MySQL
- AWS RDS
- Cassandra
- Redis
- ClickHouse

## Storage layout
- Snapshots: `database_admin/performance_reports/CPF_Observability/<db_type>/data/snapshots/`
- HTML reports: `database_admin/performance_reports/CPF_Observability/<db_type>/data/reports/`
- Runtime logs: `database_admin/performance_reports/CPF_Observability/<db_type>/logs/`

## Core report sections (all DBs)
- Workload summary (TPS/QPS, connections/sessions)
- Top SQL/operations by elapsed and resource use
- Wait events and bottleneck classes
- Blocking / deadlocks / lock waits
- Long-running transactions/queries
- Memory, cache and I/O pressure
- Replication/HA lag and health (where applicable)
- Configuration drift and risky settings

## What this adds beyond classic AWR style
- Explicit lock-chain and deadlock sections
- Slow query and long-xact sections by default
- Capacity trend and saturation guardrails
- Operational recommendation section per finding severity
