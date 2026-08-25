#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_PATH="${AWR_CONFIG:-${ROOT_DIR}/config/awr_report.env}"

exec python3 "${SCRIPT_DIR}/aurora_awr.py" --config "${CONFIG_PATH}" "$@"
