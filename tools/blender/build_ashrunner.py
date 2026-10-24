# SPDX-License-Identifier: GPL-2.0-or-later
# (Uses Blender's Python API. This is a build tool, not part of the game.)
"""Build the Ashrunner champion model, rig and clips, all from code.

  /opt/bpyenv/bin/python tools/blender/build_ashrunner.py OUT.blend

A lean hooded skirmisher: a split-tailed wool coat over a leather jerkin,
a knife bandolier, a long team scarf that streams behind, and two short
blades with glowing edges. Original geometry written as code.
"""
import math

import bpy  # noqa: F401,I001  (bpy first: it makes mathutils importable)
from mathutils import Vector

import champion_kit as ck
from champion_kit import TAU, Kit, base

S = 0.9
W = 0.95

NAMES = ck.BODY + ["blade_r", "blade_l", "scarf", "scarf2"]


def bones():
    b = ck.humanoid_bones(S, W)
    for side in ("r", "l"):
        h, t = Vector(b["hand_" + side][0]), Vector(b["hand_" + side][1])
        palm = h + (t - h).normalized() * 0.05
        b["blade_" + side] = (tuple(palm), tuple(palm + (t - h).normalized() * 0.2), "hand_" + side)
    b["scarf"] = ((0, -0.1 * S, 1.45 * S), (0, -0.2 * S, 1.17 * S), "chest")
    b["scarf2"] = ((0, -0.2 * S, 1.17 * S), (0, -0.3 * S, 0.82 * S), "scarf")
    return b


def coat_fold(th, z, r):
    depth = max(0.0, (0.98 * S - z) / 0.4)
    return r + depth * (0.012 * math.sin(th * 8.0 + 0.3) + 0.008 * math.sin(th * 15.0))


def build_model(rig, M):
    bn = rig.data.bones
    z = lambda v: v * S  # noqa: E731

    # Leather jerkin, close over the torso, with a high collar.
    k = Kit("Jerkin", M)
    prof = [(0.17, 0.9), (0.165, 1.0), (0.17, 1.12), (0.2, 1.26), (0.205, 1.35), (0.185, 1.43), (0.13, 1.49), (0.085, 1.55), (0.08, 1.6)]
    k.lathe([(r * S, z(h)) for r, h in prof], "Leather", seg=28, sx=1.12, sy=0.85)
    k.finish(rig, ["chest", "spine", "hips", "neck"], subsurf=1)

    # Coat: a wool coat open at the front, its two tails split at the back
    # and cut short at the front so the legs read in the run.
    k = Kit("Coat", M)
    seg = 30
    rings = []
    for r, h in ((0.19, 1.0), (0.205, 0.9), (0.235, 0.78), (0.26, 0.66), (0.27, 0.6)):
        ring = []
        for i in range(seg + 1):
            th = 0.55 + i / seg * (TAU - 1.1)  # open at the front
            zz = z(h)
            if h < 0.95:
                zz += 0.18 * S * max(0.0, math.cos(th)) ** 2 * (0.95 - h) / 0.35
                zz -= 0.03 * abs(math.sin(th * 2.0)) * (0.95 - h) / 0.35
            rr = coat_fold(th, zz, r * S)
            ring.append(Vector((math.sin(th) * rr * 1.1, math.cos(th) * rr * 0.92, zz)))
        rings.append(ring)
    k.ring_grid(rings, "RobeDark", closed=False)
    # Upper coat over the jerkin with a turned-back collar.
    rings = []
    for r, h in ((0.19, 1.0), (0.21, 1.14), (0.225, 1.28), (0.215, 1.38), (0.15, 1.46)):
        ring = []
        for i in range(seg + 1):
            th = 0.35 + i / seg * (TAU - 0.7)
            ring.append(Vector((math.sin(th) * r * S * 1.14, math.cos(th) * r * S * 0.9, z(h))))
        rings.append(ring)
    k.ring_grid(rings, "RobeDark", closed=False)
    k.finish(rig, ["hips", "spine", "chest", "thigh_l", "thigh_r", "skirt_b", "skirt_f"], subsurf=1, solidify=0.01)

    # Belt with pouches, a knife bandolier across the chest.
    k = Kit("Gear", M)
    k.lathe([(0.185 * S, z(0.96)), (0.19 * S, z(1.0))], "Leather", seg=28, sx=1.16, sy=0.9)
    k.box(Vector((0, 0.19 * 0.9 * S + 0.01, z(0.98))), (0.05, 0.015, 0.04), "Brass")
    for x in (-0.16, 0.15):
        k.box(Vector((x, 0.07, z(0.92))), (0.06, 0.05, 0.08), "Leather", rot=(0, 0, 25 if x > 0 else -25))
    a = Vector((-0.17, 0.0, z(1.44)))
    bb = Vector((0.16, 0.0, z(1.0)))
    strap = []
    for i in range(9):
        u = i / 8
        p = a.lerp(bb, u)
        ry = 0.205 * 0.85 * S * math.sqrt(max(0.0, 1 - (p.x / (0.22 * S)) ** 2)) + 0.012
        strap.append(Vector((p.x, ry, p.z)))
    k.tube(strap, [0.022] * 9, "Leather", seg=6, flat=0.35)
    k.tube([Vector((p.x, -p.y, p.z)) for p in strap], [0.022] * 9, "Leather", seg=6, flat=0.35)
    for i in range(2, 7):
        p = strap[i] + Vector((0, 0.012, 0))
        d = (strap[i + 1] - strap[i - 1]).normalized()
        perp = d.cross(Vector((0, 1, 0))).normalized()
        k.tube([p - perp * 0.02, p + perp * 0.05], [0.01, 0.008], "Iron", seg=5)
        k.tube([p - perp * 0.02, p - perp * 0.045], [0.012, 0.012], "Brass", seg=5)
    k.finish(rig, ["chest", "spine", "hips"])

    # Scarf: a team wrap at the neck, a mask over the lower face, and a long
    # tail that streams behind.
    hz = bn["head"].head_local.z
    hy = bn["head"].head_local.y
    k = Kit("Scarf", M)
    k.lathe([(0.1, z(1.47)), (0.11, z(1.52)), (0.095, z(1.57)), (0.082, hz + 0.0)], "Team", seg=22, sx=1.1, sy=1.05, center=(0, hy * 0.5))
    rows = []
    for j in range(10):
        f = j / 9
        p = Vector((0.03 * math.sin(f * 5), -0.11 * S - 0.2 * S * f - 0.08 * f * f, z(1.5) - 0.75 * S * f))
        w = 0.07 - 0.015 * f
        rows.append([p + Vector((u * w, 0.01 * math.sin(f * 7 + u), 0)) for u in (-1.0, 0.0, 1.0)])
    k.ring_grid(rows, "Team", closed=False)
    k.ring_grid([[rows[-1][0] + Vector((0, -0.002, dz)), rows[-1][1] + Vector((0, -0.002, dz)), rows[-1][2] + Vector((0, -0.002, dz))]
                 for dz in (0.0, 0.03)], "Trim", closed=False)
    k.finish(rig, ["neck", "chest", "scarf", "scarf2"], solidify=0.008)

    # Hood: a close cowl with a sharp peak, the face in shadow behind the
    # scarf, glowing eyes.
    k = Kit("Hood", M)
    rings = []
    for j in range(11):
        a = math.pi * (0.06 + j / 10.0 * 0.84)
        g = math.pi * 0.62 * min(1.0, max(0.0, (j - 2) / 4.0)) ** 0.8
        ring = []
        for i in range(25):
            u = i / 24.0
            th = g * 0.5 + u * (TAU - g)
            r = 0.118 * math.sin(a) + 0.016
            zz = hz + 0.075 + 0.14 * math.cos(a)
            x = math.sin(th) * r * 1.02
            y = hy + math.cos(th) * r + 0.01 + 0.035 * max(0.0, math.cos(th)) * min(1.0, j / 4.0)
            if j <= 3 and math.cos(th) < 0.0:
                zz += 0.02 * (1 - j / 3.0) * -math.cos(th)
                y -= 0.03 * (1 - j / 3.0) * -math.cos(th)
            ring.append(Vector((x, y, zz)))
        rings.append(ring)
    k.ring_grid(rings, "Robe", closed=False)
    k.tube([(0, hy - 0.07, hz + 0.19), (0, hy - 0.13, hz + 0.14), (0, hy - 0.17, hz + 0.07)], [0.04, 0.025, 0.004], "Robe", seg=8, cap=False)
    k.finish(rig, ["head", "neck"], subsurf=1, solidify=0.012)
    k = Kit("Head", M)
    k.sphere((0, hy, hz + 0.075), 0.09, "RobeInner", scale=(0.86, 0.95, 1.1))
    for sx in (-1.0, 1.0):
        k.sphere((sx * 0.032, hy + 0.08, hz + 0.1), 0.012, "Eyes", scale=(1.6, 0.6, 0.5), u=8, v=6)
    k.finish(rig, "head")

    # Arms: dark cloth sleeves, leather bracers with straps, gloves, and a
    # single steel spaulder on the left shoulder.
    for side in ("r", "l"):
        ck.sleeve(rig, M, side, "ClothDark", radii=(0.07, 0.062, 0.055, 0.05, 0.05))
        el = bn["forearm_" + side].head_local
        wr = bn["hand_" + side].head_local
        d = (wr - el).normalized()
        k = Kit("Bracer_" + side, M)
        k.tube([el + d * 0.05, el.lerp(wr, 0.6), wr + d * 0.01], [0.056, 0.058, 0.055], "Leather", seg=12)
        for f in (0.35, 0.7):
            k.tube([el.lerp(wr, f), el.lerp(wr, f) + d * 0.014], [0.06, 0.06], "Iron", seg=12, cap=False)
        k.finish(rig, "forearm_" + side, subsurf=1)
        ck.hand(rig, M, side, "Leather", fist=True)
    k = Kit("Spaulder", M)
    top = bn["upper_arm_l"].head_local
    k.sphere(top + Vector((-0.03, 0, 0.03)), 0.1, "Steel", scale=(1.0, 1.1, 0.7), u=16, v=8)
    k.sphere(top + Vector((-0.055, 0, -0.02)), 0.085, "Steel", scale=(0.9, 1.0, 0.55), u=16, v=8)
    k.finish(rig, "shoulder_l")

    # Legs: cloth trousers wrapped from the knee, soft leather boots.
    ck.limbs(rig, M, legs="ClothDark", boots="Leather", hands=None, leg_r=(0.078, 0.066, 0.055, 0.05), boot_scale=0.92, cuff="Leather")
    for side in ("l", "r"):
        knee = bn["shin_" + side].head_local
        k = Kit("KneePad_" + side, M)
        k.sphere(knee + Vector((0, 0.045, 0)), 0.045, "Leather", scale=(1.0, 0.7, 1.1), u=12, v=8)
        k.finish(rig, "shin_" + side)

    # Blades: short, slightly curved, with an ember-bright edge.
    for side in ("r", "l"):
        bb = bn["blade_" + side]
        p = bb.head_local
        d = (bb.tail_local - p).normalized()
        side_v = d.cross(Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((0, 1, 0))).normalized()
        bend = d.cross(side_v).normalized()
        k = Kit("Blade_" + side, M)
        k.tube([p - d * 0.045, p + d * 0.05], [0.017, 0.017], "Leather", seg=6)
        k.sphere(p - d * 0.055, 0.02, "Brass", u=8, v=6)
        k.tube([p + d * 0.05, p + d * 0.065], [0.04, 0.04], "Brass", seg=6, flat=0.35)
        pts = [p + d * (0.065 + 0.07 * i) + bend * (0.004 * i * i) for i in range(5)]
        k.tube(pts, [0.026, 0.026, 0.023, 0.016, 0.002], "Steel", seg=6, flat=0.18)
        k.tube([q + bend * 0.02 for q in pts[:4]], [0.004, 0.004, 0.004, 0.002], "Glow", seg=4)
        k.finish(rig, "blade_" + side)


# ---------------------------------------------------------------- clips

def animate(rig, spec):
    slots = spec["slot_clips"]
    feet = ck.rest_feet(rig)
    rest = dict(upper_arm_r=(14, 0, 8), forearm_r=(-20, 0, 0), upper_arm_l=(14, 0, -8), forearm_l=(-10, 0, 0),
                blade_r=(0, 0, 0), blade_l=(0, 0, 0), spine=(6, 0, 0), head=(-6, 0, 0), scarf=(10, 0, 0), scarf2=(10, 0, 0))

    def b(**over):
        d = dict(rest)
        d.update(over)
        return base(NAMES, **d)

    ready = {"l": (feet["l"][0] - 0.03, feet["l"][1] + 0.08, feet["l"][2]), "r": (feet["r"][0] + 0.03, feet["r"][1] - 0.08, feet["r"][2])}

    # Idle: a low ready crouch with a quick light bounce, blades low, the
    # scarf tail stirring.
    ck.idle_clip(rig, 1.6, lambda t, s: (b(spine=(6 + 1.5 * s, 0, 0), chest=(0, 0, 4), head=(-6, 0, 6 * math.sin(t / 1.6 * TAU)),
                                            upper_arm_r=(14 + 3 * s, 0, 8), upper_arm_l=(14 - 3 * s, 0, -8),
                                            scarf=(10 + 4 * s, 0, 3 * s), scarf2=(10 + 6 * s, 0, 0)),
                                          {"hips": (0, 0, -0.05 - 0.012 * s)}), step=4)

    # Run: fast and low, the body leaned well forward, the blades held back
    # along the forearms, the scarf streaming out straight.
    def upper(t, s, c2):
        rots = b(hips=(0, 0, 10 * s), spine=(-20, 0, -5 * s), chest=(-6, 0, -7 * s), head=(16, 0, 3 * s),
                 upper_arm_r=(-45 * s - 5, 0, 10), forearm_r=(-55 - 20 * s, 0, 0), blade_r=(-60, 0, 0),
                 upper_arm_l=(45 * s - 5, 0, -10), forearm_l=(-55 + 20 * s, 0, 0), blade_l=(-60, 0, 0),
                 skirt_f=(-20 - 8 * c2, 0, 0), skirt_b=(35 + 8 * c2, 0, 0), cape=(0, 0, 0),
                 scarf=(55 + 6 * c2, 0, 6 * s), scarf2=(20 + 10 * c2, 0, 8 * s))
        return rots, {}
    ck.run_clip(rig, spec["move_speed_mps"], upper, cycle=0.54, stance=0.2, hips_drop=0.1, lift=0.24, kick=0.2)

    # Twin Cut: both blades cross at the chest, then sweep out in an X.
    c = slots["attack"]
    rel, rec = c["release_s"], c["recovery_s"]
    ck.cast_clip(rig, "attack", rel, rec, [
        (0, b(), (0, 0, -0.05)),
        (rel * 0.6, b(spine=(0, 0, 0), chest=(-4, 0, 0), upper_arm_r=(80, 0, 40), forearm_r=(-60, 0, 0), blade_r=(30, 0, 0),
                      upper_arm_l=(80, 0, -40), forearm_l=(-60, 0, 0), blade_l=(30, 0, 0)), (0, -0.03, -0.06)),
        (rel, b(spine=(16, 0, 0), chest=(8, 0, 0), upper_arm_r=(70, 0, -45), forearm_r=(-10, 0, 0), blade_r=(20, 0, 0),
                upper_arm_l=(70, 0, 45), forearm_l=(-10, 0, 0), blade_l=(20, 0, 0)), (0, 0.08, -0.1)),
        (rel + rec * 0.5, b(spine=(14, 0, 0), upper_arm_r=(50, 0, -55), forearm_r=(-10, 0, 0), upper_arm_l=(50, 0, 55), forearm_l=(-10, 0, 0)),
         (0, 0.07, -0.1)),
        (rel + rec, b(), (0, 0, -0.05))], ready)

    # Vault: a coil down, then a spring forward with the arms flung back.
    c = slots["ability_1"]
    rel, rec = c["release_s"], c["recovery_s"]
    ck.cast_clip(rig, "ability_1", rel, rec, [
        (0, b(), (0, 0, -0.05)),
        (rel * 0.7, b(spine=(24, 0, 0), chest=(8, 0, 0), head=(-20, 0, 0), upper_arm_r=(-30, 0, 10), upper_arm_l=(-30, 0, -10),
                      scarf=(20, 0, 0)), (0, 0.0, -0.2)),
        (rel, b(spine=(-14, 0, 0), chest=(-8, 0, 0), head=(10, 0, 0), upper_arm_r=(-60, 0, 20), forearm_r=(-20, 0, 0), upper_arm_l=(-60, 0, -20),
                forearm_l=(-20, 0, 0), blade_r=(-40, 0, 0), blade_l=(-40, 0, 0), scarf=(60, 0, 0), scarf2=(20, 0, 0), skirt_b=(40, 0, 0)),
         (0, 0.12, 0.05)),
        (rel + rec * 0.6, b(spine=(-18, 0, 0), upper_arm_r=(-50, 0, 20), upper_arm_l=(-50, 0, -20), scarf=(70, 0, 0), scarf2=(25, 0, 0),
                            skirt_b=(40, 0, 0)), (0, 0.1, 0.04)),
        (rel + rec, b(), (0, 0, -0.05))], ready)

    # Ember Knife: the right hand draws back past the ear, then snaps an
    # overhand throw forward on release.
    c = slots["ability_2"]
    rel, rec = c["release_s"], c["recovery_s"]
    ck.cast_clip(rig, "ability_2", rel, rec, [
        (0, b(), (0, 0, -0.05)),
        (rel * 0.6, b(spine=(-4, 0, -16), chest=(-6, 0, -20), upper_arm_r=(150, 0, -30), forearm_r=(-90, 0, 0), blade_r=(-60, 0, 0),
                      upper_arm_l=(60, 0, -10), forearm_l=(-30, 0, 0)), (0, -0.05, -0.06)),
        (rel, b(spine=(18, 0, 16), chest=(8, 0, 20), upper_arm_r=(80, 0, 10), forearm_r=(-5, 0, 0), blade_r=(-10, 0, 0),
                upper_arm_l=(-10, 0, -15), forearm_l=(-30, 0, 0)), (0, 0.08, -0.1)),
        (rel + rec * 0.5, b(spine=(14, 0, 14), chest=(6, 0, 16), upper_arm_r=(60, 0, 20), forearm_r=(-10, 0, 0), upper_arm_l=(0, 0, -12)),
         (0, 0.06, -0.09)),
        (rel + rec, b(), (0, 0, -0.05))], ready)

    # Ashfall: a deep crouch, then a long leap with the blades raised high,
    # the body arched and the scarf thrown up behind.
    c = slots["ability_3"]
    rel, rec = c["release_s"], c["recovery_s"]
    ck.cast_clip(rig, "ability_3", rel, rec, [
        (0, b(), (0, 0, -0.05)),
        (rel * 0.7, b(spine=(30, 0, 0), chest=(10, 0, 0), head=(-24, 0, 0), upper_arm_r=(-40, 0, 20), upper_arm_l=(-40, 0, -20),
                      blade_r=(-30, 0, 0), blade_l=(-30, 0, 0)), (0, 0.0, -0.26)),
        (rel, b(spine=(-20, 0, 0), chest=(-12, 0, 0), head=(-10, 0, 0), upper_arm_r=(160, 0, -20), forearm_r=(-20, 0, 0), blade_r=(-90, 0, 0),
                upper_arm_l=(160, 0, 20), forearm_l=(-20, 0, 0), blade_l=(-90, 0, 0), scarf=(80, 0, 0), scarf2=(40, 0, 0), skirt_b=(40, 0, 0),
                skirt_f=(-30, 0, 0)), (0, 0.1, 0.12)),
        (rel + rec * 0.5, b(spine=(-14, 0, 0), upper_arm_r=(140, 0, -20), blade_r=(-80, 0, 0), upper_arm_l=(140, 0, 20), blade_l=(-80, 0, 0),
                            scarf=(75, 0, 0), scarf2=(35, 0, 0)), (0, 0.08, 0.08)),
        (rel + rec, b(), (0, 0, -0.05))], ready)

    ck.death_clip(rig, NAMES, lambda t: {"scarf": (30 * min(1.0, t / 0.9), 0, 0), "scarf2": (20 * min(1.0, t / 0.9), 0, 0)})


def main():
    import sys
    out = ck.out_path(sys.argv, "/tmp/ashrunner.blend")
    spec = ck.load_spec("ashrunner")
    ck.reset()
    rig = ck.make_rig(bones())
    M = ck.Mats()
    build_model(rig, M)
    hr = rig.data.bones["hand_r"]
    ck.socket("Muzzle", rig, "hand_r", hr.head_local + (hr.tail_local - hr.head_local).normalized() * 0.11)
    ox, oy, oz = spec["sockets"]["Overhead"]
    ck.socket("Overhead", rig, "root", (ox, -oz, oy))
    animate(rig, spec)
    ck.save(out)


if __name__ == "__main__":
    main()
