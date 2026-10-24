"""Make the worn steel texture set used on champion armour, from code.

  python3 tools/make_steel_maps.py

Writes assets/env/textures/forged_steel_{diff,nor_gl,arm}_1k.jpg in the
same layout as the Poly Haven sets (arm = AO, roughness, metal), so
ChampionModel can use it like any other set. Everything here is procedural
(seeded noise and random strokes), so it tiles and is our own work.

The look: hammered plate with soft rubbed patches, fine directional brushing
and a scatter of scratches. Kept low contrast so team colours and silhouettes
stay in charge at game distance.
"""
import os

import numpy as np
from PIL import Image

N = 1024
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "env", "textures")
rng = np.random.default_rng(1207)


def band_noise(lo, hi, aniso=(1.0, 1.0)):
    """Tileable noise: white noise filtered to a band of frequencies (cycles per tile)."""
    f = np.fft.fft2(rng.standard_normal((N, N)))
    ky = np.fft.fftfreq(N)[:, None] * N * aniso[1]
    kx = np.fft.fftfreq(N)[None, :] * N * aniso[0]
    k = np.sqrt(kx * kx + ky * ky)
    mask = np.exp(-((np.log(k + 1e-6) - np.log(np.sqrt(lo * hi))) ** 2) / (2 * (np.log(hi / lo) / 2) ** 2))
    mask[0, 0] = 0
    n = np.real(np.fft.ifft2(f * mask))
    return (n - n.mean()) / (n.std() + 1e-9)


def strokes(count, length, width, depth):
    """Random straight scratches, wrapping at the edges so the tile repeats."""
    h = np.zeros((N, N), np.float32)
    for _ in range(count):
        x0, y0 = rng.uniform(0, N, 2)
        a = rng.normal(0.35, 0.5)
        ln = rng.uniform(0.3, 1.0) * length
        steps = int(ln)
        xs = (x0 + np.cos(a) * np.arange(steps)) % N
        ys = (y0 + np.sin(a) * np.arange(steps)) % N
        d = depth * rng.uniform(0.4, 1.0)
        for w in range(-width, width + 1):
            fall = 1.0 - abs(w) / (width + 1)
            h[(ys.astype(int) + w) % N, xs.astype(int)] -= d * fall
    return h


# Height: broad hammer dents, fine brushing along x, and scratches.
dents = band_noise(6, 18)
brush = band_noise(60, 260, aniso=(0.12, 1.0))
scratch = strokes(110, 120, 1, 0.8)
height = 0.3 * dents + 0.1 * brush + 0.7 * scratch

# Normal map (OpenGL convention, green up) from the height field.
gy, gx = np.gradient(height)
strength = 0.6
nx, ny, nz = -gx * strength, gy * strength, np.ones_like(height)
ln = np.sqrt(nx * nx + ny * ny + nz * nz)
nor = np.stack([nx / ln, ny / ln, nz / ln], -1) * 0.5 + 0.5

# Wear: rubbed bright patches where the plate is handled most.
wear = band_noise(3, 9)
wear = np.clip((wear - 0.2) * 0.6, 0, 1)

# Roughness: mid satin, polished where worn, rougher in scratches and dents.
rough = 0.6 - 0.12 * wear + 0.03 * dents - 0.25 * np.clip(scratch, -1, 0) + 0.04 * brush
rough = np.clip(rough, 0.25, 0.9)
ao = np.clip(1.0 + 0.08 * np.minimum(dents, 0) + 0.25 * np.clip(scratch, -1, 0), 0.6, 1.0)
metal = np.ones_like(rough)
arm = np.stack([ao, rough, metal], -1)

# Albedo: near white (the material tint gives the metal colour), darker grime
# in dents and scratches, lighter where rubbed.
alb = 0.9 + 0.03 * wear - 0.015 * np.clip(-dents, 0, 2) + 0.06 * np.clip(scratch, -1, 0) + 0.015 * brush
alb = np.clip(alb, 0.55, 1.0)
diff = np.stack([alb, alb * 0.995, alb * 0.985], -1)


def save(a, name):
    Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)).save(os.path.join(OUT, "forged_steel_%s_1k.jpg" % name), quality=92)


save(diff, "diff")
save(nor, "nor_gl")
save(arm, "arm")
print("wrote forged_steel maps to", os.path.normpath(OUT))
