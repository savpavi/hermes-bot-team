#!/bin/bash
# Example: how the team's schedules are created with the Hermes CLI.
# Pattern: a collector script under ~/.hermes/scripts/ runs first; its output is handed to the
# model only when there is something new. Scripts are not included here — they're personal.
#
# Profiles first (one per bot; each gets its own Telegram bot token in its .env):
#   for p in job news fantasy nas content freelance; do hermes profile create "$p"; done
set -euo pipefail

# Orchestrator (default profile) — weekday evening team summary
hermes cron create "30 18 * * 1-5" --name "Evening team summary" \
  --script team_wrap.py --deliver telegram

# Job Seeker
hermes -p job cron create "0 8 * * *"      --name "Morning job-mail digest"   --script job_mail_collect.py --deliver telegram
hermes -p job cron create "45 7 * * *"     --name "Career page watcher"       --script career_watch.py     --deliver telegram
hermes -p job cron create "*/30 9-23 * * *" --name "Recruiter reply watcher"  --script recruiter_watch.py  --deliver telegram
hermes -p job cron create "20 8 * * *"     --name "Mail guard (phishing score)" --script mail_guard.py     --deliver telegram
hermes -p job cron create "0 20 * * 0"     --name "Weekly application goal"   --script weekly_apply_goal.py --deliver telegram

# Morning News
hermes -p news cron create "30 8 * * *" --name "Morning news + tech" --script news_collect.sh --deliver telegram

# Fantasy
hermes -p fantasy cron create "*/30 0,8-23 * * *" --name "Injury watcher" --script fantasy_injury.sh --deliver telegram
hermes -p fantasy cron create "0 11 * * *"        --name "Daily waivers"  --script fantasy_waiver.sh --skill fantasy-basketball --deliver telegram

# NAS
hermes -p nas cron create "0 10 * * 0" --name "Weekly vault maintenance" --script vault-maintenance.sh --deliver telegram
hermes -p nas cron create "0 6 * * 1"  --name "Broken-link patrol"       --script linkpatrol.py        --deliver telegram
hermes -p nas cron create "30 10 1 * *" --name "Monthly account security" --script security_collect.sh --deliver telegram

# Content
hermes -p content cron create "0 10 * * 1"  --name "Weekly content plan"  --script content_plan.py  --deliver telegram
hermes -p content cron create "30 10 * * *" --name "Daily platform stats" --script platform_stats.py --deliver telegram

# Freelance
hermes -p freelance cron create "0 7 * * 1" --name "Weekly opportunity check" --script gig_check.py --deliver telegram

# Model for scheduled jobs: set once, globally, to a small inexpensive model
#   hermes config set cron.model <small-model>
