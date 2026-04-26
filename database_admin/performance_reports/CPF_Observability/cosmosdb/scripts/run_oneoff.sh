#!/usr/bin/env bash
set -euo pipefail
TS=$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p ../data/snapshots ../data/reports ../logs
echo "Running one-off snapshot at ${TS}" | tee -a ../logs/cpf.log
