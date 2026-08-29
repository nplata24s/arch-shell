#!/usr/bin/env bash
# Audio control: set-volume, toggle-mute, set-default
set -euo pipefail

ACTION="${1:-}"
TYPE="${2:-sink}"
ID="${3:-@DEFAULT@}"
VAL="${4:-}"

case "$ACTION" in
  set-volume)
    if [[ "$ID" == "@DEFAULT@" ]]; then
      if [[ "$TYPE" == "sink" ]]; then
        wpctl set-volume @DEFAULT_AUDIO_SINK@ "${VAL}%"
      else
        wpctl set-volume @DEFAULT_AUDIO_SOURCE@ "${VAL}%"
      fi
    else
      pactl set-"${TYPE}"-volume "$ID" "${VAL}%"
    fi
    ;;
  toggle-mute)
    if [[ "$ID" == "@DEFAULT@" ]]; then
      if [[ "$TYPE" == "sink" ]]; then
        wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
      else
        wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
      fi
    else
      pactl set-"${TYPE}"-mute "$ID" toggle
    fi
    ;;
  set-default)
    pactl set-default-"${TYPE}" "$ID"
    ;;
  set-stream-volume)
    pactl set-sink-input-volume "$ID" "${VAL}%"
    ;;
  toggle-stream-mute)
    pactl set-sink-input-mute "$ID" toggle
    ;;
  *)
    echo "Usage: $0 set-volume|toggle-mute|set-default TYPE ID [VAL]" >&2
    exit 1
    ;;
esac
