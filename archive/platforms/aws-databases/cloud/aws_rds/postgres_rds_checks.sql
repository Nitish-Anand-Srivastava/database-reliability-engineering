\set ON_ERROR_STOP on
\pset pager off

\echo This compatibility entry point now routes to the active RDS PostgreSQL troubleshooting pack.
\echo Recommended install: \i ../../rds/postgresql/00_install_rds_pg_troubleshooting.sql
\echo
\ir ../../rds/postgresql/10_incident_triage.sql