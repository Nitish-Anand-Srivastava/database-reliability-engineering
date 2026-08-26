\set ON_ERROR_STOP on
\pset pager off

\echo Install helper functions first if needed
\echo Recommended: \i 00_install_rds_pg_troubleshooting.sql
\echo
\echo Running first-pass incident triage
\ir 10_incident_triage.sql
