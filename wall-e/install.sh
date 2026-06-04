#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FAILOVER_TASKS_DIR="${HOME}/failover-tasks"

echo "[install] Creating failover-tasks dir..."
mkdir -p "$FAILOVER_TASKS_DIR"
echo "[install] ${FAILOVER_TASKS_DIR} ready"

echo "[install] Making health-check.sh executable..."
chmod +x "${REPO_DIR}/wall-e/health-check.sh"

echo "[install] Running health check..."
bash "${REPO_DIR}/wall-e/health-check.sh"
