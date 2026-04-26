# Repository Taxonomy and Naming Conventions

This document defines where content belongs, how it should be named, and how cross-references should be used.

## Goals

- Reduce duplication
- Improve discoverability
- Keep operational content production-ready
- Support learning progression and architecture reference use cases

## Top-Level Taxonomy

## 1) Operations and DBRE Practice

- Primary location: `database_admin/`
- Purpose: Day-2 operations, runbooks, standards, platform-specific guidance, operational templates

## 2) Platform Engineering and Data Workflows

- Primary locations: `data-platform/`, `data_engineering/`, `etl/`, `pipelines/`
- Purpose: Data movement, transformations, orchestration, data quality, and observability in pipelines

## 3) Infrastructure and Deployment

- Primary locations: `infrastructure/`, `automation/`, `cloud-migration/`, `ha-failover/`
- Purpose: Terraform, Ansible, deployment automation, and failover orchestration

## 4) Reference Documentation and Learning Assets

- Primary location: `docs/`
- Purpose: architecture guides, playbooks, case studies, roadmap, and taxonomy standards

## 5) Optimization and Guardrails

- Primary locations: `db-optimization/`, `db-guardrails/`
- Purpose: performance and safety patterns for schema/query operations

## Placement Rules

1. Put generic operational theory in one canonical document under `docs/` or `database_admin/standards/`.
2. Put platform-specific implementation details in the corresponding platform folder.
3. Cross-reference canonical docs rather than duplicating concepts.
4. Runbooks for incident/change/recovery belong in `database_admin/sre/runbooks/`.
5. Templates belong in `database_admin/templates/` and should be reused by all teams.

## Naming Conventions

Use these standards for all new content.

- Directory names: kebab-case
- Markdown files: kebab-case.md
- Scripts: snake_case for Python, kebab-case for shell scripts where practical
- Include concise, domain-specific names, for example:
  - `replication-lag-triage.md`
  - `restore-drill-checklist.md`
  - `capacity-forecasting-model.md`

## Documentation Contract for New Runbooks

Every operational runbook must include:

- Summary
- Impact and SLO context
- Preconditions and risk gates
- Preparation checklist
- Procedure with decision points
- Verification criteria
- Rollback steps
- Communication expectations
- Evidence and audit trail

Use: `database_admin/templates/runbook_template.md`

## Cross-Reference Pattern

When a platform-specific runbook depends on common guidance:

1. Link to the shared baseline (for example backup strategy).
2. Add only platform-specific deviations (for example RMAN block change tracking for Oracle, WAL settings for PostgreSQL).
3. Record constraints and known trade-offs.

## Suggested Content Ownership Model

- Each folder should define owner/team metadata in its local README.
- Critical runbooks should have review cadence (for example quarterly).
- High-risk procedures should include last drill date and next scheduled drill.

## Incremental Migration Guidance

This repository already contains a large body of material. Apply conventions incrementally:

1. Do not mass-rename legacy paths immediately.
2. Apply conventions to new files first.
3. Refactor high-traffic documents in quarterly batches.
4. Add redirect notes in old locations when content is moved.
