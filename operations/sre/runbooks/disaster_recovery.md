# Disaster Recovery Runbook

## Summary

- Purpose: recover database services after major failure scenarios (site, region, or data corruption)
- Scope: Tier-1 and Tier-2 production data services
- Owner: DR lead DBA with incident commander and platform lead

## Objectives

- Meet documented RTO and RPO per service tier
- Restore critical business transactions first
- Re-establish secure and observable steady-state operations

## DR Scenario Classification

1. Single-node failure: handled by HA runbook (not full DR)
2. Cluster-level failure in-region
3. Region-level outage
4. Logical corruption or destructive change propagation

## Preconditions and Risk Gates

- Confirm disaster declaration level and authority.
- Confirm legal/compliance constraints for cross-region recovery.
- Verify backup integrity evidence before restore execution.

## Preparation

1. Establish DR command bridge and role assignments.
2. Freeze high-risk schema and deployment operations globally.
3. Retrieve latest validated backup metadata and restore manifests.
4. Validate target environment capacity and network routes.

## Procedure

### Phase 1: Scope and Prioritize

1. Identify affected services and data domains.
2. Prioritize restores by business criticality:
	 - Tier-1 transactional systems
	 - Tier-2 operational reporting
	 - Tier-3 back-office workloads

### Phase 2: Restore Core Data Services

1. Provision recovery infrastructure.
2. Restore from latest known-good backup.
3. Apply required logs/archives to meet RPO target where possible.
4. Recreate users, roles, and secrets integration.

Example restore verification checklist:

- Control files/log sequence continuity
- Catalog consistency
- Required schemas present
- Critical tables row counts within expected tolerance

### Phase 3: Rebuild Replication and HA

1. Establish new primary.
2. Rebuild replicas from recovered primary baseline.
3. Validate replica lag and failover readiness.

### Phase 4: Application Recovery and Controlled Re-entry

1. Start with read-only validation where possible.
2. Enable write traffic for Tier-1 applications.
3. Gradually reintroduce batch and analytics workloads.

## Verification

- Data integrity:
	- Row count reconciliation for critical entities
	- Checksums or hash sampling for high-value tables
	- Referential integrity spot checks
- Service integrity:
	- Authentication and authorization paths
	- Backup jobs resumed
	- Monitoring and alerting fully active
- Performance integrity:
	- p95 latency and throughput within degraded-but-acceptable range
	- No sustained lock storms or replication backlog

## Rollback / Alternative Path

- If restore point is invalid or corrupted:
	1. Shift to prior restore point.
	2. Reassess RPO impact and communicate explicitly.
	3. Engage data owners for business-level reconciliation decisions.

## Communication

- Status update cadence:
	- Every 15 minutes during active recovery
	- Every 30 minutes during stabilization
- Mandatory updates:
	- Recovery stage
	- Current RTO/RPO estimate vs target
	- Risks and next decision gate

## Evidence and Audit Trail

- Disaster declaration record
- Restore logs and timestamps
- Integrity validation outputs
- Approval records for major decision points

## DR Drill Program Requirements

- Conduct at least quarterly tabletop exercise.
- Conduct at least semiannual technical recovery drill.
- Track:
	- Planned vs actual RTO
	- Planned vs actual RPO
	- Manual steps converted to automation
	- Documentation gaps discovered
