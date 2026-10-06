#!/bin/bash
# Films VibeWand's own overlay by itself, with transparency, while the film build plays a script in demo mode:
# nothing is sent to any app, so it can run on a locked screen.
# Usage: overlay-take.sh <name> <script.json> <seconds> [arguments for the app]
set -euo pipefail
task_root="$(cd "$(dirname "$0")/../.." && pwd)"
task_name="$1"; task_script="$2"; task_seconds="$3"; shift 3
task_takes="$task_root/output/promo/takes"
mkdir -p "$task_takes"
cp "$task_script" "$task_takes/$task_name.json"
rm -f "$task_takes/$task_name.log.jsonl" "$task_takes/$task_name.mov"
pkill -TERM -x VibeWand 2>/dev/null || true
sleep 1.6
open -n "$task_root/dist/film/VibeWand.app" --args --film "$task_takes/$task_name.json" --demo \
  -hudVisible YES -hudScale 1 -hudOpacity 1 -VibeKeyBridge.overlayDeviceBelow YES -VibeKeyBridge.overlayAnchor "{3436, 757}" "$@"
sleep 1.6
"$task_root/output/promo/bin/wincap" "$task_takes/$task_name.mov" "$task_seconds" 2890 330 580 720 VibeWand
pkill -TERM -x VibeWand 2>/dev/null || true
