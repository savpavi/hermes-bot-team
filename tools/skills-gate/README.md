# skills-gate

An approval gate for agent skills that live in a synced folder.

**Problem.** My bots' skills (reusable procedures in Markdown) live in a notes vault that syncs
from my phone and PC. If bots loaded that folder directly, any change — mine, another agent's, or
from a compromised device — would alter bot behaviour on the next run. That's prompt injection
through a side door.

**Fix.** Bots load an *approved copy*. `gate.py` runs every 15 minutes:

```
source (synced vault)  ──diff──▶  waiting for approval  ──--accept──▶  approved copy  ──▶  bots
        ▲                                                                   │
        └──────────── auto write-back when a bot improves its own skill ────┘
```

- Source changed → one notification per distinct change; bots keep the old version until `--accept`.
- A bot updated its own skill (newer file in the approved copy) → written back to the source
  automatically, with a one-line notice. Files the bot created are told apart from files deleted
  in the source by checking the source repo's git history.

```bash
SKILLS_SRC=~/vault/.claude/skills SKILLS_APPROVED=~/ops/skills-gate/approved \
NOTIFY_CMD=~/bin/notify.sh python3 gate.py      # cron: */15 * * * *
python3 gate.py --diff                          # review
python3 gate.py --accept                        # approve
ln -s ~/ops/skills-gate/approved ~/.hermes/skills/my-skills   # bots load the approved copy
```

No model calls, no dependencies beyond Python 3.9 and git.
