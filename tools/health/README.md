# health

Health checks for a laptop running as a 24/7 home server. Silent when healthy.

- `health.sh` — every 10 min: CPU/disk temperature, SMART reallocated/pending sectors, RAM, disk
  usage, battery health and AC power (the battery is the UPS), internet (with retries — single
  lost pings on Wi-Fi caused false alarms), optional local-DNS self-heal, backup freshness, and an
  external heartbeat so a completely dead server is noticed too. One JSON line per run →
  `health.jsonl`, easy to chart or hand to an agent for a weekly report.
- `notify.sh` — Telegram alert with 6-hour de-duplication (numbers ignored when comparing), so a
  persistent problem pings once instead of every 10 minutes.

```bash
chmod +x health.sh notify.sh
DNS_SERVICE=AdGuardHome BACKUP_OK_FILE=~/ops/logs/backup.last_ok ./health.sh
# crontab -e
*/10 * * * * DNS_SERVICE=AdGuardHome BACKUP_OK_FILE=$HOME/ops/logs/backup.last_ok $HOME/ops/health.sh
```

SMART needs a narrow sudoers rule, e.g. `you ALL=(root) NOPASSWD: /usr/sbin/smartctl -A /dev/sda`.
