#!/usr/bin/env bash
set -euo pipefail

ENGINE="${1:-}"
ENGINE_ROOT="${2:-}"

if [[ -z "${ENGINE}" || -z "${ENGINE_ROOT}" ]]; then
  echo "Usage: cleanup_retention_engine.sh <engine> <engine_root>"
  exit 1
fi

CONFIG_FILE="${ENGINE_ROOT}/config/default.env"
RETENTION_DAYS=7

if [[ -f "${CONFIG_FILE}" ]]; then
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line#$'\xEF\xBB\xBF'}"
    line="${line%$'\r'}"
    [[ -z "${line}" || "${line}" == \#* ]] && continue
    [[ "${line}" != *=* ]] && continue
    key="${line%%=*}"
    value="${line#*=}"
    key="${key#${key%%[![:space:]]*}}"
    key="${key%${key##*[![:space:]]}}"
    value="${value#${value%%[![:space:]]*}}"
    value="${value%${value##*[![:space:]]}}"
    if [[ "${key}" == "RETENTION_DAYS" && "${value}" =~ ^[0-9]+$ ]]; then
      RETENTION_DAYS="${value}"
    fi
  done < "${CONFIG_FILE}"
fi

mkdir -p "${ENGINE_ROOT}/logs" "${ENGINE_ROOT}/data/snapshots" "${ENGINE_ROOT}/data/reports"
find "${ENGINE_ROOT}/data/snapshots" -type f -mtime +"${RETENTION_DAYS}" -delete
find "${ENGINE_ROOT}/data/reports" -type f -mtime +"${RETENTION_DAYS}" -delete
find "${ENGINE_ROOT}/logs" -type f -mtime +"${RETENTION_DAYS}" -delete

echo "Retention cleanup complete for ${ENGINE}. Kept last ${RETENTION_DAYS} days."
