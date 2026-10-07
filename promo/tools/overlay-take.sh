#!/bin/bash
# Films VibeWand's own overlay by itself, with transparency, while the film build plays a script in demo mode:
# nothing is sent to any app, so it can run on a locked screen. Film mode draws the overlay dark, as the film is,
# whatever the system's appearance. The take is then packed into promo/takes.
# Usage: overlay-take.sh <name> <script.json> <seconds> [arguments for the app]
# VIBEWAND_FILM_ANCHOR is where the overlay's corner is put (AppKit points) and VIBEWAND_FILM_RECT the rectangle
# recorded around it (x y w h, points from the top left of the main display); the defaults are the author's
# second display, to the right of a 1728 x 1117 main one.
set -euo pipefail
task_root="$(cd "$(dirname "$0")/../.." && pwd)"
task_name="$1"; task_script="$2"; task_seconds="$3"; shift 3
task_takes="$task_root/output/promo/takes"
task_anchor="${VIBEWAND_FILM_ANCHOR:-}"
[ -n "$task_anchor" ] || task_anchor='{3436, 757}'
mkdir -p "$task_takes"
cp "$task_script" "$task_takes/$task_name.json"
rm -f "$task_takes/$task_name.log.jsonl" "$task_takes/$task_name.mov"
pkill -TERM -x VibeWand 2>/dev/null || true
sleep 1.6
open -n "$task_root/dist/film/VibeWand.app" --args --film "$task_takes/$task_name.json" --demo \
  -hudVisible YES -hudScale 1 -hudOpacity 1 -VibeWandBridge.overlayDeviceBelow YES -VibeWandBridge.overlayAnchor "\"$task_anchor\"" "$@"
sleep 1.6
# shellcheck disable=SC2086
"$task_root/output/promo/bin/wincap" "$task_takes/$task_name.mov" "$task_seconds" ${VIBEWAND_FILM_RECT:-2890 330 580 720} VibeWand
pkill -TERM -x VibeWand 2>/dev/null || true
bash "$task_root/promo/tools/pack-take.sh" "$task_name"
