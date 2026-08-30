# Arch Shell

Custom Windows 11-style desktop shell for Arch Linux + Hyprland, built with Quickshell.

This folder is the shell source. The one-shot installers that recreate a full
desktop live in the GitHub snapshots:

- Public (no Finance): https://github.com/nplata24s/arch-shell
- Private (with Finance): https://github.com/nplata24s/arch-desktop

## Local test (this machine)

```bash
./install.sh            # deps + copy to ~/.config/arch-shell (does not replace autostart)
./test-shell.sh         # Ctrl+C to stop
./install.sh --enable   # switch Hyprland autostart to Arch Shell
./install.sh --rollback # restore the previous autostart
```

## Layout

- `shell/` — Quickshell QML (taskbar, modules, theme)
- `scripts/` — backend helpers (audio, network, Agent Centre CLIs, …)
- `config/` — default settings and keybinds
- `agent-centre/` — Agent Centre daemon
- `sddm/` / `grub/` — login and boot themes
- `packaging/` — files copied into the GitHub snapshot repos
