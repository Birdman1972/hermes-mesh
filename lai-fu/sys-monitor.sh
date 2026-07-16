#!/usr/bin/env bash
# sys-monitor.sh — 每 5 分鐘由 timer 觸發。閾值讀自 thresholds.conf（grep+數字驗證，絕不 source）。
set -uo pipefail   # 刻意不用 -e：監控腳本須容錯續跑
BASE="$HOME/hermes-mesh/lai-fu"
THRESHOLDS="$BASE/thresholds.conf"; SENSOR_READ="$BASE/sensor-read.sh"; ENV_FILE="$BASE/monitor.env"
log() { printf '%s sys-monitor: %s\n' "$(date -Is)" "$*" >&2; }
read_env() {
  local name="$1" val
  val=$(grep -E "^${name}=" "$ENV_FILE" 2>/dev/null | tail -n1); val="${val#*=}"
  val="${val%\"}"; val="${val#\"}"; val="${val%\'}"; val="${val#\'}"; printf '%s' "$val"
}
read_threshold() {
  local key="$1" default="$2" val
  val=$(grep -E "^${key}=" "$THRESHOLDS" 2>/dev/null | tail -n1 | cut -d= -f2- | tr -d '[:space:]')
  if [[ "$val" =~ ^[0-9]{1,3}(\.[0-9])?$ ]]; then printf '%s' "$val"
  else log "警告：$key 讀取失敗/非法（'$val'），改用預設 $default"; printf '%s' "$default"; fi
}
TG_BOT_TOKEN=""; TG_CHAT_ID=""
if [[ -r "$ENV_FILE" ]]; then TG_BOT_TOKEN="$(read_env TG_BOT_TOKEN)"; TG_CHAT_ID="$(read_env TG_CHAT_ID)"; fi
send_alert() {
  local msg="$1"
  [[ "$TG_BOT_TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]+$ && "$TG_CHAT_ID" =~ ^-?[0-9]+$ ]] || { log "無有效 Telegram 憑證，略過：$msg"; return 0; }
  curl -s --max-time 15 -d chat_id="$TG_CHAT_ID" --data-urlencode text="$msg" "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" >/dev/null || log "推播失敗：$msg"
}
gt() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a>b)}'; }
CPU_MAX=$(read_threshold cpu_temp_max 75); DISK_MAX=$(read_threshold disk_usage_max 85); ROOM_MAX=$(read_threshold room_temp_max 28); HERMES_MEM_MAX=$(read_threshold hermes_mem_pct_max 85)
alerts=()
if [[ -r /sys/class/thermal/thermal_zone0/temp ]]; then
  m=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
  if [[ "$m" =~ ^[0-9]+$ ]]; then cpu_c=$(awk -v m="$m" 'BEGIN{printf "%.1f", m/1000}'); gt "$cpu_c" "$CPU_MAX" && alerts+=("🌡️ CPU 溫度 ${cpu_c}°C 超過 ${CPU_MAX}°C"); fi
fi
disk_pct=$(df --output=pcent / 2>/dev/null | tail -n1 | tr -dc '0-9')
[[ "$disk_pct" =~ ^[0-9]+$ ]] && gt "$disk_pct" "$DISK_MAX" && alerts+=("💾 磁碟使用率 ${disk_pct}% 超過 ${DISK_MAX}%")
if room_line=$(timeout 10 "$SENSOR_READ" dht22 2>/dev/null); then
  room_c=$(printf '%s' "$room_line" | awk '{print $1}')
  if [[ "$room_c" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then gt "$room_c" "$ROOM_MAX" && alerts+=("🏠 室溫 ${room_c}°C 超過 ${ROOM_MAX}°C"); else log "DHT22 讀值非法：'$room_line'"; fi
else log "DHT22 讀取失敗，本輪略過室溫檢查"; fi
mem_cur=$(systemctl --user show hermes-gateway.service -p MemoryCurrent --value 2>/dev/null || true)
mem_max=$(systemctl --user show hermes-gateway.service -p MemoryMax --value 2>/dev/null || true)
if [[ "$mem_cur" =~ ^[0-9]+$ && "$mem_max" =~ ^[0-9]+$ && "$mem_max" -gt 0 ]]; then
  mem_pct=$(awk -v c="$mem_cur" -v m="$mem_max" 'BEGIN{printf "%d", (c*100)/m}')
  gt "$mem_pct" "$HERMES_MEM_MAX" && alerts+=("🧠 hermes-gateway 記憶體使用率 ${mem_pct}% 超過 ${HERMES_MEM_MAX}%")
fi
if ((${#alerts[@]})); then send_alert "⚠️ Lai.Fu 告警：$(printf '%s；' "${alerts[@]}")"; fi
mkdir -p "$HOME/.local/share/hermes-mesh"
touch "$HOME/.local/share/hermes-mesh/sys-monitor-alive"
exit 0
