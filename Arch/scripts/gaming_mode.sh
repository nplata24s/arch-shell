#!/usr/bin/env bash
# Toggle Hyprland gaming mode (fewer animations / blur)
set -euo pipefail
FLAG="${HOME}/.config/arch-shell/gaming.flag"

if [[ -f "$FLAG" ]]; then
  rm -f "$FLAG"
  hyprctl keyword animations:enabled true >/dev/null
  hyprctl keyword decoration:blur:enabled true >/dev/null
  hyprctl keyword decoration:rounding 8 >/dev/null
  echo '{"enabled":false}'
else
  mkdir -p "$(dirname "$FLAG")"
  touch "$FLAG"
  hyprctl keyword animations:enabled false >/dev/null
  hyprctl keyword decoration:blur:enabled false >/dev/null
  hyprctl keyword decoration:rounding 0 >/dev/null
  echo '{"enabled":true}'
fi
