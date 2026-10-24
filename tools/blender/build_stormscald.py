# SPDX-License-Identifier: GPL-2.0-or-later
# (Uses Blender's Python API. This is a build tool, not part of the game.)
"""Build the Stormscald champion model, rig and clips, all from code.

  /opt/bpyenv/bin/python tools/blender/build_stormscald.py OUT.blend

A tall storm caster: a slate long coat, a high stiff storm mantle with iron
studs, a team sash, swept-back hair under a brass circlet, a forked iron rod
crackling at its tines, and three sparks hovering over the shoulders.
Original geometry written as code.
"""
import math

import bpy  # noqa: F401,I001  (bpy first: it makes mathutils importable)
from mathutils import Vector

import champion_kit as ck
from champion_kit import TAU, Kit, base

S = 0.98
W = 0.98

NAMES = ck.BODY + ["rod", "sparks"]


def bones():
    b = ck.humanoid_bones(S, W)
    h, t = Vector(b["hand_r"][0]), Vector(b["hand_r"][1])
    palm = h + (t - h).normalized() * 0.05
    b["rod"] = (tuple(palm), tuple(palm + Vector((0, 0, 0.3))), "hand_r")
    b["sparks"] = ((0, -0.05 * S, 1.5 * S), (0, -0.05 * S, 1.7 * S), "root")
    return b


def build_model(rig, M):
    bn = rig.data.bones
    z = lambda v: v * S  # noqa: E731

    # Long coat to the ankles, closed to the waist, then open in two panels.
    k = Kit("Coat", M)
    prof = [(0.3, 0.08), (0.27, 0.3), (0.23, 0.58), (0.195, 0.85), (0.175, 0.97), (0.175, 1.08), (0.2, 1.22), (0.215, 1.33),
            (0.2, 1.43), (0.12, 1.5)]
    seg = 32
    rings = []
    for r, h in prof:
        ring = []
        gap = 0.35 * max(0.0, (0.9 - h) / 0.8)
        for i in range(seg + 1):
            th = gap + i / seg * (TAU - 2 * gap)
            rr = r * S + max(0.0, 0.85 - h) * 0.018 * math.sin(th * 8.0)
            ring.append(Vector((math.sin(th) * rr * 1.08, math.cos(th) * rr * 0.92, z(h))))
        rings.append(ring)
    k.ring_grid(rings, "Robe", closed=False, u_scale=2.0)
    edge_l = [[Vector((r[0].x, r[0].y, r[0].z)) * 1.0 + Vector((dx, 0.004, 0)) for dx in (0.0, 0.025)] for r in rings[:6]]
    edge_r = [[Vector((r[-1].x, r[-1].y, r[-1].z)) + Vector((-dx, 0.004, 0)) for dx in (0.0, 0.025)] for r in rings[:6]]
    k.ring_grid(edge_l, "Steel", closed=False)
    k.ring_grid(edge_r, "Steel", closed=False)
    hem = [[Vector((p.x * 1.012, p.y * 1.012, p.z + dz)) for p in rings[0]] for dz in (-0.003, 0.04)]
    k.ring_grid(hem, "Steel", closed=False)
    k.finish(rig, ["hips", "spine", "chest", "thigh_l", "thigh_r", "skirt_f", "skirt_b", "shin_l", "shin_r"], subsurf=1, solidify=0.012)

    # Under the coat: dark trousers seen through the opening, a team sash
    # at the waist, a belt.
    k = Kit("Sash", M)
    k.lathe([(0.178 * S, z(0.95)), (0.182 * S, z(1.04))], "Team", seg=28, sx=1.09, sy=0.93)
    k.lathe([(0.183 * S, z(0.97)), (0.185 * S, z(1.0))], "Leather", seg=28, sx=1.09, sy=0.93)
    k.box(Vector((0, 0.185 * 0.93 * S + 0.006, z(0.985))), (0.04, 0.012, 0.04), "Brass", rot=(0, 45, 0))
    tail = Vector((0.12, 0.13, z(0.97)))
    k.tube([tail, tail + Vector((0.02, 0.02, -0.15)), tail + Vector((0.03, 0.03, -0.3))], [0.03, 0.028, 0.024], "Team", seg=6, flat=0.25)
    k.finish(rig, ["hips", "spine", "skirt_f"], solidify=0.005)

    # Storm mantle: a stiff high collar flaring out over the shoulders,
    # studded with iron, lined with team colour.
    k = Kit("Mantle", M)
    rings = []
    for r, h in ((0.31, 1.28), (0.3, 1.36), (0.24, 1.45), (0.15, 1.52), (0.16, 1.62), (0.19, 1.72)):
        ring = []
        for i in range(37):
            th = 0.55 + i / 36 * (TAU - 1.1) if h > 1.5 else i / 36 * TAU
            zz = z(h) - (0.04 * abs(math.sin(th * 4.0)) if h < 1.3 else 0.0)
            ring.append(Vector((math.sin(th) * r * S * 1.2, math.cos(th) * r * S * (0.95 if h < 1.5 else 0.85), zz)))
        rings.append(ring)
    k.ring_grid(rings[:4], "Robe", closed=False)
    k.ring_grid(rings[3:], "RobeDark", closed=False)
    inner = [[Vector((p.x * 0.96, p.y * 0.96, p.z)) for p in r] for r in rings[3:]]
    k.ring_grid(inner, "Team", closed=False)
    for i in range(10):
        th = i / 10 * TAU
        k.sphere(Vector((math.sin(th) * 0.27 * S * 1.2, math.cos(th) * 0.27 * S * 0.95, z(1.405))), 0.014, "Iron", u=8, v=6)
    k.finish(rig, ["chest", "neck"], subsurf=1, solidify=0.012)

    # Head: a lean face with glowing pale eyes, hair swept back, a brass
    # circlet with a storm stone.
    hz = bn["head"].head_local.z
    hy = bn["head"].head_local.y
    k = Kit("Head", M)
    k.sphere((0, hy, hz + 0.085), 0.09, "Skin", scale=(0.84, 0.95, 1.14))
    for sx in (-1.0, 1.0):
        k.sphere((sx * 0.032, hy + 0.09, hz + 0.105), 0.012, "Eyes", scale=(1.6, 0.6, 0.55), u=8, v=6)
    k.sphere((0, hy + 0.092, hz + 0.08), 0.014, "Skin", scale=(0.8, 1.2, 1.3), u=8, v=6)
    k.arc_lathe([(0.07, hz + 0.0), (0.098, hz + 0.08), (0.1, hz + 0.15), (0.07, hz + 0.2), (0.02, hz + 0.215)], "Fur", 1.1, TAU - 1.1,
                seg=16, sx=0.92, center=(0, hy - 0.01))
    for i in range(5):
        a = math.pi + (i - 2) * 0.35
        p0 = Vector((math.sin(a) * 0.08, hy - 0.01 + math.cos(a) * 0.08, hz + 0.17))
        k.tube([p0, p0 + Vector((math.sin(a) * 0.04, -0.09, -0.02)), p0 + Vector((math.sin(a) * 0.05, -0.16, -0.09))], [0.025, 0.018, 0.003],
               "Fur", seg=6)
    k.lathe([(0.093, hz + 0.135), (0.095, hz + 0.15)], "Brass", seg=24, sx=0.88, center=(0, hy))
    k.octa(Vector((0, hy + 0.09, hz + 0.145)), 0.014, 0.022, 0.016, "Glow")
    k.finish(rig, "head", subsurf=1)

    # Sleeves with steel cuffs, hands, legs and boots.
    for side in ("r", "l"):
        ck.sleeve(rig, M, side, "Robe", radii=(0.078, 0.07, 0.064, 0.07, 0.085), cuff="Steel", cuff_r=0.078)
        ck.hand(rig, M, side, "Skin", fist=(side == "r"))
    ck.limbs(rig, M, legs="ClothDark", boots="Leather", hands=None)

    # Forked rod: dark iron with brass collars, splitting into two tines that
    # crackle at their tips.
    p = bn["rod"].head_local
    up = Vector((0, 0, 1))
    k = Kit("Rod", M)
    k.tube([p - up * 0.5, p + up * 0.6], [0.019, 0.021], "Iron", seg=8)
    k.tube([p - up * 0.07, p + up * 0.07], [0.025, 0.025], "Leather", seg=8)
    for zz in (0.3, 0.55):
        k.tube([p + up * zz, p + up * (zz + 0.03)], [0.028, 0.028], "Brass", seg=8)
    top = p + up * 0.6
    for sd in (-1.0, 1.0):
        d = Vector((sd, 0, 0))
        tine = [top, top + d * 0.05 + up * 0.06, top + d * 0.07 + up * 0.16, top + d * 0.055 + up * 0.26]
        k.tube(tine, [0.018, 0.014, 0.011, 0.004], "Iron", seg=6)
        k.octa(tine[-1] + up * 0.02, 0.014, 0.04, 0.02, "Glow")
    k.tube([top + Vector((-0.06, 0, 0.12)), top + Vector((0, 0, 0.15)), top + Vector((0.06, 0, 0.12))], [0.004, 0.006, 0.004], "Glow", seg=4)
    k.finish(rig, "rod")

    # Three sparks circling over the shoulders.
    k = Kit("Sparks", M)
    c = bn["sparks"].head_local
    for i in range(3):
        a = i / 3 * TAU
        q = c + Vector((math.cos(a) * 0.34, math.sin(a) * 0.3, 0.16 + 0.05 * i))
        k.octa(q, 0.022, 0.04, 0.04, "Glow")
    k.finish(rig, "sparks")


# ---------------------------------------------------------------- clips

def animate(rig, spec):
    slots = spec["slot_clips"]
    feet = ck.rest_feet(rig)
    rest = dict(upper_arm_r=(10, 0, 4), forearm_r=(-10, 0, 0), upper_arm_l=(8, 0, -4), forearm_l=(-6, 0, 0), rod=(0, 0, 0))

    def b(t=0.0, **over):
        d = dict(rest)
        d["sparks"] = (0, 0, (t * 140.0) % 360.0 - 180.0)
        d.update(over)
        return base(NAMES, **d)

    def spin(t):
        # A full turn of the sparks over each idle loop, bobbing.
        return {"sparks": (0, 0, 0.04 * math.sin(t * TAU / 1.5))}

    length = 3.0
    ck.idle_clip(rig, length, lambda t, s: (b(spine=(1.5 * s, 0, 0), chest=(-1 * s, 0, 1.5 * s), head=(2 * s, 0, 5 * math.sin(t / length * TAU)),
                                              upper_arm_r=(10 + 2 * s, 0, 4), rod=(2 * s, 0, 0),
                                              sparks=(0, 0, t / length * 360.0 - 180.0), skirt_f=(-1 * s, 0, 0)),
                                            {"hips": (0, 0, -0.012 - 0.008 * s), **spin(t)}), step=3)

    def upper(t, s, c2):
        rots = b(hips=(0, 0, 8 * s), spine=(-10, 0, -5 * s), chest=(-4, 0, -5 * s), head=(10, 0, 3 * s),
                 upper_arm_r=(-25 * s + 10, 0, 8), forearm_r=(-40 - 10 * s, 0, 0), rod=(-30, 0, 0),
                 upper_arm_l=(30 * s + 6, 0, -6), forearm_l=(-40 + 10 * s, 0, 0), sparks=(0, 0, t * 360.0 - 180.0),
                 skirt_f=(-14 - 8 * c2, 0, 0), skirt_b=(30 + 6 * c2, 0, 0))
        return rots, {}
    ck.run_clip(rig, spec["move_speed_mps"], upper, cycle=0.6, stance=0.2, hips_drop=0.08, lift=0.24, kick=0.2)

    # Spark Bolt: the rod is levelled and jabbed forward.
    c = slots["attack"]
    rel, rec = c["release_s"], c["recovery_s"]
    ck.cast_clip(rig, "attack", rel, rec, [
        (0, b(), (0, 0, -0.012)),
        (rel * 0.6, b(chest=(0, 0, 16), upper_arm_r=(40, 0, 30), forearm_r=(-70, 0, 0), rod=(-20, 0, 0)), (0, -0.03, -0.02)),
        (rel, b(spine=(-4, 0, -6), chest=(-4, 0, -12), upper_arm_r=(80, 0, -4), forearm_r=(-10, 0, 0), rod=(-60, 0, 0)), (0, 0.05, -0.04)),
        (rel + rec * 0.5, b(chest=(-3, 0, -10), upper_arm_r=(70, 0, -4), forearm_r=(-14, 0, 0), rod=(-55, 0, 0)), (0, 0.04, -0.04)),
        (rel + rec, b(), (0, 0, -0.012))], feet)

    # Called Lightning: the rod raised to the sky, the free hand pointing at
    # the mark on release.
    c = slots["ability_1"]
    rel, rec = c["release_s"], c["recovery_s"]
    ck.cast_clip(rig, "ability_1", rel, rec, [
        (0, b(), (0, 0, -0.012)),
        (rel * 0.6, b(spine=(-6, 0, 0), head=(-14, 0, 0), upper_arm_r=(160, 0, 6), forearm_r=(-10, 0, 0), rod=(-150, 0, 0),
                      upper_arm_l=(30, 0, -10)), (0, 0, 0.01)),
        (rel, b(spine=(6, 0, 0), head=(4, 0, 0), upper_arm_r=(165, 0, 6), forearm_r=(-8, 0, 0), rod=(-155, 0, 0), upper_arm_l=(80, 0, 0),
                forearm_l=(-5, 0, 0), hand_l=(-20, 0, 0)), (0, 0.03, -0.03)),
        (rel + rec, b(spine=(4, 0, 0), upper_arm_r=(150, 0, 6), rod=(-140, 0, 0), upper_arm_l=(70, 0, 0)), (0, 0.02, -0.03))], feet)

    # Storm Wall: the left arm sweeps across the body from right to left.
    c = slots["ability_2"]
    rel, rec = c["release_s"], c["recovery_s"]
    ck.cast_clip(rig, "ability_2", rel, rec, [
        (0, b(), (0, 0, -0.012)),
        (rel * 0.6, b(spine=(0, 0, -16), chest=(0, 0, -20), upper_arm_l=(80, 0, -60), forearm_l=(-30, 0, 0), upper_arm_r=(30, 0, 20),
                      rod=(-20, 0, 0)), (0, -0.02, -0.03)),
        (rel, b(spine=(4, 0, 18), chest=(2, 0, 22), upper_arm_l=(85, 0, 50), forearm_l=(-5, 0, 0), hand_l=(0, 0, 20), upper_arm_r=(30, 0, 10)),
         (0, 0.04, -0.05)),
        (rel + rec, b(spine=(3, 0, 14), upper_arm_l=(75, 0, 45), forearm_l=(-8, 0, 0)), (0, 0.03, -0.04))], feet)

    # Tempest: both arms thrown up, the head back, the sparks flung out.
    c = slots["ability_3"]
    rel, rec = c["release_s"], c["recovery_s"]
    ck.cast_clip(rig, "ability_3", rel, rec, [
        (0, b(), (0, 0, -0.012)),
        (rel * 0.6, b(spine=(10, 0, 0), chest=(6, 0, 0), head=(12, 0, 0), upper_arm_r=(40, 0, 20), forearm_r=(-60, 0, 0),
                      upper_arm_l=(40, 0, -20), forearm_l=(-60, 0, 0), sparks=(0, 0, -90)), (0, 0, -0.1)),
        (rel, b(spine=(-12, 0, 0), chest=(-8, 0, 0), head=(-24, 0, 0), upper_arm_r=(160, 0, 14), forearm_r=(-10, 0, 0), rod=(-150, 0, 0),
                upper_arm_l=(155, 0, -14), forearm_l=(-10, 0, 0), skirt_b=(8, 0, 0), sparks=(0, 0, 60)), (0, 0, 0.02)),
        (rel + rec, b(spine=(-10, 0, 0), head=(-18, 0, 0), upper_arm_r=(150, 0, 12), rod=(-140, 0, 0), upper_arm_l=(145, 0, -12),
                      sparks=(0, 0, 120)), (0, 0, 0.01))], feet)

    ck.death_clip(rig, NAMES, lambda t: {"rod": (-30 * min(1.0, t / 0.6), 0, 0), "sparks": (0, 0, 0)})


def main():
    import sys
    out = ck.out_path(sys.argv, "/tmp/stormscald.blend")
    spec = ck.load_spec("stormscald")
    ck.reset()
    rig = ck.make_rig(bones())
    M = ck.Mats()
    build_model(rig, M)
    hr = rig.data.bones["hand_r"]
    ck.socket("Muzzle", rig, "hand_r", hr.head_local + (hr.tail_local - hr.head_local).normalized() * 0.11)
    ox, oy, oz = spec["sockets"]["Overhead"]
    ck.socket("Overhead", rig, "root", (ox, -oz, oy))
    ck.socket("Focus", rig, "rod", rig.data.bones["rod"].head_local + Vector((0, 0, 0.78)))
    animate(rig, spec)
    ck.save(out)


if __name__ == "__main__":
    main()
