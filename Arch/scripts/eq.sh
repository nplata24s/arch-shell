#!/usr/bin/env bash
# Music equaliser via EasyEffects.
#
#   eq.sh get                          → {"preset":"Flat","gains":[...],"bands":[...]}
#   eq.sh set Flat|Bass|Treble|Classic|Vocal|Rock
#   eq.sh set-gains g1 g2 ... g10      → apply custom gains (dB, -12..12)
#   eq.sh reset                        → flat
set -euo pipefail

STATE="${HOME}/.config/arch-shell/eq_state.json"
PRESET_DIR="${HOME}/.config/easyeffects/output"
PRESET_NAME="arch_shell_eq"
PRESET_FILE="${PRESET_DIR}/${PRESET_NAME}.json"
mkdir -p "$(dirname "$STATE")" "$PRESET_DIR"

# The ten bands the UI exposes.
BAND_LABELS='["32","64","125","250","500","1k","2k","4k","8k","16k"]'

if [[ ! -f "$STATE" ]]; then
  echo '{"preset":"Flat","gains":[0,0,0,0,0,0,0,0,0,0]}' > "$STATE"
fi

write_preset_file() {
  python3 - "$PRESET_FILE" "$@" <<'PY'
import json, sys
path = sys.argv[1]
gains = [float(x) for x in sys.argv[2:12]]

# Ten user-facing bands mapped onto EasyEffects' 10-band IIR equaliser.
freqs = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
bands = {}
for i, (freq, gain) in enumerate(zip(freqs, gains)):
    bands[f"band{i}"] = {
        "frequency": float(freq),
        "gain": gain,
        "mode": "APO (DR)",
        "mute": False,
        "q": 1.41,
        "slope": "x1",
        "solo": False,
        "type": "Bell",
        "width": 4.0,
    }

preset = {
    "output": {
        "blocklist": [],
        "plugins_order": ["equalizer#0"],
        "equalizer#0": {
            "balance": 0.0,
            "bypass": False,
            "input-gain": 0.0,
            "output-gain": 0.0,
            "left": bands,
            "right": bands,
            "mode": "IIR",
            "num-bands": len(freqs),
            "pitch-left": 0.0,
            "pitch-right": 0.0,
            "split-channels": False,
        },
    }
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(preset, f, indent=4)
PY
}

save_state() {
  local preset="$1"; shift
  python3 - "$STATE" "$preset" "$BAND_LABELS" "$@" <<'PY'
import json, sys
path, preset, labels = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
gains = [float(x) for x in sys.argv[4:14]]
with open(path, "w", encoding="utf-8") as f:
    json.dump({"preset": preset, "gains": gains, "bands": labels}, f)
PY
}

reload_easyeffects() {
  if command -v easyeffects >/dev/null 2>&1; then
    easyeffects -l "$PRESET_NAME" >/dev/null 2>&1 || true
  fi
}

apply_gains() {
  local preset="$1"; shift
  write_preset_file "$@"
  save_state "$preset" "$@"
  reload_easyeffects
}

preset_gains() {
  case "$1" in
    #        32  64 125 250 500  1k  2k  4k  8k 16k
    Flat)    echo "0 0 0 0 0 0 0 0 0 0" ;;
    Bass)    echo "6 5 4 2 0 0 0 0 1 2" ;;
    Treble)  echo "-2 -2 -1 0 1 2 3 4 5 5" ;;
    Classic) echo "4 3 2 0 -1 -1 0 2 3 4" ;;
    Vocal)   echo "-2 -1 0 2 4 4 3 1 0 -1" ;;
    Rock)    echo "5 4 2 -1 -2 0 2 4 4 3" ;;
    *) return 1 ;;
  esac
}

case "${1:-get}" in
  get)
    # Backfill gains/bands for state files written by older versions.
    python3 - "$STATE" "$BAND_LABELS" <<'PY'
import json, sys
path, labels = sys.argv[1], json.loads(sys.argv[2])
try:
    with open(path, encoding="utf-8") as fh:
        state = json.load(fh)
except Exception:
    state = {}
gains = state.get("gains")
if not isinstance(gains, list) or len(gains) != 10:
    presets = {
        "Flat":    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        "Bass":    [6, 5, 4, 2, 0, 0, 0, 0, 1, 2],
        "Treble":  [-2, -2, -1, 0, 1, 2, 3, 4, 5, 5],
        "Classic": [4, 3, 2, 0, -1, -1, 0, 2, 3, 4],
        "Vocal":   [-2, -1, 0, 2, 4, 4, 3, 1, 0, -1],
        "Rock":    [5, 4, 2, -1, -2, 0, 2, 4, 4, 3],
    }
    gains = presets.get(state.get("preset", "Flat"), presets["Flat"])
out = {"preset": state.get("preset", "Flat"), "gains": gains, "bands": labels}
with open(path, "w", encoding="utf-8") as fh:
    json.dump(out, fh)
print(json.dumps(out, separators=(",", ":")))
PY
    ;;
  set)
    name="${2:-Flat}"
    if ! gains="$(preset_gains "$name")"; then
      echo "Unknown preset: $name" >&2
      exit 1
    fi
    # shellcheck disable=SC2086
    apply_gains "$name" $gains
    cat "$STATE"
    ;;
  set-gains)
    shift
    if [[ $# -ne 10 ]]; then
      echo "set-gains needs exactly 10 values" >&2
      exit 1
    fi
    apply_gains "Custom" "$@"
    cat "$STATE"
    ;;
  reset)
    # shellcheck disable=SC2086
    apply_gains "Flat" $(preset_gains Flat)
    cat "$STATE"
    ;;
  bands)
    echo "$BAND_LABELS"
    ;;
  *)
    echo "Usage: $0 get|set <preset>|set-gains g1..g10|reset|bands" >&2
    exit 1
    ;;
esac
