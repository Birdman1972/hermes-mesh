#!/usr/bin/env bash
# sensor-read.sh — 感測器讀取 dispatcher。登錄指令以 argv 陣列直接 exec，不經 shell。
set -euo pipefail
REGISTRY="$HOME/hermes-mesh/lai-fu/sensors/registry.conf"
die() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }
[[ -r "$REGISTRY" ]] || die "找不到或無法讀取 registry：$REGISTRY"
lookup() {
  local want="$1" name cmd _desc
  while IFS='|' read -r name cmd _desc; do
    name="$(trim "$name")"; [[ -z "$name" || "$name" == \#* ]] && continue
    [[ "$name" == "$want" ]] && { trim "$cmd"; return 0; }
  done <"$REGISTRY"; return 1
}
list() {
  printf '已登錄感測器：\n'; local name _cmd desc
  while IFS='|' read -r name _cmd desc; do
    name="$(trim "$name")"; [[ -z "$name" || "$name" == \#* ]] && continue
    printf '  %-12s %s\n' "$name" "$(trim "$desc")"
  done <"$REGISTRY"
}
[[ $# -ge 1 ]] || die "用法：sensor-read.sh <sensor-name> | --list"
[[ "$1" == "--list" ]] && { list; exit 0; }
sensor="$1"
[[ "$sensor" =~ ^[a-z0-9_-]+$ ]] || die "感測器名稱格式不合法：'$sensor'"
cmd="$(lookup "$sensor")" || die "未登錄的感測器：'$sensor'（用 --list 查看）"
read -ra argv <<< "$cmd"
[[ ${#argv[@]} -ge 1 ]] || die "登錄指令為空：$sensor"
[[ "${argv[0]}" = /* ]] || die "登錄指令須為絕對路徑：${argv[0]}"
exec "${argv[@]}"
