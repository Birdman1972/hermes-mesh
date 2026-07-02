#!/bin/bash
set -euo pipefail

KANBAN_DB="${HOME}/.hermes/kanban.db"
FAILOVER_TASKS_DIR="${HOME}/failover-tasks"

ok=0
fail=0

check() {
    local label="$1"
    local result="$2"
    local status="$3"
    if [ "$status" = "ok" ]; then
        echo "  OK  | ${label}: ${result}"
        ok=$((ok + 1))
    else
        echo " FAIL | ${label}: ${result}"
        fail=$((fail + 1))
    fi
}

echo "=== Wall.E Health Check $(date '+%Y-%m-%d %H:%M:%S %Z') ==="

gw_status=$(systemctl --user is-active hermes-gateway.service 2>/dev/null || echo "unknown")
if [ "$gw_status" = "active" ]; then
    check "hermes-gateway.service" "active" ok
else
    check "hermes-gateway.service" "$gw_status" fail
fi

if [ -f "$KANBAN_DB" ]; then
    db_size=$(du -h "$KANBAN_DB" | cut -f1)
    db_age=$(find "$KANBAN_DB" -mmin -60 | wc -l | tr -d ' ')
    if [ "$db_age" -gt 0 ]; then
        check "kanban.db" "${db_size}, modified <60min" ok
    else
        db_mtime=$(date -r "$KANBAN_DB" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "unknown")
        check "kanban.db" "${db_size}, last modified ${db_mtime}" ok
    fi
else
    check "kanban.db" "NOT FOUND at ${KANBAN_DB}" fail
fi

if [ -d "$FAILOVER_TASKS_DIR" ]; then
    dump_count=$(find "${FAILOVER_TASKS_DIR}" -maxdepth 1 -name '*.sql' | wc -l | tr -d ' ')
    check "failover-tasks/" "exists (${dump_count} sql dump(s))" ok
else
    check "failover-tasks/" "NOT FOUND — run: mkdir -p ${FAILOVER_TASKS_DIR}" fail
fi

echo "=== Result: ${ok} OK, ${fail} FAIL ==="
if [ "$fail" -gt 0 ]; then
    exit 1
fi
exit 0
