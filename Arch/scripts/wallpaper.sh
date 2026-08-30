#!/usr/bin/env bash
# List / set wallpapers via awww (Hyprland wallpaper daemon)
set -euo pipefail
ACTION="${1:-list}"
FILE="${2:-}"

dirs=(
  "${HOME}/Pictures/Wallpapers"
  "${HOME}/Pictures/wallpapers"
  "${HOME}/Pictures"
  "${HOME}/.config/arch-shell/wallpapers"
)

case "$ACTION" in
  list)
    python3 - "$HOME" <<'PY'
import json, os, sys
home = sys.argv[1]
dirs = [
    os.path.join(home, "Pictures", "Wallpapers"),
    os.path.join(home, "Pictures", "wallpapers"),
    os.path.join(home, "Pictures"),
    os.path.join(home, ".config", "arch-shell", "wallpapers"),
]
exts = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}
seen = set()
out = []
for d in dirs:
    if not os.path.isdir(d):
        continue
    try:
        names = sorted(os.listdir(d))
    except OSError:
        continue
    for name in names:
        path = os.path.join(d, name)
        if not os.path.isfile(path):
            continue
        if os.path.splitext(name)[1].lower() not in exts:
            continue
        if path in seen:
            continue
        seen.add(path)
        out.append({"name": name, "path": path})
        if len(out) >= 40:
            break
    if len(out) >= 40:
        break
print(json.dumps(out))
PY
    ;;
  set)
    [[ -z "$FILE" || ! -f "$FILE" ]] && exit 1
    if command -v awww &>/dev/null; then
      awww img "$FILE" --transition-type fade --transition-duration 0.4 >/dev/null 2>&1 \
        || awww img "$FILE"
    elif command -v hyprpaper &>/dev/null; then
      hyprctl hyprpaper reload "$FILE" >/dev/null 2>&1 || true
    else
      echo "No wallpaper daemon (awww) on PATH" >&2
      exit 1
    fi
    # Keep the login screen on the same image (best-effort; needs
    # /var/lib/arch-shell from install.sh).
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -x "${SCRIPT_DIR}/sync-sddm.sh" ]]; then
      bash "${SCRIPT_DIR}/sync-sddm.sh" "$FILE" >/dev/null 2>&1 || true
    fi
    ;;
  *)
    echo "Usage: $0 list|set FILE" >&2
    exit 1
    ;;
esac
