# Incident Runbooks Index

This page is the entry point for incident response procedures.

## Canonical Runbooks

- PostgreSQL Incident Response:
	- `database_admin/sre/runbooks/incident_response.md`
- Failover Procedure:
	- `database_admin/sre/runbooks/failover_procedure.md`
- Disaster Recovery:
	- `database_admin/sre/runbooks/disaster_recovery.md`

## Standard Format

All runbooks should follow the template:

- `database_admin/templates/runbook_template.md`

Required sections include Summary, Impact, Preconditions, Preparation, Procedure, Verification, Rollback, Communication, and Evidence.

## Incident Workflow (Conceptual)

```mermaid
flowchart TD
		A[Alert Triggered] --> B[Triage and Severity]
		B --> C[Stabilize Service]
		C --> D[Root Cause Isolation]
		D --> E{Needs Failover?}
		E -- Yes --> F[Execute Failover Runbook]
		E -- No --> G[Targeted Remediation]
		F --> H[Verification]
		G --> H
		H --> I[Post-Incident Review]
```

Diagram description: The workflow starts with alerting, moves through triage and stabilization, branches to failover when needed, and converges on verification and post-incident learning.
