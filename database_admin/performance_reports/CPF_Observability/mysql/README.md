# CPF_Observability - mysql

## Purpose
Generate AWR-style HTML performance insights for **mysql** with default **30-minute snapshots** and **7-day retention**.

## Paths
- Config: `database_admin/performance_reports/CPF_Observability/mysql/config/default.env`
- Snapshot collectors: `database_admin/performance_reports/CPF_Observability/mysql/snapshots/`
- Report datasets: `database_admin/performance_reports/CPF_Observability/mysql/reports/`
- Scripts: `database_admin/performance_reports/CPF_Observability/mysql/scripts/`
- Snapshot storage: `database_admin/performance_reports/CPF_Observability/mysql/data/snapshots/`
- HTML output: `database_admin/performance_reports/CPF_Observability/mysql/data/reports/`
- Logs: `database_admin/performance_reports/CPF_Observability/mysql/logs/`

## Quick start (junior DBA)
1. Edit `config/default.env` (connection/profile values).
2. Ensure scripts are executable: `chmod 750 scripts/*.sh`.
3. Ensure Linux line endings if files were copied from Windows: `sed -i 's/\r$//' scripts/*.sh`.
4. Run one-off: `cd .../mysql/scripts && ./run_oneoff.sh`.
5. Schedule every 30 minutes via cron/Task Scheduler using `schedule_30m.sh` guidance.
6. Run retention cleanup daily via `cleanup_retention.sh`.

## Troubleshooting

- Symptom: `No such file or directory` when running `./run_oneoff.sh`
	- Likely cause: CRLF line endings on Linux shell scripts.
	- Fix: `sed -i 's/\r$//' scripts/*.sh`
- Symptom: `Permission denied`
	- Likely cause: execute bit not set.
	- Fix: `chmod 750 scripts/*.sh`

## Modes
- Scheduled mode: `RUN_MODE=scheduled` (default)
- One-off mode: `RUN_MODE=oneoff`

## Required report sections
- Workload summary, top SQL/ops, waits, blocking/deadlocks, long-running workload, resource pressure, and recommendations.
