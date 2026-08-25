#!/usr/bin/env bash
# Performance baseline comparison runner for MySQL migration
# Author: Nitish Anand Srivastava

set -euo pipefail

SOURCE_CONN="${SOURCE_CONN:-mysql -h onprem-mysql01 -P 3306 -u root}"
TARGET_CONN="${TARGET_CONN:-mysql -h mysql-flex-prod.mysql.database.azure.com -P 3306 -u mig_user}"
QUERY_FILE="${QUERY_FILE:-config/critical_queries.sql}"
OUT_FILE="${OUT_FILE:-logs/performance_comparison.csv}"

echo "query,source_ms,target_ms,delta_pct" > "$OUT_FILE"

i=0
while IFS= read -r q; do
  [[ -z "$q" ]] && continue
  i=$((i+1))
  s_start=$(date +%s%3N)
  echo "$q" | eval "$SOURCE_CONN" >/dev/null
  s_end=$(date +%s%3N)

  t_start=$(date +%s%3N)
  echo "$q" | eval "$TARGET_CONN" >/dev/null
  t_end=$(date +%s%3N)

  s_ms=$((s_end - s_start))
  t_ms=$((t_end - t_start))
  delta=$(awk -v s="$s_ms" -v t="$t_ms" 'BEGIN { if (s==0) print 0; else printf "%.2f", ((t-s)/s)*100 }')

  echo "q${i},${s_ms},${t_ms},${delta}" >> "$OUT_FILE"
done < "$QUERY_FILE"
