#!/bin/bash
# Hermes Health Check — sends alert to Telegram & Discord if something is wrong

ISSUES=""

# Check hermes-dashboard service
if ! systemctl is-active --quiet hermes-dashboard; then
    ISSUES="$ISSUES\n❌ hermes-dashboard 服務停止"
    # Restart handled by systemd Restart=on-failure; sudo removed for NoNewPrivileges compatibility
fi

# Check hermes-gateway service
if ! systemctl --user is-active --quiet hermes-gateway 2>/dev/null; then
    ISSUES="$ISSUES\n❌ hermes-gateway 服務停止"
fi

# Check Gemini API reachability
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 https://generativelanguage.googleapis.com/v1beta/models 2>/dev/null)
if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "400" ] && [ "$HTTP_CODE" != "403" ]; then
    ISSUES="$ISSUES\n⚠️ Gemini API 無法連線 (HTTP $HTTP_CODE)"
fi

# Check SearXNG
if ! curl -s --max-time 5 http://localhost:9119 > /dev/null 2>&1; then
    ISSUES="$ISSUES\n⚠️ SearXNG 無法連線"
fi

# Check CPU temperature
CPU_TEMP=$(sensors 2>/dev/null | grep "Package id 0" | awk '{print $4}' | tr -d '+°C')
if [ -n "$CPU_TEMP" ]; then
    TEMP_INT=${CPU_TEMP%.*}
    if [ "$TEMP_INT" -ge 85 ]; then
        ISSUES="$ISSUES\n🌡️ CPU 溫度過高：${CPU_TEMP}°C（臨界 87°C）"
    elif [ "$TEMP_INT" -ge 75 ]; then
        ISSUES="$ISSUES\n⚠️ CPU 溫度偏高：${CPU_TEMP}°C"
    fi
fi

# Send alert if issues found
if [ -n "$ISSUES" ]; then
    MSG="🚨 Wall.E Hermes 健康警報\n$(date '+%Y-%m-%d %H:%M')\n$ISSUES"
    hermes send -t telegram "$MSG" 2>/dev/null
    hermes send -t discord:1507282175173722173 "$MSG" 2>/dev/null
    hermes send -t discord:1471023514503872635 "$MSG" 2>/dev/null
fi
