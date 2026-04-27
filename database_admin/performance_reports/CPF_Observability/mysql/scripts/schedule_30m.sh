#!/usr/bin/env bash
set -euo pipefail
# Cron example (every 30 minutes):
# */30 * * * * /path/to/run_oneoff.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Configure your scheduler to run ${SCRIPT_DIR}/run_oneoff.sh every 30 minutes."
