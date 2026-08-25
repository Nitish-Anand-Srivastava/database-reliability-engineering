# Database Reliability Engineering

This repository is now organized as a **hands-on senior DBRE toolkit** centered on:

- Aurora PostgreSQL and PostgreSQL operations
- AWS database platform work
- troubleshooting and performance tuning
- automation and operational scripts
- Terraform, Ansible, and platform workflows
- observability, diagnostics, and interval reporting

## Top-level structure

```text
.
|-- automation/        Reusable scripts, deployment helpers, and CI/CD utilities
|-- data-platform/     Kept data-platform patterns and supporting benchmarks
|-- infrastructure/    Terraform, Ansible, and shared infrastructure configuration
|-- migrations/        Migration runbooks, cloud migration assets, and project migrations
|-- observability/     Monitoring assets, dashboards, alerts, and database observability references
|-- operations/        Runbooks, standards, maintenance, backup, replication, and failover content
|-- platforms/         Engine and platform-specific DBRE toolkits, with Aurora PostgreSQL as the primary path
|-- reference/         Architecture notes, repository guidance, case studies, and supporting reference material
`-- archive/           Legacy or lower-priority content preserved intentionally but no longer the default authoring path
```

## Where to start

### Aurora PostgreSQL / AWS DBRE

- `platforms/aurora-postgresql/`

This is the primary working area for:

- Aurora PostgreSQL diagnostics
- PostgreSQL observability and interval reports
- RDS Proxy / PgBouncer patterns
- Kubernetes exporter and pooling integration
- Aurora-focused infrastructure examples

### Day-2 operational work

- `operations/`

Use this for:

- incident and failover runbooks
- backup and restore procedures
- replication operations
- maintenance standards
- capacity, indexing, and workload reviews

### Infra and automation

- `infrastructure/`
- `automation/`

Use these for:

- Terraform / IaC
- Ansible and environment configuration
- deployment helpers and operational automation

### Monitoring and observability

- `observability/`

Use this for:

- dashboards
- alerts
- monitoring rule sets
- database observability reference outputs

## Authoring rules for new content

When adding new material:

1. Put Aurora/PostgreSQL-specific operational content under `platforms/aurora-postgresql/` unless it clearly belongs in `operations/` or `infrastructure/`.
2. Put reusable runbooks and operating standards under `operations/`.
3. Put infrastructure code under `infrastructure/`.
4. Put scripts and deployment helpers under `automation/`.
5. Put old or non-core material in `archive/` instead of mixing it into the active toolkit.

## Intentionally preserved legacy areas

Some historical material remains under `archive/` because it may still be useful as reference, but it is **not** the default path for new work. The active opinionated structure is the top-level layout above.
