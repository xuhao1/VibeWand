#!/bin/bash
# Puts a recorded take into the repository in a form small enough to keep: the overlay as VP9 with transparency at
# 30 fps (promo/takes/<name>.webm) and what the script did, timed from the first frame (promo/takes/<name>.json).
# Usage: pack-take.sh <name>
set -euo pipefail
task_root="$(cd "$(dirname "$0")/../.." && pwd)"
task_name="$1"
task_source="$task_root/output/promo/takes/$task_name"
mkdir -p "$task_root/promo/takes"
ffmpeg -hide_banner -loglevel error -y -i "$task_source.mov" -vf "fps=30,crop=1160:1160:0:0" -an \
  -c:v libvpx-vp9 -pix_fmt yuva420p -crf 18 -b:v 0 -row-mt 1 -cpu-used 2 -g 300 "$task_root/promo/takes/$task_name.webm"
python3 - "$task_source" "$task_root/promo/takes/$task_name" <<'PY'
import json, subprocess, sys
source, target = sys.argv[1], sys.argv[2]
start = float(open(source + ".mov.start").read())
events = []
for line in open(source + ".log.jsonl"):
    row = json.loads(line)
    row["t"] = round(row["t"] - start, 3)
    events.append(row)
frames = int(subprocess.run(["ffprobe", "-v", "error", "-count_packets", "-select_streams", "v:0", "-show_entries", "stream=nb_read_packets",
                             "-of", "csv=p=0", target + ".webm"], capture_output=True, text=True, check=True).stdout.strip())
with open(target + ".json", "w") as out:
    out.write('{"fps": 30, "frames": %d, "events": [\n' % frames)
    out.write(",\n".join(" " + json.dumps(event, ensure_ascii=False, sort_keys=True) for event in events))
    out.write("\n]}\n")
print(target + ".webm", frames, "frames")
PY
