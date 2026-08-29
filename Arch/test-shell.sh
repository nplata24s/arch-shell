#!/usr/bin/env bash
# Launch Arch Shell for testing (does not change autostart)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_DIR="${ROOT}/shell"
CONFIG_DIR="${HOME}/.config/arch-shell"

if [[ ! -f "${SHELL_DIR}/shell.qml" ]]; then
  echo "shell.qml not found in ${SHELL_DIR}" >&2
  exit 1
fi

mkdir -p "${CONFIG_DIR}/scripts" "${CONFIG_DIR}/hyprland" "${CONFIG_DIR}/agent-daemon"
# Drop QML from previous versions so renamed/removed modules do not linger.
rm -f "${CONFIG_DIR}"/*.qml "${CONFIG_DIR}"/theme/*.qml
cp -a "${ROOT}/shell/." "${CONFIG_DIR}/"
cp -a "${ROOT}/scripts/." "${CONFIG_DIR}/scripts/"
cp "${ROOT}/config/hyprland/layers.conf" "${CONFIG_DIR}/hyprland/layers.conf"
cp "${ROOT}/agent-centre/daemon/arch_agentd.py" "${CONFIG_DIR}/agent-daemon/arch_agentd.py"
chmod +x "${CONFIG_DIR}/agent-daemon/arch_agentd.py"
chmod +x "${CONFIG_DIR}/scripts/"*.sh 2>/dev/null || true
chmod +x "${CONFIG_DIR}/scripts/"*.py 2>/dev/null || true
mkdir -p "${HOME}/.config/systemd/user"
cp "${ROOT}/agent-centre/daemon/systemd/arch-agentd.service" \
   "${HOME}/.config/systemd/user/arch-agentd.service" 2>/dev/null || true
systemctl --user daemon-reload >/dev/null 2>&1 || true
if [[ ! -f "${CONFIG_DIR}/settings.json" ]]; then
  cp "${ROOT}/config/settings.json" "${CONFIG_DIR}/settings.json"
fi
if [[ ! -f "${CONFIG_DIR}/keybinds.json" ]]; then
  cp "${ROOT}/config/keybinds.json" "${CONFIG_DIR}/keybinds.json"
fi

echo "Starting Arch Shell (Ctrl+C to stop)..."
echo "You may see two taskbars if your normal shell is already running."
echo ""

# Basic style so our Fluent control overrides are not fighting a platform theme.
export QT_QUICK_CONTROLS_STYLE=Basic
exec quickshell -p "${CONFIG_DIR}"
