#!/usr/bin/env bash
# Compatibility leftover from the previous shell. Arch Shell owns the desktop.
set -euo pipefail
ACTION="${1:-}"
TARGET="${2:-}"
ARCH="${HOME}/.config/arch-shell"
if [[ "$ACTION" =~ ^[0-9]+$ ]]; then
  CMD="workspace $ACTION"
  [[ "${TARGET:-}" == "move" ]] && CMD="movetoworkspace $ACTION"
  hyprctl --batch "dispatch $CMD" >/dev/null 2>&1
  exit 0
fi
if [[ "$ACTION" == "toggle" ]]; then
  case "$TARGET" in
    applauncher|guide) mod="Start" ;;
    clipboard) mod="Clipboard" ;;
    settings) mod="Settings" ;;
    music) mod="DynamicMusic" ;;
    battery) mod="BatteryNotifications" ;;
    wallpaper) mod="Wallpaper" ;;
    calendar) mod="ClockWeather" ;;
    network) mod="NetworkBluetooth" ;;
    volume) mod="Audio" ;;
    movies) mod="GamingMode" ;;
    focustime) mod="AgentCentre" ;;
    *) exit 0 ;;
  esac
  quickshell -p "$ARCH" ipc call arch toggle "$mod" >/dev/null 2>&1 || true
fi
exit 0
