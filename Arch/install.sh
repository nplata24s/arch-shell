#!/usr/bin/env bash
# Arch Shell installer
# Usage:
#   ./install.sh           — install deps, copy configs (safe; does not touch Hyprland autostart)
#   ./install.sh --enable  — switch autostart from existing quickshell to Arch Shell
#   ./install.sh --rollback — restore Hyprland autostart from backup
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${HOME}/.config/arch-shell"
BACKUP_DIR="${CONFIG_DIR}/backup"
HYPR_CONFIG="${HOME}/.config/hypr/hyprland.conf"
AUTOSTART_FILE="${HOME}/.config/hypr/config/autostart.conf"

ARCH_PACKAGES=(
  quickshell hyprland kitty zsh fastfetch ttf-jetbrains-mono-nerd
  pipewire pipewire-pulse wireplumber networkmanager bluez bluez-utils
  upower mako flameshot nemo playerctl jq cliphist wl-clipboard
  brightnessctl wlsunset pacman-contrib power-profiles-daemon
  udisks2 hyprpicker qalculate-gtk wf-recorder swww wdisplays easyeffects
  sddm imagemagick
)

install_packages() {
  echo "==> Checking pacman packages..."
  local missing=()
  for pkg in "${ARCH_PACKAGES[@]}"; do
    if ! pacman -Q "$pkg" &>/dev/null; then
      missing+=("$pkg")
    fi
  done
  if ((${#missing[@]})); then
    echo "Installing missing packages: ${missing[*]}"
    sudo pacman -S --needed --noconfirm "${missing[@]}"
  else
    echo "All packages already installed."
  fi
}

copy_configs() {
  echo "==> Copying Arch Shell configs to ${CONFIG_DIR}..."
  mkdir -p "${CONFIG_DIR}/hyprland" "${CONFIG_DIR}/scripts" "${CONFIG_DIR}/agent-daemon"
  # Drop QML from previous versions so renamed/removed modules do not linger.
  rm -f "${CONFIG_DIR}"/*.qml "${CONFIG_DIR}"/theme/*.qml
  cp -a "${ROOT}/shell/." "${CONFIG_DIR}/"
  cp -a "${ROOT}/scripts/." "${CONFIG_DIR}/scripts/"
  cp "${ROOT}/config/hyprland/layers.conf" "${CONFIG_DIR}/hyprland/layers.conf"
  cp "${ROOT}/agent-centre/daemon/"*.py "${CONFIG_DIR}/agent-daemon/"
  chmod +x "${CONFIG_DIR}/agent-daemon/"*.py
  if [[ -x "${ROOT}/scripts/install-login-clis.sh" ]]; then
    echo "==> Installing Agent Centre login CLIs (agy, Codex, Claude Code)..."
    bash "${ROOT}/scripts/install-login-clis.sh" || true
  fi
  chmod +x "${CONFIG_DIR}/scripts/"*.sh 2>/dev/null || true
  chmod +x "${CONFIG_DIR}/scripts/"*.py 2>/dev/null || true

  # Agent Centre user service (not enabled — the UI turns it on)
  local unit_dir="${HOME}/.config/systemd/user"
  mkdir -p "${unit_dir}"
  cp "${ROOT}/agent-centre/daemon/systemd/arch-agentd.service" \
     "${unit_dir}/arch-agentd.service"
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  if [[ ! -f "${CONFIG_DIR}/settings.json" ]]; then
    cp "${ROOT}/config/settings.json" "${CONFIG_DIR}/settings.json"
  fi
  if [[ ! -f "${CONFIG_DIR}/keybinds.json" ]]; then
    cp "${ROOT}/config/keybinds.json" "${CONFIG_DIR}/keybinds.json"
  fi
  mkdir -p "${HOME}/.config/arch-shell"
  touch "${CONFIG_DIR}/notes.txt"
  bash "${ROOT}/scripts/gen-hypr-binds.sh" \
    "${CONFIG_DIR}/keybinds.json" \
    "${CONFIG_DIR}/hyprland/keybinds.conf"
  echo "Configs installed to ${CONFIG_DIR}"
}

backup_hypr() {
  mkdir -p "${BACKUP_DIR}"
  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  if [[ -f "${AUTOSTART_FILE}" ]]; then
    cp "${AUTOSTART_FILE}" "${BACKUP_DIR}/autostart.conf.${ts}"
    ln -sf "autostart.conf.${ts}" "${BACKUP_DIR}/autostart.conf.latest"
    echo "Backed up autostart to ${BACKUP_DIR}/autostart.conf.${ts}"
  fi
  local kb_file="${HOME}/.config/hypr/config/keybindings.conf"
  if [[ -f "${kb_file}" ]]; then
    cp "${kb_file}" "${BACKUP_DIR}/keybindings.conf.${ts}"
    ln -sf "keybindings.conf.${ts}" "${BACKUP_DIR}/keybindings.conf.latest"
  fi
  local hypr_settings="${HOME}/.config/hypr/settings.json"
  if [[ -f "${hypr_settings}" ]]; then
    cp "${hypr_settings}" "${BACKUP_DIR}/hypr-settings.json.${ts}"
    ln -sf "hypr-settings.json.${ts}" "${BACKUP_DIR}/hypr-settings.json.latest"
  fi
  local qs_manager="${HOME}/.config/hypr/scripts/qs_manager.sh"
  if [[ -f "${qs_manager}" ]]; then
    cp "${qs_manager}" "${BACKUP_DIR}/qs_manager.sh.${ts}"
    ln -sf "qs_manager.sh.${ts}" "${BACKUP_DIR}/qs_manager.sh.latest"
  fi
}

# Hyprland has to source our layer rules or the flyouts get no blur.
# Put this in hyprland.conf — settings_watcher.sh rewrites keybindings.conf
# from settings.json and would wipe anything appended there.
# Do not source arch-shell keybinds.conf while Serpantinum's qs_manager binds
# are still loaded: the same Super+key would fire twice (e.g. close + music).
wire_hypr_includes() {
  local target="${HYPR_CONFIG}"
  if [[ ! -f "${target}" ]]; then
    echo "No Hyprland config found; skipped blur wiring." >&2
    return
  fi

  local added=0
  if ! grep -q 'arch-shell/hyprland/layers.conf' "${target}"; then
    {
      echo ""
      echo "# Arch Shell flyout blur"
      echo "source = ~/.config/arch-shell/hyprland/layers.conf"
    } >> "${target}"
    added=1
  fi

  if ((added)); then
    echo "Wired Arch Shell blur rules into ${target}"
    hyprctl reload >/dev/null 2>&1 || true
  else
    echo "Arch Shell blur rules already wired into ${target}"
  fi
}

guard_qs_manager() {
  local qs_manager="${HOME}/.config/hypr/scripts/qs_manager.sh"
  [[ -f "${qs_manager}" ]] || return 0
  if grep -q 'Arch Shell owns the desktop' "${qs_manager}"; then
    return 0
  fi
  python3 - "${qs_manager}" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
needle = '''ACTION="$1"
TARGET="$2"
SUBTARGET="$3"

if [[ "$ACTION" =~ ^[0-9]+$ ]]; then'''
insert = '''ACTION="$1"
TARGET="$2"
SUBTARGET="$3"

# Arch Shell owns the desktop. Do not IPC into Serpantinum — that call
# blocks, so Super+1 / Super+D looked like dead keybinds.
if [[ -f "${HOME}/.config/arch-shell/enabled.flag" ]]; then
    if [[ "$ACTION" =~ ^[0-9]+$ ]]; then
        CMD="workspace $ACTION"
        [[ "$TARGET" == "move" ]] && CMD="movetoworkspace $ACTION"
        hyprctl --batch "dispatch $CMD" >/dev/null 2>&1
        exit 0
    fi
    if [[ "$ACTION" == "toggle" ]]; then
        case "$TARGET" in
            applauncher|guide) mod="Start" ;;
            clipboard) mod="Clipboard" ;;
            settings) mod="Settings" ;;
            music) mod="DynamicMusic" ;;
            battery) mod="BatteryNotifications" ;;
            wallpaper) mod="Wallpaper" ;;
            calendar) mod="ClockWeather" ;;
            network) mod="NetworkBluetooth" ;;
            volume) mod="Audio" ;;
            movies) mod="GamingMode" ;;
            focustime) mod="AgentCentre" ;;
            *) exit 0 ;;
        esac
        quickshell -p "${HOME}/.config/arch-shell" ipc call arch toggle "$mod" >/dev/null 2>&1
        exit 0
    fi
    exit 0
fi

if [[ "$ACTION" =~ ^[0-9]+$ ]]; then'''
if needle not in text:
    sys.exit(0)
path.write_text(text.replace(needle, insert, 1))
PY
  local reload_sh="${HOME}/.config/hypr/scripts/reload.sh"
  if [[ -f "${reload_sh}" ]] && ! grep -q 'arch-shell/enabled.flag' "${reload_sh}"; then
    cat > "${reload_sh}" <<'EOF'
#!/usr/bin/env bash
if [[ -f "${HOME}/.config/arch-shell/enabled.flag" ]]; then
  hyprctl reload
  exit 0
fi
qs -p ~/.config/hypr/scripts/quickshell/Shell.qml ipc call main forceReload
EOF
    chmod +x "${reload_sh}"
  fi
}

enable_autostart() {
  echo "==> Enabling Arch Shell autostart..."
  mkdir -p "$(dirname "${AUTOSTART_FILE}")" "${CONFIG_DIR}"
  touch "${CONFIG_DIR}/enabled.flag"

  local hypr_settings="${HOME}/.config/hypr/settings.json"
  local arch_cmd="env QT_QUICK_CONTROLS_STYLE=Basic quickshell -p ${CONFIG_DIR}"
  if [[ -f "${hypr_settings}" ]]; then
    python3 "${ROOT}/scripts/patch_hypr_for_arch_shell.py" "${hypr_settings}" "${arch_cmd}"
    python3 "${ROOT}/scripts/patch_hypr_keybinds_arch_shell.py" "${hypr_settings}"
    echo "Pointed ~/.config/hypr/settings.json at Arch Shell (startup, OSD, keybinds)."
  fi

  guard_qs_manager

  # Let the settings watcher rebuild autostart from the patched JSON, then
  # strip any leftover qs_manager line and collapse duplicate Arch Shell entries.
  if [[ -x "${HOME}/.config/hypr/scripts/settings_watcher.sh" ]]; then
    bash "${HOME}/.config/hypr/scripts/settings_watcher.sh" --compile >/dev/null 2>&1 || true
  fi

  if [[ -f "${AUTOSTART_FILE}" ]]; then
    local tmp
    tmp="$(mktemp)"
    grep -vE 'qs_manager.sh|swayosd' "${AUTOSTART_FILE}" | awk '
      /quickshell -p .*arch-shell/ {
        if (seen_arch++) next
      }
      { print }
    ' > "${tmp}"
    if ! grep -q 'quickshell -p .*arch-shell' "${tmp}"; then
      echo "exec-once = ${arch_cmd}" >> "${tmp}"
    fi
    mv "${tmp}" "${AUTOSTART_FILE}"
  else
    echo "exec-once = ${arch_cmd}" > "${AUTOSTART_FILE}"
  fi

  # Already-running Serpantinum keeps its bar until killed. Autostart only
  # applies on the next login.
  pkill -f 'quickshell -p .*/hypr/scripts/quickshell/Shell.qml' >/dev/null 2>&1 || true
  pkill -x swayosd-server >/dev/null 2>&1 || true
  pkill -x swayosd-client >/dev/null 2>&1 || true

  echo "Autostart updated and the running Serpantinum shell was stopped."
  echo "Serpantinum files were not deleted. Roll back with: ./install.sh --rollback"
}

rollback_autostart() {
  rm -f "${CONFIG_DIR}/enabled.flag"
  if [[ -L "${BACKUP_DIR}/autostart.conf.latest" ]] || [[ -f "${BACKUP_DIR}/autostart.conf.latest" ]]; then
    cp "${BACKUP_DIR}/autostart.conf.latest" "${AUTOSTART_FILE}"
    echo "Restored autostart from backup."
  else
    echo "No backup found at ${BACKUP_DIR}/autostart.conf.latest" >&2
    exit 1
  fi
  if [[ -L "${BACKUP_DIR}/keybindings.conf.latest" ]] || [[ -f "${BACKUP_DIR}/keybindings.conf.latest" ]]; then
    cp "${BACKUP_DIR}/keybindings.conf.latest" "${HOME}/.config/hypr/config/keybindings.conf"
    echo "Restored Hyprland keybindings from backup."
  fi
  if [[ -L "${BACKUP_DIR}/hypr-settings.json.latest" ]] || [[ -f "${BACKUP_DIR}/hypr-settings.json.latest" ]]; then
    cp "${BACKUP_DIR}/hypr-settings.json.latest" "${HOME}/.config/hypr/settings.json"
    echo "Restored Hyprland settings.json from backup."
  fi
  if [[ -L "${BACKUP_DIR}/qs_manager.sh.latest" ]] || [[ -f "${BACKUP_DIR}/qs_manager.sh.latest" ]]; then
    cp "${BACKUP_DIR}/qs_manager.sh.latest" "${HOME}/.config/hypr/scripts/qs_manager.sh"
    echo "Restored qs_manager.sh from backup."
  fi
  rollback_sddm_theme
}

# Replace the stock/matugen SDDM greeter with the Arch Shell Fluent theme
# and keep a world-readable copy of the live wallpaper for the greeter user.
install_sddm_theme() {
  echo "==> Installing Arch Shell login theme..."
  mkdir -p "${BACKUP_DIR}"

  local wall=""
  if [[ -f "${CONFIG_DIR}/wallpaper.path" ]]; then
    wall="$(<"${CONFIG_DIR}/wallpaper.path")"
  elif [[ -f "${HOME}/.cache/quickshell/wallpaper_picker/current_wallpaper.png" ]]; then
    wall="${HOME}/.cache/quickshell/wallpaper_picker/current_wallpaper.png"
  fi
  if [[ -n "${wall}" && -f "${wall}" ]]; then
    bash "${ROOT}/scripts/sync-sddm.sh" "${wall}" || true
  else
    bash "${ROOT}/scripts/sync-sddm.sh" || true
  fi

  local helper="${ROOT}/scripts/install-sddm-root.sh"
  chmod +x "${helper}"
  local -a args=("${helper}" "${ROOT}" "${HOME}" "${BACKUP_DIR}")
  [[ -n "${wall}" && -f "${wall}" ]] && args+=("${wall}")

  if sudo -n true >/dev/null 2>&1; then
    sudo "${args[@]}"
  elif command -v pkexec >/dev/null; then
    echo "Authentication required to replace the SDDM login theme."
    pkexec "${args[@]}"
  else
    echo "Need root to install the login theme. Re-run with sudo." >&2
    sudo "${args[@]}"
  fi
}

rollback_sddm_theme() {
  local conf="/etc/sddm.conf.d/10-arch-shell.conf"
  local old="/etc/sddm.conf.d/10-wayland-matugen.conf"
  if [[ -f "${BACKUP_DIR}/10-wayland-matugen.conf" ]]; then
    if sudo -n true >/dev/null 2>&1; then
      sudo cp "${BACKUP_DIR}/10-wayland-matugen.conf" "${old}"
      sudo rm -f "${conf}"
    elif command -v pkexec >/dev/null; then
      pkexec bash -c "cp '$BACKUP_DIR/10-wayland-matugen.conf' '$old' && rm -f '$conf'"
    else
      sudo cp "${BACKUP_DIR}/10-wayland-matugen.conf" "${old}"
      sudo rm -f "${conf}"
    fi
    echo "Restored previous SDDM theme."
  fi
}

# Fluent GRUB theme using the same wallpaper / accent / mica as SDDM.
install_grub_theme() {
  echo "==> Installing Arch Shell GRUB theme..."
  mkdir -p "${BACKUP_DIR}" "${CONFIG_DIR}/grub-theme"
  bash "${ROOT}/scripts/render-grub-theme.sh" "${CONFIG_DIR}/grub-theme" || {
    echo "Could not render the GRUB theme." >&2
    return 1
  }
  local helper="${ROOT}/scripts/install-grub-root.sh"
  chmod +x "${helper}" "${ROOT}/scripts/render-grub-theme.sh"
  local -a args=("${helper}" "${CONFIG_DIR}/grub-theme" "" "${BACKUP_DIR}")
  if sudo -n true >/dev/null 2>&1; then
    sudo "${args[@]}"
  elif command -v pkexec >/dev/null; then
    echo "Authentication required to install the GRUB theme."
    pkexec "${args[@]}"
  else
    echo "Need root to install the GRUB theme. Re-run with sudo." >&2
    sudo "${args[@]}"
  fi
}

case "${1:-}" in
  --enable)
    install_packages
    copy_configs
    backup_hypr
    wire_hypr_includes
    install_sddm_theme
    install_grub_theme
    enable_autostart
    ;;
  --rollback)
    rollback_autostart
    ;;
  *)
    install_packages
    copy_configs
    backup_hypr
    wire_hypr_includes
    install_sddm_theme
    install_grub_theme
    echo ""
    echo "Done (safe mode). Your existing desktop autostart was NOT changed."
    echo "Test with: ./test-shell.sh"
    echo "Switch when ready: ./install.sh --enable"
    ;;
esac
