#!/usr/bin/env bash
# Music player controls via playerctl
set -euo pipefail

ACTION="${1:-}"
ARG="${2:-}"

player=$(playerctl status -f "{{playerName}}" 2>/dev/null | head -n1)
[[ -z "$player" ]] && exit 0

case "$ACTION" in
  play-pause) playerctl -p "$player" play-pause ;;
  next) playerctl -p "$player" next ;;
  previous) playerctl -p "$player" previous ;;
  seek)
    [[ -z "$ARG" ]] && exit 0
    playerctl -p "$player" position "$ARG" ;;
  *)
    echo "Usage: $0 play-pause|next|previous|seek SECONDS" >&2
    exit 1
    ;;
esac
