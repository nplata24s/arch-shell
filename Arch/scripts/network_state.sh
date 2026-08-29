#!/usr/bin/env bash
# Network status JSON for taskbar and popup
set -euo pipefail

wifi_icon() {
  local signal="${1:-0}"
  if (( signal >= 75 )); then echo "strong"
  elif (( signal >= 50 )); then echo "good"
  elif (( signal >= 25 )); then echo "fair"
  else echo "weak"; fi
}

get_wifi_ssid() {
  LC_ALL=C nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}'
}

get_wifi_signal() {
  LC_ALL=C nmcli -t -f active,signal dev wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}'
}

wifi_present=false
if ls -1d /sys/class/net/*/wireless &>/dev/null; then
  wifi_present=true
fi

radio="disabled"
if $wifi_present; then
  radio=$(LC_ALL=C nmcli radio wifi 2>/dev/null || echo disabled)
fi

ssid=""
signal=0
connected=false
if [[ "$radio" == "enabled" ]]; then
  ssid=$(get_wifi_ssid)
  signal=$(get_wifi_signal)
  [[ -n "$ssid" ]] && connected=true
fi

eth_connected=false
eth_dev=$(LC_ALL=C nmcli -t -f DEVICE,TYPE,STATE d 2>/dev/null | awk -F: '$2=="ethernet" && $3=="connected"{print $1; exit}')
[[ -n "$eth_dev" ]] && eth_connected=true

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
bt_json='{"present":false,"powered":false,"discovering":false,"connected":false,"device":"","devices":[]}'
if [[ -x /usr/bin/python3 ]]; then
  bt_json=$(python3 "${SCRIPT_DIR}/bluetooth.py" get 2>/dev/null || echo "$bt_json")
fi
bt_power=$(printf '%s' "$bt_json" | jq -r 'if .powered then "yes" else "no" end' 2>/dev/null || echo no)

networks="[]"
if $wifi_present && [[ "$radio" == "enabled" ]]; then
  networks=$(LC_ALL=C nmcli -t -f ssid,signal,security,active dev wifi list --rescan no 2>/dev/null | awk -F: '
    $1 != "" {
      ssid=$1; signal=$2; sec=$3; active=$4;
      gsub(/"/, "\\\"", ssid);
      if (!seen[ssid]++) {
        if (out != "") out = out ","
        out = out sprintf("{\"ssid\":\"%s\",\"signal\":%s,\"security\":\"%s\",\"active\":%s}",
          ssid, (signal==""?0:signal), sec, (active=="yes"?"true":"false"))
      }
    }
    END { if (out=="") print "[]"; else print "[" out "]" }')
fi

signal="${signal:-0}"
[[ "$signal" =~ ^[0-9]+$ ]] || signal=0

jq -n -c \
  --argjson wifi_present "$wifi_present" \
  --arg radio "$radio" \
  --arg ssid "$ssid" \
  --argjson signal "$signal" \
  --argjson connected "$connected" \
  --arg wifi_strength "$(wifi_icon "$signal")" \
  --argjson eth_connected "$eth_connected" \
  --arg bt_power "${bt_power:-no}" \
  --argjson bt "$bt_json" \
  --argjson networks "$networks" \
  '{
    wifi_present: $wifi_present,
    radio: $radio,
    ssid: $ssid,
    signal: $signal,
    connected: $connected,
    wifi_strength: $wifi_strength,
    eth_connected: $eth_connected,
    bt_power: $bt_power,
    bt_present: ($bt.present // false),
    bt_connected: ($bt.connected // false),
    bt_device: ($bt.device // ""),
    bt_discovering: ($bt.discovering // false),
    bt_devices: ($bt.devices // []),
    networks: $networks
  }'
