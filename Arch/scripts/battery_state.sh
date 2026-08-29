#!/usr/bin/env bash
# Battery status JSON
set -euo pipefail

percent=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -n1 || echo "100")
status=$(cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -n1 || echo "Unknown")
present=false
[[ -f /sys/class/power_supply/BAT0/capacity || -f /sys/class/power_supply/BAT1/capacity ]] && present=true

charging=false
[[ "$status" == "Charging" || "$status" == "Full" ]] && charging=true

jq -n -c \
  --argjson present "$present" \
  --argjson percent "${percent:-100}" \
  --arg status "$status" \
  --argjson charging "$charging" \
  '{present: $present, percent: $percent, status: $status, charging: $charging}'
