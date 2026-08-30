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

## archinstall — every setting

`archinstall` is the official guided installer on the Arch ISO. Menu names move around between **3.x** (curses) and **4.x** (Textual UI), but the jobs are the same. Work **top to bottom**, then choose **Install**. You can go back with Esc and change anything before that.

**Keys**

| Key | Action |
| --- | --- |
| Arrow keys / Tab | Move |
| Enter | Open / confirm |
| Esc | Back to the main list |
| Space | Toggle a checkbox (kernels, extra repos) |

**Cheat sheet (this desktop)**

| Setting | Choose |
| --- | --- |
| Archinstall language | English (or yours) — this is only the installer UI |
| Locales | Keyboard **uk** if you use a UK board, else **us**. Locale **en_GB.UTF-8** or **en_US.UTF-8**. Encoding **UTF-8** |
| Mirrors and repositories | Your country. Optional: enable **multilib**. Leave testing repos off |
| Disk configuration | **Best-effort default partition layout** on the disk you want Arch on. This **wipes that disk** |
| Filesystem | **ext4** (simplest). btrfs is fine if you already use snapshots |
| Disk encryption | Off unless you want LUKS. If on, you type that passphrase at every boot, before SDDM |
| Swap | On (zram) if the menu offers it. Harmless either way |
| Bootloader | **Grub** |
| Unified kernel images | Off / no |
| Kernels | **linux** only (the default kernel). Do not add linux-lts / zen / hardened unless you know why |
| Hostname | anything, e.g. `arch-vm` |
| Root password | set one and remember it |
| User account | create **your** user, set a password, add the user to **wheel** (sudo) |
| Profile | **Minimal** |
| Applications / audio | **Pipewire**. Bluetooth optional (this repo installs it later anyway) |
| Network configuration | **NetworkManager** |
| Additional packages | **leave empty** — `./install.sh` installs the desktop |
| Timezone | your timezone, e.g. `Europe/London` |
| Automatic time sync (NTP) | **On** |

Then **Install**. When it finishes, reboot, log in as **your user** (not root) on the TTY, and continue at **Install this desktop**.

### Archinstall language

Language of the installer screens only. It does not set the installed system language.

**Choose:** English, unless you want the menus in another language.

### Locales (keyboard, language, encoding)

On 4.x this is one **Locales** item. On 3.x you may see **Keyboard layout** and **Locale language** separately.

- **Keyboard layout** — keys in the live ISO and the installed TTY. Hyprland in this repo later defaults to **gb**. Pick **uk** (or `gb`) for a UK keyboard, **us** otherwise. You can still change Hyprland later in `~/.config/hypr/config/settings.conf`.
- **Locale language** — `en_GB.UTF-8` or `en_US.UTF-8`.
- **Locale encoding** — **UTF-8**.

Do not leave the locale unset; a missing UTF-8 locale makes some apps noisy later.

### Mirrors and repositories

Sets `/etc/pacman.d/mirrorlist`. Closer mirrors make `archinstall` and `./install.sh` much faster.

**Choose:** your country, or the geographically closest region. If the list is long, pick one country rather than “worldwide”.

**Optional repositories:** enable **multilib** if you might run 32-bit games/Wine later. Leave **core-testing** / **extra-testing** off.

If downloads stall, Esc back, pick another region, and try Install again (the disk is not written until Install runs).

### Disk configuration

This is the dangerous step. The disk you select is **erased**.

1. If you have more than one disk, leave `archinstall` with Esc, run `lsblk` in the shell, and note the right name (`/dev/sda`, `/dev/nvme0n1`, `/dev/vda` in a VM). The USB stick must **not** be the target.
2. Open **Disk configuration**.
3. Choose **Use a best-effort default partition layout** (wording may be “Best-effort default layout”).
4. Select **only** the target disk.
5. Filesystem: **ext4** unless you already want btrfs snapshots.

What that layout typically creates on UEFI:

| Partition | Role |
| --- | --- |
| ~1 GiB FAT32 | EFI, mounted at `/boot` |
| Rest of the disk | Root `/` (ext4 or btrfs) |

There is usually **no** separate `/home`. That is fine for a VM or a single-user machine.

**Do not** use manual partitioning unless you are dual-booting and already know how to reuse an existing EFI partition without formatting it. This repo does not need a special layout.

**VMs:** pick the virtual disk (often `vda` or `sda`), not the Arch ISO.

### Disk encryption (LUKS)

Optional. The EFI partition stays unencrypted; `/` is unlocked with a passphrase before Linux starts.

**Choose:** skip unless you need a stolen-laptop passphrase. If you enable it, pick a passphrase you can type in a small GRUB/EFI prompt — not only a password manager.

### Swap

4.x has a **Swap** row (often **swap on zram**). 3.x may hide this under disk options.

**Choose:** enable zram if offered (zstd compression is a good default). A swap **partition** is not required. Hibernate needs extra work and is not set up by this repo.

### Bootloader

**Choose: Grub.** This repo installs a GRUB theme that matches the login screen. If the firmware is UEFI, GRUB still works.

| Option | Use it? |
| --- | --- |
| **Grub** | Yes — recommended |
| systemd-boot | Works, but the GRUB theme is skipped |
| Limine | Works as a bootloader; the GRUB theme is skipped |

Leave **install to removable / EFI fallback** at the installer default on a single-OS machine. Turn extra “overwrite NVRAM” options off if you are dual-booting and the help text says it will replace other OS boot entries.

**Unified kernel images (UKI):** leave **off**. Not required for this desktop.

### Kernels

**Choose: `linux` only** (sometimes labelled “Latest Linux kernel”).

| Kernel | For this desktop |
| --- | --- |
| **linux** | Yes |
| linux-lts | Optional spare; skip on a first install |
| linux-zen | Gaming-oriented; skip |
| linux-hardened | Stricter; can surprise desktop apps; skip |

Space-toggles extras. More kernels mean more downloads and a busier GRUB menu. This repo does not need them.

### Hostname

The name other devices see on the network (`arch-vm`, `arch-laptop`, …). Letters, digits, and hyphens. Do not use spaces.

### Authentication (root password and user)

On 4.x this is one **Authentication** screen. On 3.x you often get **Root password** and **User account** as two rows.

1. **Root password** — required. You need it if sudo is broken. Do not leave root locked unless you already understand that choice.
2. **Create a user** — same name you want to log into SDDM with. Set a user password.
3. **Superuser / wheel / sudo** — **enable it**. `./install.sh` must be able to `sudo`. If you skip wheel, the desktop script will fail until you fix sudo.

Create **one** normal user. Do not install as root-only.

### Profile

**Choose: Minimal.**

This repo’s `./install.sh` installs Hyprland, SDDM, and the shell. Other profiles fight that:

| Profile | Why not |
| --- | --- |
| **Minimal** | Correct — base system only |
| Desktop → Hyprland | A second Hyprland/session stack on top of this one |
| Desktop → GNOME / KDE / … | Extra display manager (GDM, SDDM from Plasma, etc.) |
| Server | Extra daemons you do not want on a laptop/VM |
| Xorg | This desktop is Wayland |

If you already picked a desktop profile, Abort and start `archinstall` again, or expect to disable the extra display manager later.

### Applications (audio, Bluetooth, …)

4.x groups these under **Applications**. 3.x often has a dedicated **Audio** row.

- **Audio: Pipewire** — required. Do not pick PulseAudio.
- **Bluetooth** — optional here; the desktop script installs BlueZ either way.
- **Firewall (firewalld / ufw)** — leave off unless you need one. Not required for the shell.
- **Printers** — skip unless you have a printer to set up now.

### Network configuration

**Choose: NetworkManager.**

Wi-Fi, Ethernet, and the shell’s network flyout all expect it. `./install.sh` enables `NetworkManager.service`.

| Option | Use it? |
| --- | --- |
| **NetworkManager** | Yes |
| Copy installer default / ISO network | Only as a last resort |
| iwd alone | Skip — NM can still use iwd underneath later |
| Manual / systemd-networkd | Skip for this desktop |

### Additional packages

**Leave the list empty.** Do not type `hyprland`, `firefox`, `gnome`, or a display manager here. The desktop script installs a known set from `packages/pacman.txt`. Extra names in this box are how people accidentally pull GDM or a second compositor.

### Timezone

Pick the city that matches you (`Europe/London`, `America/New_York`, …). This sets local time for the clock widget and timestamps.

### Automatic time sync (NTP)

**On.** Wrong clocks break HTTPS and pacman signatures.

### Save configuration (optional)

You can save a JSON copy of these answers onto a second USB. Skip it unless you reinstall often.

### Install / Abort

Select **Install** and confirm the disk wipe warning. Wait until it says it finished (often it offers `chroot` — **No** / skip). Then:

```bash
reboot
```

On a USB install, **unplug the Arch ISO** so firmware boots the disk. Log in on the TTY as **your user**, not `root`. Then run the clone + `./install.sh` steps in the VM or USB section below.

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

Work through **[archinstall — every setting](#archinstall--every-setting)** (Minimal profile, Grub, Pipewire, NetworkManager, empty extra packages). The virtual disk you pick is **wiped**.

When `archinstall` finishes:

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

Use **[archinstall — every setting](#archinstall--every-setting)** again. The disk you pick will be **wiped**.

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
