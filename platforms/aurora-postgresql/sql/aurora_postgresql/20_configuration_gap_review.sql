\set ON_ERROR_STOP on
\pset pager off
\x auto

\echo Step 10: configuration gap review
SELECT * FROM dbre.config_gap_review();

\echo Installed extensions
SELECT
  extname,
  extversion
FROM pg_extension
ORDER BY extname;
