#!/usr/bin/env python3
import argparse
import json
import os
import platform
import socket
import subprocess
from datetime import datetime, timezone


def run_command(command):
    result = subprocess.run(command, capture_output=True, text=True, check=True)
    return result.stdout.strip()


def parse_findmnt():
    output = run_command([
        "findmnt",
        "--json",
        "--real",
        "--output",
        "TARGET,SOURCE,FSTYPE,SIZE,USED,AVAIL,USE%,OPTIONS",
    ])
    data = json.loads(output)
    return data.get("filesystems", [])


def build_report():
    return {
        "host": socket.getfqdn(),
        "platform": platform.platform(),
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "mounts": parse_findmnt(),
    }


def main():
    parser = argparse.ArgumentParser(description="Collect mounted disk details from a Linux host.")
    parser.add_argument("--output", default="/tmp/disk_mount_report.json")
    args = parser.parse_args()

    report = build_report()

    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2)

    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()