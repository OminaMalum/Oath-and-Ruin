# SPDX-License-Identifier: GPL-2.0-or-later
# (Uses Blender's Python API. This is a build tool, not part of the game.)
"""Build the Veilsinger champion model, rig and clips, all from code.

  /opt/bpyenv/bin/python tools/blender/build_veilsinger.py OUT.blend

A wandering bard: light on its feet in a long split coat over a doublet, a
wide feathered hat, a team sash, and a round lute held out in front with a
glowing rosette. Original geometry written as code.
"""
import math

import bpy  # noqa: F401,I001  (bpy first: it makes mathutils importable)
from mathutils import Vector

import champion_kit as ck
from champion_kit import TAU, Kit, base

S = 0.95
W = 0.96

NAMES = ck.BODY + ["lute"]


def bones():
    b = ck.humanoid_bones(S, W)
    b["lute"] = ((0, 0.3 * S, 1.2 * S), (0, 0.3 * S, 1.4 * S), "chest")
    return b


def build_model(rig, M):
    bn = rig.data.bones
    z = lambda v: v * S  # noqa: E731

    # Doublet: fitted, buttoned, with a ruffled collar.
    k = Kit("Doublet", M)
    prof = [(0.17, 0.92), (0.165, 1.02), (0.175, 1.14), (0.2, 1.27), (0.205, 1.36), (0.185, 1.44), (0.12, 1.5), (0.085, 1.55)]
    k.lathe([(r * S, z(h)) for r, h in prof], "Leather", seg=28, sx=1.1, sy=0.86)
    for i in range(6):
        h = 1.0 + i * 0.08
        r = next((rr for rr, hh in reversed(prof) if hh <= h), prof[0][0])
        k.sphere(Vector((0, r * S * 0.86 + 0.006, z(h))), 0.012, "Brass", u=8, v=6)
    ruff = []
    for r, h in ((0.1, 1.5), (0.14, 1.54), (0.1, 1.57)):
        ring = []
        for i in range(32):
            th = i / 32 * TAU
            rr = r + (0.015 * math.sin(th * 12.0) if r > 0.12 else 0.0)
            ring.append(Vector((math.sin(th) * rr * S, math.cos(th) * rr * S, z(h))))
        ruff.append(ring)
    k.ring_grid(ruff, "Paper")
    k.finish(rig, ["chest", "spine", "hips", "neck"], subsurf=1)

    # Long coat, split up the back and open at the front, to the calves.
    k = Kit("Coat", M)
    seg = 34
    for half in (0, 1):
        rings = []
        for r, h in ((0.215, 1.38), (0.225, 1.25), (0.2, 1.08), (0.205, 0.95), (0.24, 0.75), (0.28, 0.5), (0.3, 0.36)):
            ring = []
            for i in range(seg // 2 + 1):
                f = i / (seg // 2)
                # One half runs from the front opening to the back split.
                th = (0.4 + f * (math.pi - 0.45)) * (1 if half else -1)
                zz = z(h)
                rr = r * S + max(0.0, 0.9 - h) * (0.02 * math.sin(th * 7.0))
                ring.append(Vector((math.sin(th) * rr * 1.1, math.cos(th) * rr * 0.9, zz)))
            rings.append(ring)
        k.ring_grid(rings, "Robe", closed=False)
        hem = [[Vector((p.x * 1.01, p.y * 1.01, p.z + dz)) for p in rings[-1]] for dz in (-0.003, 0.04)]
        k.ring_grid(hem, "Trim", closed=False)
    k.finish(rig, ["chest", "spine", "hips", "thigh_l", "thigh_r", "skirt_b", "skirt_f", "shin_l", "shin_r"], subsurf=1, solidify=0.01)

    # Team sash over the right shoulder to the left hip, tied with a bow tail.
    k = Kit("Sash", M)
    a = Vector((0.15, 0, z(1.45)))
    bb = Vector((-0.17, 0, z(0.97)))
    for sgn in (1.0, -1.0):
        row_l, row_r = [], []
        for i in range(9):
            p = a.lerp(bb, i / 8)
            hh = p.z / S
            r = next((rr for rr, h0 in reversed(prof) if h0 <= hh), prof[0][0]) * S
            ry = r * 0.86 * math.sqrt(max(0.0, 1 - (p.x / (r * 1.1 + 0.015)) ** 2)) + 0.014
            row_l.append(Vector((p.x, sgn * ry, p.z + 0.035)))
            row_r.append(Vector((p.x, sgn * ry, p.z - 0.035)))
        k.ring_grid([row_l, row_r], "Team", closed=False)
    tie = bb + Vector((0, 0.12, 0))
    k.tube([tie, tie + Vector((-0.03, 0.03, -0.12)), tie + Vector((-0.02, 0.04, -0.25))], [0.035, 0.03, 0.025], "Team", seg=6, flat=0.25)
    k.lathe([(0.17 * S, z(0.94)), (0.172 * S, z(0.98))], "Leather", seg=28, sx=1.11, sy=0.9)
    k.finish(rig, ["chest", "spine", "hips", "skirt_f"], solidify=0.005)

    # Head: a fine face, glowing eyes, hair to the collar, and the wide
    # feathered hat tilted at an angle.
    hz = bn["head"].head_local.z
    hy = bn["head"].head_local.y
    k = Kit("Head", M)
    k.sphere((0, hy, hz + 0.085), 0.09, "Skin", scale=(0.85, 0.95, 1.12))
    for sx in (-1.0, 1.0):
        k.sphere((sx * 0.032, hy + 0.09, hz + 0.105), 0.012, "Eyes", scale=(1.5, 0.6, 0.55), u=8, v=6)
    k.sphere((0, hy + 0.09, hz + 0.08), 0.014, "Skin", scale=(0.8, 1.2, 1.2), u=8, v=6)
    k.arc_lathe([(0.07, hz - 0.03), (0.095, hz + 0.05), (0.1, hz + 0.12), (0.07, hz + 0.17)], "Fur", 1.4, TAU - 1.4, seg=14, sx=0.95,
                center=(0, hy - 0.02))
    k.finish(rig, "head", subsurf=1)
    k = Kit("Hat", M)
    bz = hz + 0.16
    tilt = math.radians(10)

    def tl(p):
        # Tilt the hat down over the left eye.
        x, y, zz = p
        dz = zz - bz
        return Vector((x * math.cos(tilt) - dz * math.sin(tilt), y, bz + x * math.sin(tilt) + dz * math.cos(tilt)))

    rings = []
    for r, dz in ((0.34, -0.035), (0.3, -0.01), (0.12, 0.005), (0.105, 0.0)):
        rings.append([tl((math.sin(i / 32 * TAU) * r, hy + math.cos(i / 32 * TAU) * r * 0.92, bz + dz + (0.03 if r > 0.2 and math.sin(i / 32 * TAU) > 0.5 else 0.0)))
                      for i in range(32)])
    k.ring_grid(rings, "RobeDark")
    crown = [[tl((math.sin(i / 24 * TAU) * r, hy + math.cos(i / 24 * TAU) * r, bz + dz)) for i in range(24)]
             for r, dz in ((0.103, 0.0), (0.105, 0.05), (0.095, 0.1), (0.06, 0.13), (0.0, 0.135))]
    k.ring_grid(crown, "RobeDark")
    k.ring_grid([[tl((math.sin(i / 24 * TAU) * 0.108, hy + math.cos(i / 24 * TAU) * 0.108, bz + dz)) for i in range(24)]
                 for dz in (0.005, 0.04)], "Team")
    # The plume: a long curved feather sweeping back from the band.
    root = tl((-0.09, hy - 0.03, bz + 0.04))
    quill = [root + Vector((-0.03 * f, -0.18 * f, 0.22 * math.sin(f * 2.2))) for f in [i / 10 for i in range(11)]]
    k.tube(quill, [0.006] * 11, "Paper", seg=4)
    rows = []
    for i, q in enumerate(quill):
        w = 0.045 * math.sin(math.pi * min(1.0, (i + 1) / 11))
        rows.append([q + Vector((-w, 0, 0)), q, q + Vector((w * 0.6, 0, 0.0))])
    k.ring_grid(rows, "Glow", closed=False)
    k.finish(rig, "head", subsurf=0, solidify=0.008)

    # Sleeves slashed with team colour, gloves, legs and tall boots.
    for side in ("r", "l"):
        ck.sleeve(rig, M, side, "Robe", radii=(0.075, 0.08, 0.06, 0.055, 0.055), cuff="Paper", cuff_r=0.07)
        sh = bn["upper_arm_" + side].head_local
        el = bn["forearm_" + side].head_local
        k = Kit("Slash_" + side, M)
        for f in (0.35, 0.6):
            c = sh.lerp(el, f)
            k.tube([c - Vector((0, 0, 0.03)), c + Vector((0, 0, 0.03))], [0.083, 0.083], "Team", seg=12, cap=False)
        k.finish(rig, "upper_arm_" + side)
        ck.hand(rig, M, side, "Leather")
    ck.limbs(rig, M, legs="ClothDark", boots="Leather", hands=None, leg_r=(0.075, 0.066, 0.056, 0.05), boot_scale=0.95, cuff="Leather")

    # Lute: a round bowl back, a pale soundboard with a glowing rosette, a
    # neck bent back at the pegbox, brass strings.
    lc = bn["lute"].head_local
    k = Kit("Lute", M)
    # The lute lies across the body: its neck points up and to the left.
    ax = Vector((-0.55, 0.0, 0.83)).normalized()
    side = Vector((0.83, 0.0, 0.55)).normalized()
    out = Vector((0, 1, 0))
    rings = []
    for f, r in ((-0.17, 0.0), (-0.16, 0.06), (-0.12, 0.12), (-0.05, 0.155), (0.03, 0.15), (0.1, 0.11), (0.15, 0.05), (0.17, 0.015)):
        ring = []
        for i in range(20):
            a = i / 19 * math.pi
            ring.append(lc + ax * f + side * (math.cos(a) * r) - out * (math.sin(a) * r * 0.7))
        rings.append(ring)
    k.ring_grid(rings, "Wood", closed=False)
    face = [[lc + ax * f + side * (u * r) + out * 0.002 for u in (-1.0, -0.5, 0.0, 0.5, 1.0)] for f, r in
            ((-0.16, 0.06), (-0.12, 0.12), (-0.05, 0.155), (0.03, 0.15), (0.1, 0.11), (0.15, 0.05))]
    k.ring_grid(face, "Bone", closed=False)
    ros = [lc + ax * 0.04 + (side * math.cos(i / 16 * TAU) + ax * math.sin(i / 16 * TAU)) * 0.04 + out * 0.006 for i in range(17)]
    k.tube(ros, [0.008] * 17, "Glow", seg=4)
    k.sphere(lc + ax * 0.04 + out * 0.004, 0.03, "RobeInner", scale=(1, 0.15, 1), u=10, v=4)
    neck = [lc + ax * 0.17 + out * -0.01, lc + ax * 0.45 + out * -0.01]
    k.tube(neck, [0.022, 0.018], "Wood", seg=6, flat=0.6)
    peg = lc + ax * 0.45
    k.tube([peg, peg + ax * 0.05 - out * 0.06, peg + ax * 0.1 - out * 0.1], [0.02, 0.018, 0.015], "Wood", seg=6, flat=0.6)
    for sx in (-0.012, -0.004, 0.004, 0.012):
        k.tube([lc - ax * 0.12 + side * sx + out * 0.006, peg + side * sx + out * 0.012], [0.0015, 0.0015], "Brass", seg=3)
    k.box(lc - ax * 0.11 + out * 0.008, (0.07, 0.012, 0.012), "Wood")
    k.finish(rig, "lute")


# ---------------------------------------------------------------- clips

def animate(rig, spec):
    slots = spec["slot_clips"]
    feet = ck.rest_feet(rig)
    # Playing pose: the left hand up on the neck, the right hand at the strings.
    play = dict(upper_arm_l=(40, 0, 30), forearm_l=(-60, 0, 40), hand_l=(0, 0, 0), upper_arm_r=(30, 0, 30), forearm_r=(-55, 0, 20))

    def b(**over):
        d = dict(play)
        d.update(over)
        return base(NAMES, **d)

    ck.idle_clip(rig, 2.0, lambda t, s: (b(spine=(2 * s, 0, 3 * s), chest=(-1 * s, 0, 2 * s), head=(4 * s, 0, 8 * math.sin(t / 2 * TAU)),
                                            forearm_r=(-55 + 8 * math.sin(t / 2 * TAU * 4), 0, 20), lute=(0, 4 * s, 0)),
                                          {"hips": (0.01 * s, 0, -0.012 - 0.01 * abs(s))}), step=3)

    def upper(t, s, c2):
        rots = b(hips=(0, 0, 9 * s), spine=(-10, 0, -5 * s), chest=(-4, 0, -6 * s), head=(10, 0, 3 * s), lute=(-6, 0, 0),
                 skirt_f=(-14 - 8 * c2, 0, 0), skirt_b=(30 + 6 * c2, 0, 0))
        return rots, {}
    ck.run_clip(rig, spec["move_speed_mps"], upper, cycle=0.58, stance=0.2, hips_drop=0.08, lift=0.25, kick=0.2)

    # Lute Note: a sharp strum, the body leaning into it.
    c = slots["attack"]
    rel, rec = c["release_s"], c["recovery_s"]
    ck.cast_clip(rig, "attack", rel, rec, [
        (0, b(), (0, 0, -0.012)),
        (rel * 0.6, b(chest=(0, 0, 10), upper_arm_r=(40, 0, 40), forearm_r=(-80, 0, 30)), (0, -0.02, -0.02)),
        (rel, b(spine=(8, 0, -6), chest=(6, 0, -8), upper_arm_r=(25, 0, 20), forearm_r=(-30, 0, 10), lute=(10, 0, 0)), (0, 0.04, -0.04)),
        (rel + rec * 0.5, b(spine=(6, 0, -4), upper_arm_r=(20, 0, 15), forearm_r=(-25, 0, 0), lute=(8, 0, 0)), (0, 0.03, -0.04)),
        (rel + rec, b(), (0, 0, -0.012))], feet)

    # War Song: the lute lifted, head thrown back, singing.
    c = slots["ability_1"]
    rel, rec = c["release_s"], c["recovery_s"]
    ck.cast_clip(rig, "ability_1", rel, rec, [
        (0, b(), (0, 0, -0.012)),
        (rel * 0.6, b(spine=(6, 0, 0), chest=(4, 0, 0), head=(10, 0, 0)), (0, 0, -0.06)),
        (rel, b(spine=(-12, 0, 0), chest=(-10, 0, 0), head=(-28, 0, 0), lute=(-25, 0, 0), upper_arm_l=(60, 0, 30), upper_arm_r=(45, 0, 30)),
         (0, 0, 0.0)),
        (rel + rec, b(spine=(-10, 0, 0), head=(-22, 0, 0), lute=(-20, 0, 0), upper_arm_l=(55, 0, 30), upper_arm_r=(42, 0, 30)), (0, 0, -0.01))],
        feet)

    # Lure: the lute thrust out ahead, a long bright note.
    c = slots["ability_2"]
    rel, rec = c["release_s"], c["recovery_s"]
    ck.cast_clip(rig, "ability_2", rel, rec, [
        (0, b(), (0, 0, -0.012)),
        (rel * 0.6, b(spine=(-6, 0, 8), chest=(-4, 0, 10), lute=(10, 0, 0)), (0, -0.05, -0.02)),
        (rel, b(spine=(16, 0, -4), chest=(10, 0, -6), head=(-6, 0, 0), lute=(30, 0, 0), upper_arm_l=(65, 0, 25), upper_arm_r=(50, 0, 25)),
         (0, 0.08, -0.08)),
        (rel + rec * 0.5, b(spine=(12, 0, -3), lute=(24, 0, 0)), (0, 0.06, -0.07)),
        (rel + rec, b(), (0, 0, -0.012))],
        {"l": (feet["l"][0], feet["l"][1] + 0.2, feet["l"][2]), "r": (feet["r"][0], feet["r"][1] - 0.15, feet["r"][2])})

    # Rally Chorus: a spin of the body, the lute raised high over the head.
    c = slots["ability_3"]
    rel, rec = c["release_s"], c["recovery_s"]
    ck.cast_clip(rig, "ability_3", rel, rec, [
        (0, b(), (0, 0, -0.012)),
        (rel * 0.5, b(spine=(4, 0, 30), chest=(2, 0, 30), head=(0, 0, -20)), (0, 0, -0.06)),
        (rel, b(spine=(-14, 0, 0), chest=(-12, 0, 0), head=(-24, 0, 0), lute=(-60, 0, 0), upper_arm_l=(150, 0, 10), forearm_l=(-30, 0, 20),
                upper_arm_r=(140, 0, 10), forearm_r=(-30, 0, 0)), (0, 0, 0.04)),
        (rel + rec, b(spine=(-12, 0, 0), head=(-20, 0, 0), lute=(-55, 0, 0), upper_arm_l=(145, 0, 10), upper_arm_r=(135, 0, 10)), (0, 0, 0.03))],
        feet)

    ck.death_clip(rig, NAMES, lambda t: {"lute": (30 * min(1.0, t / 0.6), 0, 0)})


def main():
    import sys
    out = ck.out_path(sys.argv, "/tmp/veilsinger.blend")
    spec = ck.load_spec("veilsinger")
    ck.reset()
    rig = ck.make_rig(bones())
    M = ck.Mats()
    build_model(rig, M)
    hr = rig.data.bones["hand_r"]
    ck.socket("Muzzle", rig, "hand_r", hr.head_local + (hr.tail_local - hr.head_local).normalized() * 0.11)
    ox, oy, oz = spec["sockets"]["Overhead"]
    ck.socket("Overhead", rig, "root", (ox, -oz, oy))
    ck.socket("Focus", rig, "lute", rig.data.bones["lute"].head_local + Vector((0, 0.05, 0)))
    animate(rig, spec)
    ck.save(out)


if __name__ == "__main__":
    main()
