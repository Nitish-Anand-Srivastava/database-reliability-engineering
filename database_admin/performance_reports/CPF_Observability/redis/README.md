# CPF_Observability - redis

## Purpose
Generate AWR-style HTML performance insights for **redis** with default **30-minute snapshots** and **7-day retention**.

## Paths
- Config: `database_admin/performance_reports/CPF_Observability/redis/config/default.env`
- Snapshot collectors: `database_admin/performance_reports/CPF_Observability/redis/snapshots/`
- Report datasets: `database_admin/performance_reports/CPF_Observability/redis/reports/`
- Scripts: `database_admin/performance_reports/CPF_Observability/redis/scripts/`
- Snapshot storage: `database_admin/performance_reports/CPF_Observability/redis/data/snapshots/`
- HTML output: `database_admin/performance_reports/CPF_Observability/redis/data/reports/`
- Logs: `database_admin/performance_reports/CPF_Observability/redis/logs/`

## Quick start (junior DBA)
1. Edit `config/default.env` (connection/profile values).
2. Run one-off: `cd .../redis/scripts && ./run_oneoff.sh`.
3. Schedule every 30 minutes via cron/Task Scheduler using `schedule_30m.sh` guidance.
4. Run retention cleanup daily via `cleanup_retention.sh`.

## Modes
- Scheduled mode: `RUN_MODE=scheduled` (default)
- One-off mode: `RUN_MODE=oneoff`

## Required report sections
- Workload summary, top SQL/ops, waits, blocking/deadlocks, long-running workload, resource pressure, and recommendations.
