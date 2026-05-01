# Architecture: On-Prem SQL Server to Azure SQL Database Hyperscale

## Target Scenario

- Source: SQL Server 2019 Enterprise on-premises, 72 TB OLTP database
- Target: Azure SQL Database Hyperscale
- Availability objective: migration with controlled cutover downtime <= 90 minutes
- Data objective: zero intentional data loss, full reconciliation prior to go-live

---

## Logical Architecture

```text
+--------------------------------------------------------------------------------+
| Source Zone                                                                    |
|                                                                                |
|  SQL Server (OLTP)                                                             |
|   - Full backup stripes                                                        |
|   - CDC enabled tables                                                         |
|   - LSN watermark tracking                                                     |
+------------------------------------------+-------------------------------------+
                                           |
                                           v
+--------------------------------------------------------------------------------+
| Transfer and Orchestration Zone                                                |
|                                                                                |
|  Azure Blob Storage (staging)                                                  |
|  Azure DMS (seed and online migration orchestration)                          |
|  PowerShell orchestrator + Python workers                                      |
|  Durable queue files and checkpoint store                                      |
+------------------------------------------+-------------------------------------+
                                           |
                                           v
+--------------------------------------------------------------------------------+
| Target Zone                                                                     |
|                                                                                |
|  Azure SQL Database Hyperscale                                                 |
|   - Pre-deployed schema and security model                                     |
|   - Replay worker applies ordered deltas                                       |
|   - Validation schema stores audit metrics                                     |
+--------------------------------------------------------------------------------+
```

---

## Phase-by-Phase Data Flow

## Phase 1: Bulk Seed

1. Snapshot readiness check on source (blocking, log growth, backup throughput)
2. Generate striped full backups and upload to Azure Blob staging
3. Deploy converted schema to Hyperscale
4. Execute full-load pipeline (DMS/parallel loaders)
5. Validate object counts, table row counts, and sampled checksums

## Phase 2: Continuous Delta Sync

1. Read CDC changes from source by LSN windows
2. Normalize operations to a replay format
3. Apply changes to Hyperscale using idempotent DML
4. Persist replay checkpoints and lag metrics
5. Alert and auto-retry on transient failures

## Phase 3: Validation and Cutover

1. Drain lag to near-zero state
2. Run full reconciliation suite
3. Lock source writes and execute final delta apply
4. Switch application connection to Hyperscale
5. Execute smoke and performance verification

---

## Availability and Reliability Controls

- Replay workers are restart-safe through table-level and global checkpoint state
- Failed changes are sent to dead-letter artifacts for deterministic reprocessing
- Batch commits are bounded to limit rollback blast radius
- Cutover is gated by explicit go/no-go criteria and sign-offs

---

## Security and Compliance Controls

- Secrets are externalized (no plaintext credentials in scripts)
- TLS enforced for source and target connectivity
- Data in transit protected through encrypted channels
- Validation artifacts are immutable and timestamped for audit trails

---

## Performance Design

- Bulk seed favors high-throughput stripe/parallel strategies
- Non-essential indexes are deferred during initial load
- Replay channel scales horizontally by table groups
- Baseline query set is replayed against target to verify SLOs

---

## Operational KPIs

| KPI | Target | Alert |
|---|---|---|
| Full load completion | <= 96 hours | > 120 hours |
| CDC lag | < 5 min | > 15 min |
| Replay failures | < 0.1% | > 1% |
| Row parity | 100% | < 100% |
| Critical query latency delta | <= 20% | > 30% |

---

## Failure Recovery Patterns

- Bulk load interruption: resume from table checkpoint
- Replay interruption: resume from last committed LSN
- Transient target issues: retry with exponential backoff
- Hard cutover issues: rollback by restoring source write path and endpoint mapping

---

## Deployment Topology Notes

- Use private networking where possible for migration flows
- Isolate migration worker resources from application runtime
- Keep source and target clock synchronization aligned for audit consistency
- Reserve sufficient temp/log capacity during index rebuild phases

---

Last Updated: 2026-05-01
