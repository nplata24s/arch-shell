#!/usr/bin/env bash
# Toggle screen recording with wf-recorder
set -euo pipefail
ACTION="${1:-status}"
PIDFILE="${HOME}/.config/arch-shell/recorder.pid"
OUTDIR="${HOME}/Videos"
mkdir -p "$OUTDIR" "$(dirname "$PIDFILE")"

running=false
if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  running=true
fi

case "$ACTION" in
  status)
    jq -n -c --argjson running "$running" '{running:$running}'
    ;;
  toggle)
    if $running; then
      kill "$(cat "$PIDFILE")" 2>/dev/null || true
      rm -f "$PIDFILE"
      echo '{"running":false}'
    else
      out="${OUTDIR}/recording-$(date +%Y%m%d-%H%M%S).mp4"
      wf-recorder -f "$out" >/dev/null 2>&1 &
      echo $! > "$PIDFILE"
      echo '{"running":true}'
    fi
    ;;
  *)
    echo "Usage: $0 status|toggle" >&2
    exit 1
    ;;
esac
