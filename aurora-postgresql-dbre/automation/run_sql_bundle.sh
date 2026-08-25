#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SQL_DIR="${ROOT_DIR}/sql/aurora_postgresql"
PSQL_BIN="${PSQL_BIN:-psql}"

if ! command -v "${PSQL_BIN}" >/dev/null 2>&1; then
  echo "psql was not found on PATH. Set PSQL_BIN or install PostgreSQL client tools." >&2
  exit 1
fi

if [[ -z "${DATABASE_URL:-}" && -z "${PGHOST:-}" ]]; then
  echo "Set DATABASE_URL or standard PG* environment variables before running the bundle." >&2
  exit 1
fi

for sql_file in "${SQL_DIR}"/*.sql; do
  if [[ "$(basename "${sql_file}")" == 90_* ]]; then
    continue
  fi
  if [[ "$(basename "${sql_file}")" == "install_dbre_diag.sql" ]]; then
    continue
  fi
  echo "Running $(basename "${sql_file}")"
  "${PSQL_BIN}" -v ON_ERROR_STOP=1 -f "${sql_file}"
done
