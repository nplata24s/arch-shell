#!/usr/bin/env bash
# Install this desktop on a fresh Arch Linux install.
# Run as your normal user (not root):  ./install.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCH_ROOT="${ROOT}/Arch"
CONFIG_DIR="${HOME}/.config/arch-shell"
HYPR_DIR="${HOME}/.config/hypr"
BACKUP_DIR="${CONFIG_DIR}/backup"

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

need_arch() {
  [[ -f /etc/arch-release ]] || die "This installer is for Arch Linux."
}

need_user() {
  [[ "$(id -u)" -ne 0 ]] || die "Run as your user, not root. The script will sudo when it needs to."
  command -v sudo >/dev/null || die "Install sudo and add this user to the wheel group first."
  sudo -v || die "sudo failed. Add your user to wheel and try again."
}

read_pkgs() {
  local file="$1"
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    printf '%s\n' "$line"
  done < "$file"
}

install_pacman() {
  log "Updating pacman and installing official packages..."
  sudo pacman -Syu --needed --noconfirm
  mapfile -t pkgs < <(read_pkgs "${ROOT}/packages/pacman.txt")
  sudo pacman -S --needed --noconfirm "${pkgs[@]}"
}

bootstrap_yay() {
  if command -v yay >/dev/null 2>&1; then
    return 0
  fi
  log "Installing yay (AUR helper)..."
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
  (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
}

install_aur() {
  bootstrap_yay
  log "Installing AUR packages (quickshell-git compiles — this can take a while)..."
  local pkgs=()
  local p
  while IFS= read -r p; do
    [[ "$p" == "yay-bin" ]] && command -v yay >/dev/null && continue
    pkgs+=("$p")
  done < <(read_pkgs "${ROOT}/packages/aur.txt")
  if ((${#pkgs[@]})); then
    yay -S --needed --noconfirm "${pkgs[@]}"
  fi
  command -v quickshell >/dev/null || die "quickshell did not install. Check the yay output above."
}

enable_services() {
  log "Enabling system services..."
  sudo systemctl enable NetworkManager.service
  sudo systemctl enable bluetooth.service
  sudo systemctl enable sddm.service
  sudo systemctl enable power-profiles-daemon.service
  sudo systemctl disable gdm.service lightdm.service ly.service greetd.service 2>/dev/null || true

  systemctl --user enable pipewire.socket pipewire-pulse.socket wireplumber.service 2>/dev/null || true
  systemctl --user enable hyprpolkitagent.service 2>/dev/null || true
  if systemctl list-unit-files ollama.service >/dev/null 2>&1; then
    sudo systemctl enable ollama.service
  fi
}

copy_shell() {
  log "Installing Arch Shell (taskbar, modules, widgets)..."
  mkdir -p "${CONFIG_DIR}/hyprland" "${CONFIG_DIR}/scripts" "${CONFIG_DIR}/agent-daemon" "${BACKUP_DIR}"
  rm -f "${CONFIG_DIR}"/*.qml "${CONFIG_DIR}"/theme/*.qml
  cp -a "${ARCH_ROOT}/shell/." "${CONFIG_DIR}/"
  cp -a "${ARCH_ROOT}/scripts/." "${CONFIG_DIR}/scripts/"
  cp -f "${ARCH_ROOT}/config/hyprland/layers.conf" "${CONFIG_DIR}/hyprland/layers.conf"
  cp -f "${ARCH_ROOT}/agent-centre/daemon/"*.py "${CONFIG_DIR}/agent-daemon/"
  chmod +x "${CONFIG_DIR}/agent-daemon/"*.py
  chmod +x "${CONFIG_DIR}/scripts/"*.sh 2>/dev/null || true
  chmod +x "${CONFIG_DIR}/scripts/"*.py 2>/dev/null || true
  if [[ -x "${ARCH_ROOT}/scripts/install-login-clis.sh" ]]; then
    log "Installing Agent Centre login CLIs (agy, Codex, Claude, gh, Ollama)..."
    bash "${ARCH_ROOT}/scripts/install-login-clis.sh" || true
  fi

  mkdir -p "${HOME}/.config/systemd/user"
  cp -f "${ARCH_ROOT}/agent-centre/daemon/systemd/arch-agentd.service" \
     "${HOME}/.config/systemd/user/arch-agentd.service"
  systemctl --user daemon-reload >/dev/null 2>&1 || true

  cp -f "${ARCH_ROOT}/config/settings.json" "${CONFIG_DIR}/settings.json"
  cp -f "${ARCH_ROOT}/config/keybinds.json" "${CONFIG_DIR}/keybinds.json"
  touch "${CONFIG_DIR}/notes.txt"
  touch "${CONFIG_DIR}/enabled.flag"

  bash "${ARCH_ROOT}/scripts/gen-hypr-binds.sh" \
    "${CONFIG_DIR}/keybinds.json" \
    "${CONFIG_DIR}/hyprland/keybinds.conf" \
    "~/.config/arch-shell" || true
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
  cp -f "${ROOT}/hyprland/hyprland.conf" "${HYPR_DIR}/hyprland.conf"
  cp -f "${ROOT}/hyprland/colors.conf" "${HYPR_DIR}/colors.conf"
  cp -f "${ROOT}/hyprland/hypridle.conf" "${HYPR_DIR}/hypridle.conf"
  cp -a "${ROOT}/hyprland/config/." "${HYPR_DIR}/config/"
  cp -a "${ROOT}/hyprland/scripts/." "${HYPR_DIR}/scripts/"
  chmod +x "${HYPR_DIR}/scripts/"*.sh

  local wall="${HOME}/.config/arch-shell/wallpaper"
  sed "s|WALLPAPER_PATH|${wall}|" "${ROOT}/hyprland/hyprlock.conf" > "${HYPR_DIR}/hyprlock.conf"
}

copy_extras() {
  log "Installing wallpaper, fonts, GTK, Kitty..."
  xdg-user-dirs-update >/dev/null 2>&1 || true
  mkdir -p "${HOME}/Pictures/Wallpapers" \
           "${HOME}/.config/gtk-3.0" \
           "${HOME}/.config/gtk-4.0" \
           "${HOME}/.config/qt6ct" \
           "${HOME}/.config/kitty" \
           "${HOME}/.cache/quickshell/wallpaper_picker"

  cp -f "${ROOT}/extras/wallpaper.jpg" "${HOME}/Pictures/Wallpapers/default.jpg"
  cp -f "${ROOT}/extras/wallpaper.jpg" "${CONFIG_DIR}/wallpaper"
  printf '%s\n' "${HOME}/Pictures/Wallpapers/default.jpg" > "${CONFIG_DIR}/wallpaper.path"
  cp -f "${ROOT}/extras/wallpaper.jpg" "${HOME}/.cache/quickshell/wallpaper_picker/current_wallpaper.png"

  cp -f "${ROOT}/extras/gtk-3.0/settings.ini" "${HOME}/.config/gtk-3.0/settings.ini"
  cp -f "${ROOT}/extras/gtk-4.0/settings.ini" "${HOME}/.config/gtk-4.0/settings.ini"
  cp -f "${ROOT}/extras/qt6ct/qt6ct.conf" "${HOME}/.config/qt6ct/qt6ct.conf"
  cp -f "${ROOT}/extras/kitty/kitty.conf" "${HOME}/.config/kitty/kitty.conf"
}

install_sddm() {
  log "Installing Arch Shell login screen..."
  mkdir -p "${BACKUP_DIR}"
  bash "${ARCH_ROOT}/scripts/sync-sddm.sh" "${CONFIG_DIR}/wallpaper" || true
  local helper="${ARCH_ROOT}/scripts/install-sddm-root.sh"
  chmod +x "$helper"
  sudo "$helper" "${ARCH_ROOT}" "${HOME}" "${BACKUP_DIR}" "${CONFIG_DIR}/wallpaper"
}

install_grub() {
  if [[ ! -x "${ARCH_ROOT}/scripts/install-grub.sh" ]]; then
    return 0
  fi
  if ! command -v grub-mkconfig >/dev/null 2>&1; then
    log "Skipping GRUB theme (grub is not installed — systemd-boot is fine)."
    return 0
  fi
  log "Installing Arch Shell GRUB theme..."
  bash "${ARCH_ROOT}/scripts/install-grub.sh" || {
    echo "GRUB theme install failed. The desktop still works; you can retry later with:"
    echo "  ~/.config/arch-shell/scripts/install-grub.sh"
  }
}

usage() {
  cat <<'EOF'
Install Hyprland, SDDM, and Arch Shell (taskbar and widgets).

Usage:
  ./install.sh           Install everything
  ./install.sh --help    Show this help

Run as a normal user with sudo. After it finishes, reboot and log in
through SDDM (session: Hyprland).

Finance is not part of this public repo.
EOF
}

main() {
  case "${1:-}" in
    -h|--help) usage; exit 0 ;;
  esac
  need_arch
  need_user
  install_pacman
  install_aur
  copy_shell
  copy_hypr
  copy_extras
  install_sddm
  install_grub
  enable_services

  echo
  echo "Done. Reboot, then pick Hyprland on the login screen."
}

main "$@"
