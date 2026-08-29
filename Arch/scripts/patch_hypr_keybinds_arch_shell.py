#!/usr/bin/env python3
"""Retarget Hyprland settings.json away from Serpantinum and onto Arch Shell."""
import json
import os
import re
import sys

path = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1
                          else "~/.config/hypr/settings.json")
arch = os.path.expanduser("~/.config/arch-shell")
osd = f"{arch}/scripts/osd.sh"
ipc = f"quickshell -p {arch} ipc call arch toggle"

SWAYOSD_MAP = {
    "--caps-lock": f"sleep 0.1 && {osd} caps",
    "--brightness lower": f"{osd} brightness-down",
    "--brightness raise": f"{osd} brightness-up",
    "--input-volume mute-toggle": f"{osd} mic-mute",
    "--output-volume mute-toggle": f"{osd} volume-mute",
    "--output-volume lower": f"{osd} volume-down",
    "--output-volume raise": f"{osd} volume-up",
}

with open(path, encoding="utf-8") as f:
    data = json.load(f)

data["openGuideAtStartup"] = False

drop_startup = (
    "quickshell/Shell.qml",
    "focustime/launch_daemon",
    "update_notifier.sh",
    "qs_manager.sh",
    "swayosd-server",
    "swayosd-client",
)
startup = []
seen_arch = False
for item in data.get("startup") or []:
    cmd = item.get("command") or ""
    if any(s in cmd for s in drop_startup):
        continue
    if "arch-shell" in cmd and "quickshell" in cmd:
        if seen_arch:
            continue
        seen_arch = True
        startup.append({"command": f"env QT_QUICK_CONTROLS_STYLE=Basic quickshell -p {arch}"})
        continue
    startup.append(item)
if not seen_arch:
    startup.append({"command": f"env QT_QUICK_CONTROLS_STYLE=Basic quickshell -p {arch}"})
data["startup"] = startup

toggle_map = {
    "clipboard": "Clipboard",
    "movies": "GamingMode",
    "settings": "Settings",
    "music": "DynamicMusic",
    "battery": "BatteryNotifications",
    "wallpaper": "Wallpaper",
    "calendar": "ClockWeather",
    "network": "NetworkBluetooth",
    "focustime": "AgentCentre",
    "volume": "Audio",
}

new_binds = []
for b in data.get("keybinds") or []:
    cmd = b.get("command") or ""
    key = str(b.get("key") or "")
    mods = str(b.get("mods") or "")

    # Super+D / Super+M used to open Start — Super tap replaces them.
    if key in ("D", "M") and "$mainMod" in mods and "SHIFT" not in mods and "CTRL" not in mods:
        if "applauncher" in cmd or "Start" in cmd or "Shell.qml" in cmd or cmd.strip() == "":
            continue

    if "swayosd" in cmd:
        nb = dict(b)
        mapped = None
        for needle, replacement in SWAYOSD_MAP.items():
            if needle in cmd:
                mapped = replacement
                break
        if mapped:
            nb["command"] = mapped
            new_binds.append(nb)
        continue

    if "qs_manager.sh" in cmd:
        m = re.search(r"qs_manager\.sh\s+(\d+)(?:\s+(move))?", cmd)
        if m:
            num = m.group(1)
            move = m.group(2)
            nb = dict(b)
            nb["dispatcher"] = "movetoworkspace" if move else "workspace"
            nb["command"] = num
            new_binds.append(nb)
            continue
        m = re.search(r"toggle\s+(\w+)", cmd)
        if m:
            target = m.group(1)
            if target in ("applauncher", "guide"):
                continue
            mod = toggle_map.get(target)
            if not mod:
                continue
            nb = dict(b)
            nb["dispatcher"] = "exec"
            nb["command"] = f"{ipc} {mod}"
            new_binds.append(nb)
            continue
        continue

    if "screenshot.sh" in cmd:
        nb = dict(b)
        nb["command"] = "flameshot gui"
        new_binds.append(nb)
        continue

    if "quickshell/Lock.qml" in cmd:
        nb = dict(b)
        nb["command"] = "bash ~/.config/hypr/scripts/lock.sh"
        new_binds.append(nb)
        continue

    if "Shell.qml" in cmd:
        continue

    new_binds.append(b)

# Super tap → Start (survives settings_watcher rebuilds)
tap = [
    {
        "type": "bindr",
        "mods": "$mainMod",
        "key": "Super_L",
        "dispatcher": "exec",
        "command": f"{ipc} Start",
    },
    {
        "type": "bindr",
        "mods": "$mainMod",
        "key": "Super_R",
        "dispatcher": "exec",
        "command": f"{ipc} Start",
    },
]
existing = {(b.get("type"), b.get("mods"), b.get("key")) for b in new_binds}
tap = [b for b in tap if (b["type"], b["mods"], b["key"]) not in existing]
data["keybinds"] = tap + new_binds

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

print(f"Patched {path}")
