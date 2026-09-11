#!/usr/bin/env bash
set -uo pipefail

TARGET="telegram:8577138443"
HOST="$(hostname)"
TITLE="Hermes 自動更新失敗"
BODY="機器 ${HOST} 今天的自動更新沒成功，需要你看一下。查原因指令：journalctl --user -u hermes-autoupdate.service -n 50"
DELIVERED=0

if "${HOME}/.local/bin/hermes" send --quiet --to "${TARGET}" --subject "${TITLE}" "${BODY}"; then
    DELIVERED=1
fi

if [ "${DELIVERED}" -eq 0 ]; then
    notify-send --urgency=critical "${TITLE}" "${BODY}" 2>/dev/null && DELIVERED=1
fi

if [ "${DELIVERED}" -eq 0 ]; then
    echo "hermes-autoupdate-alert: no delivery channel succeeded" >&2
    exit 1
fi

exit 0
