"""Synthesises every narration line with edge-tts and records how long each one runs.

Usage: tts.py <language> [line-id ...]
Reads promo/vo.<language>.json and writes promo/vo/<language>/<id>.flac (24 kHz mono, the rate the service speaks at,
cut to the first and last word) and durations.json, which also holds when each word is spoken, for text that appears
on the word. A line is synthesised again only when its text or voice settings changed. The recordings are kept in
the repository, so the film can be rebuilt without the service and comes out the same.
"""
import asyncio, hashlib, json, subprocess, sys
from pathlib import Path

import edge_tts


async def speak(text, voice, path):
    """Returns the words with their start and length in seconds, as the service reports them."""
    for attempt in range(4):
        try:
            words = []
            talk = edge_tts.Communicate(text, voice["voice"], rate=voice["rate"], pitch=voice["pitch"], boundary="WordBoundary")
            with open(path, "wb") as audio:
                async for chunk in talk.stream():
                    if chunk["type"] == "audio":
                        audio.write(chunk["data"])
                    elif chunk["type"] == "WordBoundary":
                        words.append([chunk["text"], chunk["offset"] / 1e7, chunk["duration"] / 1e7])
            return words
        except Exception as error:  # the service drops a connection now and then
            if attempt == 3:
                raise
            print("retry", path.name, error)
            await asyncio.sleep(2 + attempt * 2)


def cut(source, target, words):
    # From just before the first word to just after the last, so a line starts on the frame it is placed at.
    begin = max(0.0, words[0][1] - 0.04)
    end = words[-1][1] + words[-1][2] + 0.18
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(source), "-ss", f"{begin:.3f}", "-to", f"{end:.3f}",
                    "-af", "afade=t=in:d=0.01", "-ar", "24000", "-ac", "1", "-c:a", "flac", "-compression_level", "8", str(target)], check=True)
    return round(end - begin, 3), [[w, round(at - begin, 3), round(length, 3)] for w, at, length in words]


async def main():
    root = Path(__file__).resolve().parents[1]
    language = sys.argv[1]
    script = json.loads((root / f"vo.{language}.json").read_text())
    out = root / "vo" / language; out.mkdir(parents=True, exist_ok=True)
    only = set(sys.argv[2:])
    record = out / "durations.json"
    durations = json.loads(record.read_text()) if record.exists() else {}
    for line in script["lines"]:
        if only and line["id"] not in only:
            continue
        voice = script[line["role"]]
        stamp = hashlib.sha1(json.dumps([line["text"], voice, "words"], ensure_ascii=False).encode()).hexdigest()[:12]
        recording = out / f"{line['id']}.flac"
        known = durations.get(line["id"])
        if known and known["stamp"] == stamp and recording.exists():
            continue
        raw = out / f"{line['id']}.mp3"
        seconds, words = cut(raw, recording, await speak(line["text"], voice, raw))
        durations[line["id"]] = {"stamp": stamp, "seconds": seconds, "text": line["text"], "words": words}
        raw.unlink()
        print(f"{line['id']:14s} {durations[line['id']]['seconds']:6.2f}s  {line['text']}")
    record.write_text(json.dumps({line["id"]: durations[line["id"]] for line in script["lines"] if line["id"] in durations}, ensure_ascii=False, indent=1) + "\n")
    total = sum(v["seconds"] for k, v in durations.items())
    print(f"total speech {total:.1f}s over {len(durations)} lines")


asyncio.run(main())
