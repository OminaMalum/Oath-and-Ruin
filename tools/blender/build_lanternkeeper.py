# SPDX-License-Identifier: GPL-2.0-or-later
# (Uses Blender's Python API. This is a build tool, not part of the game.)
"""Build the Lanternkeeper champion model, rig and clips, all from code.

  /opt/bpyenv/bin/python tools/blender/build_lanternkeeper.py OUT.blend

A travelling cleric: a pale robe with a team stole, a short mantle, a wide
pilgrim hat, a prayer book chained to the belt, and a lantern hung from a
shepherd's crook. Original geometry written as code.
"""
import math

import bpy  # noqa: F401,I001  (bpy first: it makes mathutils importable)
from mathutils import Vector

import champion_kit as ck
from champion_kit import TAU, Kit, base

S = 0.95
W = 1.0

NAMES = ck.BODY + ["crook", "lantern", "book"]


def bones():
    b = ck.humanoid_bones(S, W)
    h, t = Vector(b["hand_l"][0]), Vector(b["hand_l"][1])
    palm = h + (t - h).normalized() * 0.05
    b["crook"] = (tuple(palm), tuple(palm + Vector((0, 0, 0.3))), "hand_l")
    top = palm + Vector((0.0, 0.16, 0.86))
    b["lantern"] = (tuple(top), tuple(top - Vector((0, 0, 0.2))), "crook")
    b["book"] = ((0.2 * S, 0.1 * S, 0.95 * S), (0.2 * S, 0.1 * S, 0.8 * S), "hips")
    return b


def robe_fold(th, z, r):
    depth = max(0.0, (0.9 - z) / 0.8)
    return r + depth * (0.018 * math.sin(th * 9.0 + 0.6) + 0.01 * math.sin(th * 15.0 + 1.1))


def build_model(rig, M):
    bn = rig.data.bones
    z = lambda v: v * S  # noqa: E731

    # Robe: long and full, to the ankles.
    k = Kit("Robe", M)
    prof = [(0.33, 0.07), (0.31, 0.18), (0.27, 0.4), (0.225, 0.66), (0.19, 0.88), (0.17, 0.98), (0.172, 1.08), (0.195, 1.2),
            (0.215, 1.32), (0.2, 1.42), (0.12, 1.5)]
    rings = []
    seg = 32
    for r, h in prof:
        ring = []
        for i in range(seg):
            th = i / seg * TAU
            zz = z(h) + (0.025 * math.sin(th * 4.0 + 0.4) if h < 0.1 else 0.0)
            rr = robe_fold(th, z(h), r * S)
            ring.append(Vector((math.sin(th) * rr * 1.08, math.cos(th) * rr * 0.92, zz)))
        rings.append(ring)
    k.ring_grid(rings, "RobeDark", u_scale=2.0)
    band = [[Vector((p.x * 1.015, p.y * 1.015, p.z + dz)) for p in rings[0]] for dz in (-0.004, 0.05)]
    k.ring_grid(band, "Trim")
    k.finish(rig, ["hips", "spine", "chest", "thigh_l", "thigh_r", "skirt_f", "skirt_b", "shin_l", "shin_r"], subsurf=1, solidify=0.012)

    # Stole: two team strips from the neck down the front, gold fringed.
    k = Kit("Stole", M)
    for sd in (-1.0, 1.0):
        rows = []
        for j in range(10):
            h = 1.22 - j * 0.085
            zz = z(h)
            x = sd * (0.07 + 0.005 * j)
            r = next((rr for rr, hh in reversed(prof) if hh <= h), prof[0][0])
            y = robe_fold(0.0, zz, r * S) * 0.92 + 0.022
            rows.append([Vector((x + u * 0.045, y, zz)) for u in (-1.0, 0.0, 1.0)])
        k.ring_grid(rows, "Team", closed=False)
        hem = [[Vector((p.x, p.y + 0.003, p.z + dz)) for p in rows[-1]] for dz in (0.0, 0.04)]
        k.ring_grid(hem, "Trim", closed=False)
        for j in (2, 5):
            k.box(rows[j][1] + Vector((0, 0.004, 0)), (0.035, 0.004, 0.035), "Trim", rot=(0, 45, 0))
    k.finish(rig, ["chest", "spine", "hips", "skirt_f"], solidify=0.006)

    # Mantle: a short shoulder cape with a scalloped hem.
    k = Kit("Mantle", M)
    rings = []
    for r, h in ((0.28, 1.25), (0.27, 1.32), (0.23, 1.41), (0.15, 1.48), (0.105, 1.52)):
        ring = []
        for i in range(36):
            th = i / 36 * TAU
            zz = z(h) - (0.03 * abs(math.sin(th * 5.0)) if h < 1.26 else 0.0)
            ring.append(Vector((math.sin(th) * r * S * 1.2, math.cos(th) * r * S * 0.95, zz)))
        rings.append(ring)
    k.ring_grid(rings, "Team", u_scale=2.0)
    band = [[Vector((p.x * 1.012, p.y * 1.012, p.z + dz)) for p in rings[0]] for dz in (-0.002, 0.025)]
    k.ring_grid(band, "Trim")
    k.finish(rig, ["chest", "spine"], subsurf=1, solidify=0.01)

    # Belt, prayer book on a chain, a small censer pouch.
    k = Kit("Belt", M)
    k.lathe([(0.176 * S, z(0.95)), (0.18 * S, z(1.0))], "Leather", seg=28, sx=1.1, sy=0.94)
    k.box(Vector((0, 0.18 * 0.94 * S + 0.008, z(0.975))), (0.05, 0.015, 0.05), "Brass")
    k.box(Vector((-0.2, 0.05, z(0.9))), (0.05, 0.08, 0.09), "Leather", rot=(0, 0, -20))
    k.finish(rig, ["hips"])
    k = Kit("Book", M)
    c = bn["book"].head_local + Vector((0.03, 0, -0.12))
    k.box(c, (0.04, 0.13, 0.17), "Leather", rot=(0, 0, 10))
    k.box(c + Vector((0.003, 0.004, 0)), (0.03, 0.12, 0.158), "Paper", rot=(0, 0, 10))
    k.box(c + Vector((0.021, 0, 0)), (0.004, 0.05, 0.05), "Trim", rot=(45, 0, 10))
    k.tube([bn["book"].head_local, c + Vector((0, 0, 0.09))], [0.006, 0.006], "Brass", seg=5)
    k.finish(rig, "book")

    # Head under a wide pilgrim hat: a weathered face, warm glowing eyes.
    hz = bn["head"].head_local.z
    hy = bn["head"].head_local.y
    k = Kit("Head", M)
    k.sphere((0, hy, hz + 0.08), 0.092, "Skin", scale=(0.86, 0.95, 1.12))
    for sx in (-1.0, 1.0):
        k.sphere((sx * 0.033, hy + 0.09, hz + 0.1), 0.012, "Eyes", scale=(1.5, 0.6, 0.55), u=8, v=6)
    k.sphere((0, hy + 0.092, hz + 0.07), 0.016, "Skin", scale=(0.8, 1.2, 1.2), u=8, v=6)
    k.lathe([(0.06, hz - 0.02), (0.085, hz + 0.02), (0.07, hz + 0.06)], "Fur", seg=16, sx=1.0, sy=0.9, center=(0, hy + 0.02))
    k.finish(rig, "head")
    k = Kit("Hat", M)
    bz = hz + 0.15
    k.lathe([(0.3, bz - 0.03), (0.26, bz - 0.005), (0.11, bz + 0.005), (0.1, bz + 0.0)], "Leather", seg=32, center=(0, hy))
    k.lathe([(0.3, bz - 0.03), (0.31, bz - 0.045)], "Leather", seg=32, center=(0, hy))
    k.lathe([(0.098, bz), (0.098, bz + 0.03), (0.09, bz + 0.09), (0.06, bz + 0.12), (0.0, bz + 0.13)], "Leather", seg=24, center=(0, hy))
    k.lathe([(0.101, bz + 0.005), (0.099, bz + 0.035)], "Team", seg=24, center=(0, hy))
    k.box(Vector((0.0, hy + 0.098, bz + 0.02)), (0.03, 0.006, 0.03), "Trim", rot=(0, 45, 0))
    k.finish(rig, "head", subsurf=1, solidify=0.008)

    # Sleeves wide at the wrist with team cuffs; hands; legs and boots.
    for side in ("r", "l"):
        ck.sleeve(rig, M, side, "RobeDark", radii=(0.08, 0.072, 0.068, 0.08, 0.1), cuff="Team", cuff_r=0.09)
        ck.hand(rig, M, side, "Skin", fist=(side == "l"))
    ck.limbs(rig, M, legs="Cloth", boots="Leather", hands=None)

    # Crook: a long staff with a curled top; the lantern hangs from the curl.
    p = bn["crook"].head_local
    k = Kit("Crook", M)
    shaft = [p + Vector((0, 0, -0.95 + 0.11 * i)) for i in range(16)]
    k.tube(shaft, [0.022 + 0.003 * math.sin(i * 1.9) for i in range(16)], "Wood", seg=7)
    top = shaft[-1]
    curl = [top + Vector((0, 0.08 * (1 - math.cos(a)) * 1.0, 0.1 * math.sin(a))) for a in [i / 8 * math.pi * 1.15 for i in range(9)]]
    k.tube([top] + curl[1:], [0.022] * 9, "Wood", seg=7)
    for zz in (0.3, 0.75):
        k.tube([p + Vector((0, 0, zz - 0.5)), p + Vector((0, 0, zz - 0.47))], [0.03, 0.03], "Brass", seg=8)
    k.tube([p + Vector((0, 0, -0.07)), p + Vector((0, 0, 0.08))], [0.026, 0.026], "Leather", seg=8)
    k.finish(rig, "crook")
    lp = bn["lantern"].head_local
    k = Kit("Lantern", M)
    k.tube([lp, lp - Vector((0, 0, 0.12))], [0.005, 0.005], "Brass", seg=5)
    lc = lp - Vector((0, 0, 0.21))
    k.lathe([(0.0, lc.z + 0.11), (0.045, lc.z + 0.09), (0.07, lc.z + 0.06), (0.07, lc.z + 0.05)], "Brass", seg=8, center=(lc.x, lc.y))
    k.lathe([(0.065, lc.z - 0.07), (0.07, lc.z - 0.085), (0.0, lc.z - 0.09)], "Brass", seg=8, center=(lc.x, lc.y))
    for i in range(6):
        a = i / 6 * TAU
        d = Vector((math.cos(a), math.sin(a), 0)) * 0.062
        k.tube([lc + d + Vector((0, 0, -0.07)), lc + d * 1.08, lc + d + Vector((0, 0, 0.055))], [0.006] * 3, "Brass", seg=4)
    k.lathe([(0.052, lc.z - 0.065), (0.058, lc.z), (0.052, lc.z + 0.05)], "Glass", seg=12, center=(lc.x, lc.y))
    k.octa(lc, 0.026, 0.05, 0.035, "Glow")
    k.finish(rig, "lantern")


# ---------------------------------------------------------------- clips

def animate(rig, spec):
    slots = spec["slot_clips"]
    feet = ck.rest_feet(rig)
    rest = dict(upper_arm_r=(6, 0, 4), forearm_r=(-6, 0, 0), upper_arm_l=(8, 0, -2), forearm_l=(0, 0, 0), lantern=(0, 0, 0))

    def b(**over):
        d = dict(rest)
        d.update(over)
        return base(NAMES, **d)

    # Idle: calm breath, the lantern swaying on its curl, the book swinging.
    ck.idle_clip(rig, 2.6, lambda t, s: (b(spine=(1.5 * s, 0, 0), chest=(-1 * s, 0, 1.5 * s), head=(2 * s, 0, 5 * math.sin(t / 2.6 * TAU)),
                                            upper_arm_r=(6 + 2 * s, 0, 4), lantern=(6 * math.sin(t / 2.6 * TAU * 2), 6 * s, 0),
                                            book=(4 * s, 0, 0), crook=(1.5 * s, 0, 0), skirt_f=(-1 * s, 0, 0)),
                                          {"hips": (0, 0, -0.012 - 0.008 * s)}))

    # Run: an upright brisk run, the crook carried forward, the lantern
    # swinging back and the robe streaming.
    def upper(t, s, c2):
        rots = b(hips=(0, 0, 8 * s), spine=(-10, 0, -5 * s), chest=(-4, 0, -5 * s), head=(10, 0, 3 * s),
                 upper_arm_r=(-32 * s + 8, 0, 8), forearm_r=(-45 - 12 * s, 0, 0),
                 upper_arm_l=(22, 0, -6), forearm_l=(-12, 0, 0), crook=(-28, 0, -6), lantern=(30 + 10 * c2, 0, 0),
                 book=(-20 - 15 * c2, 0, 0), skirt_f=(-14 - 8 * c2, 0, 0), skirt_b=(28 + 6 * c2, 0, 0))
        return rots, {}
    ck.run_clip(rig, spec["move_speed_mps"], upper, cycle=0.6, stance=0.2, hips_drop=0.08, lift=0.24, kick=0.2)

    # Censer Spark: a short flick of the right hand forward.
    c = slots["attack"]
    rel, rec = c["release_s"], c["recovery_s"]
    ck.cast_clip(rig, "attack", rel, rec, [
        (0, b(), (0, 0, -0.012)),
        (rel * 0.6, b(chest=(0, 0, 14), upper_arm_r=(-20, 0, 30), forearm_r=(-70, 0, 0), hand_r=(-20, 0, 0)), (0, 0, -0.02)),
        (rel, b(chest=(-4, 0, -10), spine=(-4, 0, -4), upper_arm_r=(60, 0, -6), forearm_r=(-10, 0, 0), hand_r=(20, 0, 0)), (0, 0.02, -0.03)),
        (rel + rec * 0.5, b(chest=(-3, 0, -8), upper_arm_r=(50, 0, -4), forearm_r=(-14, 0, 0)), (0, 0.02, -0.03)),
        (rel + rec, b(), (0, 0, -0.012))], feet)

    # Lantern Light: the crook is swung forward and planted, the lantern held
    # out over the ground ahead.
    c = slots["ability_1"]
    rel, rec = c["release_s"], c["recovery_s"]
    ck.cast_clip(rig, "ability_1", rel, rec, [
        (0, b(), (0, 0, -0.012)),
        (rel * 0.5, b(spine=(4, 0, 6), chest=(2, 0, 8), upper_arm_l=(50, 0, 6), forearm_l=(-30, 0, 0), crook=(-10, 0, 0), lantern=(-20, 0, 0),
                      upper_arm_r=(20, 0, 10)), (0, -0.02, -0.02)),
        (rel, b(spine=(14, 0, -4), chest=(8, 0, -6), head=(8, 0, 0), upper_arm_l=(70, 0, 10), forearm_l=(-10, 0, 0), crook=(20, 0, 0),
                lantern=(-30, 0, 0), upper_arm_r=(40, 0, -10), forearm_r=(-30, 0, 0)), (0, 0.06, -0.1)),
        (rel + rec, b(spine=(12, 0, -4), upper_arm_l=(66, 0, 10), forearm_l=(-12, 0, 0), crook=(18, 0, 0), lantern=(-20, 0, 0)),
         (0, 0.05, -0.09))], feet)

    # Raven's Mark: the right arm is flung out forward and up, setting the
    # raven loose.
    c = slots["ability_2"]
    rel, rec = c["release_s"], c["recovery_s"]
    ck.cast_clip(rig, "ability_2", rel, rec, [
        (0, b(), (0, 0, -0.012)),
        (rel * 0.6, b(spine=(4, 0, 10), chest=(2, 0, 14), upper_arm_r=(30, 0, 60), forearm_r=(-100, 0, 0), hand_r=(-20, 0, 0)), (0, -0.04, -0.03)),
        (rel, b(spine=(-10, 0, -8), chest=(-6, 0, -12), head=(-8, 0, 0), upper_arm_r=(120, 0, -6), forearm_r=(-5, 0, 0), hand_r=(-30, 0, 0)),
         (0, 0.06, -0.04)),
        (rel + rec * 0.5, b(spine=(-8, 0, -6), upper_arm_r=(110, 0, -6), forearm_r=(-8, 0, 0)), (0, 0.05, -0.04)),
        (rel + rec, b(), (0, 0, -0.012))], feet)

    # Dawnlight: both arms raised high, the lantern lifted to the sky.
    c = slots["ability_3"]
    rel, rec = c["release_s"], c["recovery_s"]
    ck.cast_clip(rig, "ability_3", rel, rec, [
        (0, b(), (0, 0, -0.012)),
        (rel * 0.6, b(spine=(8, 0, 0), chest=(6, 0, 0), head=(10, 0, 0), upper_arm_l=(30, 0, -10), upper_arm_r=(30, 0, 10), forearm_r=(-50, 0, 0)),
         (0, 0, -0.08)),
        (rel, b(spine=(-10, 0, 0), chest=(-8, 0, 0), head=(-22, 0, 0), upper_arm_l=(150, 0, -15), forearm_l=(-10, 0, 0), crook=(-60, 0, 0),
                lantern=(20, 0, 0), upper_arm_r=(150, 0, 15), forearm_r=(-10, 0, 0), skirt_b=(8, 0, 0)), (0, 0, 0.02)),
        (rel + rec, b(spine=(-8, 0, 0), head=(-16, 0, 0), upper_arm_l=(140, 0, -12), crook=(-55, 0, 0), upper_arm_r=(140, 0, 12)), (0, 0, 0.01))],
        feet)

    ck.death_clip(rig, NAMES, lambda t: {"crook": (-30 * min(1.0, t / 0.6), 0, -40 * min(1.0, t / 0.9)), "lantern": (20, 0, 0)})


def main():
    import sys
    out = ck.out_path(sys.argv, "/tmp/lanternkeeper.blend")
    spec = ck.load_spec("lanternkeeper")
    ck.reset()
    rig = ck.make_rig(bones())
    M = ck.Mats()
    build_model(rig, M)
    hr = rig.data.bones["hand_r"]
    ck.socket("Muzzle", rig, "hand_r", hr.head_local + (hr.tail_local - hr.head_local).normalized() * 0.11)
    ox, oy, oz = spec["sockets"]["Overhead"]
    ck.socket("Overhead", rig, "root", (ox, -oz, oy))
    ck.socket("Focus", rig, "lantern", rig.data.bones["lantern"].head_local - Vector((0, 0, 0.21)))
    animate(rig, spec)
    ck.save(out)


if __name__ == "__main__":
    main()
