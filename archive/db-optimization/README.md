# Database Optimization

Scripts for indexing, partitioning, and query tuning.

## Performance Troubleshooting Query Pack

Use `database_admin/performance/query_plan_analysis.sql` for advanced diagnostics across:

- Oracle
- SQL Server
- PostgreSQL
- MySQL

The script is organized as engine-specific sections and includes:

- **Fast health detectors** that return only active performance issues (blocking, long-running work, latency pressure)
- **Deep-dive diagnostics** for waits, top SQL, lock chains, I/O hotspots, and table/index pressure

Run only the section for your target engine.
