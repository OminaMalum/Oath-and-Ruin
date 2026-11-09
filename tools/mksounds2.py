#!/usr/bin/env python3
"""Second set of original sound effects (gate5a): ability casts by kind,
match callouts, shop and interface clicks, and a wind bed.

Like tools/mksounds.py: no recordings, no samples, no generative models.
Every sound is sines, shaped noise and a synthetic room (decaying noise
convolved in), written as 44.1 kHz 16 bit mono WAVs into assets/sounds/.
Run from the repo root: python3 tools/mksounds2.py"""
import math, os, wave
import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sounds")
rng = np.random.default_rng(11)
TAU = 2 * math.pi


def t(seconds):
    return np.arange(int(SR * seconds)) / SR


def env(n, attack, decay, curve=3.0):
    x = np.linspace(0.0, 1.0, n)
    return np.clip(x / max(attack, 1e-4), 0, 1) * np.exp(-x * decay * curve)


def bell(n, peak=0.5, sharp=2.0):
    """Rise then fall, peak at `peak` (0 to 1)."""
    x = np.linspace(0.0, 1.0, n)
    return np.where(x < peak, (x / peak) ** sharp, ((1 - x) / (1 - peak)) ** sharp)


def fade(sig, ms=4.0):
    n = min(int(SR * ms / 1000.0), len(sig) // 2)
    sig = sig.copy()
    sig[:n] *= np.linspace(0, 1, n)
    sig[-n:] *= np.linspace(1, 0, n)
    return sig


def band(sig, lo, hi, order=2):
    """Zero phase band filter in the frequency domain (lo or hi may be None)."""
    spec = np.fft.rfft(sig)
    f = np.fft.rfftfreq(len(sig), 1.0 / SR)
    g = np.ones_like(f)
    if hi:
        g *= 1.0 / np.sqrt(1.0 + (f / hi) ** (2 * order))
    if lo:
        g *= 1.0 / np.sqrt(1.0 + (lo / np.maximum(f, 1e-3)) ** (2 * order))
    return np.fft.irfft(spec * g, len(sig))


def noise(n):
    return rng.standard_normal(n)


def sweep(f0, f1, n, curve=1.0):
    """Sine whose pitch runs from f0 to f1."""
    x = np.linspace(0.0, 1.0, n) ** curve
    f = f0 + (f1 - f0) * x
    return np.sin(TAU * np.cumsum(f) / SR)


def swept_noise(n, f0, f1, width=0.5):
    """Noise through a band whose centre moves from f0 to f1: a whoosh."""
    out = np.zeros(n)
    hop = 256
    win = np.hanning(hop * 2)
    src = noise(n + hop * 2)
    for i in range(0, n, hop):
        k = i / max(n - 1, 1)
        fc = f0 * (f1 / f0) ** k
        seg = band(src[i:i + hop * 2], fc * (1 - width * 0.5), fc * (1 + width * 0.5), 2) * win
        end = min(i + hop * 2, n)
        out[i:end] += seg[:end - i]
    return out


def partials(freq, n, ratios, amps, decays):
    """Struck metal or glass: inharmonic partials, each with its own decay."""
    x = np.arange(n) / SR
    out = np.zeros(n)
    for r, a, d in zip(ratios, amps, decays):
        out += a * np.sin(TAU * freq * r * x + rng.uniform(0, TAU)) * np.exp(-x * d)
    return out


def brass(freq, seconds, bright=1.0, vib=0.004):
    """A horn note: harmonics that open up as the note swells."""
    n = int(SR * seconds)
    x = np.arange(n) / SR
    phase = TAU * freq * x + vib * freq * np.sin(TAU * 5.2 * x) / 5.2 * TAU
    swell = np.clip(x / 0.09, 0, 1) * np.clip((seconds - x) / 0.16, 0, 1)
    out = np.zeros(n)
    for h in range(1, 14):
        if freq * h > 9000:
            break
        open_ = swell ** (0.6 + 0.35 * h / bright)
        out += np.sin(phase * h) * open_ / (h ** 1.15)
    return out * swell


def room(sig, seconds=1.2, wet=0.25, tone=3500):
    """A synthetic hall: the sound convolved with decaying filtered noise."""
    n = int(SR * seconds)
    ir = band(noise(n), 150, tone, 1) * np.exp(-np.arange(n) / SR * (6.0 / seconds))
    ir[:int(SR * 0.012)] = 0.0
    ir /= np.sqrt(np.sum(ir ** 2))
    size = len(sig) + n
    tail = np.fft.irfft(np.fft.rfft(sig, size) * np.fft.rfft(ir, size), size)
    dry = np.concatenate([sig, np.zeros(n)])
    return dry + tail * wet * (np.max(np.abs(sig)) / max(np.max(np.abs(tail)), 1e-6))


def place(total, parts):
    """Mix [(start seconds, signal)] into one buffer of `total` seconds."""
    out = np.zeros(int(SR * total))
    for start, sig in parts:
        i = int(SR * start)
        end = min(i + len(sig), len(out))
        out[i:end] += sig[:end - i]
    return out


def mix(*sigs):
    """Sum signals of different lengths."""
    out = np.zeros(max(len(s) for s in sigs))
    for s in sigs:
        out[:len(s)] += s
    return out


def write(name, sig, gain=0.8, tail_fade=True):
    sig = sig / max(np.max(np.abs(sig)), 1e-6) * gain
    if tail_fade:
        # Drop the part of a room tail nobody can hear (below about -56 dB).
        loud = np.nonzero(np.abs(sig) > 0.0015)[0]
        if len(loud):
            sig = sig[:min(len(sig), loud[-1] + int(SR * 0.02))]
        # Fade the end only: a fade in would blunt every strike.
        k = min(int(SR * 0.004), len(sig) // 2)
        sig = sig.copy()
        sig[-k:] *= np.linspace(1, 0, k)
        sig[:12] *= np.linspace(0, 1, 12)
    data = (sig * 32767).astype(np.int16)
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("%-18s %.2f s" % (name, len(sig) / SR))


# ---------------------------------------------------------------- casts

# Bow or thrown blade: the string's snap, then air.
n = int(SR * 0.26)
snap = sweep(240, 150, n) * env(n, 0.004, 9.0) + 0.4 * sweep(480, 300, n) * env(n, 0.003, 14.0)
air = swept_noise(n, 1800, 5200, 0.7) * bell(n, 0.25, 1.5) * 0.7
write("cast_arrow", snap + air, 0.75)

# Heavy spell (ultimates, big shots): a deep push with a falling tear.
n = int(SR * 0.55)
push = sweep(95, 48, n) * env(n, 0.02, 3.0)
tear = sweep(1100, 260, n, 0.6) * env(n, 0.01, 5.0) * 0.35
hiss = band(noise(n), 800, 5000) * env(n, 0.01, 6.0) * 0.4
write("cast_heavy", room(push + tear + hiss, 0.6, 0.18), 0.85)

# Melee swings: air moved by a blade, light and heavy.
n = int(SR * 0.2)
write("swing", swept_noise(n, 700, 3200, 0.8) * bell(n, 0.45, 2.0), 0.55)
n = int(SR * 0.3)
write("swing_heavy", swept_noise(n, 260, 1500, 0.9) * bell(n, 0.5, 2.0) + 0.3 * sweep(120, 70, n) * bell(n, 0.5, 2.0), 0.7)

# A hit that stuns or shoves: wood and iron.
n = int(SR * 0.34)
thud = sweep(105, 42, n) * env(n, 0.002, 6.0)
crunch = band(noise(n), 300, 3200) * env(n, 0.001, 16.0) * 0.7
clank = partials(410, n, [1, 2.32, 3.9], [0.5, 0.3, 0.2], [18, 26, 34]) * 0.5
write("hit_heavy", thud + crunch + clank, 0.9)

# Dash: a quick rush of air past the ear.
n = int(SR * 0.32)
write("dash", swept_noise(n, 500, 4200, 0.9) * bell(n, 0.35, 1.6), 0.6)

# Grapple: a chain paying out, faster and faster, with a rising zip.
n = int(SR * 0.5)
chain = np.zeros(n)
at = 0.0
gap = 0.055
while at < 0.44:
    link = partials(rng.uniform(2300, 3100), int(SR * 0.05), [1, 1.47, 2.09, 2.86], [0.5, 0.4, 0.3, 0.2], [70, 90, 110, 130])
    i = int(SR * at)
    chain[i:i + len(link)] += link[:n - i] * rng.uniform(0.6, 1.0)
    at += gap
    gap = max(gap * 0.86, 0.012)
zip_ = sweep(300, 1300, n, 1.6) * bell(n, 0.8, 2.0) * 0.25
write("grapple", chain + zip_, 0.6)

# Shield: struck glass that hangs in the air.
n = int(SR * 0.6)
glass = partials(880, n, [1, 1.5, 2.01, 2.99], [0.6, 0.4, 0.3, 0.15], [5, 6, 8, 11]) * np.clip(np.arange(n) / (SR * 0.02), 0, 1)
write("shield", room(glass, 0.8, 0.3, 6000), 0.6)

# Heal: three soft bells going up.
notes = [523.25, 659.25, 783.99]
parts = []
for i, f in enumerate(notes):
    m = int(SR * 0.5)
    parts.append((i * 0.075, partials(f, m, [1, 2.0, 3.01], [0.7, 0.25, 0.1], [7, 10, 14]) * np.clip(np.arange(m) / (SR * 0.01), 0, 1)))
write("heal", room(place(0.7, parts), 0.9, 0.3, 5000), 0.55)

# Self buff (haste, brace, a song): a breath in and a bright rise.
n = int(SR * 0.4)
rise = sweep(330, 660, n, 0.7) * bell(n, 0.6, 1.5) * 0.5 + sweep(660, 1320, n, 0.7) * bell(n, 0.7, 2.0) * 0.2
breath = swept_noise(n, 900, 3000, 0.8) * bell(n, 0.5, 2.0) * 0.3
write("buff", room(rise + breath, 0.5, 0.2), 0.55)

# Summon: the ground gives, then something arrives.
n = int(SR * 0.7)
give = sweep(70, 110, n) * env(n, 0.05, 2.5)
arrive = partials(392, n, [1, 2.02, 2.98, 4.1], [0.4, 0.3, 0.2, 0.1], [6, 8, 10, 12]) * bell(n, 0.3, 1.2) * 0.5
dust = band(noise(n), 200, 1800) * env(n, 0.08, 3.0) * 0.4
write("summon", room(give + arrive + dust, 0.7, 0.22), 0.7)

# Stun: a dull bell, the kind you hear inside a helmet.
n = int(SR * 0.6)
dong = partials(330, n, [1, 2.76, 5.4, 8.9], [0.8, 0.35, 0.15, 0.05], [6, 9, 14, 20])
write("stun", room(dong, 0.5, 0.15, 2500), 0.6)

# ------------------------------------------------------------ structures

def stones(seconds, count, low, high):
    parts = []
    for _ in range(count):
        at = rng.uniform(0.0, seconds * 0.7) ** 1.0
        m = int(SR * rng.uniform(0.12, 0.3))
        f = rng.uniform(low, high)
        knock = sweep(f, f * 0.55, m) * env(m, 0.003, 7.0) + band(noise(m), 200, 2400) * env(m, 0.002, 14.0) * 0.6
        parts.append((at, knock * rng.uniform(0.4, 1.0)))
    return place(seconds, parts)

# Tower falls: a crack, then masonry coming down.
n = int(SR * 2.4)
crack = band(noise(int(SR * 0.25)), 500, 7000) * env(int(SR * 0.25), 0.002, 9.0)
rumble = band(noise(n), 30, 260) * env(n, 0.06, 1.6) * 1.4
fall = place(2.4, [(0.0, crack), (0.05, stones(2.2, 16, 70, 190))])
write("tower_fall", room(rumble + fall, 1.0, 0.2, 2200), 0.9)

# Core falls: the same, larger, with the crystal breaking.
n = int(SR * 3.4)
rumble = band(noise(n), 25, 220) * env(n, 0.05, 1.2) * 1.5
shards = []
for _ in range(22):
    m = int(SR * 0.4)
    shards.append((rng.uniform(0.05, 1.6), partials(rng.uniform(1800, 5200), m, [1, 1.52, 2.4], [0.5, 0.3, 0.2], [14, 20, 28]) * rng.uniform(0.2, 0.7)))
toll = partials(98, n, [1, 2.4, 3.9, 5.3], [0.9, 0.5, 0.3, 0.15], [1.2, 1.8, 2.6, 3.4])
fall = place(3.4, [(0.0, crack), (0.05, stones(3.0, 24, 55, 170))] + shards)
write("core_fall", room(rumble + fall + toll * 0.7, 1.6, 0.28, 3000), 0.9)

# ------------------------------------------------------------- interface

n = int(SR * 0.05)
write("ui_click", sweep(1500, 900, n) * env(n, 0.002, 12.0) + band(noise(n), 2000, 8000) * env(n, 0.001, 40.0) * 0.3, 0.4)
n = int(SR * 0.03)
write("ui_hover", sweep(2100, 1900, n) * env(n, 0.004, 14.0), 0.16)
n = int(SR * 0.09)
write("ui_back", sweep(900, 520, n) * env(n, 0.002, 9.0), 0.35)
# Shop opens: a ledger cover and a latch.
n = int(SR * 0.22)
cover = band(noise(n), 150, 1400) * env(n, 0.004, 9.0)
latch = place(0.22, [(0.07, partials(1900, int(SR * 0.08), [1, 1.6, 2.7], [0.5, 0.3, 0.2], [40, 55, 70]))])
write("shop_open", cover + latch * 0.5, 0.5)


def coin(freq, seconds=0.22):
    m = int(SR * seconds)
    return partials(freq, m, [1, 1.41, 2.25, 3.12, 4.6], [0.6, 0.5, 0.35, 0.2, 0.1], [16, 20, 26, 34, 44])

write("gold", coin(3100, 0.18), 0.3)
write("buy", room(place(0.5, [(0.0, coin(2600)), (0.07, coin(3300)), (0.13, coin(2900)), (0.2, coin(3900))]), 0.3, 0.12, 7000), 0.5)
write("sell", room(place(0.45, [(0.0, coin(3600)), (0.08, coin(2900)), (0.17, coin(2300))]), 0.3, 0.12, 7000), 0.45)
# No: a low double knock.
n = int(SR * 0.07)
knock = (np.sin(TAU * 130 * np.arange(n) / SR) + 0.4 * np.sin(TAU * 260 * np.arange(n) / SR)) * env(n, 0.004, 6.0)
write("deny", place(0.2, [(0.0, knock), (0.1, knock * 0.8)]), 0.4)


def chime(freq, seconds=0.9):
    m = int(SR * seconds)
    return partials(freq, m, [1, 2.0, 3.0, 4.2], [0.7, 0.3, 0.14, 0.06], [4.5, 6, 8, 11]) * np.clip(np.arange(m) / (SR * 0.006), 0, 1)

# Level up: four bells climbing a major chord.
write("level_up", room(place(1.2, [(0.0, chime(587.33)), (0.09, chime(739.99)), (0.18, chime(880.0)), (0.27, chime(1174.66))]), 1.0, 0.3, 6000), 0.6)
# Upgrade chosen and ultimate unlocked: a fuller chord, struck together.
write("upgrade", room(place(1.1, [(0.0, chime(392.0) + chime(587.33) + chime(783.99)), (0.12, chime(1174.66) * 0.7)]), 1.1, 0.3, 6000), 0.6)
# Recall: a hum that climbs for four seconds (stopped if the recall breaks).
n = int(SR * 4.0)
x = np.arange(n) / SR
hum = (sweep(110, 220, n, 1.4) + 0.5 * sweep(165, 330, n, 1.4) + 0.25 * sweep(220, 440, n, 1.4)) * (0.15 + 0.85 * (x / 4.0) ** 1.5)
hum *= 1.0 + 0.25 * np.sin(TAU * (3.0 + 5.0 * x / 4.0) * x)
shimmer = band(noise(n), 2500, 7000) * (x / 4.0) ** 2 * 0.25
write("recall", fade(hum + shimmer, 30.0), 0.4)
# Arrived home, and back from the dead: air closing in, one clear bell.
n = int(SR * 0.35)
write("recall_done", room(place(0.9, [(0.0, swept_noise(n, 3500, 500, 0.9) * bell(n, 0.3, 1.5) * 0.6), (0.12, chime(659.25, 0.7))]), 0.8, 0.28, 5000), 0.55)
n = int(SR * 0.8)
swell = (np.sin(TAU * 196 * np.arange(n) / SR) + 0.5 * np.sin(TAU * 294 * np.arange(n) / SR)) * bell(n, 0.7, 1.8)
write("respawn", room(place(1.3, [(0.0, swell * 0.6), (0.5, chime(783.99, 0.7))]), 1.0, 0.3, 5000), 0.5)

# -------------------------------------------------------------- callouts

D3, F3, G3, A3, C4, D4, E4, F4, Fs4, G4, A4, B4, C5, D5, E5, Fs5, G5, A5 = (146.83, 174.61, 196.0, 220.0, 261.63, 293.66,
    329.63, 349.23, 369.99, 392.0, 440.0, 493.88, 523.25, 587.33, 659.25, 739.99, 783.99, 880.0)


def horn_line(notes, bright=1.0):
    """notes: [(start, freq or [freqs], seconds)]"""
    parts = []
    total = 0.0
    for start, f, sec in notes:
        fs = f if isinstance(f, (list, tuple)) else [f]
        sig = sum(brass(q, sec, bright) for q in fs) / len(fs)
        parts.append((start, sig))
        total = max(total, start + sec)
    return place(total + 0.05, parts)

# Good news for your side: a horn call that rises a fifth.
write("horn_ally", room(horn_line([(0.0, D4, 0.32), (0.3, A4, 0.75)], 1.1), 1.6, 0.3, 3200), 0.6)
# Bad news: a lower horn that falls.
write("horn_enemy", room(horn_line([(0.0, A3, 0.34), (0.32, F3, 0.85)], 0.8), 1.6, 0.3, 2600), 0.6)
# The objective: a deep gong.
n = int(SR * 2.6)
gong = partials(98, n, [1, 1.48, 2.02, 2.74, 3.76, 5.1], [1.0, 0.6, 0.5, 0.35, 0.2, 0.1], [1.0, 1.4, 1.8, 2.4, 3.2, 4.4])
gong *= np.clip(np.arange(n) / (SR * 0.01), 0, 1)
write("objective", room(gong, 1.8, 0.3, 2800), 0.7)
# A kill for your side: two quick bright notes.
write("kill_ally", room(place(0.6, [(0.0, mix(chime(D5, 0.4), brass(D4, 0.14, 1.2) * 0.5)), (0.11, mix(chime(A5, 0.5), brass(A4, 0.3, 1.2) * 0.5))]), 0.9, 0.25, 5000), 0.55)
# An ally falls: two low notes, down.
write("kill_enemy", room(horn_line([(0.0, F4, 0.16), (0.14, D4, 0.4)], 0.7), 0.9, 0.25, 2400), 0.5)
# First blood and multi kills: a three note flourish.
write("flourish", room(horn_line([(0.0, D4, 0.14), (0.13, Fs4, 0.14), (0.26, [A4, D5], 0.6)], 1.3), 1.4, 0.3, 4000), 0.65)
# A whole team down.
write("flourish_big", room(horn_line([(0.0, D4, 0.14), (0.13, Fs4, 0.14), (0.26, A4, 0.14), (0.39, [D5, Fs5, A4], 0.9)], 1.4), 1.8, 0.32, 4200), 0.7)
# Match start: one long plain call.
write("horn_start", room(horn_line([(0.0, [D4, A3], 1.1)], 0.9), 2.0, 0.34, 2800), 0.55)
# Victory: a short fanfare that lands on a major chord.
vic = horn_line([(0.0, D4, 0.2), (0.2, D4, 0.12), (0.32, Fs4, 0.2), (0.52, A4, 0.3), (0.86, [D4, Fs4, A4, D5], 1.6)], 1.4)
write("victory", room(vic, 2.4, 0.34, 4200), 0.7)
# Defeat: slow steps down to a bare low fifth.
lose = horn_line([(0.0, A3, 0.5), (0.5, G3, 0.5), (1.0, F3, 0.55), (1.6, [D3, A3], 1.7)], 0.7)
write("defeat", room(lose, 2.6, 0.36, 2200), 0.65)

# -------------------------------------------------------------- ambience

# Wind over the walls, 12 s. Made from one random spectrum, so it is exactly
# periodic and loops without a seam; the swells have periods that divide 12 s.
n = SR * 12
spec = (rng.standard_normal(n // 2 + 1) + 1j * rng.standard_normal(n // 2 + 1))
f = np.fft.rfftfreq(n, 1.0 / SR)
shape = 1.0 / np.sqrt(1.0 + (f / 420.0) ** 4) * 1.0 / np.sqrt(1.0 + (70.0 / np.maximum(f, 1e-3)) ** 4)
low = np.fft.irfft(spec * shape, n)
spec2 = (rng.standard_normal(n // 2 + 1) + 1j * rng.standard_normal(n // 2 + 1))
shape2 = 1.0 / np.sqrt(1.0 + (f / 1500.0) ** 6) * 1.0 / np.sqrt(1.0 + (500.0 / np.maximum(f, 1e-3)) ** 6)
high = np.fft.irfft(spec2 * shape2, n)
x = np.arange(n) / SR
gust = 0.62 + 0.2 * np.sin(TAU * x / 12.0) + 0.12 * np.sin(TAU * x / 4.0 + 1.3) + 0.06 * np.sin(TAU * x / 2.4 + 0.4)
whistle = 0.25 + 0.2 * np.sin(TAU * x / 6.0 + 2.0) + 0.1 * np.sin(TAU * x / 3.0)
wind = low / np.max(np.abs(low)) * gust + high / np.max(np.abs(high)) * whistle * 0.35
write("amb_wind", wind, 0.5, tail_fade=False)
