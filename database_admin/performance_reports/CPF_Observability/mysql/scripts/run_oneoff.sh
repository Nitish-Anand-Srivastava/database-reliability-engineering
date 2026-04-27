#!/usr/bin/env bash
set -euo pipefail
# One-off snapshot + HTML report
# Usage: ./run_oneoff.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${BASE_DIR}/config/default.env"
SNAPSHOT_SQL="${BASE_DIR}/snapshots/snapshot_queries.sql"
REPORT_SQL="${BASE_DIR}/reports/report_queries.sql"
TS=$(date -u +%Y%m%dT%H%M%SZ)

mkdir -p "${BASE_DIR}/data/snapshots" "${BASE_DIR}/data/reports" "${BASE_DIR}/logs"
echo "Running one-off snapshot at ${TS}" | tee -a "${BASE_DIR}/logs/cpf.log"

if [[ ! -f "${CONFIG_FILE}" ]]; then
	echo "ERROR: Missing config file: ${CONFIG_FILE}" | tee -a "${BASE_DIR}/logs/cpf.log"
	exit 1
fi

if ! command -v mysql >/dev/null 2>&1; then
	echo "ERROR: mysql client not found in PATH." | tee -a "${BASE_DIR}/logs/cpf.log"
	exit 1
fi

# shellcheck disable=SC1090
source "${CONFIG_FILE}"

# Allow environment variables to override values from config/default.env.
MYSQL_LOGIN_PATH="${MYSQL_LOGIN_PATH:-}"
MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_DATABASE="${MYSQL_DATABASE:-performance_schema}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-}"

MYSQL_CMD=(mysql --connect-timeout=5)

if [[ -n "${MYSQL_LOGIN_PATH}" ]]; then
	MYSQL_CMD+=(--login-path="${MYSQL_LOGIN_PATH}")
	TARGET_DESC="login-path=${MYSQL_LOGIN_PATH}"
else
	MYSQL_CMD+=(
		--host="${MYSQL_HOST}"
		--port="${MYSQL_PORT}"
		--user="${MYSQL_USER}"
		--database="${MYSQL_DATABASE}"
	)
	TARGET_DESC="${MYSQL_USER}@${MYSQL_HOST}:${MYSQL_PORT}/${MYSQL_DATABASE}"
fi

if [[ -n "${MYSQL_PASSWORD}" ]]; then
	export MYSQL_PWD="${MYSQL_PASSWORD}"
fi

echo "Target MySQL instance: ${TARGET_DESC}" | tee -a "${BASE_DIR}/logs/cpf.log"

SNAPSHOT_OUT="${BASE_DIR}/data/snapshots/snapshot_${TS}.txt"
REPORT_OUT="${BASE_DIR}/data/reports/report_${TS}.txt"

"${MYSQL_CMD[@]}" < "${SNAPSHOT_SQL}" > "${SNAPSHOT_OUT}"
"${MYSQL_CMD[@]}" < "${REPORT_SQL}" > "${REPORT_OUT}"

echo "Snapshot written: ${SNAPSHOT_OUT}" | tee -a "${BASE_DIR}/logs/cpf.log"
echo "Report dataset written: ${REPORT_OUT}" | tee -a "${BASE_DIR}/logs/cpf.log"

echo "Run complete. Output root: ${BASE_DIR}/data" | tee -a "${BASE_DIR}/logs/cpf.log"
