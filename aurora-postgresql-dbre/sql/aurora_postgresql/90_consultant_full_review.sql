\set ON_ERROR_STOP on
\pset pager off
\x auto

\echo Running full Aurora PostgreSQL consultant review
\ir 00_enable_pg_stat_statements.sql
\ir 05_install_dbre_diagnostics.sql
\ir 11_instance_overview.sql
\ir 12_who_is_active.sql
\ir 13_blocking_and_waits.sql
\ir 14_database_pressure.sql
\ir 15_pg_stat_statements_review.sql
\ir 16_table_churn_and_hot_updates.sql
\ir 17_vacuum_freeze_and_stats_gaps.sql
\ir 18_index_and_io_review.sql
\ir 19_replication_and_slots.sql
\ir 20_configuration_gap_review.sql
