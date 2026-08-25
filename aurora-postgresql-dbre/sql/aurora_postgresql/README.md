# Aurora PostgreSQL SQL Diagnostics Guide

This folder is the **operator runbook** for the Aurora PostgreSQL diagnostics pack. It is designed for `psql` and assumes you are connected to the Aurora writer or to the database you want to inspect.

## What to run first

### 1. Enable `pg_stat_statements`

Run this once per database after the cluster parameter group already includes `pg_stat_statements` in `shared_preload_libraries`.

```sql
\i 00_enable_pg_stat_statements.sql
```

If `shared_preload_libraries` does not include `pg_stat_statements`, update the Aurora parameter group and reboot the cluster before continuing.

### 2. Install the helper functions

You can use either filename below:

```sql
\i 05_install_dbre_diagnostics.sql
```

or

```sql
\i install_dbre_diag.sql
```

This creates the reusable `dbre` schema and the helper functions such as:

- `dbre.who_is_active()`
- `dbre.blocking_overview()`
- `dbre.wait_profile()`
- `dbre.top_statements()`
- `dbre.table_churn_review()`
- `dbre.vacuum_gap_review()`
- `dbre.index_efficiency_review()`
- `dbre.io_overview()`
- `dbre.replica_status()`
- `dbre.config_gap_review()`

## What to do next

After the install step, use **one** of these workflows.

## Option A: run the whole consultant review

This is the fastest path when you want a structured first-hour assessment.

```sql
\i 90_consultant_full_review.sql
```

That script runs the review in this order:

1. `11_instance_overview.sql`
2. `12_who_is_active.sql`
3. `13_blocking_and_waits.sql`
4. `14_database_pressure.sql`
5. `15_pg_stat_statements_review.sql`
6. `16_table_churn_and_hot_updates.sql`
7. `17_vacuum_freeze_and_stats_gaps.sql`
8. `18_index_and_io_review.sql`
9. `19_replication_and_slots.sql`
10. `20_configuration_gap_review.sql`

## Option B: run the review step by step

Use this when you want to pause between sections and take notes.

### Step 1: baseline the instance and parameter posture

```sql
\i 11_instance_overview.sql
```

Use this to confirm uptime, recovery role, connection cap, worker settings, and timeouts before you interpret workload data.

### Step 2: inspect live sessions

```sql
\i 12_who_is_active.sql
```

This is the PostgreSQL-native equivalent of a lightweight `sp_WhoIsActive` snapshot. Start here during incidents.

### Step 3: inspect blockers and waits

```sql
\i 13_blocking_and_waits.sql
```

Run this when there is latency, stuck deploys, lock pileups, or idle-in-transaction suspicion.

### Step 4: review database-level pressure

```sql
\i 14_database_pressure.sql
```

This highlights rollback rate, temp spill volume, deadlocks, session pressure, and background-writer signals.

### Step 5: review expensive SQL

```sql
\i 15_pg_stat_statements_review.sql
```

Use this for top SQL, statement mean-latency percentiles, and planning-heavy statements.

### Step 6: find churn-heavy and HOT-poor tables

```sql
\i 16_table_churn_and_hot_updates.sql
```

This is where you identify update-heavy tables, dead tuples, poor HOT behavior, and sequential-scan-heavy objects.

### Step 7: review vacuum, freeze-age, and stale-statistics gaps

```sql
\i 17_vacuum_freeze_and_stats_gaps.sql
```

Use this to find wraparound risk, tables that have never been vacuumed or analyzed, and current vacuum progress.

### Step 8: review index value and IO posture

```sql
\i 18_index_and_io_review.sql
```

This highlights large low-value indexes, cache-hit gaps, and `pg_stat_io` pressure.

### Step 9: review replication and slots

```sql
\i 19_replication_and_slots.sql
```

Run this whenever replica lag, failover readiness, or WAL retention is in question.

### Step 10: review configuration gaps

```sql
\i 20_configuration_gap_review.sql
```

This surfaces parameter issues around observability, timeouts, SSL, autovacuum, and connection posture.

## Focused deep dives

These are more targeted scripts that complement the main walkthrough.

### Lock tracing only

```sql
\i 10_lock_tracing.sql
```

### Bloat and HOT analysis only

```sql
\i 20_bloat_and_hot_analysis.sql
```

### Statement latency percentile snapshot only

```sql
\i 30_statement_latency_percentiles.sql
```

### Zero-downtime DDL patterns and demo

```sql
\i 40_zero_downtime_ddl_patterns.sql
```

## Suggested review sequence for a new Aurora cluster

If you are walking into a new environment and want the shortest credible assessment path:

1. `00_enable_pg_stat_statements.sql`
2. `05_install_dbre_diagnostics.sql`
3. `11_instance_overview.sql`
4. `12_who_is_active.sql`
5. `13_blocking_and_waits.sql`
6. `15_pg_stat_statements_review.sql`
7. `16_table_churn_and_hot_updates.sql`
8. `17_vacuum_freeze_and_stats_gaps.sql`
9. `18_index_and_io_review.sql`
10. `19_replication_and_slots.sql`
11. `20_configuration_gap_review.sql`

## Notes

- The scripts are **read-only diagnostics** except for `40_zero_downtime_ddl_patterns.sql`, which creates and drops a demo schema to show safe migration patterns.
- `pg_stat_statements` data is cumulative since the last reset, restart, or extension reset. Interpret totals in that context.
- `pg_stat_io` requires PostgreSQL 16+, which aligns with the Aurora 16-first design of this framework.
- Run the scripts as a role with enough visibility into `pg_stat_activity`, `pg_stat_statements`, replication views, and catalog views.
