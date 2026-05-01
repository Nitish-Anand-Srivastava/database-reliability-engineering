# PostgreSQL to Azure Database for PostgreSQL Flexible Server Migration (Enterprise Scale)

## Executive Summary

This project defines a production migration framework for large PostgreSQL workloads moving from on-premises to Azure Database for PostgreSQL Flexible Server.

Reference scenario:
- Source: PostgreSQL 14 on-premises, 36 TB
- Target: Azure Database for PostgreSQL Flexible Server
- Pattern: base seed + WAL-driven CDC + reconciliation before cutover

Program phases:
1. Phase 1 (Weeks 1-4): discovery, extension review, schema and full seed
2. Phase 2 (Weeks 3-10): logical/WAL-based change synchronization
3. Phase 3 (Weeks 11-12): reconciliation, performance sign-off, cutover

---

## Architecture

```text
On-Prem PostgreSQL --(pg_dump/base copy)--> Azure staging --> Azure PG Flexible
        |                                                         ^
        +------(WAL/logical decode CDC)--> extractor --> replay--+

Final gate: row parity + checksums + business query parity + perf baseline
```

---

## Folder Structure

```text
postgresql_to_azure_postgresql_flexible_server/
  README.md
  docs/
    ARCHITECTURE.md
    MIGRATION_RUNBOOK.md
  scripts/
    schema_assessment.sql
    full_load_orchestration.sh
    postgres_wal_cdc_extractor.py
    azure_postgres_replay_worker.py
    reconciliation_checks.sql
    business_validation.sql
    performance_baseline.sh
  config/
    postgresql_flexible_migration.env
    cdc_config.yaml
  logs/
```

---

## Success Criteria

- 100% object and row parity for in-scope datasets
- >= 99.9% checksum parity on sampled sets
- CDC lag maintained below 5 minutes steady-state
- Critical query latency within +/- 20%
- Cutover window <= 90 minutes

---

Last Updated: 2026-05-01
Status: Active
Owner: Database Reliability Engineering
