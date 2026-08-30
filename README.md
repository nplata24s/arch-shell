# Arch Shell

Public Windows 11-style desktop for **Arch Linux + Hyprland**: taskbar, flyouts, Agent Centre, SDDM login theme, and optional GRUB theme.

Telegram, Discord, Spotify, Edge, Cursor, and similar apps are **not** included. The installer only adds what the shell needs, plus Firefox, Kitty, and Nautilus because the keybinds open them.

The private desktop (includes Finance) is **[arch-desktop](https://github.com/nplata24s/arch-desktop)**.

---

## Prerequisites

You need:

- A 64-bit PC or VM (x86_64)
- At least **20 GB** of disk (40 GB is more comfortable)
- An internet connection during install
- A user account that can use `sudo` (wheel group)
- About 5–15 minutes the first time (all packages are official; no AUR compile)

**Graphics**

The package list includes Intel video packages (`vulkan-intel`, `intel-media-driver`). They install on AMD and NVIDIA machines too and are unused there.

- **Intel** — leave the list as-is
- **AMD** — after the first login you can also install `vulkan-radeon` and `libva-mesa-driver`
- **NVIDIA** — Hyprland on proprietary drivers needs extra work (`nvidia-dkms`, kernel parameters). Prefer the open `nvidia-open` stack on Turing and newer, or use Intel/AMD first

**Not in this repo (on purpose)**

- API keys and Agent Centre provider keys (`~/.config/arch-shell/agent/providers.json` is created on the machine)
- Any Finance / spreadsheet / Telegram code

---

## 1. Virtual machine — from the first terminal

Use this when you open a VM and land in a shell. Two common cases: the VM is still the **Arch live ISO**, or Arch is **already installed**.

### If the VM window is the Arch live ISO (`root@archiso`)

Network is usually already up (NAT). Check it, then install Arch:

```bash
ping -c 3 archlinux.org
```

If that fails, wait a few seconds and try again. On a bridged/Wi-Fi VM, use the `iwctl` steps from the USB guide below.

Set the clock and start the official installer:

```bash
timedatectl set-ntp true
archinstall
```

In `archinstall`, use these choices (names vary slightly by version):

| Screen | Choose |
| --- | --- |
| Archinstall language | English (or yours) |
| Mirrors | Your country / closest |
| Disk configuration | **Use a best-effort default partition layout** on the virtual disk (this **wipes that disk**) |
| Disk encryption | Optional. Skip unless you want it |
| Bootloader | **Grub** (matches the theme this repo installs). systemd-boot also works; the GRUB theme is then skipped |
| Hostname | anything, e.g. `arch-vm` |
| Root password | set one |
| User account | create **your user**, set a password, and add the user to **wheel** (sudo) |
| Profile | **Minimal** |
| Audio | **pipewire** |
| Kernels | **linux** |
| Network configuration | **NetworkManager** |
| Timezone | your timezone |
| Additional packages | leave empty |

Save and install. When it finishes:

```bash
reboot
```

Log in as **your user** (not root) on the TTY. Then continue at **Install this desktop** below.

### If Arch is already installed and you are at a user prompt

You should see something like `youruser@arch-vm ~`. Confirm sudo and the network:

```bash
sudo -v
ping -c 3 archlinux.org
```

If `sudo` is missing or denied:

```bash
su -
pacman -S --needed sudo
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel
usermod -aG wheel YOUR_USERNAME
exit
```

Log out and back in as your user, then continue at **Install this desktop**.

### Install this desktop (VM)

```bash
sudo pacman -S --needed git
git clone https://github.com/nplata24s/arch-shell.git ~/arch-shell
cd ~/arch-shell
./install.sh
```

Enter your sudo password when asked. The script skips any package name that is not in the current repos instead of aborting.

When the script finishes:

```bash
reboot
```

At the **Arch Shell** login screen (SDDM), choose session **Hyprland** and sign in.

---

## 2. USB ISO — from the first terminal

Use this when you boot a real machine from an Arch Linux USB and land in the live environment (`root@archiso ~`).

### Write the USB (on another computer)

1. Download the latest **Arch Linux ISO** from https://archlinux.org/download/
2. Write it to a USB stick (this **erases the stick**):

```bash
# Linux — replace sdX with the USB device, not a partition
sudo dd if=archlinux-*.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

On Windows, [Rufus](https://rufus.ie/) in DD mode works. On macOS, use `dd` after `diskutil unmountDisk`.

### Boot the machine

1. Plug in the USB, Ethernet if you have it, and power on
2. Open the boot menu (often F12, F10, Esc, or F2) and pick the USB
3. Prefer the **UEFI** Arch entry
4. You are now at `root@archiso ~` — every command below is typed there

### Keyboard, font, and network

```bash
# Optional: UK keyboard
loadkeys uk

# Optional: larger font on HiDPI
setfont ter-132n
```

**Ethernet** (including most docks):

```bash
ping -c 3 archlinux.org
```

**Wi-Fi:**

```bash
iwctl
```

Inside `iwctl`:

```text
device list
station wlan0 scan
station wlan0 get-networks
station wlan0 connect "Your Wi-Fi name"
```

Type the Wi-Fi password when asked. Replace `wlan0` with the name from `device list` if it differs. Then:

```text
exit
```

```bash
ping -c 3 archlinux.org
```

### Install Arch

```bash
timedatectl set-ntp true
archinstall
```

Use the **same `archinstall` table as the VM section**. The disk you pick will be **wiped**.

When `archinstall` finishes:

```bash
reboot
```

**Remove the USB** so the machine boots from the disk. Log in as **your user** on the TTY.

### Install this desktop (USB machine)

```bash
sudo pacman -S --needed git
git clone https://github.com/nplata24s/arch-shell.git ~/arch-shell
cd ~/arch-shell
./install.sh
reboot
```

At SDDM, choose **Hyprland** and sign in.

---

## After the first login

- Super opens the Start menu
- Super+Return opens Kitty
- Super+E opens files
- Super+F opens Firefox
- Super+A opens Agent Centre
- Super+V / C / N open Audio, Clipboard, Network
- Super+X closes the focused window
- Super+Shift+H shows the keybind list

Keyboard layout defaults to **gb**. Change it in `~/.config/hypr/config/settings.conf` (`kb_layout`).

**Agent Centre** stores API keys in `~/.config/arch-shell/agent/providers.json` (mode 600). Nothing from that file belongs in git.

The installer also puts these CLIs on PATH so **Providers → Sign in** works:

| CLI | Used for |
| --- | --- |
| `agy` / Antigravity | Google AI Pro / Ultra |
| `codex` | ChatGPT Plus / Pro |
| `claude` | Claude Pro / Max |
| `gh` | GitHub Copilot |
| `ollama` | Local models (`ollama pull llama3.2` when you want one) |

If a vendor installer is down, re-run:

```bash
~/.config/arch-shell/scripts/install-login-clis.sh
```

Wallpaper, the bottom taskbar, mica `#1a1f28`, and the module layout are already set.

Re-running `./install.sh` backs up an existing `~/.config/hypr` under `~/.config/arch-shell/backup/` and then replaces the desktop configs with this snapshot.

---

## What the script installs

| Piece | Where it lands |
| --- | --- |
| Arch Shell (Quickshell) | `~/.config/arch-shell` |
| Hyprland + hypridle + hyprlock | `~/.config/hypr` |
| Login theme | `/usr/share/sddm/themes/arch-shell` |
| GRUB theme (if GRUB is present) | `/boot/grub/themes/arch-shell` |
| Wallpaper | `~/Pictures/Wallpapers/default.jpg` |
| Agent daemon | `systemctl --user enable arch-agentd` |

Official packages: `packages/pacman.txt`. AUR is not required (`quickshell` is in extra).

```
install.sh          ← run this
packages/           official package list
Arch/               taskbar, flyouts, SDDM/GRUB helpers, Agent Centre
hyprland/           compositor config and session scripts
extras/             wallpaper, Kitty, GTK, qt6ct
```
