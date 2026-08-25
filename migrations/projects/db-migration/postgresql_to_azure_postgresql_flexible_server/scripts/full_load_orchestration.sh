#!/usr/bin/env bash
# Full load orchestration for PostgreSQL -> Azure PostgreSQL Flexible Server
# Author: Nitish Anand Srivastava

set -euo pipefail

SRC_HOST="${SRC_HOST:-onprem-pg01}"
SRC_PORT="${SRC_PORT:-5432}"
SRC_DB="${SRC_DB:-salesdb}"
DUMP_FILE="${DUMP_FILE:-./logs/full_seed.dump}"

echo "Starting pg_dump for ${SRC_HOST}:${SRC_PORT}/${SRC_DB}"

pg_dump \
  -h "$SRC_HOST" \
  -p "$SRC_PORT" \
  -d "$SRC_DB" \
  -Fc \
  -f "$DUMP_FILE"

echo "Dump completed: $DUMP_FILE"
echo "Next: restore into Azure PostgreSQL Flexible Server using pg_restore."
