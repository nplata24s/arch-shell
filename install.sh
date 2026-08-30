#!/usr/bin/env bash
# Install Hyprland + Arch Shell on a fresh Arch Linux system.
# Run as your normal user (not root):  ./install.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCH_ROOT="${ROOT}/Arch"
CONFIG_DIR="${HOME}/.config/arch-shell"
HYPR_DIR="${HOME}/.config/hypr"
BACKUP_DIR="${CONFIG_DIR}/backup"
FINANCE_DIR="${HOME}/.local/share/finance-portal"
INCLUDE_FINANCE=0
if [[ -d "${ROOT}/finance" && -f "${ROOT}/finance/package.json" ]]; then
  INCLUDE_FINANCE=1
fi

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }
warn() { echo "warning: $*" >&2; }

need_arch() {
  [[ -f /etc/arch-release ]] || die "This installer is for Arch Linux."
}

need_user() {
  [[ "$(id -u)" -ne 0 ]] || die "Run as your user, not root. The script will sudo when it needs to."
  command -v sudo >/dev/null || die "Install sudo and add this user to the wheel group first."
  sudo -v || die "sudo failed. Add your user to wheel and try again."
}

need_network() {
  if ping -c 1 -W 4 archlinux.org >/dev/null 2>&1; then
    return 0
  fi
  if ping -c 1 -W 4 1.1.1.1 >/dev/null 2>&1; then
    warn "DNS may be broken (archlinux.org did not resolve). Continuing."
    return 0
  fi
  die "No network. Connect Ethernet or Wi-Fi, then re-run."
}

read_pkgs() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    printf '%s\n' "$line"
  done < "$file"
}

# Resolve names that exist in the synced repos. Skip anything else instead of
# aborting the whole pacman transaction (that is what broke the last installer).
resolve_official() {
  local pkg
  while IFS= read -r pkg || [[ -n "$pkg" ]]; do
    [[ -z "$pkg" ]] && continue
    if pacman -Si "$pkg" >/dev/null 2>&1; then
      printf '%s\n' "$pkg"
    else
      warn "not in the official repos, skipping: $pkg"
    fi
  done
}

install_pacman() {
  log "Refreshing keyring and system..."
  sudo pacman -Sy --needed --noconfirm archlinux-keyring
  sudo pacman -Syu --needed --noconfirm

  local -a pkgs=()
  mapfile -t pkgs < <({
    read_pkgs "${ROOT}/packages/pacman.txt"
    if [[ "${INCLUDE_FINANCE}" == "1" ]]; then
      read_pkgs "${ROOT}/packages/pacman-finance.txt"
    fi
  } | resolve_official)

  ((${#pkgs[@]})) || die "No official packages could be resolved. Check packages/pacman.txt."

  log "Installing ${#pkgs[@]} official packages..."
  sudo pacman -S --needed --noconfirm "${pkgs[@]}"
}

bootstrap_yay() {
  command -v yay >/dev/null 2>&1 && return 0
  log "Installing yay (AUR helper)..."
  local tmp
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN
  git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
  (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
}

ensure_quickshell() {
  if command -v quickshell >/dev/null 2>&1; then
    return 0
  fi
  warn "official quickshell is missing; trying AUR quickshell-git"
  bootstrap_yay
  yay -S --needed --noconfirm quickshell-git
  command -v quickshell >/dev/null || die "quickshell did not install."
}

enable_services() {
  log "Enabling system services..."
  sudo systemctl enable NetworkManager.service
  sudo systemctl enable bluetooth.service
  sudo systemctl enable sddm.service
  sudo systemctl set-default graphical.target
  sudo systemctl enable power-profiles-daemon.service 2>/dev/null || true
  sudo systemctl disable gdm.service lightdm.service ly.service greetd.service 2>/dev/null || true

  systemctl --user enable pipewire.socket pipewire-pulse.socket wireplumber.service 2>/dev/null || true
  systemctl --user enable hyprpolkitagent.service 2>/dev/null || true
  if systemctl list-unit-files --all ollama.service >/dev/null 2>&1; then
    sudo systemctl enable ollama.service 2>/dev/null || true
  fi
}

copy_shell() {
  log "Installing Arch Shell (taskbar, modules, widgets)..."
  [[ -f "${ARCH_ROOT}/shell/shell.qml" ]] || die "Arch/shell/shell.qml missing — incomplete clone."
  mkdir -p "${CONFIG_DIR}/hyprland" "${CONFIG_DIR}/scripts" "${CONFIG_DIR}/agent-daemon" "${BACKUP_DIR}"
  rm -f "${CONFIG_DIR}"/*.qml "${CONFIG_DIR}"/theme/*.qml
  cp -a "${ARCH_ROOT}/shell/." "${CONFIG_DIR}/"
  cp -a "${ARCH_ROOT}/scripts/." "${CONFIG_DIR}/scripts/"
  cp -f "${ARCH_ROOT}/config/hyprland/layers.conf" "${CONFIG_DIR}/hyprland/layers.conf"
  if [[ "${INCLUDE_FINANCE}" == "1" ]]; then
    if [[ -f "${ARCH_ROOT}/config/hyprland/finance-portal.conf" ]]; then
      cp -f "${ARCH_ROOT}/config/hyprland/finance-portal.conf" "${CONFIG_DIR}/hyprland/finance-portal.conf"
    elif [[ -f "${ROOT}/hyprland/finance-portal.conf" ]]; then
      cp -f "${ROOT}/hyprland/finance-portal.conf" "${CONFIG_DIR}/hyprland/finance-portal.conf"
    fi
  fi
  cp -f "${ARCH_ROOT}/agent-centre/daemon/"*.py "${CONFIG_DIR}/agent-daemon/"
  chmod +x "${CONFIG_DIR}/agent-daemon/"*.py
  find "${CONFIG_DIR}/scripts" -maxdepth 1 -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod +x {} +

  mkdir -p "${HOME}/.config/systemd/user"
  cp -f "${ARCH_ROOT}/agent-centre/daemon/systemd/arch-agentd.service" \
     "${HOME}/.config/systemd/user/arch-agentd.service"
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user enable arch-agentd.service >/dev/null 2>&1 || true

  cp -f "${ARCH_ROOT}/config/settings.json" "${CONFIG_DIR}/settings.json"
  cp -f "${ARCH_ROOT}/config/keybinds.json" "${CONFIG_DIR}/keybinds.json"
  touch "${CONFIG_DIR}/notes.txt"
  touch "${CONFIG_DIR}/enabled.flag"

  bash "${ARCH_ROOT}/scripts/gen-hypr-binds.sh" \
    "${CONFIG_DIR}/keybinds.json" \
    "${CONFIG_DIR}/hyprland/keybinds.conf" \
    "~/.config/arch-shell"
}

copy_hypr() {
  log "Installing Hyprland config..."
  if [[ -d "${HYPR_DIR}" ]]; then
    local ts
    ts="$(date +%Y%m%d-%H%M%S)"
    mkdir -p "${BACKUP_DIR}"
    cp -a "${HYPR_DIR}" "${BACKUP_DIR}/hypr.${ts}"
    echo "Backed up existing Hyprland config to ${BACKUP_DIR}/hypr.${ts}"
  fi
  mkdir -p "${HYPR_DIR}/config" "${HYPR_DIR}/scripts"
  if [[ "${INCLUDE_FINANCE}" == "1" && -f "${ROOT}/hyprland/hyprland-private.conf" ]]; then
    cp -f "${ROOT}/hyprland/hyprland-private.conf" "${HYPR_DIR}/hyprland.conf"
  else
    cp -f "${ROOT}/hyprland/hyprland.conf" "${HYPR_DIR}/hyprland.conf"
  fi
  cp -f "${ROOT}/hyprland/colors.conf" "${HYPR_DIR}/colors.conf"
  cp -f "${ROOT}/hyprland/hypridle.conf" "${HYPR_DIR}/hypridle.conf"
  cp -a "${ROOT}/hyprland/config/." "${HYPR_DIR}/config/"
  cp -a "${ROOT}/hyprland/scripts/." "${HYPR_DIR}/scripts/"
  chmod +x "${HYPR_DIR}/scripts/"*.sh

  local wall="${HOME}/.config/arch-shell/wallpaper"
  sed "s|WALLPAPER_PATH|${wall}|" "${ROOT}/hyprland/hyprlock.conf" > "${HYPR_DIR}/hyprlock.conf"
  apply_vm_hypr
}

apply_vm_hypr() {
  local virt=""
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    virt="$(systemd-detect-virt 2>/dev/null || true)"
  fi
  case "$virt" in
    none|"") return 0 ;;
  esac
  log "VM detected ($virt) — applying Hyprland + boot workarounds..."
  cat > "${HYPR_DIR}/config/vm.conf" <<'EOF'
# Auto-filled because systemd-detect-virt reported a VM.
# VirtualBox: VMSVGA, 128 MB video, 4 GB RAM, 3D acceleration OFF, nomodeset.
env = AQ_NO_MODIFIERS,1
env = WLR_NO_HARDWARE_CURSORS,1
env = LIBGL_ALWAYS_SOFTWARE,1
env = GALLIUM_DRIVER,llvmpipe

cursor {
    no_hardware_cursors = true
}
EOF
  if [[ "$virt" == "oracle" ]] && pacman -Si virtualbox-guest-utils >/dev/null 2>&1; then
    sudo pacman -S --needed --noconfirm virtualbox-guest-utils || \
      warn "could not install virtualbox-guest-utils"
    sudo systemctl enable vboxservice.service 2>/dev/null || true
  fi
}

apply_vm_boot() {
  local helper="${ARCH_ROOT}/scripts/apply-vm-boot.py"
  [[ -f "$helper" ]] || return 0
  command -v systemd-detect-virt >/dev/null 2>&1 || return 0
  local virt
  virt="$(systemd-detect-virt 2>/dev/null || true)"
  # nomodeset is the VirtualBox ramdisk hang workaround. Other hypervisors skip it.
  [[ "$virt" == "oracle" ]] || return 0
  log "VirtualBox detected — adding nomodeset so GRUB gets past the ramdisk..."
  sudo python3 "$helper" || warn "could not persist nomodeset; add it in GRUB (e on the linux line)"
}

copy_extras() {
  log "Installing wallpaper, GTK, Kitty..."
  xdg-user-dirs-update >/dev/null 2>&1 || true
  mkdir -p "${HOME}/Pictures/Wallpapers" \
           "${HOME}/.config/gtk-3.0" \
           "${HOME}/.config/gtk-4.0" \
           "${HOME}/.config/qt6ct" \
           "${HOME}/.config/kitty" \
           "${HOME}/.cache/quickshell/wallpaper_picker"

  local wall_src="${ROOT}/extras/wallpaper.jpg"
  [[ -f "$wall_src" ]] || die "extras/wallpaper.jpg is missing."
  cp -f "$wall_src" "${HOME}/Pictures/Wallpapers/default.jpg"
  cp -f "$wall_src" "${CONFIG_DIR}/wallpaper"
  printf '%s\n' "${HOME}/Pictures/Wallpapers/default.jpg" > "${CONFIG_DIR}/wallpaper.path"
  cp -f "$wall_src" "${HOME}/.cache/quickshell/wallpaper_picker/current_wallpaper.png"

  cp -f "${ROOT}/extras/gtk-3.0/settings.ini" "${HOME}/.config/gtk-3.0/settings.ini"
  cp -f "${ROOT}/extras/gtk-4.0/settings.ini" "${HOME}/.config/gtk-4.0/settings.ini"
  cp -f "${ROOT}/extras/qt6ct/qt6ct.conf" "${HOME}/.config/qt6ct/qt6ct.conf"
  cp -f "${ROOT}/extras/kitty/kitty.conf" "${HOME}/.config/kitty/kitty.conf"
}

install_sddm() {
  log "Installing Arch Shell login screen..."
  mkdir -p "${BACKUP_DIR}"
  bash "${ARCH_ROOT}/scripts/sync-sddm.sh" "${CONFIG_DIR}/wallpaper" || warn "could not sync SDDM wallpaper"
  local helper="${ARCH_ROOT}/scripts/install-sddm-root.sh"
  chmod +x "$helper"
  if sudo "$helper" "${ARCH_ROOT}" "${HOME}" "${BACKUP_DIR}" "${CONFIG_DIR}/wallpaper"; then
    return 0
  fi
  warn "SDDM theme install failed. You can still log in with the default greeter."
}

install_grub() {
  if ! command -v grub-mkconfig >/dev/null 2>&1; then
    log "Skipping GRUB theme (grub is not installed — systemd-boot is fine)."
    return 0
  fi
  log "Installing Arch Shell GRUB theme..."
  chmod +x "${ARCH_ROOT}/scripts/install-grub.sh" "${ARCH_ROOT}/scripts/render-grub-theme.sh" \
           "${ARCH_ROOT}/scripts/install-grub-root.sh"
  bash "${ARCH_ROOT}/scripts/install-grub.sh" || \
    warn "GRUB theme failed. The desktop still works; retry with ~/.config/arch-shell/scripts/install-grub.sh"
}

install_finance() {
  [[ "${INCLUDE_FINANCE}" == "1" ]] || return 0
  log "Installing Finance desktop app..."
  command -v npm >/dev/null || die "npm is required for Finance."
  mkdir -p "${FINANCE_DIR}"
  cp -a "${ROOT}/finance/." "${FINANCE_DIR}/"
  rm -rf "${FINANCE_DIR}/node_modules" "${FINANCE_DIR}/ui/dist"
  chmod +x "${FINANCE_DIR}/launch.sh"
  (
    cd "${FINANCE_DIR}"
    if [[ -f package-lock.json ]]; then
      npm ci --omit=optional
    else
      npm install --omit=optional
    fi
    npm run build
  )

  local apps="${HOME}/.local/share/applications"
  mkdir -p "$apps"
  cat > "${apps}/finance-portal.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Finance
Comment=Payday envelope budget
Exec=${FINANCE_DIR}/launch.sh
Icon=${FINANCE_DIR}/assets/icon.png
Terminal=false
Categories=Office;Finance;
StartupWMClass=finance-portal
Keywords=budget;pots;money;
EOF
  chmod +x "${apps}/finance-portal.desktop"
  update-desktop-database "$apps" >/dev/null 2>&1 || true
}

install_login_clis() {
  local helper="${ARCH_ROOT}/scripts/install-login-clis.sh"
  [[ -x "$helper" || -f "$helper" ]] || return 0
  chmod +x "$helper"
  log "Installing Agent Centre login CLIs (agy, Codex, Claude, gh, Ollama)..."
  bash "$helper" || warn "one or more login CLIs failed — re-run $helper later"
}

usage() {
  cat <<EOF
Install Hyprland, SDDM, and Arch Shell (taskbar and widgets).

Usage:
  ./install.sh           Install everything
  ./install.sh --help    Show this help

Run as a normal user with sudo. After it finishes, reboot and log in
through SDDM (session: Hyprland).

$(if [[ "${INCLUDE_FINANCE}" == "1" ]]; then
    echo "This build includes Finance."
  else
    echo "Finance is not part of this public repo."
  fi)
EOF
}

main() {
  case "${1:-}" in
    -h|--help) usage; exit 0 ;;
  esac
  [[ -d "${ARCH_ROOT}" ]] || die "Arch/ is missing. Clone the full repository."
  need_arch
  need_user
  need_network
  install_pacman
  ensure_quickshell
  copy_shell
  copy_hypr
  copy_extras
  install_sddm
  install_grub
  apply_vm_boot
  install_finance
  install_login_clis
  enable_services

  echo
  echo "Done. Reboot, then pick Hyprland on the login screen."
  echo "Keyboard layout defaults to gb. Edit ~/.config/hypr/config/settings.conf to change it."
  if [[ "${INCLUDE_FINANCE}" == "1" ]]; then
    echo "Finance is in the Start menu. First launch: paste the desktop"
    echo "portal key from the Google Sheet menu  Finance bot → 4."
  fi
}

main "$@"
