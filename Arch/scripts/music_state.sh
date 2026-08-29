#!/usr/bin/env bash
# Music player state via playerctl (fallback; UI uses Quickshell MPRIS)
set -euo pipefail

status=$(playerctl status 2>/dev/null || echo "Stopped")

if [[ "$status" != "Playing" && "$status" != "Paused" ]]; then
  jq -n -c '{title:"",artist:"",status:"Stopped",player:"",percent:0,positionStr:"00:00",lengthStr:"00:00"}'
  exit 0
fi

title=$(playerctl metadata title 2>/dev/null || true)
artist=$(playerctl metadata artist 2>/dev/null || true)
player=$(playerctl metadata --format '{{playerName}}' 2>/dev/null | head -n1 || true)
len_micro=$(playerctl metadata mpris:length 2>/dev/null || echo 0)
pos_sec=$(playerctl position 2>/dev/null || echo 0)

len_micro=${len_micro:-0}
pos_sec=${pos_sec:-0}
len_sec=$(awk -v n="$len_micro" 'BEGIN { printf "%.0f", (n+0)/1000000 }')
pos_int=$(awk -v n="$pos_sec" 'BEGIN { printf "%.0f", n+0 }')
percent=0
if [[ "$len_sec" -gt 0 ]]; then
  percent=$(awk -v p="$pos_int" -v l="$len_sec" 'BEGIN { printf "%.0f", (p*100)/l }')
fi

pos_str=$(printf "%02d:%02d" $((pos_int / 60)) $((pos_int % 60)))
len_str=$(printf "%02d:%02d" $((len_sec / 60)) $((len_sec % 60)))

jq -n -c \
  --arg title "$title" \
  --arg artist "$artist" \
  --arg status "$status" \
  --arg player "$player" \
  --argjson percent "$percent" \
  --arg pos_str "$pos_str" \
  --arg len_str "$len_str" \
  '{title:$title,artist:$artist,status:$status,player:$player,percent:$percent,positionStr:$pos_str,lengthStr:$len_str}'
