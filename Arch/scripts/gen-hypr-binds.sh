#!/usr/bin/env bash
# Generate Hyprland keybinds from config/keybinds.json
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEYBINDS="${1:-$ROOT/config/keybinds.json}"
OUT="${2:-$ROOT/config/hyprland/keybinds.conf}"
QS_PATH="${3:-$HOME/.config/arch-shell}"

if [[ ! -f "$KEYBINDS" ]]; then
  echo "Missing keybinds file: $KEYBINDS" >&2
  exit 1
fi

python3 - "$KEYBINDS" "$OUT" "$QS_PATH" <<'PY'
import json, os, sys

keybinds_path, out_path, qs_path = sys.argv[1:4]
os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(keybinds_path) as f:
    data = json.load(f)

mod_map = {"Super": "SUPER", "Shift": "SHIFT", "Ctrl": "CTRL", "Alt": "ALT"}
module_map = {
    "audio": "Audio",
    "agentCentre": "AgentCentre",
    "clipboard": "Clipboard",
    "notes": "Notes",
    "calculator": "Calculator",
    "taskView": "TaskView",
    "quickSettings": "QuickSettings",
    "settings": "Settings",
    "music": "DynamicMusic",
    "network": "NetworkBluetooth",
}

def hypr_mods(mods):
    parts = [mod_map.get(m, m.upper()) for m in mods if m]
    return " ".join(parts)

def ipc(name):
    return f"exec, quickshell -p {qs_path} ipc call arch toggle {name}"

lines = ["# Auto-generated from keybinds.json — do not edit by hand", ""]

binds = data.get("binds", {})
for name, b in binds.items():
    if b.get("enabled") is False:
        continue
    mods = b.get("mods", [])
    key = b.get("key", "")

    # Modifier-only binds (tap Super / $mainMod to toggle Start). Hyprland
    # requires the `r` (release) flag and the physical key, e.g. Super_L.
    if b.get("alone"):
        if not mods:
            continue
        mod_str = hypr_mods(mods)
        physical = {
            "SUPER": ("Super_L", "Super_R"),
            "ALT": ("Alt_L", "Alt_R"),
            "CTRL": ("Control_L", "Control_R"),
            "SHIFT": ("Shift_L", "Shift_R"),
        }
        primary = mod_map.get(mods[0], mods[0].upper())
        keys = physical.get(primary, ("Super_L",))
        if name == "shell.start":
            # Prefer $mainMod so this tracks Hyprland's Super/Win key.
            bind_mod = "$mainMod" if primary == "SUPER" else mod_str
            for k in keys:
                lines.append(f"bindr = {bind_mod}, {k}, {ipc('Start')}")
        continue

    if not key:
        continue

    mod_str = hypr_mods(mods)
    prefix = f"bind = {mod_str}, " if mod_str else "bind = , "

    if name.startswith("desktop."):
        num = name.split(".", 1)[1]
        if num.isdigit():
            lines.append(f"{prefix}{key}, workspace, {num}")
    elif name == "window.close":
        lines.append(f"{prefix}{key}, killactive,")
    elif name == "window.toggleFloat":
        lines.append(f"{prefix}{key}, togglefloating,")
    elif name == "app.terminal":
        lines.append(f"{prefix}{key}, exec, kitty")
    elif name == "app.screenshot":
        lines.append(f"{prefix}{key}, exec, flameshot gui")
    elif name == "app.colorPicker":
        lines.append(f"{prefix}{key}, exec, hyprpicker -a")
    elif name == "shell.keybindHelp":
        lines.append(f"{prefix}{key}, {ipc('KeybindHelp')}")
    elif name.startswith("module."):
        ident = name.split(".", 1)[1]
        mod = module_map.get(ident, ident[0].upper() + ident[1:])
        lines.append(f"{prefix}{key}, {ipc(mod)}")

with open(out_path, "w") as f:
    f.write("\n".join(lines) + "\n")

print(f"Wrote {out_path}")
PY
