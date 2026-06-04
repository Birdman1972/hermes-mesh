#!/bin/bash
# 在 Lai.Fu 上安裝 watchdog timer
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
SYSTEMD_DIR="${HOME}/.config/systemd/user"

mkdir -p "$SYSTEMD_DIR"
mkdir -p "$HOME/.local/share/hermes-mesh"
chmod +x "${SCRIPT_DIR}/watchdog.sh" \
         "${SCRIPT_DIR}/activate-failover.sh" \
         "${SCRIPT_DIR}/handback.sh"

cp "${SCRIPT_DIR}/hermes-watchdog.service" "$SYSTEMD_DIR/"
cp "${SCRIPT_DIR}/hermes-watchdog.timer"   "$SYSTEMD_DIR/"

systemctl --user daemon-reload
systemctl --user enable --now hermes-watchdog.timer
systemctl --user status hermes-watchdog.timer
echo "[install] hermes-watchdog timer installed and active"
