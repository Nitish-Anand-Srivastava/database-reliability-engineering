# AWS RDS PostgreSQL

This folder contains the **AWS RDS PostgreSQL troubleshooting toolkit** for the active Aurora/PostgreSQL platform path.

## Preferred production workflow

Use the single-file HTML report:

- `postgres_observability_report.sql`

It is designed for production-safe use because it:

- does **not** create schemas
- does **not** create helper functions
- focuses on **top resource-consuming sessions and SQL**
- includes both **performance troubleshooting** and **configuration-gap detection**
- generates a local HTML **Postgres Observability Report** with red-highlighted critical findings

Example:

```bash
psql \
  -f postgres_observability_report.sql
```

Output file:

- `postgres_observability_report.html` (written to your current working directory)

Optional legacy-only companion:

- `postgres_configuration_gap_report.sql` (kept for teams that want a standalone config-only report)

## Optional deeper workflow

If the environment allows creating helper functions, you can still use the step-by-step SQL pack:

- `00_install_rds_pg_troubleshooting.sql`
- `10_incident_triage.sql`
- `20_query_and_wait_analysis.sql`
- `30_table_storage_and_maintenance.sql`
- `40_replication_and_rds_checks.sql`
- `90_full_performance_review.sql`

That path is useful for deeper interactive troubleshooting, but the single-file HTML report should be the default for production estates.

## When to use this folder

- slow RDS PostgreSQL response
- active blockers or transaction pileups
- CPU, temp, or connection spikes
- stale statistics or autovacuum debt
- replication lag or writer pressure
- parameter posture review
- environment-level configuration gaps
- table-level autovacuum, HOT, fillfactor, and stale-statistics anomalies
