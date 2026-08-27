# Aurora PostgreSQL

This is the **primary Aurora PostgreSQL working area** for the repository.

## What lives here

- `aws-rds/` — AWS RDS PostgreSQL performance troubleshooting and the single-file HTML Postgres Observability Report
- `or/` — Aurora PostgreSQL Observability Report tooling
- `sql/` — consultant-style diagnostics and operational SQL
- `infrastructure/` — Aurora, RDS Proxy, DynamoDB, and Redis infrastructure examples
- `kubernetes/` — PgBouncer and postgres exporter manifests
- `observability/` — Grafana dashboards and Prometheus rules
- `automation/` — helper scripts and runners
- `docs/` — architecture and implementation notes
- `database-admin/` — legacy Aurora PostgreSQL reference material preserved from the previous layout

## Use this area for

- production Aurora troubleshooting
- performance tuning
- schema safety and zero-downtime migration patterns
- observability and interval reporting
- AWS-native PostgreSQL platform patterns

## Default path for new work

If a new contribution is specifically about Aurora PostgreSQL or closely related AWS PostgreSQL operations, put it here first.

## How to run the observability report

This report is read-only. It does not create permanent objects and is safe to run against Aurora PostgreSQL with a normal reporting user.

### Linux

```bash
export PGPASSWORD='your_password'
psql \
  -h your-aurora-writer.cluster-xxxx.us-east-1.rds.amazonaws.com \
  -U postgres \
  -d your_database \
  -p 5432 \
  -v ON_ERROR_STOP=1 \
  -f platforms/aurora-postgresql/aws-rds/postgres_observability_report.sql \
  -o aurora_observability_report.html
xdg-open aurora_observability_report.html
```

### Windows PowerShell

```powershell
$env:PGPASSWORD = "your_password"
$env:PGSSLMODE = "require"
& psql.exe `
  -h your-aurora-writer.cluster-xxxx.us-east-1.rds.amazonaws.com `
  -U postgres `
  -d your_database `
  -p 5432 `
  -v ON_ERROR_STOP=1 `
  -f .\platforms\aurora-postgresql\aws-rds\postgres_observability_report.sql `
  -o .\aurora_observability_report.html
Start-Process .\aurora_observability_report.html
```

### Notes

- Use the **writer endpoint** for the most complete view.
- The file is designed to degrade gracefully if `pg_stat_statements` or other optional extensions are not installed.
- For a high-sensitivity OLTP system, run first during a quiet window.
