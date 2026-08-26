# AWS RDS Engine-Agnostic Checks

## Daily
- Instance status, CPU, memory, storage free, connections.
- Backup job status and retention.
- Read replica lag and health.
- Parameter/option group drift.

## Weekly
- Restore test from latest snapshot.
- Capacity trend (storage/autoscaling).
- Slow query review and top waits.
- IAM auth, secret rotation, and network policy review.

## PostgreSQL operator path

For AWS RDS PostgreSQL incidents, use the dedicated SQL pack in:

- `platforms/aws-databases/rds/postgresql/`

Recommended order:

1. `00_install_rds_pg_troubleshooting.sql`
2. `10_incident_triage.sql`
3. `20_query_and_wait_analysis.sql`
4. `30_table_storage_and_maintenance.sql`
5. `40_replication_and_rds_checks.sql`
