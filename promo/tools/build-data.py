"""Gathers what the page needs to know into promo/src/data.js: the timeline, each narration line with the time of
every word, and what happened when in each filmed take.

Usage: build-data.py <language>
"""
import json, sys
from pathlib import Path

root = Path(__file__).resolve().parents[2]
language = sys.argv[1] if len(sys.argv) > 1 else "zh"
timeline = json.loads((root / f"promo/timeline.{language}.json").read_text())
spoken = json.loads((root / f"promo/vo/{language}/durations.json").read_text())
script = {line["id"]: line for line in json.loads((root / f"promo/vo.{language}.json").read_text())["lines"]}

lines = {}
for name, start in timeline["vo"].items():
    entry = spoken[name]
    lines[name] = {"at": start, "seconds": entry["seconds"], "text": entry["text"], "role": script[name]["role"],
                   "words": [[word, round(start + at, 3), length] for word, at, length in entry["words"]]}
ordered = sorted(lines.items(), key=lambda item: item[1]["at"])
for (first, a), (second, b) in zip(ordered, ordered[1:]):
    if a["at"] + a["seconds"] > b["at"] + 0.01:
        print(f"overlap: {first} runs to {a['at'] + a['seconds']:.2f}, {second} starts at {b['at']:.2f}")

takes = {}
for record in sorted((root / "promo/takes").glob("*.json")):
    takes[record.stem] = json.loads(record.read_text())

data = {"fps": timeline["fps"], "duration": timeline["duration"], "scenes": timeline["scenes"], "vo": lines, "takes": takes, "language": language}
(root / "promo/src/data.js").write_text("window.DATA = " + json.dumps(data, ensure_ascii=False) + ";\n")
print(f"{len(lines)} lines, {len(takes)} takes, {timeline['duration']}s")
