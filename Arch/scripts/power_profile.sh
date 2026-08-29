#!/usr/bin/env bash
# Power profile get/set
set -euo pipefail
ACTION="${1:-get}"
VAL="${2:-}"

if ! command -v powerprofilesctl &>/dev/null; then
  echo '{"present":false,"active":"balanced","profiles":["power-saver","balanced","performance"]}'
  exit 0
fi

active=$(powerprofilesctl get 2>/dev/null || echo balanced)

case "$ACTION" in
  get)
    jq -n -c --arg active "$active" '{present:true, active:$active, profiles:["power-saver","balanced","performance"]}'
    ;;
  set)
    [[ -z "$VAL" ]] && exit 1
    powerprofilesctl set "$VAL"
    ;;
  *)
    echo "Usage: $0 get|set PROFILE" >&2
    exit 1
    ;;
esac
