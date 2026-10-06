#!/bin/bash
# Lays the rendered stills out on one sheet for a quick look. Usage: sheet.sh [columns] [cell width]
set -euo pipefail
task_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$task_root/output/promo/stills"
ffmpeg -hide_banner -loglevel error -y -pattern_type glob -i 'still-*.jpg' -vf "scale=${2:-640}:-1,tile=${1:-4}x$(( ( $(ls still-*.jpg | wc -l) + ${1:-4} - 1 ) / ${1:-4} )):padding=6:color=0x404040" -frames:v 1 -q:v 3 sheet.jpg
