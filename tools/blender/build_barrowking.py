# SPDX-License-Identifier: GPL-2.0-or-later
# (Uses Blender's Python API. This is a build tool, not part of the game.)
"""Build the Barrowking champion model, rig and clips, all from code.

  /opt/bpyenv/bin/python tools/blender/build_barrowking.py OUT.blend

The biggest body on the field: bare scarred arms, a fur mantle, a leather
harness and kilt, an iron crown of grave spikes and a two handed axe with a
bone-pale glowing edge. Original geometry written as code.
"""
import math

import bpy  # noqa: F401,I001  (bpy first: it makes mathutils importable)
from mathutils import Vector

import champion_kit as ck
from champion_kit import TAU, Kit, base

S = 0.98
W = 1.28

NAMES = ck.BODY + ["axe"]


def bones():
    b = ck.humanoid_bones(S, W)
    h, t = Vector(b["hand_r"][0]), Vector(b["hand_r"][1])
    palm = h + (t - h).normalized() * 0.06
    b["axe"] = (tuple(palm), tuple(palm + Vector((0, 0, 0.3))), "hand_r")
    return b


def build_model(rig, M):
    bn = rig.data.bones
    z = lambda v: v * S  # noqa: E731

    # Torso: a broad bare chest and belly under a leather harness.
    k = Kit("Torso", M)
    prof = [(0.2, 0.95), (0.21, 1.04), (0.215, 1.14), (0.25, 1.26), (0.265, 1.35), (0.245, 1.43), (0.17, 1.5), (0.1, 1.55)]
    k.lathe([(r * S, z(h)) for r, h in prof], "Skin", seg=28, sx=1.22, sy=0.86)
    k.finish(rig, ["chest", "spine", "hips"], subsurf=1)
    k = Kit("Harness", M)
    for sd in (-1.0, 1.0):
        a = Vector((sd * 0.17, 0, z(1.46)))
        bb = Vector((-sd * 0.2, 0, z(1.0)))
        front, back = [], []
        for i in range(9):
            p = a.lerp(bb, i / 8)
            hh = p.z / S
            r = next((rr for rr, h0 in reversed(prof) if h0 <= hh), prof[0][0]) * S
            ry = r * 0.86 * math.sqrt(max(0.0, 1 - (p.x / (r * 1.22 + 0.01)) ** 2)) + 0.012
            front.append(Vector((p.x, ry, p.z)))
            back.append(Vector((p.x, -ry, p.z)))
        k.tube(front, [0.026] * 9, "Leather", seg=6, flat=0.35)
        k.tube(back, [0.026] * 9, "Leather", seg=6, flat=0.35)
    k.sphere(Vector((0, 0.25 * 0.86 * S + 0.02, z(1.24))), 0.045, "Iron", scale=(1, 0.5, 1), u=12, v=8)
    k.sphere(Vector((0, 0.25 * 0.86 * S + 0.04, z(1.24))), 0.02, "Bone", scale=(1, 0.6, 1.2), u=8, v=6)
    # Wide belt, team loin panel, leather kilt of strips.
    k.lathe([(0.205 * S, z(0.92)), (0.215 * S, z(1.02))], "Leather", seg=30, sx=1.22, sy=0.9)
    k.box(Vector((0, 0.215 * 0.9 * S + 0.012, z(0.97))), (0.1, 0.02, 0.09), "Iron")
    k.finish(rig, ["chest", "spine", "hips"])
    k = Kit("Kilt", M)
    for i in range(14):
        a = i / 14 * TAU
        if abs(math.cos(a)) > 0.93:
            continue
        top = Vector((math.sin(a) * 0.215 * S * 1.22, math.cos(a) * 0.215 * S * 0.9, z(0.93)))
        out = Vector((math.sin(a), math.cos(a), 0))
        k.tube([top, top + out * 0.04 + Vector((0, 0, -0.18)), top + out * 0.07 + Vector((0, 0, -0.36))], [0.05, 0.05, 0.045],
               "Leather", seg=4, flat=0.25)
    rows = []
    for j in range(6):
        zz = z(0.93) - j * 0.08
        y = 0.215 * 0.9 * S + 0.03 + j * 0.012
        rows.append([Vector((u * 0.1, y, zz)) for u in (-1.0, 0.0, 1.0)])
    k.ring_grid(rows, "Team", closed=False)
    k.ring_grid([[Vector((p.x, p.y + 0.003, p.z + dz)) for p in rows[-1]] for dz in (0.0, 0.03)], "Iron", closed=False)
    k.finish(rig, ["hips", "skirt_f", "skirt_b", "thigh_l", "thigh_r"], solidify=0.008)

    # Fur mantle over the shoulders and down the back, team cloak under it.
    k = Kit("Mantle", M)
    rings = []
    for r, h in ((0.33, 1.3), (0.33, 1.38), (0.29, 1.46), (0.2, 1.53), (0.13, 1.57)):
        ring = []
        for i in range(36):
            th = i / 36 * TAU
            zz = z(h) - (0.05 * abs(math.sin(th * 6.0)) if h < 1.31 else 0.0) - (0.08 * max(0.0, -math.cos(th)) if h < 1.31 else 0.0)
            rr = r * S + 0.015 * math.sin(th * 11.0 + h * 9)
            ring.append(Vector((math.sin(th) * rr * 1.25, math.cos(th) * rr * 0.92, zz)))
        rings.append(ring)
    k.ring_grid(rings, "Fur", u_scale=3.0)
    k.finish(rig, ["chest", "spine", "neck"], subsurf=1, solidify=0.03)
    k = Kit("Cloak", M)
    rows = []
    for j in range(9):
        zz = z(1.36) - j * 0.11
        w = 0.34 + j * 0.02
        row = []
        for i in range(11):
            u = (i / 10.0) * 2.0 - 1.0
            y = -0.26 * S - 0.06 * (1 - u * u) - j * 0.014
            hz = zz - (0.06 * abs(math.sin(u * 4.0 + 0.5)) if j == 8 else 0.0)
            row.append(Vector((u * w, y + 0.012 * math.sin(u * 9.0 + j), hz)))
        rows.append(row)
    k.ring_grid(rows, "Team", closed=False)
    k.finish(rig, ["chest", "cape", "spine"], subsurf=1, solidify=0.01)

    # Head: a heavy jaw, a fur beard, glowing pale eyes and the iron crown of
    # grave spikes.
    hz = bn["head"].head_local.z
    hy = bn["head"].head_local.y
    k = Kit("Head", M)
    k.sphere((0, hy + 0.01, hz + 0.09), 0.105, "Skin", scale=(0.92, 0.95, 1.05))
    k.sphere((0, hy + 0.04, hz + 0.135), 0.08, "Skin", scale=(1.1, 0.75, 0.35), u=12, v=6)
    for sx in (-1.0, 1.0):
        k.sphere((sx * 0.036, hy + 0.098, hz + 0.115), 0.012, "Eyes", scale=(1.5, 0.6, 0.55), u=8, v=6)
    k.lathe([(0.075, hz - 0.03), (0.09, hz + 0.02), (0.085, hz + 0.07), (0.05, hz + 0.09)], "Fur", seg=16, sx=1.05, sy=0.55,
            center=(0, hy + 0.06))
    k.tube([(0, hy + 0.1, hz + 0.02), (0, hy + 0.12, hz - 0.06), (0, hy + 0.1, hz - 0.13)], [0.04, 0.03, 0.008], "Fur", seg=8)
    k.finish(rig, "head", subsurf=1)
    k = Kit("Crown", M)
    cz = hz + 0.16
    k.lathe([(0.1, cz), (0.103, cz + 0.045)], "Iron", seg=24, sx=0.95, sy=1.0, center=(0, hy + 0.01))
    for i in range(9):
        a = i / 9 * TAU
        base_p = Vector((math.sin(a) * 0.1 * 0.95, hy + 0.01 + math.cos(a) * 0.1, cz + 0.04))
        tall = 0.14 if i == 0 else (0.1 if i in (1, 8) else 0.07)
        k.tube([base_p, base_p + Vector((math.sin(a) * 0.02, math.cos(a) * 0.02, tall * 0.6)),
                base_p + Vector((math.sin(a) * 0.035, math.cos(a) * 0.035, tall))], [0.02, 0.012, 0.002], "Iron", seg=5)
    k.sphere(Vector((0, hy + 0.01 + 0.105, cz + 0.022)), 0.018, "Glow", u=8, v=6)
    k.finish(rig, "head")

    # Arms: bare and huge, with scars (pale bone lines), iron wrist bands,
    # big fists.
    for side in ("r", "l"):
        ck.sleeve(rig, M, side, "Skin", radii=(0.095, 0.088, 0.078, 0.074, 0.066))
        el = bn["forearm_" + side].head_local
        wr = bn["hand_" + side].head_local
        sh = bn["upper_arm_" + side].head_local
        d = (wr - el).normalized()
        k = Kit("Band_" + side, M)
        k.tube([wr - d * 0.1, wr - d * 0.005], [0.074, 0.074], "Iron", seg=12)
        k.tube([wr - d * 0.07, wr - d * 0.05], [0.078, 0.078], "Leather", seg=12, cap=False)
        k.finish(rig, "forearm_" + side)
        k = Kit("Scars_" + side, M)
        for f, off in ((0.3, 0.0), (0.55, 0.3)):
            c = sh.lerp(el, f)
            dd = (el - sh).normalized()
            x = dd.cross(Vector((0, 1, 0))).normalized()
            k.tube([c + x * 0.06 + Vector((0, 0.07, off * 0.1)), c + Vector((0, 0.088, 0.02)), c - x * 0.05 + Vector((0, 0.07, -0.03))],
                   [0.004, 0.005, 0.003], "Bone", seg=4)
        k.finish(rig, "upper_arm_" + side)
        ck.hand(rig, M, side, "Skin", fist=True)
    for side, sx in (("r", 1.0), ("l", -1.0)):
        k = Kit("Pauldron_" + side, M)
        top = bn["upper_arm_" + side].head_local
        k.sphere(top + Vector((sx * 0.04, 0, 0.04)), 0.12, "Iron", scale=(1.0, 1.1, 0.7), u=16, v=8)
        for dy in (-0.06, 0.0, 0.06):
            k.tube([top + Vector((sx * 0.07, dy, 0.1)), top + Vector((sx * 0.1, dy, 0.17))], [0.016, 0.002], "Bone", seg=5)
        k.finish(rig, "shoulder_" + side)

    ck.limbs(rig, M, legs="Leather", boots="Fur", hands=None, leg_r=(0.11, 0.1, 0.08, 0.074), boot_scale=1.2, cuff="Fur")

    # Two handed axe: a long haft, an iron crescent blade with a pale glowing
    # edge, a spike on the back and a bone pommel.
    p = bn["axe"].head_local
    up = Vector((0, 0, 1))
    fw = Vector((0, 1, 0))
    k = Kit("Axe", M)
    k.tube([p - up * 0.45, p + up * 0.75], [0.026, 0.028], "Wood", seg=8)
    for zz in (-0.08, 0.2):
        k.tube([p + up * (zz - 0.06), p + up * (zz + 0.06)], [0.032, 0.032], "Leather", seg=8)
    k.sphere(p - up * 0.48, 0.04, "Bone", scale=(1, 1, 1.3))
    hc = p + up * 0.62
    rows = []
    for j in range(9):
        v = j / 8 * 2 - 1
        reach = 0.26 - 0.06 * v * v
        rows.append([hc + up * (v * 0.2) + fw * (0.03 + f * reach) for f in (0.0, 0.5, 0.85, 1.0)])
    k.ring_grid(rows, "Iron", closed=False)
    edge = [hc + up * ((j / 12 * 2 - 1) * 0.215) + fw * (0.035 + 0.26 - 0.06 * (j / 12 * 2 - 1) ** 2) for j in range(13)]
    k.tube(edge, [0.012] * 13, "Glow", seg=5)
    k.tube([hc - fw * 0.02, hc - fw * 0.2 + up * 0.02], [0.035, 0.004], "Iron", seg=6)
    k.tube([hc + up * 0.13, hc + up * 0.3], [0.03, 0.003], "Iron", seg=6)
    k.finish(rig, "axe", solidify=0.03)


# ---------------------------------------------------------------- clips

def animate(rig, spec):
    slots = spec["slot_clips"]
    feet = ck.rest_feet(rig)
    rest = dict(upper_arm_r=(8, 0, 6), forearm_r=(-6, 0, 0), upper_arm_l=(10, 0, -8), forearm_l=(-10, 0, 0), axe=(0, 0, 0),
                spine=(4, 0, 0), head=(-4, 0, 0))

    def b(**over):
        d = dict(rest)
        d.update(over)
        return base(NAMES, **d)

    wide = {"l": (feet["l"][0] - 0.05, feet["l"][1] + 0.05, feet["l"][2]), "r": (feet["r"][0] + 0.05, feet["r"][1] - 0.05, feet["r"][2])}

    ck.idle_clip(rig, 3.0, lambda t, s: (b(spine=(4 + 2 * s, 0, 0), chest=(-1.5 * s, 0, 1.5 * s), head=(-4 + 2 * s, 0, 5 * math.sin(t / 3 * TAU)),
                                            upper_arm_r=(8 + 2 * s, 0, 6), upper_arm_l=(10 + 2 * s, 0, -8), cape=(1.5 * s, 0, 0)),
                                          {"hips": (0, 0, -0.025 - 0.01 * s)}))

    def upper(t, s, c2):
        rots = b(hips=(0, 0, 8 * s), spine=(-12, 0, -5 * s), chest=(-4, 0, -6 * s), head=(10, 0, 3 * s),
                 upper_arm_r=(-25 * s + 14, 0, 10), forearm_r=(-40 - 10 * s, 0, 0), axe=(-30, 0, 0),
                 upper_arm_l=(30 * s + 6, 0, -12), forearm_l=(-40 + 10 * s, 0, 0),
                 skirt_f=(-14 - 8 * c2, 0, 0), skirt_b=(24 + 6 * c2, 0, 0), cape=(28 + 6 * c2, 0, 0))
        return rots, {}
    ck.run_clip(rig, spec["move_speed_mps"], upper, cycle=0.64, stance=0.21, hips_drop=0.08, lift=0.22, kick=0.18)

    # Barrow Axe: a wide flat swing from the right across the front.
    c = slots["attack"]
    rel, rec = c["release_s"], c["recovery_s"]
    ck.cast_clip(rig, "attack", rel, rec, [
        (0, b(), (0, 0, -0.025)),
        (rel * 0.6, b(spine=(2, 0, -20), chest=(-2, 0, -30), upper_arm_r=(90, 0, -70), forearm_r=(-40, 0, 0), axe=(-40, 0, 0),
                      upper_arm_l=(70, 0, -40), forearm_l=(-50, 0, 0)), (0, -0.04, -0.06)),
        (rel, b(spine=(10, 0, 18), chest=(6, 0, 30), upper_arm_r=(75, 0, 40), forearm_r=(-10, 0, 0), axe=(10, 0, 0),
                upper_arm_l=(60, 0, 30), forearm_l=(-40, 0, 0)), (0, 0.06, -0.1)),
        (rel + rec * 0.5, b(spine=(8, 0, 22), chest=(5, 0, 34), upper_arm_r=(60, 0, 60), forearm_r=(-10, 0, 0), axe=(20, 0, 0),
                            upper_arm_l=(40, 0, 20)), (0, 0.05, -0.1)),
        (rel + rec, b(), (0, 0, -0.025))], wide)

    # Grave Roar: the chest thrown open, arms wide, head back.
    c = slots["ability_1"]
    rel, rec = c["release_s"], c["recovery_s"]
    ck.cast_clip(rig, "ability_1", rel, rec, [
        (0, b(), (0, 0, -0.025)),
        (rel * 0.6, b(spine=(16, 0, 0), chest=(10, 0, 0), head=(14, 0, 0), upper_arm_r=(30, 0, 30), forearm_r=(-60, 0, 0),
                      upper_arm_l=(30, 0, -30), forearm_l=(-60, 0, 0)), (0, -0.02, -0.08)),
        (rel, b(spine=(-14, 0, 0), chest=(-10, 0, 0), head=(-26, 0, 0), upper_arm_r=(60, -70, 0), forearm_r=(-30, 0, 0),
                upper_arm_l=(60, 70, 0), forearm_l=(-30, 0, 0), cape=(14, 0, 0)), (0, 0, -0.03)),
        (rel + rec, b(spine=(-10, 0, 0), head=(-18, 0, 0), upper_arm_r=(55, -60, 0), upper_arm_l=(55, 60, 0)), (0, 0, -0.03))], wide)

    # Barrow Charge: the shoulder dropped and driven forward.
    c = slots["ability_2"]
    rel, rec = c["release_s"], c["recovery_s"]
    ck.cast_clip(rig, "ability_2", rel, rec, [
        (0, b(), (0, 0, -0.025)),
        (rel * 0.6, b(spine=(20, 0, -10), chest=(10, 0, -16), head=(-14, 0, 0), upper_arm_l=(40, 0, 20), forearm_l=(-70, 0, 0),
                      upper_arm_r=(-20, 0, 10), axe=(-40, 0, 0)), (0, -0.04, -0.12)),
        (rel, b(spine=(32, 0, -14), chest=(14, 0, -20), head=(-24, 0, 0), upper_arm_l=(60, 0, 30), forearm_l=(-80, 0, 0),
                upper_arm_r=(-30, 0, 10), forearm_r=(-20, 0, 0), axe=(-50, 0, 0), cape=(30, 0, 0)), (0, 0.12, -0.16)),
        (rel + rec, b(spine=(26, 0, -10), head=(-20, 0, 0), upper_arm_l=(55, 0, 26), forearm_l=(-75, 0, 0), upper_arm_r=(-25, 0, 10)),
         (0, 0.1, -0.15))],
        {"l": (feet["l"][0], feet["l"][1] + 0.28, feet["l"][2]), "r": (feet["r"][0], feet["r"][1] - 0.25, feet["r"][2])})

    # King's Wrath: the axe raised high in both hands for a long beat, then
    # smashed down into the ground ahead.
    c = slots["ability_3"]
    rel, rec = c["release_s"], c["recovery_s"]
    ck.cast_clip(rig, "ability_3", rel, rec, [
        (0, b(), (0, 0, -0.025)),
        (rel * 0.5, b(spine=(-8, 0, 0), chest=(-8, 0, 0), head=(-16, 0, 0), upper_arm_r=(165, 0, 10), forearm_r=(-30, 0, 0), axe=(-150, 0, 0),
                      upper_arm_l=(160, 0, -16), forearm_l=(-40, 0, 0)), (0, -0.03, 0.02)),
        (rel * 0.9, b(spine=(-12, 0, 0), chest=(-10, 0, 0), head=(-18, 0, 0), upper_arm_r=(170, 0, 10), forearm_r=(-40, 0, 0), axe=(-160, 0, 0),
                      upper_arm_l=(165, 0, -16), forearm_l=(-45, 0, 0)), (0, -0.04, 0.03)),
        (rel, b(spine=(30, 0, 0), chest=(14, 0, 0), head=(10, 0, 0), upper_arm_r=(70, 0, -10), forearm_r=(-10, 0, 0), axe=(60, 0, 0),
                upper_arm_l=(70, 0, 20), forearm_l=(-30, 0, 0), cape=(30, 0, 0)), (0, 0.08, -0.24)),
        (rel + rec, b(spine=(24, 0, 0), upper_arm_r=(60, 0, -10), axe=(60, 0, 0), upper_arm_l=(60, 0, 20), forearm_l=(-30, 0, 0)),
         (0, 0.06, -0.2))], wide)

    ck.death_clip(rig, NAMES, lambda t: {"axe": (-40 * min(1.0, t / 0.6), 0, 0)})


def main():
    import sys
    out = ck.out_path(sys.argv, "/tmp/barrowking.blend")
    spec = ck.load_spec("barrowking")
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
