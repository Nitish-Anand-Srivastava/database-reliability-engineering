#!/usr/bin/env bash
set -euo pipefail
# Delete snapshot/report files older than 7 days by default
find ../data/snapshots -type f -mtime +7 -delete
find ../data/reports -type f -mtime +7 -delete
echo "Retention cleanup complete"
