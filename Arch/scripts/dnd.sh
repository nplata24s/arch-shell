#!/usr/bin/env bash
# Do Not Disturb flag. Arch Shell reads this for its own toasts;
# makoctl is still called if mako happens to be running.
set -euo pipefail
ACTION="${1:-status}"
FLAG="${HOME}/.config/arch-shell/dnd.flag"

case "$ACTION" in
  status)
    [[ -f "$FLAG" ]] && echo '{"enabled":true}' || echo '{"enabled":false}'
    ;;
  toggle)
    if [[ -f "$FLAG" ]]; then
      rm -f "$FLAG"
      makoctl resume >/dev/null 2>&1 || makoctl mode -r dnd >/dev/null 2>&1 || true
      echo '{"enabled":false}'
    else
      mkdir -p "$(dirname "$FLAG")"
      touch "$FLAG"
      makoctl set-mode dnd >/dev/null 2>&1 || makoctl mode -a dnd >/dev/null 2>&1 || makoctl pause >/dev/null 2>&1 || true
      echo '{"enabled":true}'
    fi
    ;;
  *)
    echo "Usage: $0 status|toggle" >&2
    exit 1
    ;;
esac
