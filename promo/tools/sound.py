"""Makes the film's sound from nothing but arithmetic: an original track that follows the scenes, the effects the
scenes ask for, and the narration placed where the timeline says. Nothing here is sampled or licensed from anywhere.

Usage: sound.py <language>
Writes output/promo/audio/<language>/{music,sfx,voice,mix,mix-no-narration}.wav (48 kHz stereo).
"""
import json, sys, wave
from pathlib import Path

import numpy as np
from scipy.signal import butter, sosfilt, fftconvolve

SR = 48000
root = Path(__file__).resolve().parents[2]
language = sys.argv[1] if len(sys.argv) > 1 else "zh"
timeline = json.loads((root / f"promo/timeline.{language}.json").read_text())
spoken = json.loads((root / f"output/promo/vo/{language}/durations.json").read_text())
script = {line["id"]: line for line in json.loads((root / f"promo/vo.{language}.json").read_text())["lines"]}
cues = json.loads((root / "output/promo/cues.json").read_text())
DURATION = timeline["duration"]
N = int(DURATION * SR)
rng = np.random.default_rng(11)


def seconds(n): return np.arange(n) / SR
def lowpass(x, hz, order=2): return sosfilt(butter(order, hz, "low", fs=SR, output="sos"), x, axis=0)
def highpass(x, hz, order=2): return sosfilt(butter(order, hz, "high", fs=SR, output="sos"), x, axis=0)
def bandpass(x, lo, hi, order=2): return sosfilt(butter(order, [lo, hi], "band", fs=SR, output="sos"), x, axis=0)
def noise(n): return rng.uniform(-1, 1, n)
def hz(midi): return 440.0 * 2 ** ((midi - 69) / 12)
def saw(freq, n, phase=0.0): return 2 * ((freq * seconds(n) + phase) % 1) - 1
def sine(freq, n): return np.sin(2 * np.pi * freq * seconds(n))
def glide(f0, f1, n, curve=1.0):
    f = f0 + (f1 - f0) * (np.arange(n) / max(1, n - 1)) ** curve
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def place(bus, sound, at, gain=1.0, pan=0.0):
    """Adds a mono sound to a stereo bus at `at` seconds; pan runs from -1 (left) to 1 (right)."""
    start = int(at * SR)
    if start >= len(bus) or start + len(sound) <= 0: return
    sound = sound[max(0, -start):]; start = max(0, start)
    sound = sound[: len(bus) - start]
    left, right = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
    bus[start:start + len(sound), 0] += sound * gain * left * 1.414
    bus[start:start + len(sound), 1] += sound * gain * right * 1.414


def curve(points):
    """A level over the whole film from [seconds, value] points."""
    times, values = zip(*points)
    return np.interp(np.arange(N) / SR, times, values)


def reverb(x, length=1.6, wet=0.25):
    n = int(length * SR)
    tail = np.stack([noise(n), noise(n)], 1) * np.exp(-seconds(n) / (length / 5))[:, None]
    tail = highpass(lowpass(tail, 6500), 250)
    wet_signal = np.stack([fftconvolve(x[:, c], tail[:, c])[: len(x)] for c in range(2)], 1)
    return x + wet * wet_signal / np.sqrt(n) * 14


# ---------------------------------------------------------------- the track
scenes = timeline["scenes"]
def vo_at(name): return timeline["vo"][name]
impact = vo_at("turn1") + spoken["turn1"]["seconds"] + 0.25
BEAT, BAR = 0.6, 2.4
ORIGIN = impact - 9 * BAR
command_flash = vo_at("cmd1") + spoken["cmd1"]["seconds"] + 0.3
first_say, deck_done = vo_at("say_music"), vo_at("cmd2") - 0.6
core, apps, command, devices, ending = scenes["core"][0], scenes["apps"][0], scenes["command"][0], scenes["devices"][0], scenes["end"][0]
insight = scenes["insight"][0]
a2, a3, a4 = vo_at("apps2"), vo_at("apps3"), vo_at("apps4")
c2, c4, ps = vo_at("cmd2"), vo_at("cmd4"), vo_at("end2")

level = {
    "drone": curve([[0, 0], [0.6, 0.0], [3, 0.9], [impact - 0.3, 1.0], [impact + 0.2, 0.0], [command - 0.3, 0], [command + 0.6, 0.8], [command_flash, 0.9], [command_flash + 0.3, 0], [ps - 1.5, 0], [ps, 0.7], [DURATION - 2.5, 0.6], [DURATION, 0]]),
    "pad": curve([[0, 0], [impact - 0.05, 0], [impact, 0.9], [insight, 0.6], [core, 0.6], [apps, 0.65], [command, 0.45], [command_flash, 0.5], [c2, 0.65], [c4, 0.95], [devices, 0.75], [ending, 0.95], [ps - 2, 0.6], [ps, 0.15], [DURATION - 1, 0]]),
    "arp": curve([[0, 0], [4.4, 0], [4.6, 0.5], [7.6, 0.5], [8.0, 0], [impact - 0.05, 0], [impact, 0.75], [insight, 0.5], [core, 0.7], [apps, 0.5], [a3 - 0.1, 0.55], [a3, 0.85], [command - 0.2, 0.6], [command + 0.4, 0], [first_say - 0.5, 0], [first_say, 0.5], [c2, 0.7], [c4, 0.3], [devices, 0.85], [ending, 0.7], [ps - 2, 0.4], [ps, 0.0], [DURATION, 0]]),
    "bass": curve([[0, 0], [impact - 0.05, 0], [impact, 0.85], [insight - 0.1, 0.85], [insight + 0.3, 0.35], [core - 0.1, 0.4], [core, 0.85], [apps, 0.7], [a3, 0.9], [command - 0.2, 0.8], [command + 0.3, 0], [command_flash - 0.05, 0], [command_flash, 1.0], [c2, 0.65], [c4 - 0.2, 0.6], [c4, 0.0], [devices - 0.05, 0], [devices, 0.95], [ending, 0.8], [ending + 9, 0.6], [ps - 2, 0], [DURATION, 0]]),
    "kick": curve([[0, 0], [impact - 0.05, 0], [impact, 1], [insight - 0.1, 1], [insight, 0.0], [core - 0.05, 0.0], [core, 0.9], [apps, 0.6], [a2, 0.85], [a3, 1], [command - 0.2, 1], [command, 0], [command_flash - 0.05, 0], [command_flash, 1], [c2, 0.6], [c4 - 0.2, 0.6], [c4, 0], [devices - 0.05, 0], [devices, 1], [ending + 0.2, 0.9], [ending + 8, 0.7], [ps - 3, 0], [DURATION, 0]]),
    "hat": curve([[0, 0], [impact - 0.05, 0], [impact, 0.7], [insight, 0.35], [core, 0.7], [apps, 0.6], [a2, 0.9], [a3, 0.7], [command, 0], [first_say - 0.2, 0], [first_say, 0.6], [c2, 0.45], [c4, 0], [devices - 0.05, 0], [devices, 0.8], [ending + 0.2, 0.6], [ps - 3, 0], [DURATION, 0]]),
    "lead": curve([[0, 0], [impact - 0.05, 0], [impact + 0.4, 0.6], [insight - 0.5, 0.6], [insight, 0], [a3 - 0.1, 0], [a3 + 0.3, 0.45], [command - 0.3, 0.45], [command, 0], [devices - 0.1, 0], [devices + 0.3, 0.7], [ending, 0.75], [ending + 9, 0.5], [ps - 2, 0], [DURATION, 0]]),
}
# Bars are counted from ORIGIN; the progression is Am F C G, with a restless variant while the tools pile up.
PROGRESSION = [[57, 60, 64], [53, 57, 60], [60, 64, 67], [55, 59, 62]]
TENSE = [[57, 60, 64], [57, 60, 65], [50, 53, 57], [52, 56, 59]]
def chord(bar, at): return (TENSE if apps <= at < a3 else PROGRESSION)[bar % 4]
bars = range(-1, int((DURATION - ORIGIN) / BAR) + 1)
half_time = lambda at: command_flash <= at < c2

music = {name: np.zeros((N, 2)) for name in level}
kick_times = []

def kick():
    n = int(0.42 * SR); t = seconds(n)
    body = np.sin(2 * np.pi * np.cumsum(46 + 120 * np.exp(-t / 0.032)) / SR) * np.exp(-t / 0.17)
    return body + highpass(noise(n), 2500) * np.exp(-t / 0.004) * 0.35

def clap():
    n = int(0.3 * SR); t = seconds(n)
    env = sum(np.exp(-np.clip(t - d, 0, None) / 0.012) * (t >= d) for d in (0, 0.011, 0.023)) * 0.4 + np.exp(-t / 0.09) * 0.6
    return bandpass(noise(n), 900, 4200) * env

def hat(open_=False):
    n = int((0.22 if open_ else 0.06) * SR)
    return highpass(noise(n), 7500, 4) * np.exp(-seconds(n) / (0.07 if open_ else 0.016))

def pluck(freq, dur=0.5):
    n = int(dur * SR); t = seconds(n)
    tone = 0.6 * saw(freq, n) + 0.4 * np.sign(sine(freq, n)) * 0.6 + 0.3 * sine(freq * 2, n)
    return lowpass(tone * np.exp(-t / 0.13), 5200)

def pad_note(freq, dur):
    n = int(dur * SR); t = seconds(n)
    tone = sum(saw(freq * 2 ** (cents / 1200), n, phase) for cents, phase in ((-8, 0.0), (0, 0.33), (9, 0.71))) / 3
    env = np.clip(t / 0.5, 0, 1) * np.clip((dur - t) / 0.7, 0, 1)
    return lowpass(tone, 2400) * env

def bass_note(freq, dur):
    n = int(dur * SR); t = seconds(n)
    tone = 0.7 * saw(freq, n) + 0.6 * sine(freq, n)
    return lowpass(tone, 700) * np.clip(t / 0.006, 0, 1) * np.exp(-t / 0.28) * np.clip((dur - t) / 0.02, 0, 1)

def lead_note(freq, dur):
    n = int(dur * SR); t = seconds(n)
    vibrato = 1 + 0.004 * np.sin(2 * np.pi * 5.2 * t) * np.clip(t / 0.25, 0, 1)
    tone = 0.5 * np.sin(2 * np.pi * np.cumsum(freq * vibrato) / SR) + 0.25 * saw(freq, n) + 0.2 * sine(freq * 2, n)
    return lowpass(tone, 4200) * np.clip(t / 0.02, 0, 1) * np.exp(-t / (dur * 0.9)) * np.clip((dur - t) / 0.05, 0, 1)

KICK, CLAP, HAT, OPEN = kick(), clap(), hat(), hat(True)
ARP = [0, 2, 1, 2, 0, 2, 1, 2, 0, 2, 1, 2, 0, 1, 2, 1]
# A tune of four bars: (beat, beats long, note).
TUNE = [[(0, 1.5, 76), (1.5, 0.5, 74), (2, 0.5, 72), (2.5, 1.5, 69)], [(0, 1, 72), (1, 1, 69), (2, 2, 65)],
        [(0, 1.5, 72), (1.5, 0.5, 74), (2, 1, 76), (3, 1, 79)], [(0, 1.5, 74), (1.5, 0.5, 71), (2, 2, 67)]]
for bar in bars:
    at = ORIGIN + bar * BAR
    if at < -BAR: continue
    notes = chord(bar, at)
    # pad: the chord, held, with the fifth an octave down
    for i, note in enumerate(notes + [notes[0] - 12]):
        place(music["pad"], pad_note(hz(note), BAR + 0.5), at, 0.22, (i - 1.5) * 0.35)
    for step in range(16):
        when = at + step * BEAT / 4
        if when < 0 or when >= DURATION: continue
        # arpeggio, an octave up, with an echo on the other side
        note = notes[ARP[step] % 3] + 12 + (12 if ARP[step] == 3 or step % 8 == 7 else 0)
        sound = pluck(hz(note))
        place(music["arp"], sound, when, 0.30, -0.5 if step % 2 else 0.5)
        place(music["arp"], sound, when + BEAT * 0.75, 0.13, 0.5 if step % 2 else -0.5)
        if step % 2 == 0:
            octave = 12 if step in (6, 14) else 0
            place(music["bass"], bass_note(hz(notes[0] - 24 + octave), BEAT / 2 - 0.01), when, 0.2)
            place(music["hat"], OPEN if step == 14 else HAT, when, 0.26 if step % 4 else 0.15, 0.2)
        elif a2 <= when < a3 or devices <= when < ending:
            place(music["hat"], HAT, when, 0.13, -0.2)
        slow = half_time(when)
        if step in ((0, 10) if slow else (0, 8)) or (step == 14 and bar % 4 == 3 and not slow):
            place(music["kick"], KICK, when, 0.5); kick_times.append(when)
        if step in ((8,) if slow else (4, 12)):
            place(music["kick"], CLAP, when, 0.42)
    for beat, length, note in TUNE[bar % 4]:
        place(music["lead"], lead_note(hz(note), length * BEAT), at + beat * BEAT, 0.2, 0.15)

# Before the turn: a low hum, and a heartbeat under the thought that opens command mode.
t_all = np.arange(N) / SR
hum = lowpass(0.5 * saw(55, N) + 0.5 * saw(82.4, N, 0.3) + 0.3 * saw(110.3, N, 0.6), 240) * (0.75 + 0.25 * np.sin(2 * np.pi * 0.13 * t_all))
music["drone"][:, 0] += hum * 0.12; music["drone"][:, 1] += np.roll(hum, 200) * 0.12
for beat in np.arange(command + 0.6, command_flash - 0.3, 1.2):
    place(music["kick"], KICK, beat, 0.32); place(music["kick"], KICK, beat + 0.22, 0.2)
    level["kick"][int(beat * SR): int((beat + 0.7) * SR)] = 1

# The kick pushes everything else down for a moment, the way a dance record breathes.
pump = np.ones(N)
for when in kick_times:
    i = int(when * SR); n = min(int(0.3 * SR), N - i)
    if n > 0 and level["kick"][i] > 0.3: pump[i:i + n] = np.minimum(pump[i:i + n], 1 - 0.55 * np.exp(-seconds(n) / 0.11))
track = np.zeros((N, 2))
for name, bus in music.items():
    shaped = bus * level[name][:, None]
    if name in ("pad", "arp", "bass", "lead", "drone"): shaped = shaped * pump[:, None]
    if name == "pad": shaped = highpass(shaped, 190)
    if name in ("pad", "arp", "lead"): shaped = reverb(shaped, 1.8, 0.3)
    track += shaped

# ---------------------------------------------------------------- effects
def bell(freqs, decay, n_seconds):
    n = int(n_seconds * SR); t = seconds(n)
    return sum(sine(f, n) * np.exp(-t / (decay / (1 + i * 0.6))) / (1 + i) for i, f in enumerate(freqs))

def swept_noise(n_seconds, lo, hi, shape):
    n = int(n_seconds * SR)
    return bandpass(noise(n), lo, hi) * shape(np.arange(n) / n)

def impact_sound(size=1.0):
    n = int(2.6 * SR); t = seconds(n)
    boom = np.sin(2 * np.pi * np.cumsum(34 + 60 * np.exp(-t / 0.09)) / SR) * np.exp(-t / 0.55)
    crash = highpass(noise(n), 1800) * np.exp(-t / 0.5) * 0.35
    return (boom * 0.9 + crash) * size

def riser(n_seconds):
    n = int(n_seconds * SR); p = np.arange(n) / n
    air = highpass(noise(n), 900) * p ** 2.2 * 0.5
    tone = glide(180, 1500, n, 2.0) * p ** 2 * 0.25
    return air + tone

def make(name):
    if name in ("tick", "knob"):
        n = int(0.05 * SR); t = seconds(n)
        return highpass(noise(n), 3000) * np.exp(-t / 0.003) * 0.7 + sine(2300 if name == "tick" else 900, n) * np.exp(-t / 0.011) * 0.5
    if name == "click":
        n = int(0.09 * SR); t = seconds(n)
        return sine(190, n) * np.exp(-t / 0.02) * 0.9 + highpass(noise(n), 2500) * np.exp(-t / 0.004) * 0.4
    if name == "clack":
        n = int(0.07 * SR); t = seconds(n)
        return bandpass(noise(n), 1400, 4500) * np.exp(-t / 0.008) * 0.8 + sine(310, n) * np.exp(-t / 0.015) * 0.4
    if name == "thud":
        n = int(0.25 * SR); t = seconds(n)
        return sine(95, n) * np.exp(-t / 0.06) + highpass(noise(n), 2000) * np.exp(-t / 0.005) * 0.3
    if name == "pop":
        n = int(0.12 * SR); t = seconds(n)
        return glide(420, 980, n, 0.6) * np.exp(-t / 0.035)
    if name == "blip":
        n = int(0.07 * SR); half = n // 2
        return np.concatenate([sine(880, half), sine(1320, n - half)]) * np.exp(-seconds(n) / 0.03) * 0.7
    if name == "spark":
        n = int(0.16 * SR); t = seconds(n)
        return sine(2400, n) * np.exp(-t / 0.03) * 0.5 + highpass(noise(n), 5000) * np.exp(-t / 0.02) * 0.3
    if name == "sparkle":
        out = np.zeros(int(0.5 * SR))
        for k in range(5):
            grain = sine(3000 + rng.uniform(0, 3500), int(0.12 * SR)) * np.exp(-seconds(int(0.12 * SR)) / 0.03)
            i = int(k * 0.06 * SR); out[i:i + len(grain)] += grain * 0.4
        return out
    if name == "shimmer":
        n = int(1.6 * SR); t = seconds(n)
        return highpass(noise(n), 6000) * np.exp(-t / 0.5) * (0.6 + 0.4 * np.sin(2 * np.pi * 9 * t)) * 0.4 + bell([2093, 3136, 4186], 0.9, 1.6) * 0.25
    if name == "ding": return bell([1046.5, 1568, 2093, 3136], 0.7, 1.6) * 0.6
    if name == "rec-on": return np.concatenate([sine(660, int(0.07 * SR)), sine(990, int(0.11 * SR))]) * np.hanning(int(0.07 * SR) + int(0.11 * SR)) * 0.6
    if name == "rec-off": return np.concatenate([sine(990, int(0.07 * SR)), sine(660, int(0.11 * SR))]) * np.hanning(int(0.07 * SR) + int(0.11 * SR)) * 0.6
    if name == "womp":
        n = int(0.7 * SR)
        f = 230 * (70 / 230) ** (np.arange(n) / n)
        return lowpass(2 * ((np.cumsum(f) / SR) % 1) - 1, 900) * np.hanning(n) * 0.7
    if name == "drop":
        n = int(0.45 * SR); return glide(900, 180, n, 0.7) * np.hanning(n) * 0.5
    if name == "whoosh": return swept_noise(0.55, 500, 5200, lambda p: np.sin(np.pi * p) ** 2) * 0.8
    if name == "whoosh-soft": return swept_noise(0.42, 700, 3800, lambda p: np.sin(np.pi * p) ** 2) * 0.45
    if name == "impact": return impact_sound(1.0)
    if name == "impact-soft": return impact_sound(0.55)
    if name == "riser": return riser(impact - scenes["title"][0] - 0.1)
    if name == "riser-short": return riser(1.2)
    raise KeyError(name)

LOUD = {"tick": 0.30, "knob": 0.45, "click": 0.38, "clack": 0.22, "thud": 0.45, "pop": 0.26, "blip": 0.18, "spark": 0.16, "sparkle": 0.16,
        "shimmer": 0.3, "ding": 0.32, "rec-on": 0.22, "rec-off": 0.22, "womp": 0.4, "drop": 0.22, "whoosh": 0.3, "whoosh-soft": 0.22,
        "impact": 0.85, "impact-soft": 0.6, "riser": 0.5, "riser-short": 0.4}
sounds = {}
effects = np.zeros((N, 2))
for cue in cues:
    name = cue["name"]
    if name not in sounds: sounds[name] = make(name)
    place(effects, sounds[name], cue["at"], LOUD[name] * cue["gain"], rng.uniform(-0.3, 0.3) if name in ("pop", "clack", "sparkle", "spark") else 0)
effects = reverb(effects, 1.1, 0.12)

# ---------------------------------------------------------------- voice
def read(path):
    with wave.open(str(path)) as source:
        data = np.frombuffer(source.readframes(source.getnframes()), dtype=np.int16).astype(np.float64) / 32768
        return data.reshape(-1, source.getnchannels()).mean(1)

narration, said = np.zeros((N, 2)), np.zeros((N, 2))
for name, at in timeline["vo"].items():
    voice = highpass(read(root / f"output/promo/vo/{language}/{name}.wav"), 70)
    role = script[name]["role"]
    place(said if role == "user" else narration, voice, at, 0.95 if role == "narrator" else 0.85)
narration = reverb(narration, 0.5, 0.035)
said = reverb(said, 0.7, 0.09)

def presence(x, attack=0.08, release=0.35):
    """How much somebody is speaking, 0 to 1, rising quickly and falling slowly."""
    loud = np.abs(x).max(1)
    block = 480
    frames = loud[: len(loud) // block * block].reshape(-1, block).max(1)
    smooth = np.zeros_like(frames); value = 0.0
    for i, frame in enumerate(frames > 0.02):
        value += (frame - value) * (block / SR) / (attack if frame > value else release)
        value = min(1.0, max(0.0, value)); smooth[i] = value
    return np.interp(np.arange(N), np.arange(len(smooth)) * block, smooth)

def master(x):
    x = np.tanh(x * 1.15) / 1.15
    return x / max(1e-9, np.abs(x).max()) * 0.89

def write(name, x):
    out = root / f"output/promo/audio/{language}"; out.mkdir(parents=True, exist_ok=True)
    with wave.open(str(out / f"{name}.wav"), "wb") as target:
        target.setnchannels(2); target.setsampwidth(2); target.setframerate(SR)
        target.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())

def rms_db(x, gate=None):
    x = x if gate is None else x[gate]
    return 20 * np.log10(np.sqrt((x ** 2).mean()) + 1e-12)

def to_level(x, target, gate=None): return x * 10 ** ((target - rms_db(x, gate)) / 20)

# Levels are set against the voice: the narrator at -18 dB RMS while speaking, the track about 9 dB under that
# while anyone speaks and 4 dB under otherwise, effects in between.
speaking = np.abs(narration).max(1) > 0.02
playing = np.abs(track).max(1) > 1e-4
voice_gain = 10 ** ((-18 - rms_db(narration, speaking)) / 20)
narration, said = narration * voice_gain, said * voice_gain
# A little air and presence: the layers are dark on their own.
track = track + 1.6 * highpass(track, 2500) + 0.7 * bandpass(track, 600, 2500)
track = to_level(track, -22, playing)
effects = effects * 0.5
duck_all = 1 - 0.55 * presence(narration + said)
duck_said = 1 - 0.55 * presence(said)
write("music", master(track)); write("sfx", master(effects)); write("voice", master(narration + said))
write("mix", master(track * duck_all[:, None] + effects + narration + said))
write("mix-no-narration", master(track * duck_said[:, None] * 1.25 + effects * 1.1 + said))
both = track * duck_all[:, None]
print("origin", round(ORIGIN, 3), "impact", round(impact, 3), "cues", len(cues))
print("while speaking: voice %.1f dB, track %.1f dB, effects %.1f dB" % (rms_db(narration, speaking), rms_db(both, speaking), rms_db(effects, speaking)))
spectrum = np.abs(np.fft.rfft(track[int(50 * SR):int(60 * SR), 0])) ** 2
freqs = np.fft.rfftfreq(10 * SR, 1 / SR)
print("track energy by band:", {f"{lo}-{hi}": round(100 * spectrum[(freqs >= lo) & (freqs < hi)].sum() / spectrum.sum(), 1) for lo, hi in ((20, 120), (120, 500), (500, 2000), (2000, 6000), (6000, 16000))})
