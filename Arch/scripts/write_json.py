#!/usr/bin/env python3
"""Write JSON from argv[2] to argv[1], validating first."""
import json
import os
import subprocess
import sys

if len(sys.argv) < 3:
    sys.exit("usage: write_json.py PATH JSON")

path = sys.argv[1]
payload = sys.argv[2]
data = json.loads(payload)
os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

# Accent / glass changes should show up on the next login.
if os.path.basename(path) == "settings.json":
    sync = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sync-sddm.sh")
    if os.path.isfile(sync):
        subprocess.Popen(
            ["bash", sync],
            start_new_session=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
