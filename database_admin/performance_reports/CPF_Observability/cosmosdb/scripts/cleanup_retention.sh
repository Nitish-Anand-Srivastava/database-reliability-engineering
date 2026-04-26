#!/usr/bin/env bash
set -euo pipefail
find ../data/snapshots -type f -mtime +7 -delete
find ../data/reports -type f -mtime +7 -delete
echo "Cleanup complete"
