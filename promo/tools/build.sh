#!/bin/bash
# From sources to a finished film: page data, sound cues, sound, frames, and two encodes (with and without narration).
# Usage: build.sh <language> <name>      e.g. build.sh zh VibeWand-promo-zh
# Narration (tts.py) and overlay takes (overlay-take.sh, seq.sh) are made beforehand; see promo/README.md.
set -euo pipefail
task_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$task_root"
task_language="$1"; task_name="$2"
task_python="output/promo-tools/venv/bin/python"
"$task_python" promo/tools/build-data.py "$task_language"
node promo/tools/render.mjs --cues output/promo/cues.json
"$task_python" promo/tools/sound.py "$task_language"
rm -rf "output/promo/frames-$task_language"
node promo/tools/render.mjs --frames --fps 60 --workers 8 --out "output/promo/frames-$task_language" | tail -1
mkdir -p output/promo/cut
bash promo/tools/encode.sh "output/promo/frames-$task_language" 60 "output/promo/audio/$task_language/mix.wav" "output/promo/cut/$task_name.mp4" 16
bash promo/tools/encode.sh "output/promo/frames-$task_language" 60 "output/promo/audio/$task_language/mix-no-narration.wav" "output/promo/cut/$task_name-no-narration.mp4" 16
echo BUILD-DONE
