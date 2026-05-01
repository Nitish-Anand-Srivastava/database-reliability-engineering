#!/usr/bin/env python3
"""
Replay worker applying PostgreSQL CDC changes to Azure PostgreSQL Flexible Server.
Author: Nitish Anand Srivastava
"""

import argparse
import json
import psycopg2


def apply_event(cur, event):
    table = event['table']
    payload = event['payload']
    cols = ', '.join(payload.keys())
    vals = ', '.join(['%s'] * len(payload))
    updates = ', '.join([f"{k}=EXCLUDED.{k}" for k in payload.keys()])
    sql = f"INSERT INTO {table} ({cols}) VALUES ({vals}) ON CONFLICT (id) DO UPDATE SET {updates}"
    cur.execute(sql, list(payload.values()))


def main():
    parser = argparse.ArgumentParser(description='Replay JSONL CDC into Azure PostgreSQL')
    parser.add_argument('--host', required=True)
    parser.add_argument('--port', type=int, default=5432)
    parser.add_argument('--user', required=True)
    parser.add_argument('--password', required=True)
    parser.add_argument('--database', required=True)
    parser.add_argument('--in-file', required=True)
    args = parser.parse_args()

    conn = psycopg2.connect(
        host=args.host,
        port=args.port,
        user=args.user,
        password=args.password,
        dbname=args.database,
    )

    with conn:
        with conn.cursor() as cur:
            with open(args.in_file, 'r', encoding='utf-8') as f:
                for line in f:
                    if not line.strip():
                        continue
                    evt = json.loads(line)
                    apply_event(cur, evt)
        conn.commit()


if __name__ == '__main__':
    main()
