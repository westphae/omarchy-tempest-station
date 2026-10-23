#!/usr/bin/env python3
"""Write the Tempest personal access token to a mode-600 file.

The token arrives in TEMPEST_TOKEN, not argv, and an invalid token is
refused before any file is created.
"""

import os
import sys

TOKEN_CHARS = set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")


def sanitize_token(value):
    text = str(value or "").strip()
    if len(text) < 8 or len(text) > 128:
        return ""
    if any(ch not in TOKEN_CHARS for ch in text):
        return ""
    return text


def default_path():
    return os.path.join(os.environ.get("HOME", ""), ".config", "omarchy", "tempest-token")


def write_token(path, token):
    parent = os.path.dirname(path)
    os.makedirs(parent, exist_ok=True)
    temporary = path + ".tmp"
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        os.write(fd, (token + "\n").encode("utf-8"))
    finally:
        os.close(fd)
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)


def main(argv):
    token = sanitize_token(os.environ.get("TEMPEST_TOKEN", ""))
    if not token:
        sys.stdout.write("invalid")
        return 1
    path = argv[1] if len(argv) > 1 else default_path()
    try:
        write_token(path, token)
    except OSError:
        sys.stdout.write("failed")
        return 1
    sys.stdout.write("ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
