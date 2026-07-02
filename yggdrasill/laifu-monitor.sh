#!/bin/bash
set -euo pipefail

LAIFU_HOST="192.168.81.167"
LAIFU_SSH_PORT="11322"
LAIFU_USER="ken"
FAIL_THRESHOLD=3
COUNTER_FILE="/tmp/laifu-fail-count"

fail_count=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)

if ! nc -z -w5 "$LAIFU_HOST" "$LAIFU_SSH_PORT" 2>/dev/null; then
    fail_count=$((fail_count + 1))
    echo "$fail_count" > "$COUNTER_FILE"
    logger -t hermes-laifu-monitor "Lai.Fu L1 fail #${fail_count}"
    if [ "$fail_count" -ge "$FAIL_THRESHOLD" ]; then
        PATH="/home/ken/.local/bin:$PATH" hermes send -t telegram \
            "WARNING: Lai.Fu unreachable from Yggdrasill (${fail_count} consecutive failures)" 2>/dev/null || true
    fi
    exit 0
fi

if ! timeout 10 ssh -o ConnectTimeout=5 -o BatchMode=yes -p "$LAIFU_SSH_PORT" \
    "${LAIFU_USER}@${LAIFU_HOST}" \
    'systemctl --user is-active hermes-watchdog.timer' >/dev/null 2>&1; then
    fail_count=$((fail_count + 1))
    echo "$fail_count" > "$COUNTER_FILE"
    logger -t hermes-laifu-monitor "Lai.Fu L2 fail #${fail_count}"
    if [ "$fail_count" -ge "$FAIL_THRESHOLD" ]; then
        PATH="/home/ken/.local/bin:$PATH" hermes send -t telegram \
            "WARNING: Lai.Fu unreachable from Yggdrasill (${fail_count} consecutive failures)" 2>/dev/null || true
    fi
    exit 0
fi

if [ "$fail_count" -gt 0 ]; then
    logger -t hermes-laifu-monitor "Lai.Fu recovered after ${fail_count} failures"
fi
echo 0 > "$COUNTER_FILE"
exit 0
