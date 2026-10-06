#!/bin/bash
# Turns a take into numbered frames at 30 fps (PNG, transparency kept) for the page to show one by one.
# Usage: seq.sh <name> [ffmpeg video filter]
set -euo pipefail
task_root="$(cd "$(dirname "$0")/../.." && pwd)"
task_name="$1"; task_filter="${2:-null}"
task_source=""
for task_kind in mov mkv mp4; do
  [ -f "$task_root/output/promo/takes/$task_name.$task_kind" ] && task_source="$task_root/output/promo/takes/$task_name.$task_kind" && break
done
task_out="$task_root/output/promo/seq/$task_name"
rm -rf "$task_out"; mkdir -p "$task_out"
ffmpeg -hide_banner -loglevel error -y -i "$task_source" -vf "fps=30,$task_filter" -compression_level 3 "$task_out/%05d.png"
ls "$task_out" | wc -l | tr -d ' ' > "$task_out/count"
echo "$task_name $(cat "$task_out/count") frames"
