#!/usr/bin/env bash
# set-threshold.sh — hermes 唯一被授權修改告警閾值的介面。零 source。
set -euo pipefail
BASE="$HOME/hermes-mesh/lai-fu"
CONF="$BASE/thresholds.conf"; LOG="$BASE/threshold-history.log"
LOCK="$BASE/.thresholds.lock"; ENV_FILE="$BASE/monitor.env"
# 安全邊界：允許的 key 與範圍（硬寫於此，外部檔無法放寬）
declare -A MIN=(  [cpu_temp_max]=40  [disk_usage_max]=50 [room_temp_max]=0  )
declare -A MAX=(  [cpu_temp_max]=90  [disk_usage_max]=95 [room_temp_max]=60 )
declare -A DESC=( [cpu_temp_max]="CPU 溫度告警上限 (°C)" [disk_usage_max]="磁碟使用率告警上限 (%)" [room_temp_max]="DHT22 室溫告警上限 (°C)" )
ORDER=(cpu_temp_max disk_usage_max room_temp_max)
die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
get_current() { grep -E "^$1=" "$CONF" 2>/dev/null | tail -n1 | cut -d= -f2- || true; }
read_env() {
  local name="$1" val
  val=$(grep -E "^${name}=" "$ENV_FILE" 2>/dev/null | tail -n1); val="${val#*=}"
  val="${val%\"}"; val="${val#\"}"; val="${val%\'}"; val="${val#\'}"; printf '%s' "$val"
}
list_thresholds() {
  printf '目前告警閾值：\n'; local k
  for k in "${ORDER[@]}"; do printf '  %-16s = %-6s  %s (允許 %s–%s)\n' "$k" "$(get_current "$k")" "${DESC[$k]}" "${MIN[$k]}" "${MAX[$k]}"; done
}
if [[ $# -eq 1 && "$1" == "--list" ]]; then list_thresholds; exit 0; fi
[[ $# -eq 2 ]] || die "用法：set-threshold.sh --list | <key> <value>。可用 key：${ORDER[*]}"
key="$1"; value="$2"
[[ -n "${MIN[$key]+x}" ]] || die "不允許的 key：'$key'。可用 key：${ORDER[*]}"
[[ "$value" =~ ^[0-9]{1,3}(\.[0-9])?$ ]] || die "value 格式不合法：'$value'（僅接受最多一位小數的非負數字）"
lo="${MIN[$key]}"; hi="${MAX[$key]}"
awk -v v="$value" -v lo="$lo" -v hi="$hi" 'BEGIN{exit !(v>=lo && v<=hi)}' || die "value $value 超出 $key 允許範圍（$lo–$hi）"
old="$(get_current "$key")"
exec 9>"$LOCK"; flock 9
tmp="$(mktemp "${CONF}.XXXXXX")"
if grep -qE "^${key}=" "$CONF" 2>/dev/null; then
  sed "s|^${key}=.*|${key}=${value}|" "$CONF" >"$tmp"
else cat "$CONF" >"$tmp" 2>/dev/null || true; printf '%s=%s\n' "$key" "$value" >>"$tmp"; fi
chmod 644 "$tmp"; mv -f "$tmp" "$CONF"
actor="${HERMES_ACTOR:-unknown}"; ts="$(date -Is)"
printf '%s | %s | %s -> %s | actor=%s | pid=%s\n' "$ts" "$key" "${old:-<unset>}" "$value" "$actor" "$$" >>"$LOG"
if [[ -r "$ENV_FILE" ]]; then
  tok="$(read_env TG_BOT_TOKEN)"; chat="$(read_env TG_CHAT_ID)"
  if [[ "$tok" =~ ^[0-9]+:[A-Za-z0-9_-]+$ && "$chat" =~ ^-?[0-9]+$ ]]; then
    curl -s --max-time 15 -d chat_id="$chat" --data-urlencode text="🔧 告警閾值變更：${key} ${old:-<unset>} → ${value}（actor=${actor}）。若非你本人操作請檢查。" "https://api.telegram.org/bot${tok}/sendMessage" >/dev/null || true
  fi
fi
printf 'OK: %s 已由 %s 改為 %s（範圍 %s–%s，已記錄稽核並通知）\n' "$key" "${old:-<unset>}" "$value" "$lo" "$hi"
