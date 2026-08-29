#!/usr/bin/env python3
"""BlueZ helper for Arch Shell.

Discovery is bound to the DBus connection that started it — a one-shot
`bluetoothctl scan on` exits and BlueZ immediately stops scanning. `scan-hold`
keeps that connection alive until the process is killed (the Bluetooth tab).
"""
from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
import time

from gi.repository import Gio, GLib

BLUEZ = "org.bluez"
ADAPTER = "org.bluez.Adapter1"
DEVICE = "org.bluez.Device1"
PROPS = "org.freedesktop.DBus.Properties"
OM = "org.freedesktop.DBus.ObjectManager"


def _out(obj: dict, code: int = 0) -> None:
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()
    raise SystemExit(code)


def _bus() -> Gio.DBusConnection:
    return Gio.bus_get_sync(Gio.BusType.SYSTEM, None)


def _proxy(bus: Gio.DBusConnection, path: str, iface: str) -> Gio.DBusProxy:
    return Gio.DBusProxy.new_sync(
        bus, Gio.DBusProxyFlags.NONE, None, BLUEZ, path, iface, None)


def _managed(bus: Gio.DBusConnection) -> dict:
    om = _proxy(bus, "/", OM)
    return om.call_sync("GetManagedObjects", None, 0, 4000, None).unpack()[0]


def _adapter(bus: Gio.DBusConnection):
    objs = _managed(bus)
    for path, ifaces in objs.items():
        if ADAPTER in ifaces:
            return path, ifaces[ADAPTER], objs
    return None, None, objs


def _set(bus: Gio.DBusConnection, path: str, name: str, value: GLib.Variant) -> None:
    _proxy(bus, path, PROPS).call_sync(
        "Set", GLib.Variant("(ssv)", (ADAPTER, name, value)), 0, 4000, None)


def _device_path(objs: dict, addr: str) -> str | None:
    want = addr.strip().upper()
    for path, ifaces in objs.items():
        dev = ifaces.get(DEVICE)
        if not dev:
            continue
        if str(dev.get("Address") or "").upper() == want:
            return path
    return None


def get_state() -> dict:
    empty = {
        "present": False,
        "powered": False,
        "discovering": False,
        "pairable": False,
        "connected": False,
        "device": "",
        "devices": [],
    }
    try:
        bus = _bus()
        path, adapter, objs = _adapter(bus)
    except Exception as exc:
        empty["error"] = str(exc)
        return empty
    if not path or adapter is None:
        return empty

    devices = []
    connected_name = ""
    for _dpath, ifaces in objs.items():
        dev = ifaces.get(DEVICE)
        if not dev:
            continue
        addr = str(dev.get("Address") or "")
        name = str(dev.get("Alias") or dev.get("Name") or addr)
        connected = bool(dev.get("Connected"))
        rssi = dev.get("RSSI")
        try:
            rssi_n = int(rssi) if rssi is not None else 0
        except (TypeError, ValueError):
            rssi_n = 0
        devices.append({
            "address": addr,
            "name": name,
            "paired": bool(dev.get("Paired")),
            "connected": connected,
            "trusted": bool(dev.get("Trusted")),
            "rssi": rssi_n,
            "icon": str(dev.get("Icon") or ""),
        })
        if connected and not connected_name:
            connected_name = name
    devices.sort(key=lambda d: (
        not d["connected"], not d["paired"], -d["rssi"], d["name"].lower()))
    return {
        "present": True,
        "powered": bool(adapter.get("Powered")),
        "discovering": bool(adapter.get("Discovering")),
        "pairable": bool(adapter.get("Pairable")),
        "connected": bool(connected_name),
        "device": connected_name,
        "devices": devices,
    }


def power(want: str) -> dict:
    bus = _bus()
    path, adapter, _objs = _adapter(bus)
    if not path:
        return {"ok": False, "error": "No Bluetooth adapter"}
    on = bool(adapter.get("Powered"))
    if want == "toggle":
        target = not on
    elif want in ("on", "yes", "true", "1"):
        target = True
    else:
        target = False
    if target == on:
        return {"ok": True, "powered": on}
    if not target:
        try:
            _proxy(bus, path, ADAPTER).call_sync("StopDiscovery", None, 0, 2000, None)
        except Exception:
            pass
    _set(bus, path, "Powered", GLib.Variant("b", target))
    if target:
        try:
            _set(bus, path, "Pairable", GLib.Variant("b", True))
        except Exception:
            pass
    time.sleep(0.3)
    st = get_state()
    return {"ok": True, "powered": st["powered"]}


def scan_hold() -> None:
    """Start discovery and stay alive so BlueZ keeps scanning."""
    bus = _bus()
    path, adapter, _objs = _adapter(bus)
    if not path:
        _out({"ok": False, "error": "No Bluetooth adapter"}, 1)
    if not adapter.get("Powered"):
        _set(bus, path, "Powered", GLib.Variant("b", True))
        time.sleep(0.2)
    try:
        _set(bus, path, "Pairable", GLib.Variant("b", True))
    except Exception:
        pass
    adapter_p = _proxy(bus, path, ADAPTER)
    try:
        adapter_p.call_sync("StartDiscovery", None, 0, 4000, None)
    except Exception as exc:
        msg = str(exc)
        if "InProgress" not in msg:
            _out({"ok": False, "error": msg}, 1)

    loop = GLib.MainLoop()

    def quit_loop(*_args) -> None:
        loop.quit()

    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        try:
            signal.signal(sig, quit_loop)
        except ValueError:
            pass
    try:
        loop.run()
    finally:
        try:
            adapter_p.call_sync("StopDiscovery", None, 0, 2000, None)
        except Exception:
            pass


def _ctl(script: str, timeout: int = 30) -> subprocess.CompletedProcess:
    env = {**os.environ, "LANG": "C"}
    return subprocess.run(
        ["bluetoothctl"],
        input=script,
        text=True,
        capture_output=True,
        timeout=timeout,
        env=env,
    )


def connect(addr: str) -> dict:
    addr = addr.strip()
    if not addr:
        return {"ok": False, "error": "missing address"}
    bus = _bus()
    path, adapter, objs = _adapter(bus)
    if not path:
        return {"ok": False, "error": "No Bluetooth adapter"}
    if not adapter.get("Powered"):
        _set(bus, path, "Powered", GLib.Variant("b", True))
        time.sleep(0.3)
        objs = _managed(bus)
    try:
        _set(bus, path, "Pairable", GLib.Variant("b", True))
    except Exception:
        pass

    dpath = _device_path(objs, addr)
    if dpath:
        try:
            _proxy(bus, dpath, DEVICE).call_sync("Connect", None, 0, 20000, None)
            st = get_state()
            return {"ok": True, "connected": st["connected"], "device": st["device"]}
        except Exception:
            pass

    script = (
        "agent NoInputNoOutput\n"
        "default-agent\n"
        "pairable on\n"
        f"pair {addr}\n"
        f"trust {addr}\n"
        f"connect {addr}\n"
        "quit\n"
    )
    try:
        proc = _ctl(script, timeout=35)
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "Timed out connecting"}
    blob = (proc.stdout or "") + (proc.stderr or "")
    st = get_state()
    if st["connected"]:
        return {"ok": True, "connected": True, "device": st["device"]}
    err = "Failed to connect"
    for line in blob.splitlines():
        low = line.lower()
        if "fail" in low or "error" in low:
            err = line.strip()
    return {"ok": False, "error": err}


def disconnect(addr: str) -> dict:
    addr = addr.strip()
    bus = _bus()
    _path, _adapter, objs = _adapter(bus)
    dpath = _device_path(objs, addr)
    if not dpath:
        return {"ok": False, "error": "Unknown device"}
    try:
        _proxy(bus, dpath, DEVICE).call_sync("Disconnect", None, 0, 10000, None)
    except Exception as exc:
        return {"ok": False, "error": str(exc)}
    return {"ok": True}


def remove(addr: str) -> dict:
    addr = addr.strip()
    bus = _bus()
    path, _adapter, objs = _adapter(bus)
    dpath = _device_path(objs, addr)
    if not path or not dpath:
        return {"ok": False, "error": "Unknown device"}
    try:
        _proxy(bus, path, ADAPTER).call_sync(
            "RemoveDevice", GLib.Variant("(o)", (dpath,)), 0, 8000, None)
    except Exception as exc:
        return {"ok": False, "error": str(exc)}
    return {"ok": True}


def main() -> None:
    args = sys.argv[1:]
    cmd = args[0] if args else "get"
    try:
        if cmd == "get":
            print(json.dumps(get_state(), ensure_ascii=False), flush=True)
            return
        if cmd == "power":
            _out(power(args[1] if len(args) > 1 else "toggle"))
        if cmd == "scan-hold":
            scan_hold()
            return
        if cmd == "connect":
            _out(connect(args[1] if len(args) > 1 else ""))
        if cmd == "disconnect":
            _out(disconnect(args[1] if len(args) > 1 else ""))
        if cmd == "remove":
            _out(remove(args[1] if len(args) > 1 else ""))
        _out({"ok": False, "error": f"unknown command {cmd}"}, 1)
    except SystemExit:
        raise
    except Exception as exc:
        _out({"ok": False, "error": str(exc)}, 1)


if __name__ == "__main__":
    main()
