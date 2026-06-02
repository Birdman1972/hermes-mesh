#!/bin/bash
source /home/ken/.hermes/.env

HOSTNAME=$(hostname)
ALERTS=""

TEMP_RAW=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0)
TEMP=$((TEMP_RAW / 1000))
[ "$TEMP" -gt 75 ] && ALERTS="${ALERTS}🌡️ 溫度過高: ${TEMP}°C\n"

MEM_TOTAL=$(grep MemTotal /proc/meminfo | awk '{print $2}')
MEM_AVAIL=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
MEM_USED=$(( (MEM_TOTAL - MEM_AVAIL) * 100 / MEM_TOTAL ))
[ "$MEM_USED" -gt 85 ] && ALERTS="${ALERTS}🧠 記憶體過高: ${MEM_USED}%\n"

DISK_USED=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
[ "$DISK_USED" -gt 85 ] && ALERTS="${ALERTS}💾 磁碟過高: ${DISK_USED}%\n"

CPU_IDLE=$(top -bn2 -d1 | grep "Cpu(s)" | tail -1 | awk '{print $8}' | cut -d. -f1)
CPU_USED=$((100 - CPU_IDLE))
[ "$CPU_USED" -gt 90 ] && ALERTS="${ALERTS}⚡ CPU 過高: ${CPU_USED}%\n"

SEND_MSG() {
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_ALLOWED_USERS}" \
    -d text="$1"
}

if [ -n "$ALERTS" ]; then
  SEND_MSG "$(printf '⚠️ %s 系統異常警告\n%b\n📊 狀態: 溫度 %s°C | 記憶體 %s%% | 磁碟 %s%%' \
    "$HOSTNAME" "$ALERTS" "$TEMP" "$MEM_USED" "$DISK_USED")"
fi
