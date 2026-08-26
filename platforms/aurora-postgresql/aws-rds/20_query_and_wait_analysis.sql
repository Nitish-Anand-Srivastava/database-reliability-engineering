\set ON_ERROR_STOP on
\pset pager off
\x auto

\echo Step 5: blocking chains
SELECT * FROM dbre_rds_pg.blocking_overview();

\echo Step 6: database pressure
SELECT * FROM dbre_rds_pg.database_pressure();

\echo Step 7: top SQL from pg_stat_statements
SELECT * FROM dbre_rds_pg.top_statements(25);

\echo Step 8: checkpointer and bgwriter posture
SELECT * FROM dbre_rds_pg.checkpointer_overview();
