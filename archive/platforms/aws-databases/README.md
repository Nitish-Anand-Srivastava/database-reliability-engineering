# Archived AWS Databases Material

This folder preserves the **previous AWS database platform structure** that existed before the active PostgreSQL-on-AWS content was consolidated under:

- `platforms/aurora-postgresql/aws-rds/`

## Why this is archived

The earlier `platforms/aws-databases/` tree split active PostgreSQL-on-AWS work away from the main Aurora/PostgreSQL platform path and duplicated navigation.

To keep the active repository simpler:

- the current PostgreSQL and Aurora-on-AWS working path now lives under `platforms/aurora-postgresql/`
- the old multi-engine AWS database layout is kept here only as legacy reference

## Do not use this as the default authoring path

For new work:

1. use `platforms/aurora-postgresql/aws-rds/` for AWS RDS PostgreSQL troubleshooting
2. use `platforms/aurora-postgresql/or/` for observability reporting
3. treat this archived tree as reference-only unless content is intentionally refreshed and moved back into the active structure
