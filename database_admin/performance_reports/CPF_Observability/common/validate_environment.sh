#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CPF_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ENGINES=(
  oracle
  postgresql
  mysql
  sqlserver
  aurora_mysql
  aurora_postgresql
  aws_rds
  azure_sql_db
  cassandra
  clickhouse
  cosmosdb
  mongodb
  redis
)

load_config() {
  local file="$1"
  [[ -f "${file}" ]] || return 0
  local line key value
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
    export "${key}=${value}"
  done < "${file}"
}

reset_config_vars() {
  unset DB_HOST DB_PORT DB_USER DB_PASSWORD DB_NAME DB_SSL_MODE
  unset MYSQL_LOGIN_PATH MYSQL_HOST MYSQL_PORT MYSQL_USER MYSQL_DATABASE MYSQL_PASSWORD
  unset PGHOST PGPORT PGUSER PGDATABASE PGPASSWORD
  unset SQLSERVER_HOST SQLSERVER_PORT SQLSERVER_USER SQLSERVER_PASSWORD SQLSERVER_DATABASE SQLSERVER_TRUST_CERT
  unset ORACLE_CONNECT_STRING ORACLE_USER ORACLE_PASSWORD ORACLE_HOST ORACLE_PORT ORACLE_SERVICE
  unset REDIS_HOST REDIS_PORT REDIS_PASSWORD
  unset MONGODB_URI
  unset CLICKHOUSE_HOST CLICKHOUSE_PORT CLICKHOUSE_USER CLICKHOUSE_PASSWORD CLICKHOUSE_DATABASE
  unset CASSANDRA_HOST CASSANDRA_PORT CASSANDRA_USER CASSANDRA_PASSWORD CASSANDRA_KEYSPACE
  unset COSMOS_SUBSCRIPTION COSMOS_RESOURCE_GROUP COSMOS_ACCOUNT
}

check_tool() {
  command -v "$1" >/dev/null 2>&1
}

check_connectivity() {
  local engine="$1"
  case "${engine}" in
    mysql|aurora_mysql|aws_rds)
      local host="${DB_HOST:-${MYSQL_HOST:-127.0.0.1}}"
      local port="${DB_PORT:-${MYSQL_PORT:-3306}}"
      local user="${DB_USER:-${MYSQL_USER:-root}}"
      local db="${DB_NAME:-${MYSQL_DATABASE:-performance_schema}}"
      local login_path="${MYSQL_LOGIN_PATH:-}"
      if [[ -n "${login_path}" ]]; then
        mysql --connect-timeout=5 --login-path="${login_path}" -e "SELECT 1" >/dev/null 2>&1
      else
        mysql --connect-timeout=5 --host="${host}" --port="${port}" --user="${user}" --database="${db}" -e "SELECT 1" >/dev/null 2>&1
      fi
      ;;
    postgresql|aurora_postgresql)
      local host="${DB_HOST:-${PGHOST:-127.0.0.1}}"
      local port="${DB_PORT:-${PGPORT:-5432}}"
      local user="${DB_USER:-${PGUSER:-postgres}}"
      local db="${DB_NAME:-${PGDATABASE:-postgres}}"
      PGPASSWORD="${DB_PASSWORD:-${PGPASSWORD:-}}" psql -X -h "${host}" -p "${port}" -U "${user}" -d "${db}" -c "SELECT 1" >/dev/null 2>&1
      ;;
    sqlserver|azure_sql_db)
      local host="${DB_HOST:-${SQLSERVER_HOST:-127.0.0.1}}"
      local port="${DB_PORT:-${SQLSERVER_PORT:-1433}}"
      local db="${DB_NAME:-${SQLSERVER_DATABASE:-master}}"
      local user="${DB_USER:-${SQLSERVER_USER:-}}"
      local pass="${DB_PASSWORD:-${SQLSERVER_PASSWORD:-}}"
      if [[ -n "${user}" && -n "${pass}" ]]; then
        sqlcmd -S "${host},${port}" -d "${db}" -U "${user}" -P "${pass}" -Q "SELECT 1" >/dev/null 2>&1
      else
        sqlcmd -S "${host},${port}" -d "${db}" -E -Q "SELECT 1" >/dev/null 2>&1
      fi
      ;;
    oracle)
      local conn="${ORACLE_CONNECT_STRING:-}"
      if [[ -z "${conn}" ]]; then
        local host="${DB_HOST:-${ORACLE_HOST:-127.0.0.1}}"
        local port="${DB_PORT:-${ORACLE_PORT:-1521}}"
        local service="${DB_NAME:-${ORACLE_SERVICE:-ORCLPDB1}}"
        local user="${DB_USER:-${ORACLE_USER:-system}}"
        local pass="${DB_PASSWORD:-${ORACLE_PASSWORD:-}}"
        conn="${user}/${pass}@//${host}:${port}/${service}"
      fi
      sqlplus -s "${conn}" <<EOF >/dev/null 2>&1
SELECT 1 FROM dual;
EXIT
EOF
      ;;
    redis)
      local host="${DB_HOST:-${REDIS_HOST:-127.0.0.1}}"
      local port="${DB_PORT:-${REDIS_PORT:-6379}}"
      local pass="${DB_PASSWORD:-${REDIS_PASSWORD:-}}"
      if [[ -n "${pass}" ]]; then
        redis-cli -h "${host}" -p "${port}" -a "${pass}" PING | grep -q PONG
      else
        redis-cli -h "${host}" -p "${port}" PING | grep -q PONG
      fi
      ;;
    mongodb)
      local uri="${MONGODB_URI:-mongodb://127.0.0.1:27017/admin}"
      mongosh "${uri}" --quiet --eval "db.runCommand({ ping: 1 }).ok" | grep -q 1
      ;;
    clickhouse)
      local host="${DB_HOST:-${CLICKHOUSE_HOST:-127.0.0.1}}"
      local port="${DB_PORT:-${CLICKHOUSE_PORT:-9000}}"
      local user="${DB_USER:-${CLICKHOUSE_USER:-default}}"
      local db="${DB_NAME:-${CLICKHOUSE_DATABASE:-default}}"
      clickhouse-client --host "${host}" --port "${port}" --user "${user}" --database "${db}" --query "SELECT 1" >/dev/null 2>&1
      ;;
    cassandra)
      local host="${DB_HOST:-${CASSANDRA_HOST:-127.0.0.1}}"
      local port="${DB_PORT:-${CASSANDRA_PORT:-9042}}"
      cqlsh "${host}" "${port}" -e "SELECT release_version FROM system.local;" >/dev/null 2>&1
      ;;
    cosmosdb)
      local sub="${COSMOS_SUBSCRIPTION:-}"
      local rg="${COSMOS_RESOURCE_GROUP:-}"
      local acct="${COSMOS_ACCOUNT:-}"
      [[ -n "${sub}" && -n "${rg}" && -n "${acct}" ]] || return 1
      az cosmosdb show --subscription "${sub}" --resource-group "${rg}" --name "${acct}" --output none >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

tools_for_engine() {
  local engine="$1"
  case "${engine}" in
    mysql|aurora_mysql|aws_rds) echo "mysql" ;;
    postgresql|aurora_postgresql) echo "psql" ;;
    sqlserver|azure_sql_db) echo "sqlcmd" ;;
    oracle) echo "sqlplus" ;;
    redis) echo "redis-cli" ;;
    mongodb) echo "mongosh" ;;
    clickhouse) echo "clickhouse-client" ;;
    cassandra) echo "cqlsh nodetool" ;;
    cosmosdb) echo "az" ;;
    *) echo "" ;;
  esac
}

printf "%-18s %-8s %-11s %-13s %-8s %s\n" "ENGINE" "TOOLS" "CONFIG" "CONNECTIVITY" "READY" "NOTES"
printf "%-18s %-8s %-11s %-13s %-8s %s\n" "------" "-----" "------" "------------" "-----" "-----"

overall_ok=true
for engine in "${ENGINES[@]}"; do
  reset_config_vars
  engine_root="${CPF_ROOT}/${engine}"
  config_file="${engine_root}/config/default.env"
  load_config "${config_file}"

  config_ok="PASS"
  if [[ ! -f "${config_file}" ]]; then
    config_ok="FAIL"
  fi

  tools_ok="PASS"
  missing=()
  for t in $(tools_for_engine "${engine}"); do
    if ! check_tool "${t}"; then
      tools_ok="FAIL"
      missing+=("${t}")
    fi
  done

  conn_ok="SKIPPED"
  if [[ "${tools_ok}" == "PASS" && "${config_ok}" == "PASS" ]]; then
    if check_connectivity "${engine}"; then
      conn_ok="PASS"
    else
      conn_ok="FAIL"
    fi
  fi

  ready="PASS"
  notes="ready"
  if [[ "${tools_ok}" != "PASS" || "${config_ok}" != "PASS" || ( "${conn_ok}" != "PASS" && "${conn_ok}" != "SKIPPED" ) ]]; then
    ready="FAIL"
    overall_ok=false
    if [[ ${#missing[@]} -gt 0 ]]; then
      notes="missing tools: ${missing[*]}"
    elif [[ "${config_ok}" != "PASS" ]]; then
      notes="missing config/default.env"
    else
      notes="connectivity check failed"
    fi
  fi

  printf "%-18s %-8s %-11s %-13s %-8s %s\n" "${engine}" "${tools_ok}" "${config_ok}" "${conn_ok}" "${ready}" "${notes}"
done

if [[ "${overall_ok}" == true ]]; then
  echo
  echo "Validation result: PASS (all engines ready)"
  exit 0
else
  echo
  echo "Validation result: FAIL (one or more engines not ready)"
  exit 2
fi
