#!/usr/bin/env bash
# Brightness get/set via brightnessctl
set -euo pipefail
ACTION="${1:-get}"
VAL="${2:-}"

if ! command -v brightnessctl &>/dev/null; then
  echo '{"present":false,"percent":100}'
  exit 0
fi

percent=$(brightnessctl -m 2>/dev/null | awk -F, '{gsub(/%/,"",$4); print $4}' | head -n1)
percent=${percent:-100}

case "$ACTION" in
  get)
    jq -n -c --argjson percent "${percent:-100}" '{present:true, percent:$percent}'
    ;;
  set)
    [[ -z "$VAL" ]] && exit 1
    brightnessctl set "${VAL}%" >/dev/null
    ;;
  *)
    echo "Usage: $0 get|set PERCENT" >&2
    exit 1
    ;;
esac
