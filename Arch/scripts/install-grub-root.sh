#!/usr/bin/env bash
# Root half of the Arch Shell GRUB theme install.
# Usage: install-grub-root.sh THEME_DIR [--assets-only]
set -euo pipefail

SRC="${1:?theme dir}"
MODE="${2:-}"
DEST="/boot/grub/themes/arch-shell"
GRUB_DEF="/etc/default/grub"
GRUB_CFG="/boot/grub/grub.cfg"
BACKUP_DIR="${3:-}"

[[ -f "${SRC}/theme.txt" && -f "${SRC}/background.png" ]] || {
  echo "Theme not rendered: missing theme.txt or background.png in ${SRC}" >&2
  exit 1
}

mkdir -p "$DEST"
cp -f "${SRC}/"* "$DEST/"
chmod 644 "${DEST}/"*

W="$(cat "${SRC}/width" 2>/dev/null || echo 1920)"
H="$(cat "${SRC}/height" 2>/dev/null || echo 1200)"

if [[ "$MODE" == "--assets-only" ]]; then
  echo "Updated GRUB theme assets in ${DEST}"
  exit 0
fi

if [[ -n "${BACKUP_DIR}" ]]; then
  mkdir -p "${BACKUP_DIR}"
  [[ -f "$GRUB_DEF" ]] && cp -n "$GRUB_DEF" "${BACKUP_DIR}/grub.default" || true
fi

# Point GRUB at this theme and a matching gfx mode.
tmp="$(mktemp)"
awk -v theme="${DEST}/theme.txt" -v mode="${W}x${H},1920x1080,auto" '
  BEGIN { t=0; g=0; o=0 }
  /^#?GRUB_THEME=/ {
    print "GRUB_THEME=\"" theme "\""
    t=1
    next
  }
  /^#?GRUB_GFXMODE=/ {
    print "GRUB_GFXMODE=" mode
    g=1
    next
  }
  /^GRUB_TERMINAL_OUTPUT=console/ {
    print "#GRUB_TERMINAL_OUTPUT=console"
    o=1
    next
  }
  { print }
  END {
    if (!t) print "GRUB_THEME=\"" theme "\""
    if (!g) print "GRUB_GFXMODE=" mode
  }
' "$GRUB_DEF" > "$tmp"
mv "$tmp" "$GRUB_DEF"

grub-mkconfig -o "$GRUB_CFG"
echo "Installed Arch Shell GRUB theme to ${DEST}"
