# SQL Server to Azure SQL Database Hyperscale Migration (Enterprise Scale)

## Executive Summary

This project defines an enterprise-grade migration program for moving a large on-premises SQL Server estate to Azure SQL Database Hyperscale.

Reference scenario used in this project:
- Source platform: SQL Server 2019 Enterprise (on-premises, Always On)
- Source database size: 72 TB OLTP database
- Target platform: Azure SQL Database Hyperscale (single write replica + scale-out read replicas)
- Migration pattern: staged full load + online change synchronization + cutover validation

Core approach:
1. Phase 1 (Weeks 1-4): Discovery, schema remediation, bulk load seeding to Hyperscale
2. Phase 2 (Weeks 3-10): Continuous delta synchronization from SQL Server to Hyperscale
3. Phase 3 (Weeks 11-12): Multi-layer reconciliation, performance sign-off, and controlled cutover

---

## Architecture Overview

```text
+----------------------------------------------------------------------------------+
| Phase 1: Bulk Seeding (Weeks 1-4)                                                |
|                                                                                  |
| On-Prem SQL Server -> Native backup stripes -> Azure Blob staging               |
|          |                                                        |              |
|          +-> Schema conversion & pre-deploy scripts               v              |
|                                                          Azure DMS full load     |
|                                                                   |              |
|                                                                   v              |
|                                                     Azure SQL Hyperscale         |
+----------------------------------------------------------------------------------+

+----------------------------------------------------------------------------------+
| Phase 2: Continuous Sync (Weeks 3-10, overlaps)                                  |
|                                                                                  |
| SQL Server CDC / Change Tracking -> Python CDC extractor -> replay queue        |
|                                                      |                           |
|                                                      v                           |
|                                           Azure SQL apply worker                 |
|                                                      |                           |
|                                                      v                           |
|                                             Checkpoint + lag monitor             |
+----------------------------------------------------------------------------------+

+----------------------------------------------------------------------------------+
| Phase 3: Validation + Cutover (Weeks 11-12)                                     |
|                                                                                  |
| Row counts | PK/FK checks | checksums | business query parity | perf baseline   |
|                                |                                                |
|                                +--> Go/No-Go gates --> Cutover                 |
+----------------------------------------------------------------------------------+
```

---

## Migration Phases

## Phase 1: Seeding and Foundation (Weeks 1-4)

### 1.1 Estate discovery and risk profiling
- Inventory tables, indexes, partitions, filegroups, jobs, linked servers, CLR usage
- Identify unsupported SQL Server features for Azure SQL Database Hyperscale
- Profile top wait types, blocking patterns, and critical query baselines

### 1.2 Schema and code remediation
- Convert server-level dependencies to database-scoped alternatives
- Replace unsupported features:
  - SQL Agent jobs -> Azure Elastic Jobs or Automation Runbooks
  - Cross-database dependencies -> external tables / service patterns
  - CLR assemblies -> application layer or approved alternatives
- Generate deployable T-SQL package for Hyperscale

### 1.3 Bulk seeding to Azure
- Create striped backups from SQL Server to Azure Blob storage
- Use Azure DMS and/or staged BCP parallel loads for massive tables
- Pre-create target schema and partitioning strategy in Hyperscale
- Disable non-critical indexes during load, then rebuild post-load

### 1.4 Initial quality gates
- Table-level row count parity
- Sample checksum checks on high-volume entities
- Referential integrity checks on critical transactional tables

---

## Phase 2: Online Synchronization (Weeks 3-10)

### 2.1 Delta capture design
- Enable CDC on source SQL Server for migration scope tables
- Capture changes after seeding watermark (LSN)
- Serialize changes to a durable replay queue

### 2.2 Replay and consistency management
- Apply ordered changes into Hyperscale using idempotent MERGE/UPSERT patterns
- Persist checkpoints by table and LSN
- Implement retry with exponential backoff and dead-letter file handling

### 2.3 Lag and throughput management
- Target sync lag: < 5 minutes during business hours
- Scale replay workers by table group and transaction profile
- Alert on lag > 15 minutes or replay failures > threshold

---

## Phase 3: Reconciliation and Cutover (Weeks 11-12)

### 3.1 Validation stack
- Row count parity across all migration scope tables
- PK uniqueness and FK consistency checks
- Deterministic checksums over sampled key ranges
- Business query result parity against source

### 3.2 Cutover readiness
- Freeze window approved by app, infra, and DBA stakeholders
- Final delta drain to zero lag
- Final reconciliation report signed off

### 3.3 Controlled cutover
- Quiesce writes on source
- Final apply cycle and checkpoint
- Switch application connection endpoints
- Run smoke tests and rollback timer monitoring (72 hours)

---

## Folder Structure

```text
sqlserver_to_azure_sql_hyperscale/
  README.md
  docs/
    ARCHITECTURE.md
    MIGRATION_RUNBOOK.md
  scripts/
    schema_assessment.sql
    bulk_seed_orchestration.ps1
    sqlserver_cdc_extractor.py
    azure_sql_replay_worker.py
    reconciliation_checks.sql
    business_validation.sql
    performance_baseline.ps1
  config/
    hyperscale_migration.env
    cdc_config.yaml
  logs/
```

---

## Tooling and Platform Matrix

| Capability | Recommended Tool | Notes |
|---|---|---|
| Assessment and compatibility | DMA + custom SQL checks | Validate unsupported features early |
| Bulk movement | Azure DMS + backup/BCP strategy | Choose by table size and change rate |
| Delta synchronization | SQL Server CDC + custom Python | Fine-grained replay and checkpoints |
| Validation | T-SQL + Python reports | Repeatable pre-cutover evidence |
| Orchestration | PowerShell + Azure CLI | CI/CD friendly and auditable |

---

## Success Criteria

- 100% table availability in target scope
- 100% row parity for all in-scope tables
- >= 99.9% checksum match on sampled reconciliation sets
- 95% of critical queries within +/- 20% of source baseline
- Zero high-severity defects in 72-hour hypercare window
- Cutover downtime <= 90 minutes

---

## Known Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| High churn tables cause sync lag | Delayed cutover | Partitioned replay workers + prioritized queues |
| Unsupported SQL Server features | Deployment blockers | Pre-remediation and feature substitution backlog |
| Large index rebuild windows | Extended migration time | Deferred/reduced index strategy during seed |
| Network throughput variability | Load delays | Parallel stripes, retry policy, staging buffers |
| Data type edge cases | Data quality drift | Explicit mapping rules + targeted validation |

---

## Recommended Timeline

| Week | Milestone |
|---|---|
| 1 | Discovery complete, remediation backlog approved |
| 2 | Target schema deploy ready, seed pipeline tested |
| 3-4 | Full seed completed and validated |
| 3-10 | CDC sync running with stable lag controls |
| 11 | Reconciliation and performance sign-off |
| 12 | Cutover and hypercare start |

---

## Related Documents

- docs/ARCHITECTURE.md
- docs/MIGRATION_RUNBOOK.md
- scripts/reconciliation_checks.sql

---

Last Updated: 2026-05-01
Status: Active
Owner: Database Reliability Engineering
