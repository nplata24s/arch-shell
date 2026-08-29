#!/usr/bin/env python3
"""Write keybinds.json, regenerate Hyprland binds, and load them now."""
import json
import os
import subprocess
import sys

if len(sys.argv) < 5:
    sys.exit("usage: apply_keybinds.py JSON_PATH CONF_PATH QS_PATH PAYLOAD")

json_path, conf_path, qs_path, payload = sys.argv[1:5]
data = json.loads(payload)
os.makedirs(os.path.dirname(json_path), exist_ok=True)
with open(json_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

script_dir = os.path.dirname(os.path.abspath(__file__))
subprocess.run(
    ["bash", os.path.join(script_dir, "gen-hypr-binds.sh"), json_path, conf_path, qs_path],
    check=False,
)
# A full reload, not `hyprctl keyword source`: re-sourcing only adds binds, so
# a rebound or removed shortcut would leave the old one still registered.
# (`hyprctl source` is not a command at all — it silently did nothing.)
subprocess.run(["hyprctl", "reload"], check=False,
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
