# Aurora PostgreSQL AWR-Style Reporting

This folder provides an **Oracle AWR-style reporting flow for Aurora PostgreSQL** that is safe enough to run on a busy production estate:

- stores lightweight **cumulative snapshots** in PostgreSQL
- generates a **local HTML report** on the remote Linux host
- supports **automatic 30-minute reports**
- supports **manual start/end interval reports**

It is designed for high-throughput systems where millions of low-latency queries happen between samples. The report therefore leans on:

- cumulative PostgreSQL counters
- `pg_stat_statements` deltas
- end-of-interval table, index, vacuum, IO, and session posture
- start/end wait snapshots instead of continuous ASH-style sampling

## Folder layout

```text
awr/
|-- README.md
|-- config/
|   `-- awr_report.env
|-- scripts/
|   |-- aurora_awr.py
|   |-- awrctl.sh
|   `-- install_awr_cron.sh
`-- sql/
    `-- 00_install_awr_repository.sql
```

## Prerequisites

1. Aurora PostgreSQL 16+.
2. `pg_stat_statements` enabled in the cluster parameter group.
3. `psql` installed on the Linux host that will run the reports.
4. A database role with access to:
   - `pg_stat_activity`
   - `pg_stat_statements`
   - `pg_stat_database`
   - `pg_stat_bgwriter`
   - `pg_stat_wal`
   - `pg_stat_io`
   - `pg_stat_replication`
   - `pg_replication_slots`
   - `pg_stat_user_tables`
   - `pg_stat_user_indexes`

## Configuration

Edit `config/awr_report.env`.

Important keys:

- `DATABASE_URL` or standard `PG*` connection variables
- `OUTPUT_DIR` for generated HTML reports
- `STATE_DIR` for manual interval state
- `TOP_SQL_LIMIT` to cap stored `pg_stat_statements` rows per snapshot
- `STATEMENT_TEXT_LENGTH` to limit stored SQL text length
- `RETENTION_DAYS` for local HTML cleanup

## Linux shell install and configuration

This is the most direct way to deploy it on a remote Linux host that can reach Aurora.

### 1. Change into the AWR folder

```bash
cd /opt/database-reliability-engineering/aurora-postgresql-dbre/awr
```

Adjust the path for wherever the repository lives on the host.

### 2. Make the shell wrappers executable

```bash
chmod 750 scripts/awrctl.sh scripts/install_awr_cron.sh
```

### 3. Copy and edit the config

```bash
cp config/awr_report.env /tmp/awr_report.env
vi /tmp/awr_report.env
```

You can also edit the in-repo file directly, but many teams prefer a host-local copy outside the repo.

At minimum set:

```bash
DATABASE_URL=postgresql://monitor_user:REDACTED@aurora-writer.cluster-xxxx.eu-west-1.rds.amazonaws.com:5432/appdb?sslmode=require
OUTPUT_DIR=/var/tmp/aurora_awr/reports
STATE_DIR=/var/tmp/aurora_awr/state
TOP_SQL_LIMIT=150
STATEMENT_TEXT_LENGTH=400
RETENTION_DAYS=14
```

If you do not want to use `DATABASE_URL`, leave it blank and set:

```bash
PGHOST=aurora-writer.cluster-xxxx.eu-west-1.rds.amazonaws.com
PGPORT=5432
PGDATABASE=appdb
PGUSER=monitor_user
PGPASSWORD=REDACTED
```

### 4. Create the output directories

```bash
mkdir -p /var/tmp/aurora_awr/reports /var/tmp/aurora_awr/state
chmod 700 /var/tmp/aurora_awr/state
```

### 5. Test connectivity with the same config

```bash
AWR_CONFIG=/tmp/awr_report.env psql "$DATABASE_URL" -c "select now(), version();"
```

If you are using `PG*` variables instead of `DATABASE_URL`:

```bash
set -a
. /tmp/awr_report.env
set +a
psql -c "select now(), version();"
```

## Installation

### 1. Install the SQL repository

```bash
AWR_CONFIG=/tmp/awr_report.env ./scripts/awrctl.sh install-sql
```

This creates the `dbre_awr` schema, snapshot tables, and the `dbre_awr.take_snapshot()` function.

### 2. Take a smoke-test snapshot

```bash
AWR_CONFIG=/tmp/awr_report.env ./scripts/awrctl.sh snapshot --label smoke-test --type on_demand
```

You should get back a numeric snapshot ID.

### 3. Generate a quick manual report from two snapshots

Take a start snapshot:

```bash
AWR_CONFIG=/tmp/awr_report.env ./scripts/awrctl.sh manual-start --label smoke-window
```

Wait a few minutes while normal traffic runs, then end the interval:

```bash
AWR_CONFIG=/tmp/awr_report.env ./scripts/awrctl.sh manual-end --label smoke-window
```

The command prints the path to the generated HTML file under `OUTPUT_DIR`.

### 4. Open the generated HTML report on the server

```bash
ls -lh /var/tmp/aurora_awr/reports
```

If the host is headless, copy the HTML file off the server:

```bash
scp user@remote-host:/var/tmp/aurora_awr/reports/awr_*.html .
```

## Automatic 30-minute HTML reports

Run this once to print the cron line:

```bash
AWR_CONFIG=/tmp/awr_report.env ./scripts/install_awr_cron.sh
```

If you want it applied automatically:

```bash
AWR_CONFIG=/tmp/awr_report.env ./scripts/install_awr_cron.sh --apply
```

The cron job runs:

```bash
AWR_CONFIG=/tmp/awr_report.env ./scripts/awrctl.sh auto-run
```

That command:

1. takes a new `auto` snapshot
2. finds the previous `auto` snapshot
3. generates an HTML report for that interval
4. stores the report under `OUTPUT_DIR`
5. cleans up old HTML files according to `RETENTION_DAYS`

## Manual start/end interval workflow

### Start a manual interval

```bash
AWR_CONFIG=/tmp/awr_report.env ./scripts/awrctl.sh manual-start --label exchange-open-investigation
```

This takes the start snapshot and stores the state on disk under `STATE_DIR`.

### End the interval and build the HTML report

```bash
AWR_CONFIG=/tmp/awr_report.env ./scripts/awrctl.sh manual-end --label exchange-open-investigation
```

This takes the end snapshot, builds the HTML report for the exact interval, and clears the saved state file.

## Build a report for any two snapshot IDs

```bash
AWR_CONFIG=/tmp/awr_report.env ./scripts/awrctl.sh report --start-id 101 --end-id 102
```

If you want the HTML file in a specific place:

```bash
AWR_CONFIG=/tmp/awr_report.env ./scripts/awrctl.sh report --start-id 101 --end-id 102 --output /tmp/exchange_peak_window.html
```

## Typical manual shell session

```bash
cd /opt/database-reliability-engineering/aurora-postgresql-dbre/awr
chmod 750 scripts/awrctl.sh scripts/install_awr_cron.sh
cp config/awr_report.env /tmp/awr_report.env
vi /tmp/awr_report.env
mkdir -p /var/tmp/aurora_awr/reports /var/tmp/aurora_awr/state

AWR_CONFIG=/tmp/awr_report.env ./scripts/awrctl.sh install-sql
AWR_CONFIG=/tmp/awr_report.env ./scripts/awrctl.sh manual-start --label post-release-watch
sleep 1800
AWR_CONFIG=/tmp/awr_report.env ./scripts/awrctl.sh manual-end --label post-release-watch
ls -lh /var/tmp/aurora_awr/reports
```

## What the report includes

- interval metadata and duration
- database-level delta counters
- start/end wait profile snapshots
- top SQL by interval execution time, calls, temp usage, and WAL generation
- table churn and HOT update posture
- vacuum/freeze/statistics risk at interval end
- large low-value index review
- IO overview from `pg_stat_io`
- end-of-interval active sessions
- replication and slot posture
- configuration-gap review from the captured parameter snapshot

## Notes

- This is **AWR-style**, not a byte-for-byte Oracle AWR clone.
- Wait sections are boundary snapshots unless you add continuous sampling separately.
- The collector intentionally stores **top N statements** instead of every row from `pg_stat_statements` to stay safer on very busy systems.
- Reports are generated locally on the Linux host, which matches the remote-server deployment model you described.
