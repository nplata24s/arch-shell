#!/usr/bin/env bash
# List clipboard history from cliphist as JSON
set -euo pipefail

if ! command -v cliphist &>/dev/null; then
  echo '[]'
  exit 0
fi

cliphist list 2>/dev/null | head -n 40 | python3 -c '
import json, sys
items = []
for line in sys.stdin:
    line = line.rstrip("\n")
    if "\t" not in line:
        continue
    cid, text = line.split("\t", 1)
    items.append({"id": cid.strip(), "text": text[:160]})
print(json.dumps(items))
'
