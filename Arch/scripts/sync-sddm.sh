#!/usr/bin/env bash
# Mirror the live wallpaper and Fluent tokens to a path the SDDM greeter
# can read (it runs as the sddm user, so $HOME is off-limits).
set -euo pipefail

STATE_DIR="${ARCH_SDDM_STATE:-/var/lib/arch-shell}"
USER_DIR="${HOME}/.config/arch-shell"
SETTINGS="${USER_DIR}/settings.json"
WALL_PATH_FILE="${USER_DIR}/wallpaper.path"
SRC_WALL="${1:-}"

mkdir -p "${USER_DIR}"

if [[ -z "${SRC_WALL}" || ! -f "${SRC_WALL}" ]]; then
    if [[ -f "${WALL_PATH_FILE}" ]]; then
        SRC_WALL="$(<"${WALL_PATH_FILE}")"
    fi
fi

if [[ -z "${SRC_WALL}" || ! -f "${SRC_WALL}" ]]; then
    for candidate in \
        "${HOME}/.cache/quickshell/wallpaper_picker/current_wallpaper.png" \
        "${HOME}/.config/arch-shell/wallpaper"
    do
        if [[ -f "${candidate}" ]]; then
            SRC_WALL="${candidate}"
            break
        fi
    done
fi

if [[ -n "${SRC_WALL}" && -f "${SRC_WALL}" ]]; then
    printf '%s\n' "${SRC_WALL}" > "${WALL_PATH_FILE}"
    cp -f "${SRC_WALL}" "${USER_DIR}/wallpaper"
fi

python3 - "${SETTINGS}" "${USER_DIR}/sddm-theme.json" <<'PY'
import json
import os
import sys

settings_path, out_path = sys.argv[1], sys.argv[2]
data = {}
if os.path.isfile(settings_path):
    try:
        with open(settings_path, encoding="utf-8") as f:
            data = json.load(f) or {}
    except (OSError, json.JSONDecodeError):
        data = {}

taskbar = data.get("taskbar") or {}
theme = data.get("theme") or {}
color = str(taskbar.get("color") or "#1c1c1c").strip()
if color.startswith("#") and len(color) == 7:
    r = int(color[1:3], 16) / 255.0
    g = int(color[3:5], 16) / 255.0
    b = int(color[5:7], 16) / 255.0
else:
    r, g, b = 0x1c / 255.0, 0x1c / 255.0, 0x1c / 255.0

try:
    opacity = float(taskbar["opacity"]) if taskbar.get("opacity") is not None else 0.72
except (TypeError, ValueError):
    opacity = 0.72
opacity = max(0.0, min(1.0, opacity))

# Same luminosity floor as ShellState.barColor
luminosity = 0.55
combined = 1 - (1 - luminosity) * (1 - opacity)
a = max(0, min(255, round(combined * 255)))

def hex2(v):
    return f"{max(0, min(255, round(v * 255))):02x}"

accent = str(theme.get("accent") or "#60cdff").strip()
if accent.startswith("#") and len(accent) == 9:
    accent = "#" + accent[3:]
if not (accent.startswith("#") and len(accent) == 7):
    accent = "#60cdff"

payload = {
    "accent": accent,
    "mica": f"#{a:02x}{hex2(r)}{hex2(g)}{hex2(b)}",
    "barColor": color if color.startswith("#") else "#1c1c1c",
    "opacity": opacity,
    "fontFamily": theme.get("fontFamily") or "JetBrainsMono Nerd Font",
    "position": taskbar.get("position") or "top",
    "barHeight": int(taskbar.get("height") or 48),
    "wallpaper": "/var/lib/arch-shell/wallpaper",
}
os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(payload, f, indent=2)
    f.write("\n")

# QML the greeter can import (XMLHttpRequest cannot read local files).
qml_path = os.path.join(os.path.dirname(out_path), "LiveTheme.qml")
bar_on_top = "true" if payload["position"] == "top" else "false"
accent_qml = accent if accent.startswith("#") and len(accent) == 7 else "#60cdff"
with open(qml_path, "w", encoding="utf-8") as f:
    f.write(
        "import QtQuick\n\n"
        "QtObject {\n"
        f'    property color accent: "#ff{accent_qml[1:]}"\n'
        f'    property color mica: "{payload["mica"]}"\n'
        f"    property bool barOnTop: {bar_on_top}\n"
        f"    property int barHeight: {payload['barHeight']}\n"
        "}\n"
    )
qmldir_path = os.path.join(os.path.dirname(out_path), "qmldir.sddm-live")
with open(qmldir_path, "w", encoding="utf-8") as f:
    f.write("LiveTheme 1.0 LiveTheme.qml\n")
PY

if [[ -d "${STATE_DIR}" && -w "${STATE_DIR}" ]]; then
    if [[ -n "${SRC_WALL}" && -f "${SRC_WALL}" ]]; then
        cp -f "${SRC_WALL}" "${STATE_DIR}/wallpaper"
        chmod 644 "${STATE_DIR}/wallpaper" 2>/dev/null || true
    fi
    if [[ -f "${USER_DIR}/sddm-theme.json" ]]; then
        cp -f "${USER_DIR}/sddm-theme.json" "${STATE_DIR}/theme.json"
        chmod 644 "${STATE_DIR}/theme.json" 2>/dev/null || true
    fi
    if [[ -f "${USER_DIR}/LiveTheme.qml" ]]; then
        cp -f "${USER_DIR}/LiveTheme.qml" "${STATE_DIR}/LiveTheme.qml"
        printf 'LiveTheme 1.0 LiveTheme.qml\n' > "${STATE_DIR}/qmldir"
        chmod 644 "${STATE_DIR}/LiveTheme.qml" "${STATE_DIR}/qmldir" 2>/dev/null || true
    fi
    # Keep a fallback copy next to Main.qml when the theme is installed.
    THEME_DIR="/usr/share/sddm/themes/arch-shell"
    if [[ -d "${THEME_DIR}" && -w "${THEME_DIR}" && -n "${SRC_WALL}" && -f "${SRC_WALL}" ]]; then
        cp -f "${SRC_WALL}" "${THEME_DIR}/wallpaper.jpg"
        chmod 644 "${THEME_DIR}/wallpaper.jpg" 2>/dev/null || true
    fi
fi

# Keep GRUB on the same wallpaper when we can write it without a password.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -x "${SCRIPT_DIR}/render-grub-theme.sh" ]]; then
    bash "${SCRIPT_DIR}/render-grub-theme.sh" "${USER_DIR}/grub-theme" \
        "${SRC_WALL:-}" "${USER_DIR}/sddm-theme.json" >/dev/null 2>&1 || true
    if [[ -d /boot/grub/themes/arch-shell ]] && sudo -n true >/dev/null 2>&1; then
        sudo "${SCRIPT_DIR}/install-grub-root.sh" "${USER_DIR}/grub-theme" --assets-only \
            >/dev/null 2>&1 || true
    fi
fi
