# Migration Runbook: MySQL to Azure MySQL Flexible Server

## Phase 1: Seed (Weeks 1-4)

1. Run source schema assessment and compatibility checks
2. Export full dataset using parallel loaders
3. Load into Azure target using DMS/parallel ingest
4. Validate row/object parity at table level

## Phase 2: CDC Sync (Weeks 3-10)

1. Enable binlog and capture settings
2. Start CDC extractor and replay workers
3. Monitor lag and replay errors continuously
4. Tune batch size/workers for high-churn tables

## Phase 3: Validation and Cutover (Weeks 11-12)

1. Execute reconciliation checks and business parity queries
2. Compare baseline performance across critical queries
3. Freeze source writes and drain final changes
4. Switch application connection and run smoke checks

## Rollback

- Keep source write path rollback-ready for 72-hour hypercare window
- Repoint application endpoints to source on critical failure

Last Updated: 2026-05-01
