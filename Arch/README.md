# Arch Shell

Custom Windows 11-style desktop shell for Arch Linux + Hyprland, built with Quickshell.

## Sprint 5 — Agent Centre

- **Agent Centre** module — teams, agents, per-agent task input, live activity log
- Backend is a stdlib-only Python daemon (`agent-centre/daemon/arch_agentd.py`) exposed as
  the `arch-agentd` systemd user service; the popup can start/stop/enable it
- **Providers** tab stores OpenAI / Anthropic / Google keys in `providers.json` (mode 600)
- Agents ask before acting: permission requests surface in the popup and via `notify-send`

```bash
systemctl --user enable --now arch-agentd     # or use the button in the popup
```

## Fluent theme

- Translucent mica taskbar and flyouts, Hyprland blur behind every layer
- Everything is driven by `shell/theme/ArchTheme.qml` (colours, radii, type scale) and
  `shell/theme/Icons.qml` (Nerd Font glyphs)
- **Settings → Appearance** — accent, transparency, glass tint, bar position, bar height,
  desktop count, temperature unit
- **Settings → Taskbar** — add, remove and reorder modules across the left / centre / right
  zones

## Sprint 4 — daily driver

- **Quick Settings** — Wi‑Fi, Bluetooth, night light, do-not-disturb, brightness, power profile, screen record
- **Clipboard history** — Super + V (needs cliphist, already in your autostart)
- **Quick notes**, **calculator**, **colour picker**, **wallpaper**, **updates**, **gaming mode**, **task view**
- **Settings → Keybinds** — click a row, press new keys, save
- **Start menu** is an overlay (does not push windows aside)
- **Escape** closes any popup

To switch from Serpantinum (only when you are ready):

```bash
./install.sh --enable    # backup + autostart Arch Shell
./install.sh --rollback  # restore Serpantinum autostart
```

## Sprint 3 features

- Audio, Network, Music (album art + 10-band EQ), Battery, Clock & weather popup

## Quick start (safe — does not replace Serpantinum)

```bash
./install.sh
./test-shell.sh     # Ctrl+C to stop
```

`./install.sh` appends two `source` lines to your Hyprland config (in
`~/.config/hypr/config/keybindings.conf`, falling back to `hyprland.conf`) and
backs the file up first:

- `~/.config/arch-shell/hyprland/keybinds.conf` — without this Hyprland never
  sees the shell shortcuts, so no keybind fires
- `~/.config/arch-shell/hyprland/layers.conf` — the blur rules for the taskbar
  and flyouts. Runtime `hyprctl keyword` rules are wiped by any config reload,
  so they have to live in the config to survive

Undo both with `./install.sh --rollback`.

## Agent Centre

The Agent Centre talks to a local user service (`arch-agentd`). Opening the
flyout starts it if it is not already running; nothing can be created while it
is stopped. To have it start with your session:

```bash
systemctl --user enable --now arch-agentd
```

## Project layout

- `shell/` — Quickshell QML (taskbar, modules, theme)
- `scripts/` — backend helpers
- `config/` — default settings and keybinds
- `agent-centre/` — Agent Centre (Sprint 5)
