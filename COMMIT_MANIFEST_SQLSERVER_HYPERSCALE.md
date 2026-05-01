# Commit Manifest: SQL Server to Azure SQL Database Hyperscale Migration Project

Date: 2026-05-01
Owner: Database Reliability Engineering
Author requested in scripts: Nitish Anand Srivastava

## Objective

Add a full-scale, production-style migration project for on-prem SQL Server to Azure SQL Database Hyperscale with:
- Enterprise architecture and phased plan
- Runbook-grade execution details
- Scripted assessment, seed orchestration, CDC extraction/replay, reconciliation, and performance checks
- Config templates for hyperscale migration and CDC operations

## Added Paths

- projects/db_migration/sqlserver_to_azure_sql_hyperscale/README.md
- projects/db_migration/sqlserver_to_azure_sql_hyperscale/docs/ARCHITECTURE.md
- projects/db_migration/sqlserver_to_azure_sql_hyperscale/docs/MIGRATION_RUNBOOK.md
- projects/db_migration/sqlserver_to_azure_sql_hyperscale/scripts/schema_assessment.sql
- projects/db_migration/sqlserver_to_azure_sql_hyperscale/scripts/bulk_seed_orchestration.ps1
- projects/db_migration/sqlserver_to_azure_sql_hyperscale/scripts/sqlserver_cdc_extractor.py
- projects/db_migration/sqlserver_to_azure_sql_hyperscale/scripts/azure_sql_replay_worker.py
- projects/db_migration/sqlserver_to_azure_sql_hyperscale/scripts/reconciliation_checks.sql
- projects/db_migration/sqlserver_to_azure_sql_hyperscale/scripts/business_validation.sql
- projects/db_migration/sqlserver_to_azure_sql_hyperscale/scripts/performance_baseline.ps1
- projects/db_migration/sqlserver_to_azure_sql_hyperscale/config/hyperscale_migration.env
- projects/db_migration/sqlserver_to_azure_sql_hyperscale/config/cdc_config.yaml
- COMMIT_MANIFEST_SQLSERVER_HYPERSCALE.md

## Project Scope Summary

1. Phase 1 (Weeks 1-4): discovery, schema remediation, and bulk seeding
2. Phase 2 (Weeks 3-10): online CDC synchronization with checkpointing and lag controls
3. Phase 3 (Weeks 11-12): reconciliation, performance parity validation, cutover and rollback guardrails

## Validation Notes

- Script headers include requested author text: Nitish Anand Srivastava
- Deliverables align to enterprise-scale migration requirements and runbook standards

## Risk Notes

- Scripts are templates/reference implementations and require environment-specific hardening before production execution.
- CDC table mappings and business validation SQL should be aligned to actual domain schema.

## Expected Outcome

Repository now contains a complete SQL Server to Azure SQL Hyperscale migration blueprint parallel to existing large-scale migration assets.
