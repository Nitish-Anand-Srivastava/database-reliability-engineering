#!/usr/bin/env bash
set -euo pipefail
# Delete snapshot/report files older than 7 days by default
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

find "${BASE_DIR}/data/snapshots" -type f -mtime +7 -delete
find "${BASE_DIR}/data/reports" -type f -mtime +7 -delete
echo "Retention cleanup complete"
