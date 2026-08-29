#!/usr/bin/env python3
"""Return PipeWire/PulseAudio state as JSON."""
import json
import subprocess


def run_cmd(cmd):
    try:
        return subprocess.check_output(cmd, shell=True, stderr=subprocess.DEVNULL).decode()
    except subprocess.CalledProcessError:
        return ""


def parse_json(text):
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return []


def wpctl_default(node_target):
    out = run_cmd(f"wpctl inspect {node_target}")
    for line in out.splitlines():
        if "node.name" in line and "=" in line:
            return line.split("=", 1)[1].strip().strip('"')
    return ""


def volume_percent(node):
    vol = node.get("volume", {})
    if isinstance(vol, dict):
        for key in ("front-left", "mono"):
            if key in vol:
                raw = vol[key].get("value_percent", "0%")
                return int(str(raw).strip().replace("%", "") or 0)
    return 0


def format_device(node, is_default=False, is_app=False):
    props = node.get("properties", {})
    if is_app:
        name = props.get("application.name") or props.get("application.process.binary") or "App"
        desc = props.get("media.name") or props.get("window.title") or "Audio stream"
    else:
        name = props.get("device.description") or node.get("name") or "Device"
        desc = node.get("name") or ""
    return {
        "id": str(node.get("index", "")),
        "name": name,
        "description": desc,
        "volume": volume_percent(node),
        "mute": bool(node.get("mute", False)),
        "is_default": bool(is_default),
    }


def main():
    sinks = parse_json(run_cmd("pactl -f json list sinks"))
    sources = parse_json(run_cmd("pactl -f json list sources"))
    sink_inputs = parse_json(run_cmd("pactl -f json list sink-inputs"))

    default_sink = wpctl_default("@DEFAULT_AUDIO_SINK@")
    default_source = wpctl_default("@DEFAULT_AUDIO_SOURCE@")

    if not default_sink or not default_source:
        info = parse_json(run_cmd("pactl -f json info"))
        if isinstance(info, dict):
            default_sink = default_sink or info.get("default_sink_name", "")
            default_source = default_source or info.get("default_source_name", "")

    apps = []
    for stream in sink_inputs:
        props = stream.get("properties", {})
        if props.get("application.id") == "org.PulseAudio.pavucontrol":
            continue
        apps.append(format_device(stream, is_app=True))

    inputs = []
    for source in sources:
        props = source.get("properties", {})
        name = source.get("name", "")
        if props.get("device.class") == "monitor" or name.endswith(".monitor"):
            continue
        inputs.append(format_device(source, source.get("name") == default_source))

    outputs = [format_device(s, s.get("name") == default_sink) for s in sinks]

    master = outputs[0] if outputs else {"volume": 0, "mute": False}
    for out in outputs:
        if out.get("is_default"):
            master = out
            break

    mic = inputs[0] if inputs else {"volume": 0, "mute": False}
    for inp in inputs:
        if inp.get("is_default"):
            mic = inp
            break

    print(json.dumps({
        "master_volume": master.get("volume", 0),
        "master_mute": master.get("mute", False),
        "input_volume": mic.get("volume", 0),
        "input_mute": mic.get("mute", False),
        "default_sink": default_sink,
        "outputs": outputs,
        "inputs": inputs,
        "apps": apps,
    }))


if __name__ == "__main__":
    main()
