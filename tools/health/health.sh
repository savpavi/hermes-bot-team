#!/bin/bash
# health.sh — home-server health snapshot every 10 min; alerts only when something is wrong.
#
# Writes one JSON line per run to $LOG_DIR/health.jsonl and alerts via notify.sh.
# Built for a laptop-as-server: checks battery (it's the UPS), AC power, CPU and disk temperature,
# SMART sectors, RAM, disk usage, internet, local DNS, and the age of the last good backup.
#
# Env (all optional):
#   LOG_DIR        default ~/ops/logs
#   NOTIFY         default <script dir>/notify.sh
#   DISK_DEV       default /dev/sda      (smartctl needs a sudoers entry: NOPASSWD /usr/sbin/smartctl -A *)
#   DNS_SERVICE    systemd unit of a local DNS resolver to self-heal (e.g. AdGuardHome); empty = skip
#   BACKUP_OK_FILE file holding the timestamp of the last successful backup; empty = skip
#   HEARTBEAT_URL  external heartbeat (Better Stack, healthchecks.io …) pinged on every run
# Cron: */10 * * * * ~/ops/health.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="${LOG_DIR:-$HOME/ops/logs}"; NOTIFY="${NOTIFY:-$HERE/notify.sh}"
DISK_DEV="${DISK_DEV:-/dev/sda}"; DNS_SERVICE="${DNS_SERVICE:-}"
BACKUP_OK_FILE="${BACKUP_OK_FILE:-}"; HEARTBEAT_URL="${HEARTBEAT_URL:-}"
mkdir -p "$LOG_DIR"
ts=$(date -Is)
alert(){ echo "$ts $1" >> "$LOG_DIR/alerts.log"; "$NOTIFY" "$1"; }

cpu_t=$(( $(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -n | tail -1 || echo 0) / 1000 ))
mem=$(free | awk '/Mem/{printf "%d", ($2-$7)*100/$2}')
disk=$(df / | awk 'NR==2{gsub("%","",$5); print $5}')
load=$(cut -d' ' -f1 /proc/loadavg)

# Battery / AC (laptops only)
BAT=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)
ADP=$(ls -d /sys/class/power_supply/A[CD]* 2>/dev/null | head -1)
bat=-1; bat_h=-1; ac=1
if [ -n "$BAT" ]; then
  bat=$(cat "$BAT/capacity")
  [ -f "$BAT/energy_full" ] && bat_h=$(( $(cat "$BAT/energy_full") * 100 / $(cat "$BAT/energy_full_design") ))
fi
[ -n "$ADP" ] && ac=$(cat "$ADP/online")

# SMART
sm=$(sudo -n smartctl -A "$DISK_DEV" 2>/dev/null)
realloc=$(awk '/Reallocated_Sector/{print $10}' <<<"$sm"); realloc=${realloc:-0}
pend=$(awk '/Current_Pending/{print $10}' <<<"$sm");      pend=${pend:-0}
dtemp=$(awk '/Temperature_Celsius/{print $10}' <<<"$sm"); dtemp=${dtemp:-0}

# Internet — retry before declaring it down; a single lost ping on Wi-Fi caused false alarms
net=0; for h in 1.1.1.1 8.8.8.8 1.1.1.1; do ping -c1 -W3 "$h" >/dev/null 2>&1 && { net=1; break; }; sleep 2; done

echo "{\"ts\":\"$ts\",\"cpu_t\":$cpu_t,\"mem\":$mem,\"disk\":$disk,\"load\":$load,\"bat\":$bat,\"bat_health\":$bat_h,\"ac\":$ac,\"realloc\":$realloc,\"pending\":$pend,\"disk_t\":$dtemp,\"net\":$net}" >> "$LOG_DIR/health.jsonl"

[ "$cpu_t" -gt 85 ] && alert "CPU hot: ${cpu_t}C"
[ "$mem" -gt 85 ]   && alert "RAM high: ${mem}%"
[ "$disk" -gt 80 ]  && alert "Disk full: ${disk}%"
[ "$dtemp" -gt 50 ] && alert "HDD hot: ${dtemp}C"
{ [ "$realloc" -gt 0 ] || [ "$pend" -gt 0 ]; } && alert "HDD bad sectors! realloc=$realloc pending=$pend"
[ "$ac" -eq 0 ]     && alert "Power cut, running on battery: ${bat}%"
[ "$bat_h" -ge 0 ] && [ "$bat_h" -lt 40 ] && alert "Battery health dropped: ${bat_h}%"
[ "$net" -eq 0 ]    && alert "Internet down"

# Local DNS resolver — restart once if it stops answering
if [ -n "$DNS_SERVICE" ] && [ -z "$(dig +time=3 +tries=1 +short example.com @127.0.0.1 2>/dev/null)" ]; then
  sudo -n systemctl restart "$DNS_SERVICE"; sleep 5
  [ -z "$(dig +time=3 +tries=1 +short example.com @127.0.0.1 2>/dev/null)" ] && alert "DNS not answering (restart tried)"
fi

# Backup freshness — alert if the last good backup is older than 36 h
if [ -n "$BACKUP_OK_FILE" ]; then
  last=$(date -d "$(cat "$BACKUP_OK_FILE" 2>/dev/null || echo 1970-01-01)" +%s)
  [ $(( $(date +%s) - last )) -gt 129600 ] && alert "No successful backup for 36 h"
fi

# "I'm alive" — the external service alerts if this stops arriving (catches a dead server)
[ -n "$HEARTBEAT_URL" ] && curl -fsS -m 10 --retry 2 "$HEARTBEAT_URL" >/dev/null 2>&1
exit 0
