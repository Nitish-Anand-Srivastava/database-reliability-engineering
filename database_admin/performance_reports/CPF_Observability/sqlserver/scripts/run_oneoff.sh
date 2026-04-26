#!/usr/bin/env bash
set -euo pipefail
# One-off snapshot + HTML report
# Usage: ./run_oneoff.sh
TS=$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p ../data/snapshots ../data/reports ../logs
echo "Running one-off snapshot at ${TS}" | tee -a ../logs/cpf.log
# 1) execute snapshot query script for engine
# 2) write JSON/CSV snapshot into ../data/snapshots/
# 3) invoke common/report_builder_stub.py to render HTML
