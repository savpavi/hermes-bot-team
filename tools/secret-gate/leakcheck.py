#!/usr/bin/env python3
"""leakcheck — fail if any *known real secret value* appears in a directory tree.

Pattern scanners (gitleaks, trufflehog) catch things that *look* like secrets. This catches the
ones you actually have: it loads the real values from your secret files and searches the tree
for them. Values are never printed — only the file and the name of the secret it matched.

Usage:
    leakcheck.py <tree> [--source FILE ...]

Default sources (missing files are skipped):
    ~/.hermes/.env, ~/.hermes/profiles/*/.env, ~/.hermes/auth.json,
    ~/.hermes/mcp-tokens/*.json, ~/.hermes/profiles/*/mcp-tokens/*.json
Extra sources: --source, or LEAKCHECK_SOURCES (colon-separated globs).
Supported formats: KEY=value files (.env, rclone.conf …) and JSON (walks keys that look secret).

Exit code: 0 clean, 1 leak found.
"""
import argparse
import glob
import json
import os
import re
import sys
from pathlib import Path

MIN_LEN = 12
SECRETISH = re.compile(r"(?i)token|secret|key|password|credential|cookie|refresh|access")
NOT_SECRET = re.compile(r"(?i)endpoint|method|type|ur[il]|label|expir|scope|_env$|supported")

DEFAULT_SOURCES = [
    "~/.hermes/.env", "~/.hermes/profiles/*/.env", "~/.hermes/auth.json",
    "~/.hermes/mcp-tokens/*.json", "~/.hermes/profiles/*/mcp-tokens/*.json",
]


def looks_random(v: str) -> bool:
    """Mixed letters and digits, no spaces, not a path or URL."""
    return (len(v) >= MIN_LEN and " " not in v and not re.match(r"^(https?://|/|~|\$)", v)
            and re.search(r"[A-Za-z]", v) is not None and re.search(r"\d", v) is not None)


def collect(sources):
    secrets = {}

    def add(val, label):
        if isinstance(val, str):
            v = val.strip().strip("\"'")
            if looks_random(v):
                secrets[v] = label

    def walk(o, label):
        if isinstance(o, dict):
            for k, v in o.items():
                walk(v, f"{label}:{k}")
        elif isinstance(o, list):
            for v in o:
                walk(v, label)
        else:
            leaf = label.rsplit(":", 1)[-1]
            if SECRETISH.search(leaf) and not NOT_SECRET.search(leaf):
                add(o, label)

    for pattern in sources:
        for f in glob.glob(os.path.expanduser(pattern)):
            p = Path(f)
            if not p.is_file() or p.stat().st_size > 1_000_000:
                continue
            text = p.read_text(errors="ignore")
            label = f"{p.parent.name}/{p.name}"
            try:
                walk(json.loads(text), label)
                continue
            except ValueError:
                pass
            for line in text.splitlines():
                m = re.match(r"\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_.\-]*)\s*=\s*(.*)$", line)
                if m:
                    add(m.group(2), f"{label}:{m.group(1)}")
    return secrets


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("tree")
    ap.add_argument("--source", action="append", default=[])
    a = ap.parse_args()

    sources = DEFAULT_SOURCES + a.source
    if os.environ.get("LEAKCHECK_SOURCES"):
        sources += os.environ["LEAKCHECK_SOURCES"].split(":")
    secrets = collect(sources)

    root = Path(a.tree).resolve()
    hits = []
    for f in root.rglob("*"):
        if not f.is_file() or ".git" in f.relative_to(root).parts:
            continue
        text = f.read_text(errors="ignore")
        hits += [f"{f.relative_to(root)}  <-  {label}" for v, label in secrets.items() if v in text]

    print(f"leakcheck: {len(secrets)} known secret values checked, {len(hits)} hits")
    for h in hits:
        print("  LEAK:", h)
    sys.exit(1 if hits else 0)


if __name__ == "__main__":
    main()
