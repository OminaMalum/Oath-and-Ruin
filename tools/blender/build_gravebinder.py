# SPDX-License-Identifier: GPL-2.0-or-later
# (Uses Blender's Python API. This is a build tool, not part of the game.)
"""Build the Gravebinder champion model, rig and clips, all from code.

  /opt/bpyenv/bin/python tools/blender/build_gravebinder.py OUT.blend

A grave priest: a dark ragged robe with a team tabard, a spiked iron collar,
a deep hood over a bone mask, a length of chain hanging from the left fist
and an iron rod in the right hand with a violet orb held in a bone claw.
Original geometry written as code.
"""
import math

import bpy  # noqa: F401,I001  (bpy first: it makes mathutils importable)
from mathutils import Vector

import champion_kit as ck
from champion_kit import TAU, Kit, base

S = 0.95
W = 1.0

NAMES = ck.BODY + ["rod", "chain", "chain2"]


def bones():
    b = ck.humanoid_bones(S, W)
    h, t = Vector(b["hand_r"][0]), Vector(b["hand_r"][1])
    palm = h + (t - h).normalized() * 0.05
    b["rod"] = (tuple(palm), tuple(palm + Vector((0, 0, 0.3))), "hand_r")
    h, t = Vector(b["hand_l"][0]), Vector(b["hand_l"][1])
    palm = h + (t - h).normalized() * 0.05
    b["chain"] = (tuple(palm), tuple(palm - Vector((0, 0, 0.28))), "hand_l")
    b["chain2"] = (tuple(palm - Vector((0, 0, 0.28))), tuple(palm - Vector((0, 0, 0.56))), "chain")
    return b


def rag_fold(th, z, r):
    depth = max(0.0, (0.95 - z) / 0.85)
    return r + depth * (0.02 * math.sin(th * 7.0 + 0.2) + 0.012 * math.sin(th * 17.0 + 0.9))


def build_model(rig, M):
    bn = rig.data.bones
    z = lambda v: v * S  # noqa: E731

    # Robe: long, dark, with a torn hem in long tatters.
    k = Kit("Robe", M)
    prof = [(0.34, 0.05), (0.32, 0.16), (0.27, 0.38), (0.225, 0.64), (0.19, 0.88), (0.17, 0.98), (0.172, 1.08), (0.195, 1.2),
            (0.215, 1.32), (0.2, 1.42), (0.12, 1.5)]
    rings = []
    seg = 32
    for r, h in prof:
        ring = []
        for i in range(seg):
            th = i / seg * TAU
            zz = z(h)
            if h < 0.1:
                zz += 0.06 * abs(math.sin(th * 6.0 + 0.3)) ** 3 + 0.02 * math.sin(th * 13.0)
            rr = rag_fold(th, z(h), r * S)
            ring.append(Vector((math.sin(th) * rr * 1.08, math.cos(th) * rr * 0.92, zz)))
        rings.append(ring)
    k.ring_grid(rings, "Robe", u_scale=2.0)
    k.finish(rig, ["hips", "spine", "chest", "thigh_l", "thigh_r", "skirt_f", "skirt_b", "shin_l", "shin_r"], subsurf=1, solidify=0.012)

    # Tabard: a team panel at the front, iron edged, with a column of
    # glowing grave runes.
    k = Kit("Tabard", M)
    rows = []
    for j in range(9):
        h = 1.3 - j * 0.13
        r = next((rr for rr, hh in reversed(prof) if hh <= h), prof[0][0])
        y = rag_fold(0.0, z(h), r * S) * 0.92 + 0.02
        w = 0.08 + 0.007 * j
        zz = z(h) - (0.04 * (1 if j == 8 else 0))
        rows.append([Vector((u * w, y + 0.006 * (1 - u * u), zz)) for u in (-1.0, -0.5, 0.0, 0.5, 1.0)])
    k.ring_grid(rows, "Team", closed=False)
    for sd in (-1.0, 1.0):
        strip = [[Vector((r[0 if sd < 0 else 4].x + sd * dx, r[0].y + 0.003, r[0].z)) for dx in (-0.012, 0.012)] for r in rows]
        k.ring_grid(strip, "Iron", closed=False)
    for j in range(1, 8):
        r = rows[j]
        k.box(Vector((0, r[2].y + 0.008, r[2].z)), (0.025, 0.004, 0.045), "Glow", rot=(0, 0, 0) if j % 2 else (0, 45, 0))
    k.finish(rig, ["chest", "spine", "hips", "skirt_f", "thigh_l", "thigh_r"], solidify=0.006)

    # Belt with a skull clasp and a hanging censer of bones.
    k = Kit("Belt", M)
    k.lathe([(0.176 * S, z(0.95)), (0.18 * S, z(1.0))], "Leather", seg=28, sx=1.1, sy=0.94)
    k.sphere(Vector((0, 0.18 * 0.94 * S + 0.02, z(0.975))), 0.03, "Bone", scale=(1.0, 0.8, 1.1), u=10, v=8)
    for x in (-0.012, 0.012):
        k.sphere(Vector((x, 0.18 * 0.94 * S + 0.044, z(0.98))), 0.008, "RobeInner", u=6, v=4)
    k.finish(rig, ["hips"])

    # Spiked iron collar over the shoulders, and bone shoulder guards.
    k = Kit("Collar", M)
    k.lathe([(0.25, z(1.37)), (0.22, z(1.43)), (0.16, z(1.5)), (0.14, z(1.58))], "Iron", seg=24, sx=1.15, sy=1.0)
    for i in range(9):
        a = math.pi * (0.55 + i / 8 * 0.9)
        d = Vector((math.sin(a) * 1.15, math.cos(a), 0)).normalized()
        p0 = Vector((math.sin(a) * 0.2 * 1.15, math.cos(a) * 0.2, z(1.45)))
        k.tube([p0, p0 + d * 0.06 + Vector((0, 0, 0.09)), p0 + d * 0.09 + Vector((0, 0, 0.17))], [0.018, 0.01, 0.002], "Iron", seg=5)
    k.finish(rig, ["chest", "neck"], subsurf=0)
    for side, sx in (("r", 1.0), ("l", -1.0)):
        k = Kit("BoneGuard_" + side, M)
        top = bn["upper_arm_" + side].head_local
        k.sphere(top + Vector((sx * 0.04, 0, 0.02)), 0.09, "Bone", scale=(1.0, 1.15, 0.8), u=14, v=8)
        for dy in (-0.05, 0.0, 0.05):
            k.tube([top + Vector((sx * 0.06, dy, 0.07)), top + Vector((sx * 0.12, dy, 0.1)), top + Vector((sx * 0.14, dy * 1.2, 0.03))],
                   [0.014, 0.012, 0.004], "Bone", seg=5)
        k.finish(rig, "shoulder_" + side)

    # Deep hood with a long drooping point; a bone mask inside with dark
    # sockets and violet eyes.
    hz = bn["head"].head_local.z
    hy = bn["head"].head_local.y
    k = Kit("Hood", M)
    rings = []
    for j in range(11):
        a = math.pi * (0.06 + j / 10.0 * 0.86)
        g = math.pi * 0.62 * min(1.0, max(0.0, (j - 2) / 4.0)) ** 0.8
        ring = []
        for i in range(25):
            th = g * 0.5 + i / 24.0 * (TAU - g)
            r = 0.15 * math.sin(a) + 0.018
            zz = hz + 0.075 + 0.17 * math.cos(a)
            x = math.sin(th) * r * 1.04
            y = hy + math.cos(th) * r + 0.012 + 0.05 * max(0.0, math.cos(th)) * min(1.0, j / 4.0)
            if j <= 3 and math.cos(th) < 0.0:
                zz += 0.02 * (1 - j / 3.0) * -math.cos(th)
                y -= 0.035 * (1 - j / 3.0) * -math.cos(th)
            ring.append(Vector((x, y, zz)))
        rings.append(ring)
    k.ring_grid(rings, "RobeDark", closed=False)
    k.tube([(0, hy - 0.1, hz + 0.22), (0, hy - 0.2, hz + 0.16), (0, hy - 0.27, hz + 0.02), (0, hy - 0.29, hz - 0.1)],
           [0.05, 0.032, 0.015, 0.003], "RobeDark", seg=8, cap=False)
    k.finish(rig, ["head", "neck"], subsurf=1, solidify=0.014)
    k = Kit("Mask", M)
    k.sphere((0, hy, hz + 0.075), 0.085, "RobeInner", scale=(0.86, 0.95, 1.1))
    k.sphere((0, hy + 0.035, hz + 0.08), 0.075, "Bone", scale=(0.9, 0.75, 1.15), u=16, v=10)
    for sx in (-1.0, 1.0):
        k.sphere((sx * 0.03, hy + 0.088, hz + 0.1), 0.02, "RobeInner", scale=(1.1, 0.5, 0.9), u=8, v=6)
        k.sphere((sx * 0.03, hy + 0.095, hz + 0.1), 0.009, "Eyes", scale=(1.2, 0.6, 0.8), u=8, v=6)
    for i in range(5):
        k.box(Vector(((i - 2) * 0.012, hy + 0.088, hz + 0.025)), (0.008, 0.006, 0.016), "RobeInner")
    k.finish(rig, "head")

    # Sleeves, bony hands wrapped in strips, legs and boots.
    for side in ("r", "l"):
        ck.sleeve(rig, M, side, "RobeDark", radii=(0.078, 0.07, 0.066, 0.075, 0.09), cuff="Iron", cuff_r=0.08)
        ck.hand(rig, M, side, "Bone", fist=True)
    ck.limbs(rig, M, legs="ClothDark", boots="Leather", hands=None)

    # Rod: dark iron with a bone claw holding a violet orb.
    p = bn["rod"].head_local
    up = Vector((0, 0, 1))
    k = Kit("Rod", M)
    k.tube([p - up * 0.35, p + up * 0.5], [0.018, 0.02], "Iron", seg=8)
    k.tube([p - up * 0.07, p + up * 0.07], [0.024, 0.024], "Leather", seg=8)
    k.octa(p - up * 0.37, 0.025, 0.02, 0.06, "Iron")
    top = p + up * 0.5
    for i in range(4):
        a = i / 4 * TAU + 0.4
        d = Vector((math.cos(a), math.sin(a), 0))
        k.tube([top, top + d * 0.05 + up * 0.04, top + d * 0.055 + up * 0.11, top + d * 0.02 + up * 0.16],
               [0.012, 0.01, 0.008, 0.003], "Bone", seg=5)
    k.sphere(top + up * 0.09, 0.045, "Glow", u=12, v=8)
    k.finish(rig, "rod")

    # Chain: oval links hanging from the left fist, a hook at the end.
    for bone, start, n in (("chain", 0, 6), ("chain2", 6, 6)):
        k = Kit("Chain_" + bone, M)
        hp = bn["chain"].head_local
        for i in range(start, start + n):
            c = hp - up * (0.03 + i * 0.045)
            ring = []
            for t in range(13):
                a = t / 12 * TAU
                off = Vector((math.cos(a) * 0.018, 0, math.sin(a) * 0.028)) if i % 2 else Vector((0, math.cos(a) * 0.018, math.sin(a) * 0.028))
                ring.append(c + off)
            k.tube(ring, [0.006] * 13, "Iron", seg=5, cap=False)
        if bone == "chain2":
            c = hp - up * (0.03 + 12 * 0.045)
            k.tube([c, c - up * 0.06, c - up * 0.09 + Vector((0, 0.04, 0)), c - up * 0.05 + Vector((0, 0.06, 0))], [0.012, 0.011, 0.008, 0.003],
                   "Iron", seg=6)
        k.finish(rig, bone)


# ---------------------------------------------------------------- clips

def animate(rig, spec):
    slots = spec["slot_clips"]
    feet = ck.rest_feet(rig)
    rest = dict(upper_arm_r=(8, 0, 4), forearm_r=(-6, 0, 0), upper_arm_l=(8, 0, -4), forearm_l=(0, 0, 0), rod=(0, 0, 0),
                chain=(0, 0, 0), chain2=(0, 0, 0), spine=(4, 0, 0), head=(-4, 0, 0))

    def b(**over):
        d = dict(rest)
        d.update(over)
        return base(NAMES, **d)

    ck.idle_clip(rig, 2.8, lambda t, s: (b(spine=(4 + 1.5 * s, 0, 0), chest=(-1 * s, 0, 2 * s), head=(-4 + 2 * s, 0, 6 * math.sin(t / 2.8 * TAU)),
                                            upper_arm_r=(8 + 2 * s, 0, 4), chain=(4 * math.sin(t / 2.8 * TAU), 5 * s, 0),
                                            chain2=(6 * math.sin(t / 2.8 * TAU + 1), 0, 0), skirt_f=(-1 * s, 0, 0)),
                                          {"hips": (0, 0, -0.015 - 0.008 * s)}))

    def upper(t, s, c2):
        rots = b(hips=(0, 0, 8 * s), spine=(-10, 0, -5 * s), chest=(-4, 0, -5 * s), head=(10, 0, 3 * s),
                 upper_arm_r=(-25 * s + 10, 0, 8), forearm_r=(-40 - 10 * s, 0, 0), rod=(-25, 0, 0),
                 upper_arm_l=(28 * s + 6, 0, -6), forearm_l=(-30, 0, 0), chain=(20 + 10 * c2, 0, 0), chain2=(20 + 12 * c2, 0, 0),
                 skirt_f=(-14 - 8 * c2, 0, 0), skirt_b=(28 + 6 * c2, 0, 0))
        return rots, {}
    ck.run_clip(rig, spec["move_speed_mps"], upper, cycle=0.6, stance=0.2, hips_drop=0.08, lift=0.24, kick=0.2)

    # Grave Bolt: the rod is levelled and thrust forward.
    c = slots["attack"]
    rel, rec = c["release_s"], c["recovery_s"]
    ck.cast_clip(rig, "attack", rel, rec, [
        (0, b(), (0, 0, -0.015)),
        (rel * 0.6, b(chest=(0, 0, 16), upper_arm_r=(40, 0, 30), forearm_r=(-70, 0, 0), rod=(-20, 0, 0)), (0, -0.03, -0.02)),
        (rel, b(spine=(-4, 0, -6), chest=(-4, 0, -12), upper_arm_r=(80, 0, -4), forearm_r=(-10, 0, 0), rod=(-60, 0, 0)), (0, 0.05, -0.04)),
        (rel + rec * 0.5, b(chest=(-3, 0, -10), upper_arm_r=(70, 0, -4), forearm_r=(-14, 0, 0), rod=(-55, 0, 0)), (0, 0.04, -0.04)),
        (rel + rec, b(), (0, 0, -0.015))], feet)

    # Binding Chains: the chain is whirled up behind and lashed forward.
    c = slots["ability_1"]
    rel, rec = c["release_s"], c["recovery_s"]
    ck.cast_clip(rig, "ability_1", rel, rec, [
        (0, b(), (0, 0, -0.015)),
        (rel * 0.55, b(spine=(-4, 0, 14), chest=(-6, 0, 18), upper_arm_l=(150, 0, 20), forearm_l=(-40, 0, 0), chain=(-60, 0, 0),
                       chain2=(-40, 0, 0)), (0, -0.05, -0.03)),
        (rel, b(spine=(14, 0, -10), chest=(8, 0, -14), upper_arm_l=(85, 0, -10), forearm_l=(-5, 0, 0), chain=(70, 0, 0), chain2=(20, 0, 0)),
         (0, 0.08, -0.08)),
        (rel + rec * 0.5, b(spine=(10, 0, -8), upper_arm_l=(70, 0, -8), forearm_l=(-10, 0, 0), chain=(40, 0, 0), chain2=(10, 0, 0)),
         (0, 0.06, -0.07)),
        (rel + rec, b(), (0, 0, -0.015))], feet)

    # Grasping Earth: the rod is turned down and driven at the ground ahead.
    c = slots["ability_2"]
    rel, rec = c["release_s"], c["recovery_s"]
    ck.cast_clip(rig, "ability_2", rel, rec, [
        (0, b(), (0, 0, -0.015)),
        (rel * 0.6, b(spine=(-4, 0, 0), upper_arm_r=(130, 0, -10), forearm_r=(-30, 0, 0), rod=(-140, 0, 0), upper_arm_l=(30, 0, -20)),
         (0, -0.02, 0.0)),
        (rel, b(spine=(22, 0, 0), chest=(10, 0, 0), head=(14, 0, 0), upper_arm_r=(60, 0, -8), forearm_r=(-10, 0, 0), rod=(-170, 0, 0),
                upper_arm_l=(-20, 0, -20)), (0, 0.06, -0.14)),
        (rel + rec, b(spine=(16, 0, 0), upper_arm_r=(55, 0, -6), rod=(-160, 0, 0)), (0, 0.05, -0.11))], feet)

    # Grave Pact: both arms raised, the rod high and the chain swinging, the
    # head thrown back.
    c = slots["ability_3"]
    rel, rec = c["release_s"], c["recovery_s"]
    ck.cast_clip(rig, "ability_3", rel, rec, [
        (0, b(), (0, 0, -0.015)),
        (rel * 0.6, b(spine=(10, 0, 0), chest=(6, 0, 0), head=(12, 0, 0), upper_arm_r=(40, 0, 20), forearm_r=(-60, 0, 0),
                      upper_arm_l=(40, 0, -20), forearm_l=(-60, 0, 0)), (0, 0, -0.1)),
        (rel, b(spine=(-12, 0, 0), chest=(-8, 0, 0), head=(-24, 0, 0), upper_arm_r=(160, 0, 14), forearm_r=(-10, 0, 0), rod=(-150, 0, 0),
                upper_arm_l=(155, 0, -14), forearm_l=(-10, 0, 0), chain=(-150, 0, 0), chain2=(-10, 0, 0), skirt_b=(8, 0, 0)), (0, 0, 0.02)),
        (rel + rec, b(spine=(-10, 0, 0), head=(-18, 0, 0), upper_arm_r=(150, 0, 12), rod=(-140, 0, 0), upper_arm_l=(145, 0, -12),
                      chain=(-140, 0, 0)), (0, 0, 0.01))], feet)

    ck.death_clip(rig, NAMES, lambda t: {"rod": (-30 * min(1.0, t / 0.6), 0, 0), "chain": (30 * min(1.0, t / 0.9), 0, 0)})


def main():
    import sys
    out = ck.out_path(sys.argv, "/tmp/gravebinder.blend")
    spec = ck.load_spec("gravebinder")
    ck.reset()
    rig = ck.make_rig(bones())
    M = ck.Mats()
    build_model(rig, M)
    hr = rig.data.bones["hand_r"]
    ck.socket("Muzzle", rig, "hand_r", hr.head_local + (hr.tail_local - hr.head_local).normalized() * 0.11)
    ox, oy, oz = spec["sockets"]["Overhead"]
    ck.socket("Overhead", rig, "root", (ox, -oz, oy))
    ck.socket("Focus", rig, "rod", rig.data.bones["rod"].head_local + Vector((0, 0, 0.59)))
    animate(rig, spec)
    ck.save(out)


if __name__ == "__main__":
    main()
