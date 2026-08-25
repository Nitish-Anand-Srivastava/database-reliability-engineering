#!/usr/bin/env python3
"""Aurora PostgreSQL AWR-style snapshot and HTML report runner."""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import html
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Iterable


ROOT_DIR = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG = ROOT_DIR / "config" / "awr_report.env"
DEFAULT_SQL_INSTALL = ROOT_DIR / "sql" / "00_install_awr_repository.sql"


def load_env_file(path: Path) -> dict[str, str]:
    config: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        key, _, value = line.partition("=")
        config[key.strip()] = value.strip()
    return config


def merged_env(config: dict[str, str]) -> dict[str, str]:
    env = os.environ.copy()
    for key, value in config.items():
        if value:
            env[key] = value
    return env


def psql_base_command(config: dict[str, str]) -> list[str]:
    cmd = [config.get("PSQL_BIN", "psql"), "-X", "-v", "ON_ERROR_STOP=1", "-q"]
    database_url = config.get("DATABASE_URL", "")
    if database_url:
        cmd.extend(["-d", database_url])
    return cmd


def run_psql_sql(config: dict[str, str], sql: str, tuples_only: bool = False) -> str:
    cmd = psql_base_command(config)
    if tuples_only:
        cmd.extend(["-t", "-A"])
    cmd.extend(["-c", sql])
    result = subprocess.run(
        cmd,
        env=merged_env(config),
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return result.stdout.strip()


def run_psql_file(config: dict[str, str], sql_file: Path) -> None:
    cmd = psql_base_command(config)
    cmd.extend(["-f", str(sql_file)])
    result = subprocess.run(
        cmd,
        env=merged_env(config),
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())


def query_scalar(config: dict[str, str], sql: str) -> str | None:
    output = run_psql_sql(config, sql, tuples_only=True)
    if not output:
        return None
    return output.splitlines()[-1].strip() or None


def query_csv(config: dict[str, str], sql: str) -> list[dict[str, str]]:
    cmd = psql_base_command(config)
    cmd.extend(["-c", f"COPY ({sql}) TO STDOUT WITH CSV HEADER"])
    result = subprocess.run(
        cmd,
        env=merged_env(config),
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    payload = result.stdout.strip()
    if not payload:
        return []
    return list(csv.DictReader(payload.splitlines()))


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def state_file(config: dict[str, str]) -> Path:
    return Path(config["STATE_DIR"]) / "manual_interval.json"


def slugify(text: str) -> str:
    value = re.sub(r"[^A-Za-z0-9._-]+", "-", text.strip()).strip("-")
    return value or "report"


def sql_quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def take_snapshot(config: dict[str, str], label: str | None, snapshot_type: str) -> int:
    safe_label = "NULL" if label is None else sql_quote(label)
    safe_snapshot_type = sql_quote(snapshot_type)
    sql = (
        "SELECT dbre_awr.take_snapshot("
        f"{safe_label}, "
        f"{safe_snapshot_type}, "
        f"{int(config['TOP_SQL_LIMIT'])}, "
        f"{int(config['STATEMENT_TEXT_LENGTH'])}"
        ");"
    )
    value = query_scalar(config, sql)
    if value is None:
        raise RuntimeError("snapshot did not return an id")
    return int(value)


def previous_snapshot(config: dict[str, str], snapshot_type: str, before_snapshot_id: int) -> int | None:
    safe_snapshot_type = sql_quote(snapshot_type)
    sql = (
        "SELECT snapshot_id "
        "FROM dbre_awr.snapshots "
        f"WHERE snapshot_type = {safe_snapshot_type} "
        f"AND snapshot_id < {before_snapshot_id} "
        "ORDER BY snapshot_id DESC LIMIT 1;"
    )
    value = query_scalar(config, sql)
    return int(value) if value else None


def clean_old_reports(config: dict[str, str]) -> None:
    output_dir = Path(config["OUTPUT_DIR"])
    if not output_dir.exists():
        return
    retention_days = int(config.get("RETENTION_DAYS", "14"))
    cutoff = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=retention_days)
    for path in output_dir.glob("*.html"):
        modified = dt.datetime.fromtimestamp(path.stat().st_mtime, tz=dt.timezone.utc)
        if modified < cutoff:
            path.unlink()


def html_table(title: str, rows: list[dict[str, str]]) -> str:
    if not rows:
        return f"<section><h2>{html.escape(title)}</h2><p>No rows returned.</p></section>"
    headers = list(rows[0].keys())
    thead = "".join(f"<th>{html.escape(header)}</th>" for header in headers)
    tbody_rows: list[str] = []
    for row in rows:
        cells = "".join(f"<td>{html.escape(row.get(header, ''))}</td>" for header in headers)
        tbody_rows.append(f"<tr>{cells}</tr>")
    tbody = "".join(tbody_rows)
    return (
        f"<section><h2>{html.escape(title)}</h2>"
        "<div class=\"table-wrap\">"
        f"<table><thead><tr>{thead}</tr></thead><tbody>{tbody}</tbody></table>"
        "</div></section>"
    )


def render_report(title: str, summary_rows: list[dict[str, str]], sections: Iterable[str]) -> str:
    generated_at = dt.datetime.now(dt.timezone.utc).isoformat()
    summary_html = html_table("Interval summary", summary_rows)
    body_sections = summary_html + "".join(sections)
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>{html.escape(title)}</title>
  <style>
    body {{
      font-family: Arial, Helvetica, sans-serif;
      margin: 24px;
      background: #0b1020;
      color: #e5e7eb;
    }}
    h1, h2 {{
      color: #f8fafc;
    }}
    section {{
      margin-bottom: 28px;
      padding: 16px;
      background: #111827;
      border: 1px solid #1f2937;
      border-radius: 10px;
    }}
    .meta {{
      margin-bottom: 20px;
      color: #cbd5e1;
    }}
    .table-wrap {{
      overflow-x: auto;
    }}
    table {{
      width: 100%;
      border-collapse: collapse;
      font-size: 13px;
    }}
    th, td {{
      border: 1px solid #334155;
      padding: 8px 10px;
      vertical-align: top;
      text-align: left;
    }}
    th {{
      background: #1e293b;
      position: sticky;
      top: 0;
    }}
    tr:nth-child(even) td {{
      background: #0f172a;
    }}
    code {{
      color: #93c5fd;
    }}
  </style>
</head>
<body>
  <h1>{html.escape(title)}</h1>
  <p class="meta">Generated at {html.escape(generated_at)}</p>
  {body_sections}
</body>
</html>
"""


def configuration_review_rows(config: dict[str, str], end_snapshot_id: int) -> list[dict[str, str]]:
    rows = query_csv(
        config,
        f"""
        WITH settings AS (
          SELECT setting_name, setting_value
          FROM dbre_awr.settings_snapshot
          WHERE snapshot_id = {end_snapshot_id}
        )
        SELECT * FROM (
          VALUES
            (
              'extensions',
              'shared_preload_libraries',
              coalesce((SELECT setting_value FROM settings WHERE setting_name = 'shared_preload_libraries'), ''),
              'must include pg_stat_statements',
              CASE WHEN coalesce((SELECT setting_value FROM settings WHERE setting_name = 'shared_preload_libraries'), '') LIKE '%pg_stat_statements%' THEN 'ok' ELSE 'critical' END,
              CASE WHEN coalesce((SELECT setting_value FROM settings WHERE setting_name = 'shared_preload_libraries'), '') LIKE '%pg_stat_statements%' THEN 'pg_stat_statements preload is enabled.' ELSE 'Add pg_stat_statements to shared_preload_libraries and reboot the cluster.' END
            ),
            (
              'instrumentation',
              'track_io_timing',
              coalesce((SELECT setting_value FROM settings WHERE setting_name = 'track_io_timing'), ''),
              'on',
              CASE WHEN coalesce((SELECT setting_value FROM settings WHERE setting_name = 'track_io_timing'), '') = 'on' THEN 'ok' ELSE 'critical' END,
              CASE WHEN coalesce((SELECT setting_value FROM settings WHERE setting_name = 'track_io_timing'), '') = 'on' THEN 'IO timing is enabled.' ELSE 'Turn on track_io_timing so latency attribution is available.' END
            ),
            (
              'logging',
              'log_lock_waits',
              coalesce((SELECT setting_value FROM settings WHERE setting_name = 'log_lock_waits'), ''),
              'on',
              CASE WHEN coalesce((SELECT setting_value FROM settings WHERE setting_name = 'log_lock_waits'), '') = 'on' THEN 'ok' ELSE 'warning' END,
              CASE WHEN coalesce((SELECT setting_value FROM settings WHERE setting_name = 'log_lock_waits'), '') = 'on' THEN 'Lock wait logging is enabled.' ELSE 'Enable log_lock_waits for transient blocker visibility.' END
            ),
            (
              'timeouts',
              'idle_in_transaction_session_timeout',
              coalesce((SELECT setting_value FROM settings WHERE setting_name = 'idle_in_transaction_session_timeout'), ''),
              'greater than 0',
              CASE WHEN coalesce((SELECT setting_value FROM settings WHERE setting_name = 'idle_in_transaction_session_timeout'), '0') <> '0' THEN 'ok' ELSE 'warning' END,
              CASE WHEN coalesce((SELECT setting_value FROM settings WHERE setting_name = 'idle_in_transaction_session_timeout'), '0') <> '0' THEN 'Idle-in-transaction sessions are bounded.' ELSE 'Set idle_in_transaction_session_timeout to protect vacuum and lock health.' END
            ),
            (
              'security',
              'password_encryption',
              coalesce((SELECT setting_value FROM settings WHERE setting_name = 'password_encryption'), ''),
              'scram-sha-256',
              CASE WHEN coalesce((SELECT setting_value FROM settings WHERE setting_name = 'password_encryption'), '') = 'scram-sha-256' THEN 'ok' ELSE 'warning' END,
              CASE WHEN coalesce((SELECT setting_value FROM settings WHERE setting_name = 'password_encryption'), '') = 'scram-sha-256' THEN 'SCRAM is configured.' ELSE 'Move to scram-sha-256 unless application compatibility blocks it.' END
            ),
            (
              'autovacuum',
              'autovacuum',
              coalesce((SELECT setting_value FROM settings WHERE setting_name = 'autovacuum'), ''),
              'on',
              CASE WHEN coalesce((SELECT setting_value FROM settings WHERE setting_name = 'autovacuum'), '') = 'on' THEN 'ok' ELSE 'critical' END,
              CASE WHEN coalesce((SELECT setting_value FROM settings WHERE setting_name = 'autovacuum'), '') = 'on' THEN 'Autovacuum is enabled.' ELSE 'Autovacuum must remain enabled on Aurora PostgreSQL.' END
            )
        ) AS review(section, setting_name, current_value, expected_state, severity, observation)
        ORDER BY CASE severity WHEN 'critical' THEN 1 WHEN 'warning' THEN 2 ELSE 3 END, section, setting_name
        """,
    )
    return rows


def build_report(config: dict[str, str], start_id: int, end_id: int, output_path: Path | None = None) -> Path:
    summary_rows = query_csv(
        config,
        f"""
        WITH start_snap AS (
          SELECT * FROM dbre_awr.snapshots WHERE snapshot_id = {start_id}
        ),
        end_snap AS (
          SELECT * FROM dbre_awr.snapshots WHERE snapshot_id = {end_id}
        )
        SELECT
          start_snap.snapshot_id AS start_snapshot_id,
          start_snap.captured_at AS start_time,
          end_snap.snapshot_id AS end_snapshot_id,
          end_snap.captured_at AS end_time,
          (end_snap.captured_at - start_snap.captured_at) AS interval_length,
          coalesce(start_snap.label, '') AS start_label,
          coalesce(end_snap.label, '') AS end_label,
          end_snap.database_name,
          end_snap.server_version,
          coalesce(end_snap.aurora_version, '') AS aurora_version
        FROM start_snap
        CROSS JOIN end_snap
        """,
    )

    database_deltas = query_csv(
        config,
        f"""
        WITH start_stats AS (
          SELECT * FROM dbre_awr.database_stats WHERE snapshot_id = {start_id}
        ),
        end_stats AS (
          SELECT * FROM dbre_awr.database_stats WHERE snapshot_id = {end_id}
        )
        SELECT
          end_stats.datname,
          (end_stats.xact_commit - coalesce(start_stats.xact_commit, 0)) AS xact_commit_delta,
          (end_stats.xact_rollback - coalesce(start_stats.xact_rollback, 0)) AS xact_rollback_delta,
          (end_stats.temp_bytes - coalesce(start_stats.temp_bytes, 0)) AS temp_bytes_delta,
          (end_stats.deadlocks - coalesce(start_stats.deadlocks, 0)) AS deadlocks_delta,
          round((end_stats.blk_read_time - coalesce(start_stats.blk_read_time, 0))::numeric, 2) AS blk_read_ms_delta,
          round((end_stats.blk_write_time - coalesce(start_stats.blk_write_time, 0))::numeric, 2) AS blk_write_ms_delta,
          (end_stats.sessions - coalesce(start_stats.sessions, 0)) AS sessions_delta,
          (end_stats.sessions_fatal - coalesce(start_stats.sessions_fatal, 0)) AS sessions_fatal_delta,
          end_stats.numbackends AS end_numbackends
        FROM end_stats
        LEFT JOIN start_stats USING (datid)
        ORDER BY xact_commit_delta DESC, end_stats.datname
        """,
    )

    start_waits = query_csv(
        config,
        f"SELECT state, wait_event_type, wait_event, sessions, active_sessions, longest_query_age_seconds, longest_xact_age_seconds FROM dbre_awr.activity_snapshot WHERE snapshot_id = {start_id} ORDER BY sessions DESC, active_sessions DESC"
    )
    end_waits = query_csv(
        config,
        f"SELECT state, wait_event_type, wait_event, sessions, active_sessions, longest_query_age_seconds, longest_xact_age_seconds FROM dbre_awr.activity_snapshot WHERE snapshot_id = {end_id} ORDER BY sessions DESC, active_sessions DESC"
    )

    top_sql = query_csv(
        config,
        f"""
        WITH start_sql AS (
          SELECT * FROM dbre_awr.statement_stats WHERE snapshot_id = {start_id}
        ),
        end_sql AS (
          SELECT * FROM dbre_awr.statement_stats WHERE snapshot_id = {end_id}
        ),
        delta AS (
          SELECT
            end_sql.dbid,
            end_sql.queryid,
            (end_sql.calls - coalesce(start_sql.calls, 0)) AS calls_delta,
            (end_sql.total_exec_time - coalesce(start_sql.total_exec_time, 0)) AS total_exec_ms_delta,
            (end_sql.rows - coalesce(start_sql.rows, 0)) AS rows_delta,
            (end_sql.shared_blks_hit - coalesce(start_sql.shared_blks_hit, 0)) AS shared_blks_hit_delta,
            (end_sql.shared_blks_read - coalesce(start_sql.shared_blks_read, 0)) AS shared_blks_read_delta,
            (end_sql.temp_blks_written - coalesce(start_sql.temp_blks_written, 0)) AS temp_blks_written_delta,
            (end_sql.blk_read_time - coalesce(start_sql.blk_read_time, 0)) AS blk_read_ms_delta,
            (end_sql.blk_write_time - coalesce(start_sql.blk_write_time, 0)) AS blk_write_ms_delta,
            (end_sql.wal_bytes - coalesce(start_sql.wal_bytes, 0)) AS wal_bytes_delta,
            end_sql.query_text
          FROM end_sql
          LEFT JOIN start_sql
            ON start_sql.dbid = end_sql.dbid
           AND start_sql.queryid = end_sql.queryid
        )
        SELECT
          queryid,
          calls_delta,
          round(total_exec_ms_delta::numeric / 1000, 2) AS total_exec_s_delta,
          round(total_exec_ms_delta::numeric / NULLIF(calls_delta, 0), 2) AS mean_exec_ms_delta,
          rows_delta,
          round(100.0 * shared_blks_hit_delta / NULLIF(shared_blks_hit_delta + shared_blks_read_delta, 0), 2) AS shared_hit_pct_delta,
          round(temp_blks_written_delta::numeric * current_setting('block_size')::numeric / 1048576, 2) AS temp_written_mb_delta,
          round(wal_bytes_delta::numeric / 1048576, 2) AS wal_mb_delta,
          round(blk_read_ms_delta::numeric, 2) AS blk_read_ms_delta,
          round(blk_write_ms_delta::numeric, 2) AS blk_write_ms_delta,
          query_text
        FROM delta
        WHERE total_exec_ms_delta > 0 OR calls_delta > 0 OR wal_bytes_delta > 0
        ORDER BY total_exec_ms_delta DESC, calls_delta DESC
        LIMIT {int(config['TOP_SQL_LIMIT'])}
        """,
    )

    table_deltas = query_csv(
        config,
        f"""
        WITH start_tab AS (
          SELECT * FROM dbre_awr.table_stats WHERE snapshot_id = {start_id}
        ),
        end_tab AS (
          SELECT * FROM dbre_awr.table_stats WHERE snapshot_id = {end_id}
        )
        SELECT
          end_tab.schemaname,
          end_tab.relname,
          pg_size_pretty(end_tab.table_bytes) AS end_table_size,
          (end_tab.n_tup_ins - coalesce(start_tab.n_tup_ins, 0)) AS inserts_delta,
          (end_tab.n_tup_upd - coalesce(start_tab.n_tup_upd, 0)) AS updates_delta,
          (end_tab.n_tup_del - coalesce(start_tab.n_tup_del, 0)) AS deletes_delta,
          (end_tab.n_tup_hot_upd - coalesce(start_tab.n_tup_hot_upd, 0)) AS hot_updates_delta,
          end_tab.n_dead_tup AS end_dead_tup,
          end_tab.n_live_tup AS end_live_tup,
          end_tab.n_mod_since_analyze,
          end_tab.relfrozenxid_age,
          end_tab.fillfactor
        FROM end_tab
        LEFT JOIN start_tab USING (relid)
        ORDER BY (end_tab.n_tup_ins - coalesce(start_tab.n_tup_ins, 0))
               + (end_tab.n_tup_upd - coalesce(start_tab.n_tup_upd, 0))
               + (end_tab.n_tup_del - coalesce(start_tab.n_tup_del, 0)) DESC,
                 end_tab.n_dead_tup DESC
        LIMIT 30
        """,
    )

    vacuum_risks = query_csv(
        config,
        f"""
        SELECT
          schemaname,
          relname,
          pg_size_pretty(table_bytes) AS table_size,
          relfrozenxid_age,
          round(100.0 * relfrozenxid_age / current_setting('autovacuum_freeze_max_age')::numeric, 2) AS freeze_consumed_pct,
          n_dead_tup,
          n_mod_since_analyze,
          fillfactor,
          last_autovacuum,
          last_autoanalyze
        FROM dbre_awr.table_stats
        WHERE snapshot_id = {end_id}
        ORDER BY freeze_consumed_pct DESC, n_dead_tup DESC
        LIMIT 25
        """,
    )

    index_review = query_csv(
        config,
        f"""
        WITH start_idx AS (
          SELECT * FROM dbre_awr.index_stats WHERE snapshot_id = {start_id}
        ),
        end_idx AS (
          SELECT * FROM dbre_awr.index_stats WHERE snapshot_id = {end_id}
        )
        SELECT
          end_idx.schemaname,
          end_idx.relname,
          end_idx.indexrelname,
          end_idx.is_unique,
          pg_size_pretty(end_idx.index_bytes) AS index_size,
          (end_idx.idx_scan - coalesce(start_idx.idx_scan, 0)) AS idx_scan_delta,
          end_idx.idx_blks_read,
          end_idx.idx_blks_hit,
          round(100.0 * end_idx.idx_blks_hit / NULLIF(end_idx.idx_blks_hit + end_idx.idx_blks_read, 0), 2) AS cache_hit_pct
        FROM end_idx
        LEFT JOIN start_idx USING (indexrelid)
        ORDER BY end_idx.index_bytes DESC, idx_scan_delta ASC
        LIMIT 30
        """,
    )

    io_overview = query_csv(
        config,
        f"""
        SELECT
          backend_type,
          object,
          context,
          reads,
          round(read_time::numeric, 2) AS read_ms,
          writes,
          round(write_time::numeric, 2) AS write_ms,
          writebacks,
          extends,
          hits,
          evictions,
          fsyncs
        FROM dbre_awr.io_stats
        WHERE snapshot_id = {end_id}
        ORDER BY (reads + writes + writebacks + fsyncs) DESC, backend_type
        """,
    )

    end_sessions = query_csv(
        config,
        f"""
        SELECT
          pid,
          usename,
          datname,
          application_name,
          client_addr,
          state,
          wait_event_type,
          wait_event,
          round(xact_age_seconds::numeric, 2) AS xact_age_s,
          round(query_age_seconds::numeric, 2) AS query_age_s,
          blocker_count,
          query_text
        FROM dbre_awr.session_snapshot
        WHERE snapshot_id = {end_id}
        ORDER BY xact_age_seconds DESC NULLS LAST, query_age_seconds DESC NULLS LAST
        LIMIT 25
        """,
    )

    replication = query_csv(
        config,
        f"SELECT application_name, client_addr, state, sync_state, write_lag, flush_lag, replay_lag FROM dbre_awr.replication_stats WHERE snapshot_id = {end_id} ORDER BY application_name"
    )
    slots = query_csv(
        config,
        f"SELECT slot_name, slot_type, active, wal_status, pg_size_pretty(safe_wal_size) AS safe_wal_size, inactive_since FROM dbre_awr.replication_slots WHERE snapshot_id = {end_id} ORDER BY active ASC, slot_name"
    )

    config_gaps = configuration_review_rows(config, end_id)

    sections = [
        html_table("Database delta counters", database_deltas),
        html_table("Start wait profile snapshot", start_waits),
        html_table("End wait profile snapshot", end_waits),
        html_table("Top SQL by interval execution time", top_sql),
        html_table("High-churn tables for the interval", table_deltas),
        html_table("End-of-interval vacuum and freeze risks", vacuum_risks),
        html_table("Large index and cache review", index_review),
        html_table("End-of-interval IO overview", io_overview),
        html_table("End-of-interval active sessions", end_sessions),
        html_table("Replication posture", replication),
        html_table("Replication slots", slots),
        html_table("Configuration gap review", config_gaps),
    ]

    title = f"{config['REPORT_TITLE']} ({start_id} -> {end_id})"
    document = render_report(title, summary_rows, sections)

    output_dir = Path(config["OUTPUT_DIR"])
    ensure_dir(output_dir)
    if output_path is None:
        suffix = slugify(summary_rows[0].get("end_label", "") or f"{start_id}-{end_id}")
        output_path = output_dir / f"awr_{start_id}_{end_id}_{suffix}.html"
    output_path.write_text(document, encoding="utf-8")
    return output_path


def manual_start(config: dict[str, str], label: str | None) -> int:
    ensure_dir(Path(config["STATE_DIR"]))
    state_path = state_file(config)
    if state_path.exists():
        raise RuntimeError(f"manual interval state already exists at {state_path}")
    snapshot_id = take_snapshot(config, label, "manual_start")
    state_path.write_text(
        json.dumps({"start_snapshot_id": snapshot_id, "label": label or ""}, indent=2),
        encoding="utf-8",
    )
    return snapshot_id


def manual_end(config: dict[str, str], label: str | None) -> tuple[int, int, Path]:
    state_path = state_file(config)
    if not state_path.exists():
        raise RuntimeError("no manual interval state file found")
    payload = json.loads(state_path.read_text(encoding="utf-8"))
    start_snapshot_id = int(payload["start_snapshot_id"])
    end_snapshot_id = take_snapshot(config, label or payload.get("label") or None, "manual_end")
    report_path = build_report(config, start_snapshot_id, end_snapshot_id)
    state_path.unlink()
    clean_old_reports(config)
    return start_snapshot_id, end_snapshot_id, report_path


def auto_run(config: dict[str, str], label: str | None) -> tuple[int, int | None, Path | None]:
    snapshot_id = take_snapshot(config, label, "auto")
    previous_id = previous_snapshot(config, "auto", snapshot_id)
    if previous_id is None:
        clean_old_reports(config)
        return snapshot_id, None, None
    report_path = build_report(config, previous_id, snapshot_id)
    clean_old_reports(config)
    return snapshot_id, previous_id, report_path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Aurora PostgreSQL AWR-style report runner")
    parser.add_argument("--config", default=str(DEFAULT_CONFIG), help="Path to env-style config file")
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("install-sql", help="Install snapshot schema and SQL objects")

    snapshot = subparsers.add_parser("snapshot", help="Take a raw snapshot")
    snapshot.add_argument("--label", default=None)
    snapshot.add_argument("--type", default="on_demand", choices=["auto", "on_demand", "manual_start", "manual_end"])

    manual_start_parser = subparsers.add_parser("manual-start", help="Take the start snapshot for a manual interval")
    manual_start_parser.add_argument("--label", default=None)

    manual_end_parser = subparsers.add_parser("manual-end", help="Take the end snapshot and generate the manual report")
    manual_end_parser.add_argument("--label", default=None)

    auto = subparsers.add_parser("auto-run", help="Take an auto snapshot and generate the latest interval report")
    auto.add_argument("--label", default=None)

    report = subparsers.add_parser("report", help="Generate a report for two snapshot IDs")
    report.add_argument("--start-id", type=int, required=True)
    report.add_argument("--end-id", type=int, required=True)
    report.add_argument("--output", default=None)

    return parser.parse_args()


def main() -> int:
    args = parse_args()
    config_path = Path(args.config)
    config = load_env_file(config_path)
    ensure_dir(Path(config["OUTPUT_DIR"]))
    ensure_dir(Path(config["STATE_DIR"]))

    if args.command == "install-sql":
        run_psql_file(config, DEFAULT_SQL_INSTALL)
        print("Installed dbre_awr SQL repository.")
        return 0

    if args.command == "snapshot":
        snapshot_id = take_snapshot(config, args.label, args.type)
        print(snapshot_id)
        return 0

    if args.command == "manual-start":
        snapshot_id = manual_start(config, args.label)
        print(f"Manual interval started at snapshot {snapshot_id}.")
        return 0

    if args.command == "manual-end":
        start_snapshot_id, end_snapshot_id, report_path = manual_end(config, args.label)
        print(f"Manual report generated: {report_path} ({start_snapshot_id} -> {end_snapshot_id})")
        return 0

    if args.command == "auto-run":
        end_snapshot_id, start_snapshot_id, report_path = auto_run(config, args.label)
        if start_snapshot_id is None:
            print(f"Captured initial auto snapshot {end_snapshot_id}; no previous auto snapshot available yet.")
        else:
            print(f"Auto report generated: {report_path} ({start_snapshot_id} -> {end_snapshot_id})")
        return 0

    if args.command == "report":
        output_path = Path(args.output) if args.output else None
        report_path = build_report(config, args.start_id, args.end_id, output_path=output_path)
        print(f"Report generated: {report_path}")
        return 0

    raise RuntimeError(f"Unhandled command: {args.command}")


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
