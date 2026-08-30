#!/usr/bin/env python3
"""Point Hyprland settings.json at Arch Shell so Serpantinum cannot respawn."""
import json
import os
import sys


def is_serp_shell(cmd: str) -> bool:
    c = cmd.replace("~", os.path.expanduser("~"))
    return "quickshell" in c and "quickshell/Shell.qml" in c


def is_arch_shell(cmd: str) -> bool:
    return "quickshell" in cmd and "arch-shell" in cmd


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: patch_hypr_for_arch_shell.py SETTINGS_JSON ARCH_SHELL_CMD", file=sys.stderr)
        return 2
    path, arch_cmd = sys.argv[1], sys.argv[2]
    with open(path, encoding="utf-8") as f:
        data = json.load(f)

    data["openGuideAtStartup"] = False

    drop = (
        "focustime/launch_daemon",
        "update_notifier.sh",
        "swayosd-server",
        "swayosd-client",
        "qs_manager.sh",
    )
    startup = []
    replaced = False
    for item in data.get("startup") or []:
        cmd = item.get("command") or ""
        if any(s in cmd for s in drop):
            continue
        if is_serp_shell(cmd) or is_arch_shell(cmd):
            if not replaced:
                startup.append({"command": arch_cmd})
                replaced = True
            continue
        startup.append(item)
    if not replaced:
        startup.append({"command": arch_cmd})
    data["startup"] = startup

    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
