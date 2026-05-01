# Architecture: On-Prem MySQL to Azure MySQL Flexible Server

## Scenario Baseline

- Source: MySQL 8.0 on-premises, 48 TB
- Target: Azure Database for MySQL Flexible Server
- Availability target: controlled downtime <= 90 minutes

## Logical Flow

1. Full data seed from source exports into Azure staging
2. Target schema deployed and seeded
3. Binlog CDC captures ongoing deltas
4. Replay workers apply ordered changes into target
5. Reconciliation gates enforce cutover quality

## Reliability Controls

- Checkpoint by binlog file and position
- Dead-letter output for failed events
- Idempotent replay logic for restart-safe operations
- Cutover blocked unless all validation gates pass

## Operational KPIs

| KPI | Target | Alert |
|---|---|---|
| Seed completion | <= 96h | > 120h |
| CDC lag | < 5m | > 15m |
| Replay failure rate | < 0.1% | > 1% |
| Row parity | 100% | < 100% |

Last Updated: 2026-05-01
