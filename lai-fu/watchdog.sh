#!/bin/bash
# Lai.Fu watchdog: 探測 Wall.E 狀態，連續 3 次失敗觸發 failover
set -euo pipefail

WALLE_HOST="100.119.88.20"
WALLE_SSH_PORT="16622"
WALLE_USER="ken"
FAIL_THRESHOLD=3
COUNTER_FILE="/tmp/walle-fail-count"
SUCCESS_THRESHOLD=3
SUCCESS_COUNTER_FILE="/tmp/walle-success-count"
LOCK_FILE="/run/user/$(id -u)/laifu-active"

fail_count=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
SCRIPT_DIR="$(dirname "$(realpath "$0")")"

if ! nc -z -w5 "$WALLE_HOST" "$WALLE_SSH_PORT" 2>/dev/null; then
    fail_count=$((fail_count + 1))
    echo "$fail_count" > "$COUNTER_FILE"
    echo 0 > "$SUCCESS_COUNTER_FILE"
    logger -t hermes-watchdog "Wall.E L1 fail #${fail_count}"
    if [ "$fail_count" -ge "$FAIL_THRESHOLD" ] && [ ! -f "$LOCK_FILE" ]; then
        bash "${SCRIPT_DIR}/activate-failover.sh"
    fi
    exit 0
fi

if ! ssh -o ConnectTimeout=5 -o BatchMode=yes -p "$WALLE_SSH_PORT" \
    "${WALLE_USER}@${WALLE_HOST}" \
    'systemctl --user is-active hermes-gateway.service' >/dev/null 2>&1; then
    fail_count=$((fail_count + 1))
    echo "$fail_count" > "$COUNTER_FILE"
    echo 0 > "$SUCCESS_COUNTER_FILE"
    logger -t hermes-watchdog "Wall.E L2 fail #${fail_count}"
    if [ "$fail_count" -ge "$FAIL_THRESHOLD" ] && [ ! -f "$LOCK_FILE" ]; then
        bash "${SCRIPT_DIR}/activate-failover.sh"
    fi
    exit 0
fi

success_count=$(cat "$SUCCESS_COUNTER_FILE" 2>/dev/null || echo 0)
if [ -f "$LOCK_FILE" ]; then
    success_count=$((success_count + 1))
    echo "$success_count" > "$SUCCESS_COUNTER_FILE"
    if [ "$success_count" -ge "$SUCCESS_THRESHOLD" ]; then
        logger -t hermes-watchdog "Wall.E recovered after ${success_count} probes, initiating handback"
        bash "${SCRIPT_DIR}/handback.sh"
    else
        logger -t hermes-watchdog "Wall.E healthy probe ${success_count}/${SUCCESS_THRESHOLD}, handback pending"
    fi
else
    echo 0 > "$SUCCESS_COUNTER_FILE"
fi
echo 0 > "$COUNTER_FILE"
