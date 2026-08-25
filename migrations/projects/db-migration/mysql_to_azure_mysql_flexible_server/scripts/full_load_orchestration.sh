#!/usr/bin/env bash
# Full load seed orchestration for MySQL -> Azure MySQL Flexible Server
# Author: Nitish Anand Srivastava

set -euo pipefail

SRC_HOST="${SRC_HOST:-onprem-mysql01}"
SRC_PORT="${SRC_PORT:-3306}"
SRC_DB="${SRC_DB:-salesdb}"
OUT_DIR="${OUT_DIR:-./logs/full_load_dump}"
THREADS="${THREADS:-16}"

mkdir -p "$OUT_DIR"

echo "Starting full-load export from ${SRC_HOST}:${SRC_PORT}/${SRC_DB}"

mydumper \
  --host "$SRC_HOST" \
  --port "$SRC_PORT" \
  --database "$SRC_DB" \
  --outputdir "$OUT_DIR" \
  --threads "$THREADS" \
  --compress \
  --build-empty-files

echo "Export complete. Next step: load into Azure Flexible Server using myloader/DMS."
