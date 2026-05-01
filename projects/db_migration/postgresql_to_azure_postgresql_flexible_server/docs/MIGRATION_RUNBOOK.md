# Migration Runbook: PostgreSQL to Azure PostgreSQL Flexible Server

## Phase 1: Full Seed (Weeks 1-4)

1. Run extension and schema compatibility review
2. Export schema/data and seed target database
3. Validate object count and row parity snapshots

## Phase 2: CDC Sync (Weeks 3-10)

1. Enable logical decoding/WAL extraction pipeline
2. Start CDC extractor and replay worker
3. Monitor lag and apply-rate trends continuously

## Phase 3: Validation and Cutover (Weeks 11-12)

1. Execute reconciliation and business validation suites
2. Compare critical query baselines
3. Freeze source writes, drain final CDC lag, switch endpoints

## Rollback

- Maintain source rollback path for 72-hour hypercare window
- Restore endpoint mapping to source upon critical post-cutover issue

Last Updated: 2026-05-01
