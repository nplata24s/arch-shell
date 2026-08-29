#!/usr/bin/env bash
# Weather via IP geolocation + Open-Meteo (no API key)
# Usage: weather_state.sh [celsius|fahrenheit]
set -euo pipefail

UNIT="${1:-celsius}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/arch-shell/weather-${UNIT}.json"
mkdir -p "$(dirname "$CACHE")"

# Use cache if fresh (< 20 min)
if [[ -f "$CACHE" ]]; then
  age=$(( $(date +%s) - $(stat -c %Y "$CACHE" 2>/dev/null || echo 0) ))
  if (( age < 1200 )); then
    cat "$CACHE"
    exit 0
  fi
fi

fail() {
  jq -n -c '{city:"Unknown",temp:null,description:"Unavailable",code:0,unit:"celsius",daily:[]}'
  exit 0
}

loc=$(curl -s --max-time 4 'http://ip-api.com/json/?fields=status,city,lat,lon' 2>/dev/null || echo '{}')
city=$(echo "$loc" | jq -r '.city // "Unknown"')
lat=$(echo "$loc" | jq -r '.lat // empty')
lon=$(echo "$loc" | jq -r '.lon // empty')

[[ -z "$lat" || -z "$lon" ]] && fail

if [[ "$UNIT" == "fahrenheit" ]]; then
  unit_param="&temperature_unit=fahrenheit&wind_speed_unit=mph"
else
  unit_param=""
fi

wx=$(curl -s --max-time 6 \
  "https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&current=temperature_2m,weather_code,relative_humidity_2m,wind_speed_10m&daily=weather_code,temperature_2m_max,temperature_2m_min&forecast_days=4&timezone=auto${unit_param}" \
  2>/dev/null || echo '{}')

temp=$(echo "$wx" | jq -r '.current.temperature_2m // empty')
code=$(echo "$wx" | jq -r '.current.weather_code // 0')
humidity=$(echo "$wx" | jq -r '.current.relative_humidity_2m // 0')
wind=$(echo "$wx" | jq -r '.current.wind_speed_10m // 0')

[[ -z "$temp" ]] && fail

describe() {
  case "$1" in
    0) echo "Clear" ;;
    1|2) echo "Partly cloudy" ;;
    3) echo "Cloudy" ;;
    45|48) echo "Fog" ;;
    51|53|55|56|57) echo "Drizzle" ;;
    61|63|65|66|67) echo "Rain" ;;
    80|81|82) echo "Showers" ;;
    71|73|75|77|85|86) echo "Snow" ;;
    95|96|99) echo "Storm" ;;
    *) echo "Clear" ;;
  esac
}

desc="$(describe "$code")"

daily=$(echo "$wx" | jq -c '
  [ range(0; (.daily.time // [] | length)) as $i
    | { date: .daily.time[$i],
        code: .daily.weather_code[$i],
        max:  .daily.temperature_2m_max[$i],
        min:  .daily.temperature_2m_min[$i] } ]' 2>/dev/null || echo '[]')

# Attach a label to each forecast day.
daily=$(python3 - "$daily" <<'PY'
import json, sys, datetime
try:
    days = json.loads(sys.argv[1]) or []
except Exception:
    days = []
labels = {
    0: "Clear", 1: "Partly cloudy", 2: "Partly cloudy", 3: "Cloudy",
    45: "Fog", 48: "Fog", 51: "Drizzle", 53: "Drizzle", 55: "Drizzle",
    56: "Drizzle", 57: "Drizzle", 61: "Rain", 63: "Rain", 65: "Rain",
    66: "Rain", 67: "Rain", 71: "Snow", 73: "Snow", 75: "Snow", 77: "Snow",
    80: "Showers", 81: "Showers", 82: "Showers", 85: "Snow", 86: "Snow",
    95: "Storm", 96: "Storm", 99: "Storm",
}
today = datetime.date.today()
for d in days:
    try:
        dt = datetime.date.fromisoformat(d.get("date", ""))
        d["day"] = "Today" if dt == today else dt.strftime("%a")
    except Exception:
        d["day"] = ""
    d["description"] = labels.get(d.get("code"), "Clear")
print(json.dumps(days, separators=(",", ":")))
PY
)

result=$(jq -n -c \
  --arg city "$city" \
  --argjson temp "${temp:-null}" \
  --arg description "$desc" \
  --argjson code "${code:-0}" \
  --arg unit "$UNIT" \
  --argjson humidity "${humidity:-0}" \
  --argjson wind "${wind:-0}" \
  --argjson daily "${daily:-[]}" \
  '{city:$city, temp:$temp, description:$description, code:$code, unit:$unit,
    humidity:$humidity, wind:$wind, daily:$daily}')

echo "$result" | tee "$CACHE"
