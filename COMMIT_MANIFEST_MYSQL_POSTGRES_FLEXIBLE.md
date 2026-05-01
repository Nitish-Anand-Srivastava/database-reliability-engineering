# Commit Manifest: MySQL and PostgreSQL to Azure Flexible Server Migration Projects

Date: 2026-05-01
Owner: Database Reliability Engineering

## Objective

Add two enterprise-scale migration project blueprints in parity with existing migration assets:
1. On-prem MySQL -> Azure Database for MySQL Flexible Server
2. On-prem PostgreSQL -> Azure Database for PostgreSQL Flexible Server

## Added Paths

### MySQL project
- projects/db_migration/mysql_to_azure_mysql_flexible_server/README.md
- projects/db_migration/mysql_to_azure_mysql_flexible_server/docs/ARCHITECTURE.md
- projects/db_migration/mysql_to_azure_mysql_flexible_server/docs/MIGRATION_RUNBOOK.md
- projects/db_migration/mysql_to_azure_mysql_flexible_server/scripts/schema_assessment.sql
- projects/db_migration/mysql_to_azure_mysql_flexible_server/scripts/full_load_orchestration.sh
- projects/db_migration/mysql_to_azure_mysql_flexible_server/scripts/mysql_binlog_cdc_extractor.py
- projects/db_migration/mysql_to_azure_mysql_flexible_server/scripts/azure_mysql_replay_worker.py
- projects/db_migration/mysql_to_azure_mysql_flexible_server/scripts/reconciliation_checks.sql
- projects/db_migration/mysql_to_azure_mysql_flexible_server/scripts/business_validation.sql
- projects/db_migration/mysql_to_azure_mysql_flexible_server/scripts/performance_baseline.sh
- projects/db_migration/mysql_to_azure_mysql_flexible_server/config/mysql_flexible_migration.env
- projects/db_migration/mysql_to_azure_mysql_flexible_server/config/cdc_config.yaml

### PostgreSQL project
- projects/db_migration/postgresql_to_azure_postgresql_flexible_server/README.md
- projects/db_migration/postgresql_to_azure_postgresql_flexible_server/docs/ARCHITECTURE.md
- projects/db_migration/postgresql_to_azure_postgresql_flexible_server/docs/MIGRATION_RUNBOOK.md
- projects/db_migration/postgresql_to_azure_postgresql_flexible_server/scripts/schema_assessment.sql
- projects/db_migration/postgresql_to_azure_postgresql_flexible_server/scripts/full_load_orchestration.sh
- projects/db_migration/postgresql_to_azure_postgresql_flexible_server/scripts/postgres_wal_cdc_extractor.py
- projects/db_migration/postgresql_to_azure_postgresql_flexible_server/scripts/azure_postgres_replay_worker.py
- projects/db_migration/postgresql_to_azure_postgresql_flexible_server/scripts/reconciliation_checks.sql
- projects/db_migration/postgresql_to_azure_postgresql_flexible_server/scripts/business_validation.sql
- projects/db_migration/postgresql_to_azure_postgresql_flexible_server/scripts/performance_baseline.sh
- projects/db_migration/postgresql_to_azure_postgresql_flexible_server/config/postgresql_flexible_migration.env
- projects/db_migration/postgresql_to_azure_postgresql_flexible_server/config/cdc_config.yaml

### Manifest
- COMMIT_MANIFEST_MYSQL_POSTGRES_FLEXIBLE.md

## Scope Summary

Both projects include:
- Enterprise migration plan with phased execution model
- Architecture and runbook documentation
- Seed orchestration, CDC extraction/replay, validation scripts
- Operational configuration templates

## Notes

- Scripts are framework templates and require environment-specific adaptation before production execution.
- CDC extractor/replay scripts include placeholders where organization-specific integration code should be implemented.
