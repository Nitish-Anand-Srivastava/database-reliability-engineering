"""Build an AWR-style HTML report from a detailed TXT report.

Usage:
        python report_builder_stub.py --engine mysql --input report.txt --output report.html
"""
from __future__ import annotations

import argparse
import html
from datetime import datetime, timezone
from pathlib import Path


def parse_sections(report_text: str) -> list[tuple[str, str]]:
        sections: list[tuple[str, str]] = []
        current_title = "Overview"
        current_lines: list[str] = []

        for raw_line in report_text.splitlines():
                line = raw_line.rstrip("\n")
                if line.startswith("## "):
                        if current_lines:
                                sections.append((current_title, "\n".join(current_lines).strip()))
                        current_title = line[3:].strip()
                        current_lines = []
                        continue
                current_lines.append(line)

        if current_lines:
                sections.append((current_title, "\n".join(current_lines).strip()))
        return sections


def build_findings(report_text: str) -> tuple[list[str], str]:
        findings: list[str] = []
        lower = report_text.lower()

        if "section unavailable" in lower:
                findings.append("Some sections were unavailable due to privileges, feature flags, or engine/version differences.")
        if "deadlock" in lower:
                findings.append("Deadlock signals were detected; review lock chains and top contending statements.")
        if "lock wait" in lower or "row_lock" in lower:
                findings.append("Lock wait pressure detected; investigate blocking sessions and transaction scope.")
        if "log waits" in lower:
                findings.append("Redo/log write pressure may be present; validate IOPS and log file throughput.")
        if "tmp_disk" in lower or "tmp table" in lower:
                findings.append("Temporary object usage observed; inspect sort/hash memory limits and query patterns.")

        if not findings:
                findings.append("No explicit high-risk indicators were auto-detected; validate against workload SLO baselines.")

        recommendation = (
                "Prioritize sections with elevated wait/lock/error counters, compare against previous runs, "
                "and correlate with deployment and traffic changes in the report window."
        )
        return findings, recommendation


def render_html(engine: str, report_text: str, sections: list[tuple[str, str]]) -> str:
        findings, recommendation = build_findings(report_text)
        generated = datetime.now(timezone.utc).isoformat()

        toc = []
        body = []
        for idx, (title, content) in enumerate(sections, start=1):
                anchor = f"sec-{idx}"
                toc.append(f"<li><a href='#{anchor}'>{html.escape(title)}</a></li>")
                body.append(
                        "\n".join(
                                [
                                        f"<section id='{anchor}' class='card'>",
                                        f"  <h3>{html.escape(title)}</h3>",
                                        f"  <pre>{html.escape(content)}</pre>",
                                        "</section>",
                                ]
                        )
                )

        findings_html = "\n".join(f"<li>{html.escape(item)}</li>" for item in findings)

        return f"""<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>CPF AWR-Style Report - {html.escape(engine)}</title>
    <style>
        :root {{
            --bg: #f7f9fc;
            --fg: #0f172a;
            --muted: #475569;
            --card: #ffffff;
            --border: #dbe3ef;
            --accent: #0f766e;
        }}
        body {{ margin: 0; background: var(--bg); color: var(--fg); font-family: Segoe UI, Arial, sans-serif; }}
        .wrap {{ max-width: 1280px; margin: 0 auto; padding: 24px; }}
        .hero {{ background: linear-gradient(135deg, #e2f6f3, #e8efff); border: 1px solid var(--border); border-radius: 10px; padding: 18px; }}
        h1 {{ margin: 0 0 10px 0; }}
        .meta {{ color: var(--muted); font-size: 13px; }}
        .grid {{ display: grid; grid-template-columns: 300px 1fr; gap: 16px; margin-top: 16px; }}
        .card {{ background: var(--card); border: 1px solid var(--border); border-radius: 10px; padding: 14px; margin-bottom: 14px; }}
        pre {{ margin: 0; white-space: pre-wrap; word-break: break-word; font-family: Consolas, 'Courier New', monospace; font-size: 12px; line-height: 1.35; }}
        ul {{ margin-top: 8px; }}
        a {{ color: #0b4d9c; text-decoration: none; }}
        a:hover {{ text-decoration: underline; }}
        @media (max-width: 1024px) {{ .grid {{ grid-template-columns: 1fr; }} }}
    </style>
</head>
<body>
    <div class="wrap">
        <div class="hero">
            <h1>CPF Observability AWR-Style Report ({html.escape(engine)})</h1>
            <div class="meta">Generated at {html.escape(generated)} UTC</div>
            <div class="meta">Single-run deep diagnostic report (TXT + HTML)</div>
        </div>

        <div class="grid">
            <aside>
                <div class="card">
                    <h3>Auto Findings</h3>
                    <ul>
                        {findings_html}
                    </ul>
                </div>
                <div class="card">
                    <h3>Recommendations</h3>
                    <p>{html.escape(recommendation)}</p>
                </div>
                <div class="card">
                    <h3>Sections</h3>
                    <ol>
                        {''.join(toc)}
                    </ol>
                </div>
            </aside>
            <main>
                {''.join(body)}
            </main>
        </div>
    </div>
</body>
</html>
"""


def main() -> int:
        parser = argparse.ArgumentParser(description="Render CPF AWR-style HTML report from TXT input")
        parser.add_argument("--engine", required=True, help="Database engine name")
        parser.add_argument("--input", required=True, help="Input TXT report path")
        parser.add_argument("--output", required=True, help="Output HTML report path")
        args = parser.parse_args()

        src = Path(args.input)
        dst = Path(args.output)

        report_text = src.read_text(encoding="utf-8", errors="replace")
        sections = parse_sections(report_text)
        html_content = render_html(args.engine, report_text, sections)
        dst.write_text(html_content, encoding="utf-8")
        return 0


if __name__ == "__main__":
        raise SystemExit(main())

