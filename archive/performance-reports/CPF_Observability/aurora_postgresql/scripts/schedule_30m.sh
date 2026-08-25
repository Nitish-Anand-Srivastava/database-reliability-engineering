#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="${SCRIPT_DIR}/run_oneoff.sh"
CLEANUP="${SCRIPT_DIR}/cleanup_retention.sh"

cat <<EOF
Recommended cron entries for aurora_postgresql:
*/30 * * * * "${RUNNER}" >> "${SCRIPT_DIR}/../logs/scheduler.log" 2>&1
15 1 * * * "${CLEANUP}" >> "${SCRIPT_DIR}/../logs/scheduler.log" 2>&1
EOF
