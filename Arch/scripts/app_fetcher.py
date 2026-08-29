#!/usr/bin/env python3
import glob
import json
import os

def fetch_apps():
    apps = {}
    home = os.path.expanduser("~")
    dirs = [
        "/usr/share/applications",
        "/usr/local/share/applications",
        f"{home}/.local/share/applications",
        "/var/lib/flatpak/exports/share/applications",
        f"{home}/.local/share/flatpak/exports/share/applications",
    ]

    for d in dirs:
        if not os.path.isdir(d):
            continue
        for f in glob.glob(os.path.join(d, "*.desktop")):
            try:
                app = {"name": "", "exec": "", "icon": "", "desktop": f, "comment": ""}
                is_desktop = False
                no_display = False
                with open(f, encoding="utf-8") as file:
                    for line in file:
                        line = line.strip()
                        if line == "[Desktop Entry]":
                            is_desktop = True
                        elif line.startswith("["):
                            is_desktop = False
                        if not is_desktop:
                            continue
                        if line.startswith("Name=") and not app["name"]:
                            app["name"] = line[5:]
                        elif line.startswith("Exec=") and not app["exec"]:
                            app["exec"] = line[5:].split(" %")[0].split(" @@")[0]
                        elif line.startswith("Icon=") and not app["icon"]:
                            app["icon"] = line[5:]
                        elif line.startswith("Comment=") and not app["comment"]:
                            app["comment"] = line[8:]
                        elif line.startswith("NoDisplay=true"):
                            no_display = True
                if app["name"] and app["exec"] and not no_display:
                    apps[app["name"]] = app
            except OSError:
                pass

    result = sorted(apps.values(), key=lambda x: x["name"].lower())
    print(json.dumps(result))

if __name__ == "__main__":
    fetch_apps()
