# Aurora PostgreSQL DBRE Architecture

## Scope

This framework is designed for a Staff Database Engineer who owns:

- Aurora PostgreSQL 16+
- RDS Proxy
- DynamoDB coordination state
- ElastiCache Redis
- EKS-hosted PgBouncer and `postgres_exporter`
- Prometheus and Grafana
- Migration safety and operational diagnostics

## Architecture principles

### 1. Keep the writer boring

The Aurora writer is the constrained part of the system. The framework therefore pushes connection fan-in and retry behavior outward:

- **RDS Proxy** handles client pooling, IAM-capable authentication, and failover-friendly connection reuse.
- **PgBouncer** runs close to workloads in EKS for transaction pooling and connection smoothing during pod churn.
- **Redis** absorbs latency-sensitive cache traffic that does not belong on the database.
- **DynamoDB** carries coordination state that needs predictable single-digit millisecond lookups without relational locking.

### 2. Prefer bounded concurrency over heroic tuning

Connection storms, lock pileups, and vacuum debt are more common production killers than raw CPU shortage. The delivered assets therefore emphasize:

- connection caps
- short `lock_timeout`
- long-transaction alerting
- blocking-chain visibility
- autovacuum debt and HOT ratio checks
- explicit failover posture

### 3. Observe both database internals and AWS-managed behavior

Aurora is not self-managed PostgreSQL on EC2. Useful operations require both SQL-level and AWS-native signals:

- `pg_stat_activity`, `pg_locks`, `pg_stat_statements`, `pg_stat_user_tables`
- CloudWatch metrics for CPU, freeable memory, database connections, replica lag, and storage pressure
- Performance Insights for AAS, top waits, and SQL attribution during incidents

## Recommended runtime pattern

```text
Application pods
  -> PgBouncer (transaction pooling in-cluster for noisy clients)
  -> RDS Proxy (centralized pool and failover-aware entry point)
  -> Aurora writer / readers
```

Use **RDS Proxy** as the canonical application endpoint. Keep **PgBouncer** for EKS-local smoothing when horizontal pod scaling or cron spikes would otherwise produce excessive authentication churn.

## Folder responsibilities

| Path | Purpose |
|---|---|
| `infrastructure/terraform/modules/aurora_postgresql` | Aurora cluster, subnet group, security group, parameter group, instances |
| `infrastructure/terraform/modules/rds_proxy` | Proxy, connection pool defaults, IAM role for Secrets Manager |
| `infrastructure/terraform/modules/dynamodb` | Coordination table for migration and cutover metadata |
| `infrastructure/terraform/modules/elasticache_redis` | Multi-AZ Redis replication group with encryption |
| `kubernetes/pgbouncer` | EKS deployment with health probes, PDB, and templated config |
| `kubernetes/postgres-exporter` | Writer-side exporter deployment and Prometheus Operator ServiceMonitor |
| `sql/aurora_postgresql` | Operational SQL for visibility, migration guardrails, and performance posture |
| `observability` | Grafana dashboard plus alert rules that map to DBRE actions |
| `automation` | Secret-material generation and repeatable SQL bundle execution |

## Secret and config expectations

The Kubernetes manifests intentionally reference pre-created runtime objects rather than embedding credentials:

- `ConfigMap/aurora-platform-endpoints`
  - `AURORA_WRITER_ENDPOINT`
  - `AURORA_PORT`
  - `AURORA_DATABASE`
  - `AURORA_APP_USER`
- `Secret/aurora-app-credentials`
  - `AURORA_APP_PASSWORD`
- `Secret/pgbouncer-auth`
  - `users.txt`

Generate `users.txt` with:

```bash
python automation/generate_pgbouncer_scram.py app_user
```

The script prompts for the password and emits a PgBouncer-compatible SCRAM line.

## Safe operations defaults

- `pool_mode=transaction` in PgBouncer
- TLS required in RDS Proxy
- Aurora parameter group enables `pg_stat_statements`, `log_connections`, `log_disconnections`, and `track_io_timing`
- SQL bundle uses `ON_ERROR_STOP`, short `lock_timeout`, and concurrent index creation
- Prometheus alerts are tuned toward symptoms that warrant action, not low-signal noise
