#!/usr/bin/env bash
set -euo pipefail
WALL_DIR="${WALLPAPER_DIR:-$HOME/Pictures/Wallpapers}"
CACHE="${HOME}/.cache/quickshell/wallpaper_picker"
mkdir -p "$WALL_DIR" "$CACHE" "${HOME}/.config/arch-shell"

pick=""
if [[ -f "${HOME}/.config/arch-shell/wallpaper.path" ]]; then
  pick="$(<"${HOME}/.config/arch-shell/wallpaper.path")"
fi
if [[ -z "$pick" || ! -f "$pick" ]]; then
  if [[ -f "${HOME}/.config/arch-shell/wallpaper" ]]; then
    pick="${HOME}/.config/arch-shell/wallpaper"
  elif [[ -f "${WALL_DIR}/default.jpg" ]]; then
    pick="${WALL_DIR}/default.jpg"
  else
    pick="$(find "$WALL_DIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) 2>/dev/null | head -n 1 || true)"
  fi
fi
[[ -n "$pick" && -f "$pick" ]] || exit 0

printf '%s\n' "$pick" > "${HOME}/.config/arch-shell/wallpaper.path"
cp -f "$pick" "${HOME}/.config/arch-shell/wallpaper"
cp -f "$pick" "${CACHE}/current_wallpaper.png"

if command -v awww >/dev/null 2>&1; then
  awww img "$pick" --transition-type fade --transition-duration 0.4 >/dev/null 2>&1 || awww img "$pick" || true
fi
if [[ -x "${HOME}/.config/arch-shell/scripts/sync-sddm.sh" ]]; then
  bash "${HOME}/.config/arch-shell/scripts/sync-sddm.sh" "$pick" >/dev/null 2>&1 || true
fi
