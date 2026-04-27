#!/usr/bin/env bash
set -euo pipefail
# One-off snapshot + HTML report
# Usage: ./run_oneoff.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${BASE_DIR}/config/default.env"
SNAPSHOT_SQL="${BASE_DIR}/snapshots/snapshot_queries.sql"
TS=$(date -u +%Y%m%dT%H%M%SZ)

mkdir -p "${BASE_DIR}/data/snapshots" "${BASE_DIR}/data/reports" "${BASE_DIR}/logs"
echo "Running one-off snapshot at ${TS}" | tee -a "${BASE_DIR}/logs/cpf.log"

if [[ ! -f "${CONFIG_FILE}" ]]; then
	echo "ERROR: Missing config file: ${CONFIG_FILE}" | tee -a "${BASE_DIR}/logs/cpf.log"
	exit 1
fi

if ! command -v mysql >/dev/null 2>&1; then
	echo "ERROR: mysql client not found in PATH." | tee -a "${BASE_DIR}/logs/cpf.log"
	exit 1
fi

load_config() {
	local line
	while IFS= read -r line || [[ -n "${line}" ]]; do
		# Remove UTF-8 BOM on first line (if present) and any CRLF carriage return.
		line="${line#$'\xEF\xBB\xBF'}"
		line="${line%$'\r'}"

		# Skip empty lines and comments.
		[[ -z "${line}" || "${line}" == \#* ]] && continue

		# Accept only KEY=VALUE lines.
		if [[ "${line}" != *=* ]]; then
			continue
		fi

		local key="${line%%=*}"
		local value="${line#*=}"

		# Trim whitespace around key/value.
		key="${key#${key%%[![:space:]]*}}"
		key="${key%${key##*[![:space:]]}}"
		value="${value#${value%%[![:space:]]*}}"
		value="${value%${value##*[![:space:]]}}"

		case "${key}" in
		SNAPSHOT_INTERVAL_MINUTES|RETENTION_DAYS|RUN_MODE|OUTPUT_ROOT|MYSQL_LOGIN_PATH|MYSQL_HOST|MYSQL_PORT|MYSQL_USER|MYSQL_DATABASE|MYSQL_PASSWORD)
			export "${key}=${value}"
			;;
		esac
	done < "${CONFIG_FILE}"
}

load_config

# Allow environment variables to override values from config/default.env.
MYSQL_LOGIN_PATH="${MYSQL_LOGIN_PATH:-}"
MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_DATABASE="${MYSQL_DATABASE:-performance_schema}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-}"

MYSQL_CMD=(mysql --connect-timeout=5)

if [[ -n "${MYSQL_LOGIN_PATH}" ]]; then
	MYSQL_CMD+=(--login-path="${MYSQL_LOGIN_PATH}")
	TARGET_DESC="login-path=${MYSQL_LOGIN_PATH}"
else
	MYSQL_CMD+=(
		--host="${MYSQL_HOST}"
		--port="${MYSQL_PORT}"
		--user="${MYSQL_USER}"
		--database="${MYSQL_DATABASE}"
	)
	TARGET_DESC="${MYSQL_USER}@${MYSQL_HOST}:${MYSQL_PORT}/${MYSQL_DATABASE}"
fi

if [[ -n "${MYSQL_PASSWORD}" ]]; then
	export MYSQL_PWD="${MYSQL_PASSWORD}"
fi

echo "Target MySQL instance: ${TARGET_DESC}" | tee -a "${BASE_DIR}/logs/cpf.log"

SNAPSHOT_OUT="${BASE_DIR}/data/snapshots/snapshot_${TS}.txt"
REPORT_OUT="${BASE_DIR}/data/reports/report_${TS}.txt"
REPORT_HTML_OUT="${BASE_DIR}/data/reports/report_${TS}.html"

mysql_exec() {
	"${MYSQL_CMD[@]}" --table -e "$1"
}

append_section() {
	local title="$1"
	local sql="$2"

	{
		echo
		echo "## ${title}"
		echo
		if mysql_exec "${sql}" 2>>"${BASE_DIR}/logs/cpf.log"; then
			echo
		else
			echo "Section unavailable on this server/version or insufficient privileges."
			echo
		fi
	} >> "${REPORT_OUT}"
}

render_html_report() {
	{
		echo "<!doctype html>"
		echo "<html lang=\"en\">"
		echo "<head>"
		echo "  <meta charset=\"utf-8\" />"
		echo "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />"
		echo "  <title>MySQL CPF Observability Report ${TS}</title>"
		echo "  <style>"
		echo "    body { font-family: Segoe UI, Arial, sans-serif; margin: 24px; color: #1f2937; background: #f7fafc; }"
		echo "    h1 { margin-bottom: 6px; }"
		echo "    .meta { color: #4b5563; margin-bottom: 16px; }"
		echo "    pre { white-space: pre-wrap; word-break: break-word; background: #ffffff; border: 1px solid #d1d5db; border-radius: 8px; padding: 14px; line-height: 1.35; }"
		echo "  </style>"
		echo "</head>"
		echo "<body>"
		echo "  <h1>MySQL CPF Observability Detailed Report</h1>"
		echo "  <div class=\"meta\">Generated at ${TS} UTC | Target: ${TARGET_DESC}</div>"
		echo "  <pre>"
		awk '{
			gsub(/&/,"\\&amp;");
			gsub(/</,"\\&lt;");
			gsub(/>/,"\\&gt;");
			print;
		}' "${REPORT_OUT}"
		echo "  </pre>"
		echo "</body>"
		echo "</html>"
	} > "${REPORT_HTML_OUT}"
}

if "${MYSQL_CMD[@]}" < "${SNAPSHOT_SQL}" > "${SNAPSHOT_OUT}" 2>>"${BASE_DIR}/logs/cpf.log"; then
	echo "Snapshot written: ${SNAPSHOT_OUT}" | tee -a "${BASE_DIR}/logs/cpf.log"
else
	echo "WARNING: Snapshot SQL failed partially; see log ${BASE_DIR}/logs/cpf.log" | tee -a "${BASE_DIR}/logs/cpf.log"
	echo "Snapshot collection encountered errors. Check logs/cpf.log for details." >> "${SNAPSHOT_OUT}"
fi

{
	echo "MySQL CPF Observability Detailed Performance Report"
	echo "Generated (UTC): ${TS}"
	echo "Target: ${TARGET_DESC}"
	echo ""
	echo "This report is AWR-style and sectioned by workload, waits, SQL, locking, memory, and replication signals."
} > "${REPORT_OUT}"

append_section "Instance Identity and Version" "SELECT NOW() AS collected_at_utc, @@hostname AS hostname, @@port AS port, @@version AS version, @@version_comment AS flavor, @@datadir AS datadir, @@read_only AS read_only;"
append_section "Uptime and Connection Pressure" "SHOW GLOBAL STATUS WHERE Variable_name IN ('Uptime','Threads_running','Threads_connected','Max_used_connections','Connections','Aborted_connects','Connection_errors_max_connections');"
append_section "Workload Volume and Throughput Counters" "SHOW GLOBAL STATUS WHERE Variable_name IN ('Queries','Questions','Com_select','Com_insert','Com_update','Com_delete','Com_commit','Com_rollback');"
append_section "Temporary Objects and Sort Pressure" "SHOW GLOBAL STATUS WHERE Variable_name IN ('Created_tmp_tables','Created_tmp_disk_tables','Created_tmp_files','Sort_rows','Sort_merge_passes','Sort_scan','Sort_range');"
append_section "InnoDB Buffer and IO Signals" "SHOW GLOBAL STATUS WHERE Variable_name IN ('Innodb_buffer_pool_read_requests','Innodb_buffer_pool_reads','Innodb_buffer_pool_pages_total','Innodb_buffer_pool_pages_free','Innodb_data_reads','Innodb_data_writes','Innodb_data_read','Innodb_data_written','Innodb_log_waits','Innodb_os_log_written');"
append_section "Lock Wait and Deadlock Counters" "SHOW GLOBAL STATUS WHERE Variable_name IN ('Innodb_row_lock_current_waits','Innodb_row_lock_waits','Innodb_row_lock_time','Innodb_deadlocks');"
append_section "Current Long-Running Sessions" "SELECT ID, USER, HOST, DB, COMMAND, TIME, STATE, LEFT(INFO, 240) AS SQL_TEXT FROM information_schema.processlist WHERE COMMAND <> 'Sleep' ORDER BY TIME DESC LIMIT 20;"
append_section "Active Lock Wait Chains" "SELECT r.trx_id AS waiting_trx_id, b.trx_id AS blocking_trx_id, TIMESTAMPDIFF(SECOND, r.trx_started, NOW()) AS waiting_seconds, LEFT(r.trx_query, 200) AS waiting_query, LEFT(b.trx_query, 200) AS blocking_query FROM information_schema.innodb_lock_waits w JOIN information_schema.innodb_trx b ON b.trx_id = w.blocking_trx_id JOIN information_schema.innodb_trx r ON r.trx_id = w.requesting_trx_id ORDER BY waiting_seconds DESC LIMIT 20;"
append_section "Top SQL by Total Time (performance_schema)" "SELECT DIGEST, LEFT(DIGEST_TEXT, 200) AS sql_text, COUNT_STAR AS exec_count, ROUND(SUM_TIMER_WAIT/1000000000000,3) AS total_s, ROUND(AVG_TIMER_WAIT/1000000000,3) AS avg_ms, SUM_ROWS_EXAMINED AS rows_examined, SUM_NO_INDEX_USED AS no_index_used FROM performance_schema.events_statements_summary_by_digest ORDER BY SUM_TIMER_WAIT DESC LIMIT 20;"
append_section "Top SQL by Errors and Rows Examined" "SELECT DIGEST, LEFT(DIGEST_TEXT, 200) AS sql_text, COUNT_STAR AS exec_count, SUM_ERRORS AS total_errors, SUM_WARNINGS AS total_warnings, SUM_ROWS_EXAMINED AS rows_examined FROM performance_schema.events_statements_summary_by_digest ORDER BY SUM_ERRORS DESC, SUM_ROWS_EXAMINED DESC LIMIT 20;"
append_section "Replication Summary (MySQL 8+)" "SHOW REPLICA STATUS;"
append_section "Replication Summary (MySQL 5.7 Legacy)" "SHOW SLAVE STATUS;"
append_section "InnoDB Engine Status (excerpt)" "SHOW ENGINE INNODB STATUS;"

render_html_report

echo "Report dataset written: ${REPORT_OUT}" | tee -a "${BASE_DIR}/logs/cpf.log"
echo "HTML report written: ${REPORT_HTML_OUT}" | tee -a "${BASE_DIR}/logs/cpf.log"

echo "Run complete. Output root: ${BASE_DIR}/data" | tee -a "${BASE_DIR}/logs/cpf.log"
