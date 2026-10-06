#!/bin/bash
# From what is in the repository to a finished film: the overlay takes unpacked into frames, page data, sound cues,
# sound, every frame, and two encodes (with and without narration). Run setup.sh once before.
# Usage: build.sh <language> <name>      e.g. build.sh zh VibeWand-promo-zh
set -euo pipefail
task_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$task_root"
task_language="$1"; task_name="$2"
task_python="output/promo-tools/venv/bin/python"
for task_take in promo/takes/*.webm; do
  task_frames="output/promo/seq/$(basename "${task_take%.webm}")"
  # Unpacked again only when the take is newer than its frames. The libvpx decoder is the one that reads transparency.
  if [ ! -f "$task_frames/.unpacked" ] || [ "$task_take" -nt "$task_frames/.unpacked" ]; then
    rm -rf "$task_frames"; mkdir -p "$task_frames"
    ffmpeg -hide_banner -loglevel error -y -c:v libvpx-vp9 -i "$task_take" -compression_level 1 "$task_frames/%05d.png"
    touch "$task_frames/.unpacked"
  fi
done
"$task_python" promo/tools/build-data.py "$task_language"
node promo/tools/render.mjs --cues output/promo/cues.json
"$task_python" promo/tools/sound.py "$task_language"
rm -rf "output/promo/frames-$task_language"
node promo/tools/render.mjs --frames --fps 60 --workers 8 --out "output/promo/frames-$task_language" | tail -1
mkdir -p output/promo/cut
bash promo/tools/encode.sh "output/promo/frames-$task_language" 60 "output/promo/audio/$task_language/mix.wav" "output/promo/cut/$task_name.mp4" 16
bash promo/tools/encode.sh "output/promo/frames-$task_language" 60 "output/promo/audio/$task_language/mix-no-narration.wav" "output/promo/cut/$task_name-no-narration.mp4" 16
echo BUILD-DONE
