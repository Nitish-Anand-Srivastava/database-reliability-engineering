#!/usr/bin/env python3
"""
Replay worker applying MySQL CDC changes to Azure MySQL Flexible Server.
Author: Nitish Anand Srivastava
"""

import argparse
import json
import mysql.connector


def apply_event(cur, event):
    table = event['table']
    payload = event['payload']
    cols = ', '.join(payload.keys())
    vals = ', '.join(['%s'] * len(payload))
    updates = ', '.join([f"{k}=VALUES({k})" for k in payload.keys()])
    sql = f"INSERT INTO {table} ({cols}) VALUES ({vals}) ON DUPLICATE KEY UPDATE {updates}"
    cur.execute(sql, list(payload.values()))


def main():
    parser = argparse.ArgumentParser(description='Replay JSONL CDC into Azure MySQL')
    parser.add_argument('--host', required=True)
    parser.add_argument('--port', type=int, default=3306)
    parser.add_argument('--user', required=True)
    parser.add_argument('--password', required=True)
    parser.add_argument('--database', required=True)
    parser.add_argument('--in-file', required=True)
    args = parser.parse_args()

    conn = mysql.connector.connect(
        host=args.host,
        port=args.port,
        user=args.user,
        password=args.password,
        database=args.database,
    )

    with conn:
        cur = conn.cursor()
        with open(args.in_file, 'r', encoding='utf-8') as f:
            for line in f:
                if not line.strip():
                    continue
                evt = json.loads(line)
                apply_event(cur, evt)
        conn.commit()


if __name__ == '__main__':
    main()
