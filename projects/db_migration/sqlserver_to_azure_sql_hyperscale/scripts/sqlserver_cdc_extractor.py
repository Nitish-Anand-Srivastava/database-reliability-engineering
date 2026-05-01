#!/usr/bin/env python3
"""
SQL Server CDC extractor for Azure SQL Hyperscale migration.
Author: Nitish Anand Srivastava
"""

import argparse
import json
import logging
from datetime import datetime
from pathlib import Path

import pyodbc

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s %(message)s'
)


def get_connection(conn_str: str):
    return pyodbc.connect(conn_str, autocommit=False)


def fetch_cdc_batch(cursor, capture_instance: str, from_lsn: bytes, to_lsn: bytes):
    sql = f"""
    SELECT *
    FROM cdc.fn_cdc_get_all_changes_{capture_instance}(?, ?, 'all')
    ORDER BY __$start_lsn, __$seqval
    """
    cursor.execute(sql, from_lsn, to_lsn)
    return cursor.fetchall(), [c[0] for c in cursor.description]


def to_json_records(rows, columns):
    payload = []
    for row in rows:
        item = {}
        for idx, col in enumerate(columns):
            val = row[idx]
            if isinstance(val, (bytes, bytearray)):
                item[col] = val.hex()
            elif isinstance(val, datetime):
                item[col] = val.isoformat()
            else:
                item[col] = val
        payload.append(item)
    return payload


def main():
    parser = argparse.ArgumentParser(description='Extract SQL Server CDC changes to JSONL')
    parser.add_argument('--source-conn', required=True, help='ODBC connection string to source SQL Server')
    parser.add_argument('--capture-instance', required=True, help='CDC capture instance name')
    parser.add_argument('--from-lsn', required=True, help='Start LSN hex string')
    parser.add_argument('--to-lsn', required=True, help='End LSN hex string')
    parser.add_argument('--out-file', required=True, help='Output JSONL file path')
    args = parser.parse_args()

    out_path = Path(args.out_file)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    from_lsn = bytes.fromhex(args.from_lsn)
    to_lsn = bytes.fromhex(args.to_lsn)

    with get_connection(args.source_conn) as conn:
        cur = conn.cursor()
        rows, cols = fetch_cdc_batch(cur, args.capture_instance, from_lsn, to_lsn)
        records = to_json_records(rows, cols)

    with out_path.open('a', encoding='utf-8') as f:
        for rec in records:
            f.write(json.dumps(rec, ensure_ascii=True) + '\n')

    logging.info('Extracted %d CDC records for capture instance %s', len(records), args.capture_instance)


if __name__ == '__main__':
    main()
