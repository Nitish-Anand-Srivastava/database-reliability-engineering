#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
exec "${SCRIPT_DIR}/../../common/run_oneoff_engine.sh" "cosmosdb" "${ENGINE_ROOT}"
