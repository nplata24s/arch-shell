#!/usr/bin/env bash
# Night light via wlsunset
set -euo pipefail
ACTION="${1:-status}"

running=false
pgrep -x wlsunset >/dev/null && running=true

case "$ACTION" in
  status)
    jq -n -c --argjson running "$running" '{running:$running}'
    ;;
  toggle)
    if $running; then
      pkill wlsunset || true
      echo '{"running":false}'
    else
      wlsunset -t 4000 -T 6500 >/dev/null 2>&1 &
      echo '{"running":true}'
    fi
    ;;
  *)
    echo "Usage: $0 status|toggle" >&2
    exit 1
    ;;
esac
