#!/bin/bash
# Makes the copies of the films that the project site plays itself: site/video/vibewand-<language>.mp4, a fifth of
# the size of the film in output/promo/cut/. Git ignores them; scripts/publish-site.sh publishes them.
# Usage: web.sh [language ...]
set -euo pipefail
task_root="$(cd "$(dirname "$0")/../.." && pwd)"
[ $# -gt 0 ] || set -- zh en
mkdir -p "$task_root/site/video"
for task_language in "$@"; do
    ffmpeg -hide_banner -loglevel error -y -i "$task_root/output/promo/cut/VibeWand-promo-$task_language.mp4" \
        -c:v libx264 -preset veryslow -crf 27 -pix_fmt yuv420p \
        -color_range tv -colorspace bt709 -color_primaries bt709 -color_trc bt709 \
        -c:a aac -b:a 128k -movflags +faststart "$task_root/site/video/vibewand-$task_language.mp4"
done
ls -l "$task_root/site/video"
