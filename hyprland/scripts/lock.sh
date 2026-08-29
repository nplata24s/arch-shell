#!/usr/bin/env bash
if command -v hyprlock >/dev/null 2>&1; then
  exec hyprlock
fi
notify-send -u critical "Arch Shell" "hyprlock is not installed." >/dev/null 2>&1 || true
exit 1
