#!/usr/bin/env bash
# Render and install the Arch Shell GRUB theme (needs sudo once).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${HOME}/.config/arch-shell/grub-theme"
mkdir -p "$DEST"
bash "${ROOT}/scripts/render-grub-theme.sh" "$DEST"
sudo "${ROOT}/scripts/install-grub-root.sh" "$DEST" "" "${HOME}/.config/arch-shell/backup"
