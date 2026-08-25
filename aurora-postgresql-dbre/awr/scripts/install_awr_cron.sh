#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CTL="${SCRIPT_DIR}/awrctl.sh"
LOG_DIR="/var/tmp/aurora_awr"
CRON_LINE="*/30 * * * * ${CTL} auto-run >> ${LOG_DIR}/awr_cron.log 2>&1"

if [[ "${1:-}" == "--apply" ]]; then
  mkdir -p "${LOG_DIR}"
  current_crontab="$(mktemp)"
  trap 'rm -f "${current_crontab}"' EXIT
  crontab -l > "${current_crontab}" 2>/dev/null || true
  if ! grep -Fq "${CTL} auto-run" "${current_crontab}"; then
    {
      cat "${current_crontab}"
      echo "${CRON_LINE}"
    } | crontab -
  fi
  echo "Installed cron entry:"
  echo "${CRON_LINE}"
else
  echo "Suggested cron entry:"
  echo "${CRON_LINE}"
  echo
  echo "Apply automatically with:"
  echo "  ${0} --apply"
fi
