#!/usr/bin/env python3
"""Persist nomodeset on VirtualBox so GRUB does not hang at 'Loading initial ramdisk'.

Run as root. Safe to re-run. Bare metal and other hypervisors: no-op unless --force.
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path


def is_virtualbox() -> bool:
    try:
        out = subprocess.run(
            ["systemd-detect-virt"],
            capture_output=True,
            text=True,
            check=False,
        )
        if (out.stdout or "").strip() == "oracle":
            return True
    except FileNotFoundError:
        pass
    product = Path("/sys/class/dmi/id/product_name")
    if product.is_file() and "virtualbox" in product.read_text(errors="ignore").lower():
        return True
    return False


def patch_grub_default(path: Path) -> bool:
    if not path.is_file():
        return False
    text = path.read_text()
    if re.search(r"^GRUB_CMDLINE_LINUX_DEFAULT=.*nomodeset", text, re.M):
        return False

    def add(match: re.Match[str]) -> str:
        quote, inner = match.group(1), match.group(2)
        if "nomodeset" in inner.split():
            return match.group(0)
        inner = (inner + " nomodeset").strip()
        return f"GRUB_CMDLINE_LINUX_DEFAULT={quote}{inner}{quote}"

    new, n = re.subn(
        r'^GRUB_CMDLINE_LINUX_DEFAULT=(["\'])(.*?)\1',
        add,
        text,
        count=1,
        flags=re.M,
    )
    if n == 0:
        if not text.endswith("\n"):
            text += "\n"
        new = text + 'GRUB_CMDLINE_LINUX_DEFAULT="nomodeset"\n'
    path.write_text(new)
    return True


def patch_loader_entries() -> int:
    changed = 0
    roots = [Path("/boot/loader/entries"), Path("/efi/loader/entries")]
    for root in roots:
        if not root.is_dir():
            continue
        for conf in root.glob("*.conf"):
            text = conf.read_text()
            lines = text.splitlines(True)
            out = []
            did = False
            for line in lines:
                if line.startswith("options ") and "nomodeset" not in line.split():
                    line = line.rstrip("\n") + " nomodeset\n"
                    did = True
                out.append(line)
            if did:
                conf.write_text("".join(out))
                changed += 1
    return changed


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()
    if os.geteuid() != 0:
        print("error: run as root", file=sys.stderr)
        return 1
    if not args.force and not is_virtualbox():
        return 0

    grub_def = Path("/etc/default/grub")
    if patch_grub_default(grub_def):
        print("Added nomodeset to /etc/default/grub")
    entries = patch_loader_entries()
    if entries:
        print(f"Added nomodeset to {entries} systemd-boot entry(ies)")

    if Path("/usr/bin/grub-mkconfig").is_file() and grub_def.is_file():
        cfg = Path("/boot/grub/grub.cfg")
        if cfg.parent.is_dir():
            subprocess.run(["grub-mkconfig", "-o", str(cfg)], check=False)
            print(f"Regenerated {cfg}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
