#!/bin/bash
source /home/ken/.hermes/.env

HOSTNAME=$(hostname)
ALERTS=""

TEMP_RAW=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0)
TEMP=$((TEMP_RAW / 1000))
[ "$TEMP" -gt 75 ] && ALERTS="${ALERTS}🌡️ 溫度過高: ${TEMP}°C\n"

DISK_USED=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
[ "$DISK_USED" -gt 85 ] && ALERTS="${ALERTS}💾 磁碟過高: ${DISK_USED}%\n"

DHT_OUT=$(/home/ken/dht22-env/bin/python3 /home/ken/.local/bin/dht_read.py)
DHT_TEMP=$(echo "$DHT_OUT" | awk '{print $1}')
DHT_HUM=$(echo "$DHT_OUT" | awk '{print $2}')
if [[ "$DHT_TEMP" =~ ^-?[0-9]+\.[0-9]+$ ]] && awk "BEGIN {exit !($DHT_TEMP > 30)}"; then
    ALERTS="${ALERTS}🌡️ 室溫過高: ${DHT_TEMP}°C (濕度 ${DHT_HUM}%)\n"
fi

SEND_MSG() {
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_ALLOWED_USERS}" \
    -d text="$1"
}

if [ -n "$ALERTS" ]; then
  SEND_MSG "$(printf '⚠️ %s 系統異常警告\n%b\n📊 狀態: CPU %s°C | 磁碟 %s%% | 室溫 %s°C 濕度 %s%%' \
    "$HOSTNAME" "$ALERTS" "$TEMP" "$DISK_USED" "${DHT_TEMP:--}" "${DHT_HUM:--}")"
fi
