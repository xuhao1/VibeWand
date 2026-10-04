#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_source="$task_root/assets/app-icon/AppIcon.png"
task_output="${1:-$task_root/assets/app-icon/AppIcon.icns}"
task_temp="$(mktemp -d "${TMPDIR:-/tmp}/vibewand-icon.XXXXXX")"
trap 'rm -rf "$task_temp"' EXIT
task_iconset="$task_temp/AppIcon.iconset"
mkdir -p "$task_iconset" "$(dirname "$task_output")"
for task_size in 16 32 128 256 512; do
  sips -z "$task_size" "$task_size" "$task_source" --out "$task_iconset/icon_${task_size}x${task_size}.png" >/dev/null
  task_retina=$((task_size * 2))
  sips -z "$task_retina" "$task_retina" "$task_source" --out "$task_iconset/icon_${task_size}x${task_size}@2x.png" >/dev/null
done
iconutil -c icns "$task_iconset" -o "$task_output"
printf '%s\n' "$task_output"
