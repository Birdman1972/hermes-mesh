#!/bin/bash
# 啟動 failover：通知 Ken + 喚醒 Yggdrasill
set -euo pipefail

LOCK_FILE="$HOME/.local/share/hermes-mesh/laifu-active"
YGGDRASILL_HOST="192.168.81.195"
YGGDRASILL_SSH_PORT="19522"
YGGDRASILL_USER="ken"
HERMES="/home/ken/.local/bin/hermes"

mkdir -p "$HOME/.local/share/hermes-mesh"
touch "$LOCK_FILE"
logger -t hermes-watchdog "FAILOVER ACTIVATED: Wall.E unreachable"

# 通知 Ken via Lai.Fu Telegram bot
PATH="/home/ken/.local/bin:$PATH" hermes send -t telegram \
    "⚠️ Wall.E unreachable — Lai.Fu 監測觸發備援流程，正在喚醒 Yggdrasill。" 2>/dev/null || true

# 喚醒 Yggdrasill hermes gateway
timeout 10 ssh -o ConnectTimeout=5 -o BatchMode=yes -p "${YGGDRASILL_SSH_PORT}" \
    "${YGGDRASILL_USER}@${YGGDRASILL_HOST}" \
    'systemctl --user start hermes-gateway.service && logger -t hermes-mesh "Yggdrasill standby activated"' || \
    logger -t hermes-watchdog "WARNING: Failed to wake Yggdrasill"
