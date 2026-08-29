#!/usr/bin/env bash
# Control + query the Agent Centre daemon.
#   agentd.sh status   → {"running":true,"enabled":false}
#   agentd.sh start | stop | enable | disable
#   agentd.sh get  <path>
#   agentd.sh post <path> <json>
set -uo pipefail

PORT="${ARCH_AGENTD_PORT:-8787}"
BASE="http://127.0.0.1:${PORT}"
UNIT="arch-agentd.service"

running() {
  curl -s --max-time 2 "${BASE}/health" >/dev/null 2>&1
}

case "${1:-status}" in
  status)
    if running; then run=true; else run=false; fi
    if systemctl --user is-enabled "$UNIT" >/dev/null 2>&1; then en=true; else en=false; fi
    echo "{\"running\":${run},\"enabled\":${en},\"port\":${PORT}}"
    ;;
  start)
    systemctl --user start "$UNIT" >/dev/null 2>&1 || \
      nohup python3 "${HOME}/.config/arch-shell/agent-daemon/arch_agentd.py" \
        >/dev/null 2>&1 &
    sleep 1
    if running; then echo '{"ok":true}'; else echo '{"ok":false}'; fi
    ;;
  stop)
    systemctl --user stop "$UNIT" >/dev/null 2>&1 || pkill -f arch_agentd.py || true
    echo '{"ok":true}'
    ;;
  enable)
    systemctl --user enable --now "$UNIT" >/dev/null 2>&1 && echo '{"ok":true}' || echo '{"ok":false}'
    ;;
  disable)
    systemctl --user disable --now "$UNIT" >/dev/null 2>&1 && echo '{"ok":true}' || echo '{"ok":false}'
    ;;
  get)
    tmax=15
    case "${2:-}" in
      /models*) tmax=40 ;;
    esac
    curl -s --max-time "${tmax}" "${BASE}${2:-/state}" || echo '{"ok":false}'
    ;;
  post)
    tmax=40
    case "${2:-}" in
      /chat/send) tmax=120 ;;
      /permissions/resolve) tmax=180 ;;
    esac
    if [[ "${3:-}" == "-" ]]; then
      curl -s --max-time "${tmax}" -X POST -H 'Content-Type: application/json' \
        -d @- "${BASE}${2:-/}" || echo '{"ok":false}'
    else
      curl -s --max-time "${tmax}" -X POST -H 'Content-Type: application/json' \
        -d "${3:-\{\}}" "${BASE}${2:-/}" || echo '{"ok":false}'
    fi
    ;;
  *)
    echo "Usage: $0 status|start|stop|enable|disable|get <path>|post <path> <json>" >&2
    exit 1
    ;;
esac
