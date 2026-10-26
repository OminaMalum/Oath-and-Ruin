# SPDX-License-Identifier: GPL-2.0-or-later
# (Uses Blender's Python API. This is a build tool, not part of the game.)
"""Build Gravebinder's summon, the Willing Dead: a tall shrouded figure that
floats, its hem torn into strips that fade into violet light, bound in pale
funeral cords, a dark hooded face with two lit eyes and long bone hands.
Serious, not a cartoon skeleton. No legs are drawn: the shroud hangs clear
of the ground. Original geometry.

  /opt/bpyenv/bin/python tools/blender/build_willing_dead.py OUT.blend
"""
import math

import bpy  # noqa: F401,I001  (bpy first: it makes mathutils importable)
from mathutils import Vector

import champion_kit as ck
from champion_kit import TAU, Kit, base

S = 0.94
W = 0.95
FLOAT = 0.24  # the hem hangs this far above the ground

NAMES = ck.BODY


def bones():
    return ck.humanoid_bones(S, W)


def _ring(cz, r, n=14, cy=0.0, sx=1.0, sy=1.0):
    return [(math.sin(i / n * TAU) * r * sx, cy + math.cos(i / n * TAU) * r * sy, cz) for i in range(n + 1)]


def build_model(rig, M):
    bn = rig.data.bones
    z = lambda v: v * S  # noqa: E731
    n = 20

    # The shroud, one piece from the shoulders to a torn hem. Each strip of
    # the hem ends at its own height, so the bottom edge never reads as a cone.
    k = Kit("Shroud", M)
    prof = [(0.33, FLOAT), (0.33, FLOAT + 0.08), (0.31, 0.34), (0.27, 0.62), (0.24, 0.92), (0.25, 1.12), (0.27, 1.3),
            (0.26, 1.42), (0.18, 1.5), (0.11, 1.54)]
    rings = []
    for j, (r, h) in enumerate(prof):
        ring = []
        for i in range(n):
            th = i / n * TAU
            tear = 0.0
            if j == 0:
                tear = (0.09 * (0.5 + 0.5 * math.sin(i * 2.7 + 0.4)) + (0.05 if i % 3 == 0 else 0.0))
            elif j == 1:
                tear = 0.03 * (0.5 + 0.5 * math.sin(i * 2.7 + 0.4))
            wob = (0.018 * math.sin(i * 1.9 + j)) if h < 0.7 else 0.0
            ring.append(Vector((math.sin(th) * (r * S + wob) * 1.05, math.cos(th) * (r * S + wob) * 0.9,
                                z(h) - tear * S + 0.02 * math.sin(i * 1.3) * (1 if j == 0 else 0))))
        rings.append(ring)
    k.ring_grid(rings, "Robe", u_scale=2.0)
    # The inside of the hem, darker, so the open bottom does not show the sky.
    k.lathe([(0.3 * S, z(FLOAT + 0.04)), (0.18 * S, z(0.42)), (0.05 * S, z(0.6))], "RobeInner", seg=n, sx=1.05, sy=0.9)
    k.finish(rig, ["hips", "spine", "chest", "skirt_f", "skirt_b"], solidify=0.01)

    # The light the hem dissolves into: a faint glowing band just inside it
    # and the ends of a few strips.
    k = Kit("HemGlow", M)
    k.lathe([(0.3 * S, z(FLOAT + 0.01)), (0.31 * S, z(FLOAT + 0.07))], "Glow", seg=n, sx=1.05, sy=0.9)
    for i in range(0, n, 2):
        th = i / n * TAU + 0.15
        p = Vector((math.sin(th) * 0.3 * S, math.cos(th) * 0.27 * S, z(FLOAT + 0.02)))
        k.tube([p, p + Vector((0, 0.0, -0.06)), p + Vector((0, 0, -0.16))], [0.022, 0.012, 0.003], "Glow", seg=5)
    k.finish(rig, ["hips", "skirt_f", "skirt_b"])

    # Funeral cords: pale bindings at the chest, the waist and the knees.
    k = Kit("Cords", M)
    for h, r in ((1.3, 0.275), (0.95, 0.245)):
        pts = [Vector(p) for p in _ring(z(h), r * S + 0.01, n=16, sx=1.05, sy=0.9)]
        k.tube(pts, [0.009] * len(pts), "Bone", seg=5, cap=False)
    # A loose cord end hanging from the waist knot, in front.
    kn = Vector((0.05, 0.24 * S * 0.9 + 0.01, z(0.95)))
    k.tube([kn, kn + Vector((0.01, 0.02, -0.14)), kn + Vector((-0.01, 0.015, -0.3))], [0.012, 0.011, 0.008], "Bone", seg=5)
    k.finish(rig, ["hips", "spine", "chest", "skirt_f"])

    # A deep hood. The face inside is in shadow; only the eyes catch light.
    hz = bn["head"].head_local.z
    hy = bn["head"].head_local.y
    k = Kit("Hood", M)
    k.lathe([(0.17, z(1.46)), (0.15, z(1.53)), (0.11, z(1.58))], "Robe", seg=14, sx=1.1)
    k.sphere((0, hy - 0.01, hz + 0.08), 0.085, "RobeInner", scale=(0.88, 0.95, 1.05), u=12, v=8)
    for sx in (-1.0, 1.0):
        k.sphere((sx * 0.03, hy + 0.07, hz + 0.1), 0.013, "Eyes", scale=(1.3, 0.6, 0.8), u=8, v=5)
    rings = []
    for j in range(8):
        a = math.pi * (0.08 + j / 7 * 0.8)
        rings.append([Vector((math.sin(th) * (0.12 * math.sin(a) + 0.014), hy - 0.01 + math.cos(th) * (0.125 * math.sin(a) + 0.02),
                              hz + 0.08 + 0.135 * math.cos(a)))
                      for th in [1.0 + i / 14 * (TAU - 2.0) for i in range(15)]])
    k.ring_grid(rings, "Robe", closed=False)
    # The hood's point droops behind.
    k.tube([(0, hy - 0.1, hz + 0.18), (0, hy - 0.18, hz + 0.12), (0, hy - 0.22, hz + 0.02)], [0.04, 0.022, 0.003], "Robe", seg=6)
    k.finish(rig, ["head", "neck"], solidify=0.012)

    # Long sleeves, wide at the cuff, and thin bone hands reaching from them.
    for side in ("r", "l"):
        ck.sleeve(rig, M, side, "Robe", radii=(0.06, 0.055, 0.055, 0.07, 0.09), smooth=0)
        h = bn["hand_" + side]
        k = Kit("Hand_" + side, M)
        a, b = h.head_local.copy(), h.tail_local.copy()
        d = (b - a).normalized()
        sidev = Vector((1, 0, 0))
        k.tube([a - d * 0.02, a + d * 0.04], [0.022, 0.026], "Bone", seg=6)
        for f in range(4):
            o = sidev * (f - 1.5) * 0.014
            base_p = a + d * 0.04 + o
            k.tube([base_p, base_p + d * 0.06 + Vector((0, 0, -0.012)), base_p + d * 0.1 + Vector((0, 0, -0.035))],
                   [0.007, 0.006, 0.003], "Bone", seg=4)
        k.finish(rig, "hand_" + side)


def main():
    import sys
    out = ck.out_path(sys.argv, "/tmp/willing_dead.blend")
    spec = ck.load_spec("willing_dead")
    ck.reset()
    rig = ck.make_rig(bones())
    M = ck.Mats()
    build_model(rig, M)
    hr = rig.data.bones["hand_r"]
    ck.socket("Muzzle", rig, "hand_r", hr.head_local + (hr.tail_local - hr.head_local).normalized() * 0.1)
    ox, oy, oz = spec["sockets"]["Overhead"]
    ck.socket("Overhead", rig, "root", (ox, -oz, oy))

    # Arms held a little forward and open, hands low: waiting, not menacing.
    rest = dict(upper_arm_r=(18, 0, 6), forearm_r=(-14, 0, 0), upper_arm_l=(18, 0, -6), forearm_l=(-14, 0, 0),
                head=(8, 0, 0), skirt_f=(-4, 0, 0), skirt_b=(4, 0, 0))

    def b(**over):
        d = dict(rest)
        d.update(over)
        return base(NAMES, **d)

    feet = ck.rest_feet(rig)
    # It floats: a slow rise and fall, the hem lagging behind the body.
    ck.idle_clip(rig, 2.4, lambda t, s: (b(spine=(3 * s, 0, 0), chest=(-2 * s, 0, 3 * s), head=(8 + 3 * s, 0, 5 * math.sin(t / 2.4 * TAU)),
                                           skirt_f=(-4 - 5 * s, 0, 0), skirt_b=(4 + 5 * s, 0, 0)),
                                         {"hips": (0, 0, 0.035 * s)}))

    def run(t, s, c2):
        # A glide: leaning in, arms trailing low, the hem streaming back.
        return dict(hips=(0, 0, 4 * s), spine=(-14, 0, -3 * s), chest=(-6, 0, -3 * s), head=(16, 0, 2 * s),
                    upper_arm_r=(-18 + 6 * s, 0, 10), forearm_r=(-10, 0, 0), upper_arm_l=(-18 - 6 * s, 0, -10), forearm_l=(-10, 0, 0),
                    skirt_f=(-6 - 3 * c2, 0, 0), skirt_b=(20 + 4 * c2, 0, 0))
    ck.run_clip(rig, spec["move_speed_mps"], lambda t, s, c2: (b(**run(t, s, c2)), {"hips": (0, 0, 0.03 + 0.02 * c2)}),
                cycle=0.7, stance=0.2, hips_drop=0.0, lift=0.04, kick=0.04)

    # Grave Touch: both hands drawn back to the chest, then thrust out together.
    c = spec["slot_clips"]["attack"]
    rel, rec = c["release_s"], c["recovery_s"]
    keys = [(0, {}, (0, 0, 0.02)),
            (rel * 0.65, dict(spine=(-8, 0, 0), chest=(-6, 0, 0), head=(0, 0, 0), upper_arm_r=(30, 0, 40), forearm_r=(-95, 0, 0),
                              upper_arm_l=(30, 0, -40), forearm_l=(-95, 0, 0), skirt_b=(10, 0, 0)), (0, -0.05, 0.05)),
            (rel, dict(spine=(14, 0, 0), chest=(8, 0, 0), head=(4, 0, 0), upper_arm_r=(62, 0, 6), forearm_r=(-6, 0, 0),
                       upper_arm_l=(62, 0, -6), forearm_l=(-6, 0, 0), skirt_f=(-4, 0, 0), skirt_b=(12, 0, 0)), (0, 0.06, 0.0)),
            (rel + rec * 0.5, dict(spine=(10, 0, 0), upper_arm_r=(54, 0, 8), forearm_r=(-10, 0, 0),
                                   upper_arm_l=(54, 0, -8), forearm_l=(-10, 0, 0)), (0, 0.05, 0.01)),
            (rel + rec, {}, (0, 0, 0.02))]
    ck.cast_clip(rig, "attack", rel, rec, [(t, b(**rots), hp) for t, rots, hp in keys], feet, amp=1.0)
    ck.death_clip(rig, NAMES)
    ck.save(out)


if __name__ == "__main__":
    main()
