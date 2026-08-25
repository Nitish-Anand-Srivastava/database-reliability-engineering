#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
exec "${SCRIPT_DIR}/../../common/cleanup_retention_engine.sh" "mysql" "${ENGINE_ROOT}"
