#!/usr/bin/env python3
"""Original sound effects, synthesised from sine waves and filtered noise.
No recordings, no samples, no generative models: every sound is a short
formula, so the project owns it outright. Writes 44.1 kHz 16 bit mono WAVs
into assets/sounds/. Run from the repo root: python3 tools/mksounds.py"""
import math, os, wave, numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sounds")
rng = np.random.default_rng(7)


def t(seconds):
    return np.arange(int(SR * seconds)) / SR


def env(n, attack, decay, curve=3.0):
    x = np.linspace(0.0, 1.0, n)
    a = np.clip(x / max(attack, 1e-4), 0, 1)
    d = np.exp(-x * decay * curve)
    return a * d


def lowpass(sig, cutoff):
    rc = 1.0 / (2 * math.pi * cutoff)
    alpha = (1.0 / SR) / (rc + 1.0 / SR)
    out = np.zeros_like(sig)
    acc = 0.0
    for i, v in enumerate(sig):
        acc += alpha * (v - acc)
        out[i] = acc
    return out


def write(name, sig, gain=0.8):
    sig = sig / max(np.max(np.abs(sig)), 1e-6) * gain
    data = (sig * 32767).astype(np.int16)
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(name, len(sig) / SR, "s")


# Bolt cast: a bright chirp sliding up with a whisper of air behind it.
x = t(0.22)
f = 520 + 900 * (x / x[-1]) ** 0.6
chirp = np.sin(2 * math.pi * np.cumsum(f) / SR) * env(len(x), 0.01, 6.0)
air = lowpass(rng.standard_normal(len(x)), 3500) * env(len(x), 0.005, 9.0) * 0.5
write("cast_bolt.wav", chirp + air)

# Bolt hit: a short low thump with a crackle on top.
x = t(0.18)
thump = np.sin(2 * math.pi * (160 - 90 * x / x[-1]) * x) * env(len(x), 0.002, 10.0)
crackle = lowpass(rng.standard_normal(len(x)), 6000) * env(len(x), 0.001, 25.0) * 0.6
write("hit_bolt.wav", thump + crackle)

# Melee hit: a dull knock, lower and shorter.
x = t(0.12)
knock = np.sin(2 * math.pi * (110 - 50 * x / x[-1]) * x) * env(len(x), 0.002, 14.0)
tick = lowpass(rng.standard_normal(len(x)), 2500) * env(len(x), 0.001, 40.0) * 0.4
write("hit_melee.wav", knock + tick)

# Ground area: a low swell that lands as a boom.
x = t(0.7)
swell = np.sin(2 * math.pi * 70 * x) * env(len(x), 0.25, 2.5) + np.sin(2 * math.pi * 105 * x) * env(len(x), 0.3, 3.0) * 0.5
rumble = lowpass(rng.standard_normal(len(x)), 400) * env(len(x), 0.2, 3.0) * 0.8
write("area_land.wav", swell + rumble)

# Ward: a soft rising chord that holds.
x = t(0.9)
chord = sum(np.sin(2 * math.pi * fq * x) for fq in (261.6, 329.6, 392.0)) * env(len(x), 0.15, 1.2) / 3
write("ward_rise.wav", chord)

# Tower shot: a hard crack with a short metallic ring.
x = t(0.35)
crack = lowpass(rng.standard_normal(len(x)), 9000) * env(len(x), 0.001, 30.0)
ring = np.sin(2 * math.pi * 880 * x) * env(len(x), 0.002, 8.0) * 0.5 + np.sin(2 * math.pi * 1320 * x) * env(len(x), 0.002, 12.0) * 0.25
write("tower_shot.wav", crack + ring)

# Champion death: a falling tone with a thud at the end.
x = t(0.8)
fall = np.sin(2 * math.pi * np.cumsum(300 * (1 - 0.7 * x / x[-1])) / SR) * env(len(x), 0.01, 2.0)
thud_i = int(SR * 0.45)
thud = np.zeros_like(x)
xt = t(0.25)
thud[thud_i:thud_i + len(xt)] = np.sin(2 * math.pi * (90 - 40 * xt / xt[-1]) * xt) * env(len(xt), 0.002, 8.0)
write("death_champion.wav", fall * 0.6 + thud)

# Minion death: a small pop.
x = t(0.1)
pop = lowpass(rng.standard_normal(len(x)), 1800) * env(len(x), 0.001, 30.0)
write("death_minion.wav", pop, 0.5)

# Footstep on stone, four variants: short filtered tap.
for i in range(4):
    x = t(0.07)
    step = lowpass(rng.standard_normal(len(x)), 900 + 200 * i) * env(len(x), 0.001, 35.0)
    write("step_%d.wav" % i, step, 0.35)
