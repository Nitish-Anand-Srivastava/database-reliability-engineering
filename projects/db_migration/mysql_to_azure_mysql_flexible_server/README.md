# MySQL to Azure Database for MySQL Flexible Server Migration (Enterprise Scale)

## Executive Summary

This project defines a production-grade migration program for moving large on-premises MySQL workloads to Azure Database for MySQL Flexible Server.

Reference scenario:
- Source: MySQL 8.0 (on-prem), 48 TB mixed OLTP + reporting
- Target: Azure Database for MySQL Flexible Server
- Pattern: full load seed + binlog CDC synchronization + reconciliation-driven cutover

Program phases:
1. Phase 1 (Weeks 1-4): discovery, schema readiness, full load seeding
2. Phase 2 (Weeks 3-10): near-real-time change sync from binlog
3. Phase 3 (Weeks 11-12): reconciliation, performance validation, cutover

---

## Architecture Overview

```text
+----------------------------------------------------------------------------+
| Phase 1: Full Load Seed                                                    |
|                                                                            |
| On-Prem MySQL -> mydumper/backup export -> Azure Blob staging             |
|                                      |                                     |
|                                      v                                     |
|                         Azure DMS / MySQL loader to target                |
|                                      |                                     |
|                                      v                                     |
|                        Azure MySQL Flexible Server                         |
+----------------------------------------------------------------------------+

+----------------------------------------------------------------------------+
| Phase 2: Continuous Sync (binlog CDC)                                      |
|                                                                            |
| MySQL binlog -> Python CDC extractor -> replay queue -> target apply       |
|                                              |                             |
|                                              v                             |
|                                   LSN/position checkpointing               |
+----------------------------------------------------------------------------+

+----------------------------------------------------------------------------+
| Phase 3: Validation + Cutover                                              |
|                                                                            |
| Row count | checksum | FK checks | business queries | perf baseline        |
|                                 |                                          |
|                                 +-> go/no-go -> cutover                    |
+----------------------------------------------------------------------------+
```

---

## Folder Structure

```text
mysql_to_azure_mysql_flexible_server/
  README.md
  docs/
    ARCHITECTURE.md
    MIGRATION_RUNBOOK.md
  scripts/
    schema_assessment.sql
    full_load_orchestration.sh
    mysql_binlog_cdc_extractor.py
    azure_mysql_replay_worker.py
    reconciliation_checks.sql
    business_validation.sql
    performance_baseline.sh
  config/
    mysql_flexible_migration.env
    cdc_config.yaml
  logs/
```

---

## Key Success Criteria

- 100% table and row parity for in-scope objects
- >= 99.9% checksum parity on sampled key ranges
- CDC lag < 5 minutes during steady-state sync
- Critical query latency within +/- 20% baseline
- Cutover downtime <= 90 minutes

---

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| High-write tables increase lag | Shard replay workers by table groups |
| Collation/charset mismatches | Standardize utf8mb4 mapping early |
| Large secondary index load time | Defer non-critical indexes during seed |
| Network instability | Resume-safe checkpoints + retry/backoff |

---

Last Updated: 2026-05-01
Status: Active
Owner: Database Reliability Engineering
