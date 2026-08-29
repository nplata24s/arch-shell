#!/usr/bin/env bash
# Output JSON: cpu%, mem%, disk%, downKbs, upKbs
set -euo pipefail

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/arch-shell"
mkdir -p "$CACHE"
PREV="$CACHE/net_prev"

cpu=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {printf "%.0f", usage}')
read -r memUsed memTotal <<< "$(awk '/MemTotal/ {t=$2} /MemAvailable/ {a=$2} END {printf "%d %d", t-a, t}' /proc/meminfo)"
memPct=$(awk -v u="$memUsed" -v t="$memTotal" 'BEGIN { if (t>0) printf "%.0f", u/t*100; else print 0 }')
read -r diskPct diskUsed diskTotal <<< "$(df -B1 / | awk 'NR==2 {printf "%s %s %s", $5, $3, $2}' | tr -d '%')"

read -r rx tx <<< "$(awk '
  $1 !~ /:/ { next }
  $1 ~ /lo:/ { next }
  {
    gsub(/:/, "", $1)
    rx += $2
    tx += $10
  }
  END { printf "%d %d", rx+0, tx+0 }
' /proc/net/dev)"
now=$(date +%s)

down_kbs=0
up_kbs=0
if [[ -f "$PREV" ]]; then
  read -r prev_now prev_rx prev_tx < "$PREV" || true
  dt=$((now - ${prev_now:-0}))
  if (( dt > 0 && dt < 30 )); then
    down_kbs=$(( (rx - prev_rx) / dt / 1024 ))
    up_kbs=$(( (tx - prev_tx) / dt / 1024 ))
    (( down_kbs < 0 )) && down_kbs=0
    (( up_kbs < 0 )) && up_kbs=0
  fi
fi
echo "$now $rx $tx" > "$PREV"

printf '{"cpu":%s,"mem":%s,"disk":%s,"memUsed":%s,"memTotal":%s,"diskUsed":%s,"diskTotal":%s,"downKbs":%s,"upKbs":%s}\n' \
  "$cpu" "$memPct" "$diskPct" "$memUsed" "$memTotal" "$diskUsed" "$diskTotal" "$down_kbs" "$up_kbs"
