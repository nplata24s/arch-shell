#!/usr/bin/env bash
# Copy a cliphist entry back to the clipboard
set -euo pipefail
ID="${1:-}"
[[ -z "$ID" ]] && exit 1
cliphist decode "$ID" | wl-copy
