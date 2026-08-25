# Architecture: On-Prem PostgreSQL to Azure PostgreSQL Flexible Server

## Scenario Baseline

- Source: PostgreSQL 14 on-premises, 36 TB
- Target: Azure Database for PostgreSQL Flexible Server
- Objective: controlled cutover with low downtime and reconciled data parity

## Data Movement Model

1. Full seed using logical dump/base table copy strategy
2. WAL/logical decoding extraction for post-seed deltas
3. Replay workers applying ordered changes to target
4. Checkpoint and lag monitoring
5. Multi-gate reconciliation before cutover

## Reliability Controls

- LSN checkpoints persisted after each successful batch
- Replay idempotency and retries for transient errors
- Dead-letter files for invalid or conflicting events
- Cutover block on failed reconciliation gates

## KPIs

| KPI | Target | Alert |
|---|---|---|
| Full seed | <= 96h | > 120h |
| CDC lag | < 5m | > 15m |
| Replay failures | < 0.1% | > 1% |
| Row parity | 100% | < 100% |

Last Updated: 2026-05-01
