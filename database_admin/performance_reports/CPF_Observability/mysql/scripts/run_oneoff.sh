#!/usr/bin/env bash
set -euo pipefail
# One-off snapshot + HTML report
# Usage: ./run_oneoff.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TS=$(date -u +%Y%m%dT%H%M%SZ)

mkdir -p "${BASE_DIR}/data/snapshots" "${BASE_DIR}/data/reports" "${BASE_DIR}/logs"
echo "Running one-off snapshot at ${TS}" | tee -a "${BASE_DIR}/logs/cpf.log"
# 1) execute snapshot query script for engine
# 2) write JSON/CSV snapshot into ../data/snapshots/
# 3) invoke common/report_builder_stub.py to render HTML

echo "Run complete. Output root: ${BASE_DIR}/data" | tee -a "${BASE_DIR}/logs/cpf.log"
