#!/usr/bin/env bash
# Network control actions
set -euo pipefail

ACTION="${1:-}"
ARG="${2:-}"

case "$ACTION" in
  toggle-wifi)
    if [[ "$(nmcli radio wifi)" == "enabled" ]]; then
      nmcli radio wifi off
    else
      nmcli radio wifi on
    fi
    ;;
  connect)
    [[ -z "$ARG" ]] && exit 1
    nmcli dev wifi connect "$ARG"
    ;;
  disconnect)
    nmcli dev disconnect
    ;;
  toggle-bt)
    python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bluetooth.py" power toggle
    ;;
  bt-connect)
    [[ -z "$ARG" ]] && exit 1
    python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bluetooth.py" connect "$ARG"
    ;;
  bt-disconnect)
    [[ -z "$ARG" ]] && exit 1
    python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bluetooth.py" disconnect "$ARG"
    ;;
  bt-remove)
    [[ -z "$ARG" ]] && exit 1
    python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bluetooth.py" remove "$ARG"
    ;;
  *)
    echo "Usage: $0 toggle-wifi|connect SSID|disconnect|toggle-bt|bt-connect ADDR|bt-disconnect ADDR|bt-remove ADDR" >&2
    exit 1
    ;;
esac
