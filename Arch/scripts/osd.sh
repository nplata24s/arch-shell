#!/usr/bin/env bash
# Volume / brightness / caps OSD for Arch Shell (replaces swayosd).
set -euo pipefail
ARCH="${HOME}/.config/arch-shell"
ACTION="${1:-}"

notify() {
  quickshell -p "$ARCH" ipc call arch osd "$1" "$2" "$3" >/dev/null 2>&1 || true
}

vol_state() {
  local pct="0" mute="false"
  if command -v pamixer >/dev/null 2>&1; then
    pct=$(pamixer --get-volume 2>/dev/null || echo 0)
    mute=$(pamixer --get-mute 2>/dev/null || echo false)
  elif command -v wpctl >/dev/null 2>&1; then
    local raw
    raw=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || echo "Volume: 0")
    pct=$(awk '{printf "%d", ($2+0)*100}' <<<"$raw")
    mute=false
    grep -qi muted <<<"$raw" && mute=true
  fi
  echo "${pct:-0} ${mute:-false}"
}

mic_state() {
  local pct="0" mute="false"
  if command -v wpctl >/dev/null 2>&1; then
    local raw
    raw=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null || echo "Volume: 0")
    pct=$(awk '{printf "%d", ($2+0)*100}' <<<"$raw")
    mute=false
    grep -qi muted <<<"$raw" && mute=true
  fi
  echo "${pct:-0} ${mute:-false}"
}

bright_state() {
  if command -v brightnessctl >/dev/null 2>&1; then
    brightnessctl -m 2>/dev/null | awk -F, '{gsub(/%/,"",$4); print $4}' | head -n1
  else
    echo 100
  fi
}

case "$ACTION" in
  volume-up)
    wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+ 2>/dev/null \
      || pamixer -i 5 >/dev/null
    read -r pct mute < <(vol_state)
    notify volume "$pct" "$mute"
    ;;
  volume-down)
    wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- 2>/dev/null \
      || pamixer -d 5 >/dev/null
    read -r pct mute < <(vol_state)
    notify volume "$pct" "$mute"
    ;;
  volume-mute)
    wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle 2>/dev/null \
      || pamixer -t >/dev/null
    read -r pct mute < <(vol_state)
    notify volume "$pct" "$mute"
    ;;
  volume-show)
    read -r pct mute < <(vol_state)
    notify volume "$pct" "$mute"
    ;;
  mic-mute)
    wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle 2>/dev/null || true
    read -r pct mute < <(mic_state)
    notify mic "$pct" "$mute"
    ;;
  brightness-up)
    brightnessctl set 5%+ >/dev/null 2>&1 || true
    notify brightness "$(bright_state)" false
    ;;
  brightness-down)
    brightnessctl set 5%- >/dev/null 2>&1 || true
    notify brightness "$(bright_state)" false
    ;;
  caps)
    notify caps 0 false
    ;;
  *)
    echo "Usage: $0 volume-up|volume-down|volume-mute|volume-show|mic-mute|brightness-up|brightness-down|caps" >&2
    exit 1
    ;;
esac
