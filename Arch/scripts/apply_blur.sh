#!/usr/bin/env bash
# Acrylic blur for Arch Shell layers (Hyprland 0.56 named layerrules)
set -u
CONF="${HOME}/.config/arch-shell/hyprland/layers.conf"
if [[ -f "${CONF}" ]]; then
  hyprctl keyword source "${CONF}" >/dev/null 2>&1 || true
fi
hyprctl keyword 'layerrule[arch-shell-bar-blur]:match:namespace' '^(arch-shell-bar)$' >/dev/null 2>&1 || true
hyprctl keyword 'layerrule[arch-shell-bar-blur]:blur' on >/dev/null 2>&1 || true
hyprctl keyword 'layerrule[arch-shell-bar-blur]:ignore_alpha' 0.05 >/dev/null 2>&1 || true
hyprctl keyword 'layerrule[arch-shell-bar-blur]:no_anim' on >/dev/null 2>&1 || true
hyprctl keyword 'layerrule[arch-shell-popup-blur]:match:namespace' '^(arch-shell-popup)$' >/dev/null 2>&1 || true
hyprctl keyword 'layerrule[arch-shell-popup-blur]:blur' on >/dev/null 2>&1 || true
hyprctl keyword 'layerrule[arch-shell-popup-blur]:ignore_alpha' 0.05 >/dev/null 2>&1 || true
hyprctl keyword 'layerrule[arch-shell-popup-blur]:no_anim' on >/dev/null 2>&1 || true
hyprctl keyword 'layerrule[arch-shell-notif-blur]:match:namespace' '^(arch-shell-notif)$' >/dev/null 2>&1 || true
hyprctl keyword 'layerrule[arch-shell-notif-blur]:blur' on >/dev/null 2>&1 || true
hyprctl keyword 'layerrule[arch-shell-notif-blur]:ignore_alpha' 0.05 >/dev/null 2>&1 || true
hyprctl keyword 'layerrule[arch-shell-notif-blur]:no_anim' on >/dev/null 2>&1 || true
exit 0
