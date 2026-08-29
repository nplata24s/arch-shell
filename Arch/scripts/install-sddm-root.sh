#!/usr/bin/env bash
# Root half of the SDDM theme install. Invoked via pkexec/sudo.
# Usage: install-sddm-root.sh ROOT_DIR USER_HOME BACKUP_DIR [WALLPAPER]
set -euo pipefail

ROOT="${1:?root dir}"
USER_HOME="${2:?user home}"
BACKUP_DIR="${3:?backup dir}"
WALL="${4:-}"

DEST="/usr/share/sddm/themes/arch-shell"
STATE="/var/lib/arch-shell"
CONF="/etc/sddm.conf.d/10-arch-shell.conf"
OLD="/etc/sddm.conf.d/10-wayland-matugen.conf"

mkdir -p "${DEST}/theme" "${STATE}" /etc/sddm.conf.d "${BACKUP_DIR}"
rm -rf "${DEST}"
mkdir -p "${DEST}/theme"

cp "${ROOT}/sddm/arch-shell/Main.qml" \
   "${ROOT}/sddm/arch-shell/metadata.desktop" \
   "${ROOT}/sddm/arch-shell/theme.conf" \
   "${DEST}/"
cp -a "${ROOT}/shell/theme/." "${DEST}/theme/"

if [[ -n "${WALL}" && -f "${WALL}" ]]; then
  cp -f "${WALL}" "${DEST}/wallpaper.jpg"
  cp -f "${WALL}" "${STATE}/wallpaper"
fi

# Live copies written by the user-owned sync script.
if [[ -f "${STATE}/wallpaper" ]]; then
  cp -f "${STATE}/wallpaper" "${DEST}/wallpaper.jpg"
elif [[ -f "${USER_HOME}/.config/arch-shell/wallpaper" ]]; then
  cp -f "${USER_HOME}/.config/arch-shell/wallpaper" "${DEST}/wallpaper.jpg"
  cp -f "${USER_HOME}/.config/arch-shell/wallpaper" "${STATE}/wallpaper"
fi

if [[ -f "${USER_HOME}/.config/arch-shell/sddm-theme.json" ]]; then
  cp -f "${USER_HOME}/.config/arch-shell/sddm-theme.json" "${STATE}/theme.json"
fi
if [[ -f "${USER_HOME}/.config/arch-shell/LiveTheme.qml" ]]; then
  cp -f "${USER_HOME}/.config/arch-shell/LiveTheme.qml" "${STATE}/LiveTheme.qml"
fi
if [[ ! -f "${STATE}/LiveTheme.qml" ]]; then
  cp -f "${ROOT}/sddm/arch-shell/live/LiveTheme.qml" "${STATE}/LiveTheme.qml"
fi
printf 'LiveTheme 1.0 LiveTheme.qml\n' > "${STATE}/qmldir"
rm -rf "${DEST}/live"
ln -sfn "${STATE}" "${DEST}/live"

chmod 755 "${STATE}"
chmod 644 "${STATE}/wallpaper" 2>/dev/null || true
chmod 644 "${STATE}/theme.json" 2>/dev/null || true
chmod 644 "${STATE}/LiveTheme.qml" 2>/dev/null || true
chmod 644 "${STATE}/qmldir" 2>/dev/null || true
chmod 644 "${DEST}/wallpaper.jpg" 2>/dev/null || true

# Installing user must be able to refresh the wallpaper after login.
uid="${SUDO_UID:-${PKEXEC_UID:-}}"
if [[ -n "${uid}" ]]; then
  gid="$(id -g "${uid}" 2>/dev/null || echo "${uid}")"
  chown "${uid}:${gid}" "${STATE}"
  [[ -f "${STATE}/wallpaper" ]] && chown "${uid}:${gid}" "${STATE}/wallpaper"
  [[ -f "${STATE}/theme.json" ]] && chown "${uid}:${gid}" "${STATE}/theme.json"
  [[ -f "${STATE}/LiveTheme.qml" ]] && chown "${uid}:${gid}" "${STATE}/LiveTheme.qml"
  [[ -f "${STATE}/qmldir" ]] && chown "${uid}:${gid}" "${STATE}/qmldir"
fi

if [[ -f "${OLD}" ]]; then
  cp "${OLD}" "${BACKUP_DIR}/10-wayland-matugen.conf"
  rm -f "${OLD}"
fi

cat > "${CONF}" <<'EOF'
[Theme]
Current=arch-shell
Font=JetBrainsMono Nerd Font

[General]
DisplayServer=x11-user
GreeterEnvironment=QT_QUICK_CONTROLS_STYLE=Basic
EOF

echo "Installed Arch Shell SDDM theme to ${DEST}"
