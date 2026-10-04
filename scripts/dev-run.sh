#!/bin/bash
# Rebuilds the development bundle and restarts it with the automation socket.
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
bash "$task_root/scripts/dev-app.sh" >/dev/null 2>&1 || { bash "$task_root/scripts/dev-app.sh"; exit 1; }
pkill -TERM -x VibeWand 2>/dev/null || true
for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x VibeWand >/dev/null || break; sleep 0.2; done
open -n "$task_root/dist/dev/VibeWand.app" --args --automation-socket "$task_root/dist/dev/vw.sock" "$@"
for _ in $(seq 1 30); do [ -S "$task_root/dist/dev/vw.sock" ] && "$task_root/scripts/vwctl" '{"cmd":"ping"}' 2>/dev/null && exit 0; sleep 0.2; done
echo "VibeWand did not answer on the automation socket" >&2; exit 1
