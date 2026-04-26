# Failover Procedure

## Summary

- Purpose: controlled promotion of a healthy replica when the primary is unavailable or unsafe
- Scope: planned and unplanned failover for primary PostgreSQL service
- Owner: DBRE/DBA on-call with incident commander approval

## Impact and Reliability Context

- Failover is a risk trade-off between downtime and potential data loss.
- Always quantify expected RPO before promotion.
- Default policy: prefer shortest safe outage over prolonged instability.

## Trigger Conditions

- Primary node unreachable beyond policy window
- Primary node reachable but unable to sustain critical transaction throughput
- Storage or corruption indicators make continued writes unsafe

## Preconditions and Risk Gates

- Confirm candidate replica health:
	- replication lag within policy
	- no data corruption markers
	- adequate CPU/storage headroom
- Confirm application connection strategy (DNS/proxy/service endpoint)
- Confirm rollback or fallback approach before promotion

## Preparation

1. Freeze non-critical write workloads.
2. Capture final lag metrics and replication state.
3. Notify stakeholders that failover is about to begin.

## Procedure

### Step 1: Select Promotion Candidate

Selection criteria:

- Lowest replication lag
- Stable resource profile
- Healthy WAL apply status
- Same major engine version and parameter compatibility

### Step 2: Promote Replica

Example command (adjust for orchestration tooling):

```bash
# Example only; use platform-specific failover command
pg_ctl promote -D /var/lib/postgresql/data
```

Managed services should use native API/CLI promotion operations to preserve control-plane metadata.

### Step 3: Redirect Traffic

1. Update writer endpoint (proxy, service discovery, or DNS).
2. Drain stale client connections.
3. Validate connection success from critical applications.

### Step 4: Post-Promotion Safety Checks

Run write/read validation:

```sql
CREATE TABLE IF NOT EXISTS failover_probe(id int primary key, ts timestamptz);
INSERT INTO failover_probe VALUES (1, now())
ON CONFLICT (id) DO UPDATE SET ts = excluded.ts;
SELECT * FROM failover_probe;
```

## Verification

- Application write path restored.
- Error rate and latency return within SLO envelope.
- Replica topology converges with new primary.
- Alerting and backups now target the new primary.

## Rollback / Fallback

- If new primary becomes unstable:
	1. Evaluate alternate replica promotion.
	2. If safe and necessary, perform second failover.
	3. Escalate to DR runbook if region-level issue persists.

Note: reverting to old primary is not a simple rollback unless consistency has been explicitly reconciled.

## Post-Failover Actions

1. Rebuild failed node as replica from a consistent base backup.
2. Revalidate HA policy thresholds and failover guardrails.
3. Complete post-incident review and update runbook gaps.

## Communication

- Announce phases: decision, promotion, traffic cutover, stabilization.
- Include estimated RPO impact and expected stabilization window.

## Evidence

- Failover decision log
- Replication lag snapshots before/after
- Cutover timestamps and validation outputs
