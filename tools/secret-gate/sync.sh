#!/bin/bash
# sync.sh — export config into a git repo and push it only if every secret gate passes.
#
#   1. EXPORT_CMD  copies an allowlist of files into the repo and masks secret-looking fields
#                  (bring your own; mine is a ~250-line Python allowlist + regex masker)
#   2. leakcheck   searches the tree for your *real* secret values
#   3. gitleaks    pattern scan of the tree, then of the git history after commit
#
# Any failure: no commit / no push, NOTIFY_CMD gets a message.
#
# Env:
#   REPO        repo directory (default: this script's parent)
#   EXPORT_CMD  command that refreshes the tree (default: "$REPO/bin/export.py $REPO")
#   NOTIFY_CMD  alert command, gets the message as $1 (default: echo)
# Usage: sync.sh [--no-push]
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO:-$(cd "$HERE/.." && pwd)}"
EXPORT_CMD="${EXPORT_CMD:-python3 $REPO/bin/export.py $REPO}"
NOTIFY_CMD="${NOTIFY_CMD:-echo}"
export PATH="$HOME/.local/bin:$PATH"

fail(){ echo "ERROR: $1"; $NOTIFY_CMD "config sync stopped: $1" || true; exit 1; }
command -v gitleaks >/dev/null || fail "gitleaks not installed"

cd "$REPO" || fail "repo not found"
$EXPORT_CMD                                  || fail "export"
python3 "$HERE/leakcheck.py" "$REPO"         || fail "leakcheck found a real secret"
gitleaks dir "$REPO" --no-banner --redact --log-level warn || fail "gitleaks (tree)"

git add -A
if git diff --cached --quiet; then echo "no changes"; exit 0; fi
git commit -q -m "sync $(date '+%Y-%m-%d %H:%M')"         || fail "commit"
gitleaks git "$REPO" --no-banner --redact --log-level warn || fail "gitleaks (history)"
[ "${1:-}" = "--no-push" ] && { echo "push skipped"; exit 0; }
git push -q                                                || fail "push"
echo "pushed"
