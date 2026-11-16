#!/usr/bin/env python3
"""skills-gate — approval gate between a synced skills folder and the copy live bots load.

Skills (agent procedures in Markdown) are kept in a notes vault that syncs from other devices.
If bots loaded that folder directly, any edit — from a phone, another agent, or a compromised
device — would change bot behaviour immediately (prompt injection via synced text).

Instead bots load an APPROVED copy. Changes in the source wait until a human reviews the diff.

    gate.py              notify once per distinct pending change, otherwise silent (run every 15 min)
    gate.py --diff       show the pending diff (truncated unified diff)
    gate.py --accept     copy the source into the approved folder (previous copy kept as .old)
    gate.py --pull-back  write files that a bot improved in the approved copy back to the source

Bots may update their own skills (written to the approved copy). The default run detects files
that are newer in the approved copy and writes them back to the source automatically, with a
one-line notification. The other direction — source → bots — always needs --accept.

Env:
    SKILLS_SRC       source folder        (default ~/vault/.claude/skills)
    SKILLS_APPROVED  approved copy        (default ~/ops/skills-gate/approved)
    SKILLS_STATE     notification state   (default ~/ops/skills-gate/state.json)
    NOTIFY_CMD       alert command, message passed as $1 (default: print)

Point your agent's skills directory at SKILLS_APPROVED (e.g. a symlink).
"""
import difflib
import filecmp
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

E = os.environ.get
SRC = Path(os.path.expanduser(E("SKILLS_SRC", "~/vault/.claude/skills")))
DST = Path(os.path.expanduser(E("SKILLS_APPROVED", "~/ops/skills-gate/approved")))
STATE = Path(os.path.expanduser(E("SKILLS_STATE", "~/ops/skills-gate/state.json")))
NOTIFY = E("NOTIFY_CMD")
IGNORE = {".DS_Store", "__pycache__", ".stfolder"}


def notify(msg):
    if NOTIFY:
        subprocess.run([os.path.expanduser(NOTIFY), msg], capture_output=True, timeout=30)
    else:
        print(msg)


def files(root):
    out = {}
    if root.exists():
        for p in root.rglob("*"):
            if p.is_file() and not any(part in IGNORE or part.startswith(".syncthing") or part.endswith("~")
                                       for part in p.parts):
                out[str(p.relative_to(root))] = p
    return out


def changes():
    a, b = files(DST), files(SRC)
    added = sorted(set(b) - set(a))
    removed = sorted(set(a) - set(b))
    changed = sorted(k for k in set(a) & set(b) if not filecmp.cmp(a[k], b[k], shallow=False))
    return added, removed, changed, a, b


def created_by_bot(removed):
    """A file present only in the approved copy: if the source repo's git history has never seen it,
    a bot created it (write it back). If git knows it, it was deleted in the source (needs approval)."""
    repo = next((p for p in SRC.parents if (p / ".git").exists()), None)
    if repo is None:
        return []
    out = []
    for k in removed:
        rel = str((SRC / k).relative_to(repo))
        seen = subprocess.run(["git", "-C", str(repo), "log", "--all", "--format=%h", "-1", "--", rel],
                              capture_output=True, text=True, timeout=30).stdout.strip()
        if not seen:
            out.append(k)
    return out


def newer_in_approved(changed, removed, a, b):
    return [k for k in changed if a[k].stat().st_mtime > b[k].stat().st_mtime] + created_by_bot(removed)


def write_back(keys, a):
    for k in keys:
        (SRC / k).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(a[k], SRC / k)


def fingerprint(added, removed, changed, b):
    h = hashlib.sha256()
    for k in added + changed:
        h.update(k.encode())
        h.update(b[k].read_bytes())
    for k in removed:
        h.update(b"-" + k.encode())
    return h.hexdigest()[:16]


def main():
    added, removed, changed, a, b = changes()

    if "--accept" in sys.argv:
        tmp, old = DST.with_name(DST.name + ".new"), DST.with_name(DST.name + ".old")
        shutil.rmtree(tmp, ignore_errors=True)
        shutil.copytree(SRC, tmp, ignore=shutil.ignore_patterns(*IGNORE, ".syncthing*", "*~"))
        shutil.rmtree(old, ignore_errors=True)
        if DST.exists():
            DST.rename(old)
        tmp.rename(DST)
        STATE.parent.mkdir(parents=True, exist_ok=True)
        STATE.write_text(json.dumps({"notified": None}))
        print(f"Approved: +{len(added)} ~{len(changed)} -{len(removed)} files. Previous copy: {old}")
        return

    if "--pull-back" in sys.argv:
        keys = newer_in_approved(changed, removed, a, b)
        write_back(keys, a)
        print("\n".join(f"written back: {k}" for k in keys) or "Nothing newer in the approved copy.")
        return

    if "--diff" in sys.argv:
        for k in added:
            print(f"+ NEW {k}")
        for k in removed:
            print(f"- DELETED {k}")
        for k in changed:
            lines = list(difflib.unified_diff(
                a[k].read_text(errors="replace").splitlines(), b[k].read_text(errors="replace").splitlines(),
                f"approved/{k}", f"source/{k}", lineterm="", n=1))
            print("\n".join(lines[:80]) + (f"\n… (+{len(lines) - 80} lines)" if len(lines) > 80 else ""))
        if not (added or removed or changed):
            print("No differences.")
        return

    # default run: bot edits flow back automatically, source edits wait for approval
    keys = newer_in_approved(changed, removed, a, b)
    if keys:
        write_back(keys, a)
        notify("A bot updated its skill; written back to the source: " + ", ".join(keys[:6]))
        added, removed, changed, a, b = changes()
    if not (added or removed or changed):
        return

    fp = fingerprint(added, removed, changed, b)
    st = json.loads(STATE.read_text()) if STATE.exists() else {}
    if st.get("notified") == fp:
        return  # already told the human about exactly this change
    names = [f"+{k}" for k in added] + [f"~{k}" for k in changed] + [f"-{k}" for k in removed]
    notify("Skill change waiting for approval (bots still use the old version): "
           + ", ".join(names[:6]) + (f" +{len(names) - 6}" if len(names) > 6 else "")
           + ". Review: gate.py --diff, then gate.py --accept")
    st["notified"] = fp
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(st))


if __name__ == "__main__":
    main()
