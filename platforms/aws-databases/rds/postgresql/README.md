# AWS RDS PostgreSQL Troubleshooting Pack

This folder is the **step-by-step operational pack** for troubleshooting **AWS RDS PostgreSQL performance issues**.

It is designed for:

- slow application response
- spikes in CPU, IO, temp usage, or connections
- blockers and long transactions
- replication lag and writer pressure
- stale statistics, bloat, and autovacuum debt
- parameter/configuration gaps that hurt production stability

## Files

- `00_install_rds_pg_troubleshooting.sql` — installs reusable `dbre_rds_pg.*` helper functions
- `10_incident_triage.sql` — first-pass triage for sessions, waits, and current pressure
- `20_query_and_wait_analysis.sql` — blockers, top SQL, and database pressure
- `30_table_storage_and_maintenance.sql` — churn-heavy tables, bloat proxies, vacuum debt, stale stats
- `40_replication_and_rds_checks.sql` — replication posture and RDS parameter review
- `90_full_performance_review.sql` — runs the whole workflow in order
- `admin_checks.sql` — compatibility entry point that starts the first-pass triage

## Recommended workflow

### Fast triage during an incident

```sql
\i 00_install_rds_pg_troubleshooting.sql
\i 10_incident_triage.sql
\i 20_query_and_wait_analysis.sql
```

### Full review

```sql
\i 00_install_rds_pg_troubleshooting.sql
\i 90_full_performance_review.sql
```

## What the helper functions give you

- `dbre_rds_pg.instance_overview()`
- `dbre_rds_pg.who_is_active()`
- `dbre_rds_pg.blocking_overview()`
- `dbre_rds_pg.wait_profile()`
- `dbre_rds_pg.database_pressure()`
- `dbre_rds_pg.top_statements()`
- `dbre_rds_pg.table_churn_review()`
- `dbre_rds_pg.checkpointer_overview()`
- `dbre_rds_pg.replication_overview()`
- `dbre_rds_pg.rds_parameter_review()`

## AWS-specific operator notes

Always correlate the SQL output here with:

- CloudWatch: `CPUUtilization`, `FreeableMemory`, `ReadLatency`, `WriteLatency`, `DiskQueueDepth`, `DBLoad`, `DatabaseConnections`
- Performance Insights: top waits, top SQL, active sessions, load by host/user/application
- RDS events: failover, maintenance, storage autoscaling, parameter group changes
