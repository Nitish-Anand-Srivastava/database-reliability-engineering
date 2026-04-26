# Incident Response Runbook - PostgreSQL

## Summary

- Scope: Production PostgreSQL service degradation or outage
- Primary goals: stabilize service, reduce blast radius, restore SLO compliance
- Owner: DBA on-call / DBRE primary
- Escalation: SRE incident commander after 15 minutes unresolved at Sev-1

## Impact and Reliability Context

- Typical symptoms:
	- Elevated p95/p99 latency
	- Error spikes (timeouts, connection exhaustion)
	- Replication lag growth
	- Increased lock waits or deadlocks
- Reliability targets:
	- Availability SLO: 99.95% monthly (example)
	- RTO target for primary outage: <= 15 minutes
	- RPO target for HA failover: <= 60 seconds (asynchronous replication caveat)

## Preconditions and Risk Gates

- Ensure incident ticket and bridge channel are active.
- Confirm break-glass access path and approval policy.
- Do not execute destructive remediation (for example aggressive VACUUM FULL) during live incidents.

## Preparation

1. Record UTC start time and affected services.
2. Capture baseline metrics from dashboards:
	 - CPU, memory, IOPS, storage queue depth
	 - Active sessions, blocked sessions, deadlocks
	 - Replication lag and WAL generation rate
3. Confirm last change events (deployments, DDL, parameter changes).

## Procedure

### Phase 1: Fast Triage (0-10 minutes)

1. Confirm database reachability.
2. Check connection pressure.
3. Identify top resource consumers and blocking chains.

SQL checks:

```sql
-- Active workload by duration
SELECT pid, usename, state, wait_event_type, wait_event,
			 now() - query_start AS runtime,
			 left(query, 200) AS query
FROM pg_stat_activity
WHERE state <> 'idle'
ORDER BY runtime DESC
LIMIT 20;

-- Blocking relationships
SELECT blocked.pid AS blocked_pid,
			 blocker.pid AS blocker_pid,
			 blocked.query AS blocked_query,
			 blocker.query AS blocker_query
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked ON blocked.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocker_locks
	ON blocker_locks.locktype = blocked_locks.locktype
 AND blocker_locks.database IS NOT DISTINCT FROM blocked_locks.database
 AND blocker_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
 AND blocker_locks.page IS NOT DISTINCT FROM blocked_locks.page
 AND blocker_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
 AND blocker_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
 AND blocker_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
 AND blocker_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
 AND blocker_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
 AND blocker_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
 AND blocker_locks.pid <> blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocker ON blocker.pid = blocker_locks.pid
WHERE NOT blocked_locks.granted;
```

### Phase 2: Stabilization (10-25 minutes)

1. Apply minimally invasive controls first:
	 - Temporarily reduce app concurrency
	 - Route noisy background jobs away from primary
	 - Terminate known abusive sessions with incident commander approval
2. If connection exhaustion is active:
	 - Enforce pooling limits
	 - Reserve DBA/admin connection slots
3. If storage or I/O saturation is active:
	 - Pause heavy ETL batches
	 - Validate autovacuum pressure and checkpoint stress

### Phase 3: Root Cause Isolation (parallel track)

1. Correlate with recent schema/index and parameter changes.
2. Check plan regression candidates from query fingerprints.
3. Assess replication health before any failover decision.

### Phase 4: Escalated Recovery

Trigger failover only when one or more apply:

- Primary is unavailable or unstable beyond RTO window.
- Recovery on current primary exceeds failover risk.
- Replica health and lag are within policy threshold.

Use: `database_admin/sre/runbooks/failover_procedure.md`

## Verification

- Error rate returns below SLO budget burn threshold.
- p95/p99 latency recovers to baseline band.
- Replication lag stabilizes within policy.
- Critical business transactions succeed.
- No unresolved blocking chains for priority workloads.

## Rollback

- If remediation introduces instability:
	1. Revert temporary parameter overrides.
	2. Re-enable throttled jobs in controlled sequence.
	3. Re-validate query performance against baseline.
- If failover occurred and new primary is unstable, execute DR escalation according to DR policy.

## Communication

- Update cadence:
	- Every 10 minutes during active Sev-1
	- Every 30 minutes during stabilization
- Required recipients:
	- Incident commander
	- Application owner
	- Customer communications lead (if external impact)

## Evidence and Audit Trail

- Preserve:
	- Incident timeline (UTC)
	- Query outputs used for decisions
	- Dashboards/screenshots
	- Change IDs associated with incident window

## Automation Opportunities

- Auto-detect blocking chains above threshold and create incident context payload.
- Guardrail auto-throttling for non-critical ETL queues when storage latency breaches threshold.
- Automatic runbook card generation with top diagnostics at incident start.
