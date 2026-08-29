#!/usr/bin/env bash
# Pacman update count + list
set -euo pipefail
ACTION="${1:-count}"

if ! command -v checkupdates &>/dev/null; then
  echo '{"count":0,"packages":[]}'
  exit 0
fi

list=$(checkupdates 2>/dev/null || true)
count=$(printf '%s\n' "$list" | grep -c . || true)

case "$ACTION" in
  count)
    jq -n -c --argjson count "${count:-0}" '{count:$count}'
    ;;
  list)
    pkgs=$(printf '%s\n' "$list" | head -n 30 | python3 -c 'import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))')
    jq -n -c --argjson count "${count:-0}" --argjson packages "$pkgs" '{count:$count, packages:$packages}'
    ;;
  *)
    echo "Usage: $0 count|list" >&2
    exit 1
    ;;
esac
