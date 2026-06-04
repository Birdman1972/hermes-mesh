#!/bin/bash
# Wall.E 恢復後交還控制：drain + export failover tasks + 通知
set -euo pipefail

LOCK_FILE="$HOME/.local/share/hermes-mesh/laifu-active"
WALLE_HOST="100.119.88.20"
WALLE_SSH_PORT="16622"
WALLE_USER="ken"
YGGDRASILL_HOST="192.168.81.195"
YGGDRASILL_SSH_PORT="19522"
YGGDRASILL_USER="ken"
EXPORT_FILE="/tmp/laifu-failover-tasks-$(date +%Y%m%d-%H%M%S).sql"

logger -t hermes-watchdog "Handback: Wall.E recovered"

# 停止 Yggdrasill gateway（drain gracefully）
timeout 10 ssh -o ConnectTimeout=5 -o BatchMode=yes -p "${YGGDRASILL_SSH_PORT}" \
    "${YGGDRASILL_USER}@${YGGDRASILL_HOST}" \
    'systemctl --user stop hermes-gateway.service' 2>/dev/null || true

if timeout 10 ssh -o ConnectTimeout=5 -o BatchMode=yes -p "${YGGDRASILL_SSH_PORT}" \
    "${YGGDRASILL_USER}@${YGGDRASILL_HOST}" \
    'sqlite3 ~/.hermes/kanban/kanban.db .dump 2>/dev/null || echo ""' > "$EXPORT_FILE" 2>/dev/null; then
    scp -P "$WALLE_SSH_PORT" -o BatchMode=yes \
        "$EXPORT_FILE" "${WALLE_USER}@${WALLE_HOST}:~/failover-tasks/" 2>/dev/null || true
else
    logger -t hermes-watchdog "WARNING: sqlite3 dump from Yggdrasill failed, skipping export"
fi

rm -f "$LOCK_FILE"

PATH="/home/ken/.local/bin:$PATH" hermes send -t telegram \
    "✅ Wall.E 已恢復，Yggdrasill 備援結束。failover 期間任務已匯出供 Wall.E 合併。" 2>/dev/null || true

logger -t hermes-watchdog "Handback complete"
echo 0 > /tmp/walle-success-count
