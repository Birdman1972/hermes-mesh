#!/bin/bash
set -euo pipefail

WALLE_HOST="100.119.88.20"
WALLE_SSH_PORT="16622"
WALLE_USER="ken"
YGGDRASILL_HOST="192.168.81.195"
YGGDRASILL_SSH_PORT="19522"
YGGDRASILL_USER="ken"
LOCK_FILE="$HOME/.local/share/hermes-mesh/laifu-active"
REPO_ROOT="$(dirname "$(dirname "$(dirname "$(realpath "$0")")")")"
LAI_FU_DIR="$REPO_ROOT/lai-fu"
LIVE=false
PASS=0
FAIL=0

[[ "${1:-}" == "--live" ]] && LIVE=true

check() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        printf "PASS  %s\n" "$desc"
        PASS=$((PASS+1))
    else
        printf "FAIL  %s\n" "$desc"
        FAIL=$((FAIL+1))
    fi
}

poll_until() {
    local desc="$1" max_sec="$2" interval="$3"; shift 3
    local elapsed=0
    while [ "$elapsed" -lt "$max_sec" ]; do
        if "$@" >/dev/null 2>&1; then
            printf "PASS  %s (%ds)\n" "$desc" "$elapsed"
            PASS=$((PASS+1))
            return 0
        fi
        sleep "$interval"
        elapsed=$((elapsed+interval))
    done
    printf "FAIL  %s (timeout %ds)\n" "$desc" "$max_sec"
    FAIL=$((FAIL+1))
}

printf "=== hermes-mesh failover drill %s ===\n" "$(date '+%Y-%m-%d %H:%M:%S')"
printf "mode: %s\n\n" "$([[ "$LIVE" == true ]] && echo live || echo dry-run)"

mkdir -p "$(dirname "$LOCK_FILE")"

check "wall-e L1 nc" nc -z -w5 "$WALLE_HOST" "$WALLE_SSH_PORT"
check "wall-e L2 ssh" timeout 10 ssh -o ConnectTimeout=5 -o BatchMode=yes \
    -p "$WALLE_SSH_PORT" "${WALLE_USER}@${WALLE_HOST}" true
check "wall-e gateway active" timeout 10 ssh -o ConnectTimeout=5 -o BatchMode=yes \
    -p "$WALLE_SSH_PORT" "${WALLE_USER}@${WALLE_HOST}" \
    'systemctl --user is-active hermes-gateway.service'
check "yggdrasill ssh" timeout 10 ssh -o ConnectTimeout=5 -o BatchMode=yes \
    -p "$YGGDRASILL_SSH_PORT" "${YGGDRASILL_USER}@${YGGDRASILL_HOST}" true
check "yggdrasill gateway standby" bash -c \
    "timeout 10 ssh -o ConnectTimeout=5 -o BatchMode=yes -p '$YGGDRASILL_SSH_PORT' '${YGGDRASILL_USER}@${YGGDRASILL_HOST}' \
    'systemctl --user is-active hermes-gateway.service' 2>/dev/null | grep -q inactive"
check "lock-file dir writable" test -w "$(dirname "$LOCK_FILE")"
check "lock-file not held" test ! -f "$LOCK_FILE"
check "activate-failover.sh present" test -f "$LAI_FU_DIR/activate-failover.sh"
check "handback.sh present" test -f "$LAI_FU_DIR/handback.sh"
check "watchdog.sh present" test -f "$LAI_FU_DIR/watchdog.sh"
check "hermes binary" bash -c 'PATH="/home/ken/.local/bin:$PATH" command -v hermes'

printf "\nDry-run: %d PASS / %d FAIL\n" "$PASS" "$FAIL"

if [[ "$LIVE" != true ]]; then
    [[ $FAIL -eq 0 ]] && echo "System ready for failover." || echo "Fix failures before live drill."
    exit $((FAIL > 0 ? 1 : 0))
fi

if [[ $FAIL -gt 0 ]]; then
    echo "Aborting live drill: $FAIL prerequisite check(s) failed."
    exit 1
fi

PASS=0; FAIL=0
printf "\n=== LIVE DRILL: stopping Wall.E gateway ===\n"

timeout 10 ssh -o ConnectTimeout=5 -o BatchMode=yes \
    -p "$WALLE_SSH_PORT" "${WALLE_USER}@${WALLE_HOST}" \
    'systemctl --user stop hermes-gateway.service' || true

poll_until "lock-file appears" 120 10 test -f "$LOCK_FILE"
poll_until "yggdrasill gateway active" 120 10 bash -c \
    "timeout 10 ssh -o ConnectTimeout=5 -o BatchMode=yes -p '$YGGDRASILL_SSH_PORT' '${YGGDRASILL_USER}@${YGGDRASILL_HOST}' \
    'systemctl --user is-active hermes-gateway.service' >/dev/null 2>&1"

printf "\n=== Restoring Wall.E gateway ===\n"
timeout 10 ssh -o ConnectTimeout=5 -o BatchMode=yes \
    -p "$WALLE_SSH_PORT" "${WALLE_USER}@${WALLE_HOST}" \
    'systemctl --user start hermes-gateway.service' || true

poll_until "handback complete (lock-file removed)" 300 15 test ! -f "$LOCK_FILE"
poll_until "yggdrasill back to standby" 300 15 bash -c \
    "timeout 10 ssh -o ConnectTimeout=5 -o BatchMode=yes -p '$YGGDRASILL_SSH_PORT' '${YGGDRASILL_USER}@${YGGDRASILL_HOST}' \
    'systemctl --user is-active hermes-gateway.service' 2>/dev/null | grep -q inactive"
check "failover-tasks on wall-e" timeout 10 ssh -o ConnectTimeout=5 -o BatchMode=yes \
    -p "$WALLE_SSH_PORT" "${WALLE_USER}@${WALLE_HOST}" \
    'ls ~/failover-tasks/*.sql >/dev/null 2>&1'

printf "\nLive drill: %d PASS / %d FAIL\n" "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]] && echo "Drill complete: all checks passed." || echo "Drill incomplete: $FAIL check(s) failed."
exit $((FAIL > 0 ? 1 : 0))
