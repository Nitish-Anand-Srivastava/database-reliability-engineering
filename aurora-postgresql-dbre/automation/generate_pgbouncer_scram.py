#!/usr/bin/env python3
"""Generate a PgBouncer SCRAM userlist line for Aurora/PostgreSQL users."""

from __future__ import annotations

import argparse
import base64
import getpass
import hashlib
import hmac
import os
import sys


def scram_secret(password: str, iterations: int = 4096) -> str:
    salt = os.urandom(16)
    salted_password = hashlib.pbkdf2_hmac(
        "sha256", password.encode("utf-8"), salt, iterations
    )
    client_key = hmac.new(salted_password, b"Client Key", hashlib.sha256).digest()
    stored_key = hashlib.sha256(client_key).digest()
    server_key = hmac.new(salted_password, b"Server Key", hashlib.sha256).digest()
    salt_b64 = base64.b64encode(salt).decode("ascii")
    stored_b64 = base64.b64encode(stored_key).decode("ascii")
    server_b64 = base64.b64encode(server_key).decode("ascii")
    return f"SCRAM-SHA-256${iterations}:{salt_b64}${stored_b64}:{server_b64}"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate a PgBouncer users.txt line using SCRAM-SHA-256."
    )
    parser.add_argument("username", help="Database role name")
    args = parser.parse_args()

    password = getpass.getpass("Password: ")
    confirmation = getpass.getpass("Confirm password: ")

    if password != confirmation:
        print("Passwords do not match.", file=sys.stderr)
        return 1

    print(f"\"{args.username}\" \"{scram_secret(password)}\"")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
