"""CPF_Observability HTML report builder stub.
Reads collected snapshot JSON and renders an HTML report.
"""
from datetime import datetime
from pathlib import Path


def build_report(db_type: str, out_file: str) -> None:
    template = Path(__file__).with_name("html_report_template.html").read_text()
    html = (template
        .replace("{{DB_TYPE}}", db_type)
        .replace("{{WINDOW}}", "last 30 minutes")
        .replace("{{GENERATED_AT}}", datetime.utcnow().isoformat() + "Z")
        .replace("{{SUMMARY}}", "Populate from snapshot summary metrics")
        .replace("{{FINDINGS_TABLE}}", "<div class='card'>Populate findings</div>")
        .replace("{{TOP_WORKLOAD_TABLE}}", "<div class='card'>Populate top workload</div>")
        .replace("{{LOCKING_TABLE}}", "<div class='card'>Populate lock/deadlock analysis</div>")
        .replace("{{WAITS_TABLE}}", "<div class='card'>Populate wait/resource sections</div>")
        .replace("{{RECOMMENDATIONS}}", "<div class='card'>Populate recommendations</div>"))
    Path(out_file).write_text(html)


if __name__ == "__main__":
    build_report("generic", "cpf_report_generic.html")
