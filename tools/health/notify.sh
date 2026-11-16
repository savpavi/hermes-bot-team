#!/bin/bash
# notify.sh "message" — Telegram alert; the same message is not repeated within DEDUPE_SECONDS.
# Digits are ignored when comparing, so "RAM high: 86%" and "RAM high: 91%" count as one alert.
#
# Env: TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID — read from the environment or from ENV_FILE
#      ENV_FILE        default ~/.hermes/.env (a Hermes profile's .env works as-is if it defines
#                      TELEGRAM_BOT_TOKEN; TELEGRAM_HOME_CHANNEL is accepted as the chat id)
#      DEDUPE_SECONDS  default 21600 (6 h)
#      HOST_LABEL      prefix, default $(hostname)
MSG="${1:-}"; [ -z "$MSG" ] && exit 0
ENV_FILE="${ENV_FILE:-$HOME/.hermes/.env}"
STATE="${STATE:-$HOME/ops/logs/.notify-sent}"; mkdir -p "$(dirname "$STATE")"; touch "$STATE"
DEDUPE="${DEDUPE_SECONDS:-21600}"

KEY=$(printf %s "$MSG" | sed -E 's/[0-9]+//g' | md5sum | cut -c1-12); NOW=$(date +%s)
LAST=$(grep "^$KEY " "$STATE" | tail -1 | cut -d' ' -f2)
[ -n "$LAST" ] && [ $((NOW - LAST)) -lt "$DEDUPE" ] && exit 0

if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] && [ -f "$ENV_FILE" ]; then set -a; . "$ENV_FILE"; set +a; fi
CHAT="${TELEGRAM_CHAT_ID:-${TELEGRAM_HOME_CHANNEL:-}}"
[ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "$CHAT" ] && { echo "notify: no Telegram credentials" >&2; exit 1; }

curl -s -m 15 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  --data-urlencode "chat_id=$CHAT" --data-urlencode "text=⚠️ ${HOST_LABEL:-$(hostname)}: $MSG" >/dev/null \
  && echo "$KEY $NOW" >> "$STATE"
