# SPDX-License-Identifier: GPL-2.0-or-later
# (Uses Blender's Python API. This is a build tool, not part of the game.)
"""Build the Thornwright champion model, rig and clips, all from code.

  /opt/bpyenv/bin/python tools/blender/build_thornwright.py OUT.blend

A hooded archer in green: a wool tunic over leathers, a team cape, a quiver
of fletched arrows on the back and a tall recurved longbow wound with thorn
vines. Original geometry written as code.
"""
import math

import bpy  # noqa: F401,I001  (bpy first: it makes mathutils importable)
from mathutils import Vector

import champion_kit as ck
from champion_kit import TAU, Kit, base

S = 0.95
W = 1.0

NAMES = ck.BODY + ["bow"]


def bones():
    b = ck.humanoid_bones(S, W)
    h, t = Vector(b["hand_l"][0]), Vector(b["hand_l"][1])
    palm = h + (t - h).normalized() * 0.05
    b["bow"] = (tuple(palm), tuple(palm + Vector((0, 0, 0.3))), "hand_l")
    return b


def tunic_fold(th, z, r):
    depth = max(0.0, (0.95 * S - z) / 0.35)
    return r + depth * (0.01 * math.sin(th * 8.0 + 0.4) + 0.007 * math.sin(th * 13.0))


def build_model(rig, M):
    bn = rig.data.bones
    z = lambda v: v * S  # noqa: E731

    # Leather jerkin under a wool tunic that splits at the sides to the thigh.
    k = Kit("Jerkin", M)
    prof = [(0.17, 0.95), (0.168, 1.05), (0.19, 1.2), (0.205, 1.32), (0.19, 1.42), (0.13, 1.49), (0.09, 1.54)]
    k.lathe([(r * S, z(h)) for r, h in prof], "Leather", seg=28, sx=1.12, sy=0.86)
    k.finish(rig, ["chest", "spine", "hips"], subsurf=1)
    k = Kit("Tunic", M)
    seg = 32
    rings = []
    for r, h in ((0.2, 1.36), (0.205, 1.22), (0.18, 1.06), (0.185, 0.96), (0.215, 0.82), (0.24, 0.66)):
        ring = []
        for i in range(seg):
            th = i / seg * TAU
            zz = z(h)
            if h < 0.9:
                zz += 0.06 * abs(math.sin(th)) ** 4  # side splits ride up
            ring.append(Vector((math.sin(th) * tunic_fold(th, zz, r * S) * 1.12, math.cos(th) * tunic_fold(th, zz, r * S) * 0.9, zz)))
        rings.append(ring)
    k.ring_grid(rings, "Robe", u_scale=2.0)
    band = [[Vector((p.x * 1.012, p.y * 1.012, p.z + dz)) for p in rings[-1]] for dz in (-0.004, 0.035)]
    k.ring_grid(band, "Leather")
    k.finish(rig, ["chest", "spine", "hips", "thigh_l", "thigh_r", "skirt_f", "skirt_b"], subsurf=1, solidify=0.01)

    # Belt, pouch, a bracer of thorny vine on the bow arm.
    k = Kit("Gear", M)
    k.lathe([(0.188 * S, z(0.95)), (0.19 * S, z(1.0))], "Leather", seg=28, sx=1.13, sy=0.92)
    k.box(Vector((0, 0.19 * 0.92 * S + 0.008, z(0.975))), (0.05, 0.015, 0.045), "Brass")
    k.box(Vector((0.17, 0.08, z(0.9))), (0.06, 0.06, 0.08), "Leather", rot=(0, 0, 25))
    # Baldric for the quiver, from the right shoulder to the left hip.
    a = Vector((0.15, 0, z(1.44)))
    bb = Vector((-0.15, 0, z(0.98)))
    front, back = [], []
    for i in range(9):
        p = a.lerp(bb, i / 8)
        ry = 0.205 * 0.86 * S * math.sqrt(max(0.0, 1 - (p.x / (0.235 * S)) ** 2)) + 0.026
        front.append(Vector((p.x, ry, p.z)))
        back.append(Vector((p.x, -ry, p.z)))
    k.tube(front, [0.02] * 9, "Leather", seg=6, flat=0.35)
    k.tube(back, [0.02] * 9, "Leather", seg=6, flat=0.35)
    k.finish(rig, ["chest", "spine", "hips"])

    # Team cape, short, from the shoulders to mid thigh, leaf-cut hem.
    k = Kit("Cape", M)
    rows = []
    for j in range(7):
        zz = z(1.44) - j * 0.11
        w = 0.24 + j * 0.02
        row = []
        for i in range(11):
            u = (i / 10.0) * 2.0 - 1.0
            y = -0.22 * S - 0.05 * (1 - u * u) - j * 0.012
            hz = zz - (0.05 * abs(math.sin(u * 5.5)) if j == 6 else 0.0)
            row.append(Vector((u * w, y + 0.01 * math.sin(u * 8.0 + j), hz)))
        rows.append(row)
    k.ring_grid(rows, "Team", closed=False)
    k.finish(rig, ["chest", "cape", "spine"], subsurf=1, solidify=0.01)

    # Quiver on the back, angled over the right shoulder, full of arrows.
    k = Kit("Quiver", M)
    q0 = Vector((-0.1, -0.3 * S, z(0.95)))
    q1 = Vector((0.12, -0.3 * S, z(1.5)))
    k.tube([q0, q0.lerp(q1, 0.5), q1], [0.052, 0.056, 0.06], "Leather", seg=12)
    k.tube([q1 - (q1 - q0).normalized() * 0.03, q1 + (q1 - q0).normalized() * 0.005], [0.064, 0.064], "Brass", seg=12, cap=False)
    d = (q1 - q0).normalized()
    for i in range(7):
        a = i / 7 * TAU
        off = Vector((math.cos(a) * 0.03, math.sin(a) * 0.03, 0))
        base_p = q1 + off - d * 0.02
        tip = base_p + d * (0.2 + 0.02 * (i % 3))
        k.tube([base_p, tip], [0.006, 0.006], "Wood", seg=4, cap=False)
        k.box(tip - d * 0.04 + off * 0.2, (0.004, 0.05, 0.08), "Feather", rot=(0, -math.degrees(math.atan2(d.x, d.z)), a * 57.3))
    k.finish(rig, ["chest", "spine"])

    # Hood and face: a pointed hood, a shadowed face and green-gold eyes.
    hz = bn["head"].head_local.z
    hy = bn["head"].head_local.y
    k = Kit("Hood", M)
    rings = []
    for j in range(11):
        a = math.pi * (0.06 + j / 10.0 * 0.84)
        g = math.pi * 0.6 * min(1.0, max(0.0, (j - 2) / 4.0)) ** 0.8
        ring = []
        for i in range(25):
            th = g * 0.5 + i / 24.0 * (TAU - g)
            r = 0.128 * math.sin(a) + 0.016
            zz = hz + 0.08 + 0.15 * math.cos(a)
            x = math.sin(th) * r * 1.02
            y = hy + math.cos(th) * r + 0.01 + 0.035 * max(0.0, math.cos(th)) * min(1.0, j / 4.0)
            if j <= 3 and math.cos(th) < 0.0:
                zz += 0.02 * (1 - j / 3.0) * -math.cos(th)
                y -= 0.03 * (1 - j / 3.0) * -math.cos(th)
            ring.append(Vector((x, y, zz)))
        rings.append(ring)
    k.ring_grid(rings, "RobeDark", closed=False)
    k.tube([(0, hy - 0.08, hz + 0.21), (0, hy - 0.16, hz + 0.16), (0, hy - 0.21, hz + 0.06)], [0.045, 0.028, 0.004], "RobeDark", seg=8, cap=False)
    k.lathe([(0.14, z(1.47)), (0.16, z(1.5)), (0.13, z(1.55))], "RobeDark", seg=24, sx=1.1, sy=1.0)
    k.finish(rig, ["head", "neck"], subsurf=1, solidify=0.012)
    k = Kit("Head", M)
    k.sphere((0, hy, hz + 0.08), 0.09, "RobeInner", scale=(0.86, 0.95, 1.1))
    for sx in (-1.0, 1.0):
        k.sphere((sx * 0.032, hy + 0.086, hz + 0.1), 0.012, "Eyes", scale=(1.6, 0.6, 0.5), u=8, v=6)
    k.finish(rig, "head")

    # Arms: tunic sleeves to the elbow, leather bracers, gloves.
    for side in ("r", "l"):
        ck.sleeve(rig, M, side, "ClothDark", radii=(0.072, 0.064, 0.056, 0.05, 0.05))
        el = bn["forearm_" + side].head_local
        wr = bn["hand_" + side].head_local
        dd = (wr - el).normalized()
        k = Kit("Bracer_" + side, M)
        k.tube([el + dd * 0.04, el.lerp(wr, 0.6), wr + dd * 0.01], [0.058, 0.06, 0.056], "Leather", seg=12)
        if side == "l":
            vine = []
            for i in range(17):
                f = i / 16
                a = f * TAU * 2.5
                c = el.lerp(wr, 0.1 + 0.85 * f)
                x = dd.cross(Vector((0, 0, 1))).normalized()
                y = dd.cross(x)
                vine.append(c + (x * math.cos(a) + y * math.sin(a)) * 0.064)
            k.tube(vine, [0.008] * 17, "Wood", seg=5)
        k.finish(rig, "forearm_" + side, subsurf=1)
        ck.hand(rig, M, side, "Leather", fist=(side == "l"))
    ck.limbs(rig, M, legs="ClothDark", boots="Leather", hands=None, leg_r=(0.08, 0.07, 0.058, 0.052))

    # Longbow: a tall recurve of dark wood, a leather grip, thorn vines wound
    # up each limb with glowing buds, and a taut string.
    p = bn["bow"].head_local
    k = Kit("Bow", M)

    def limb(sd):
        pts = []
        for i in range(9):
            f = i / 8
            zz = sd * (0.06 + 0.66 * f)
            y = 0.08 * math.sin(f * math.pi * 0.8) - 0.06 * max(0.0, f - 0.75) / 0.25 + 0.06 * f
            pts.append(p + Vector((0, y, zz)))
        return pts

    up_l, dn_l = limb(1.0), limb(-1.0)
    k.tube(list(reversed(dn_l)) + up_l, [0.012 + 0.012 * (1 - abs(i - 8.5) / 8.5) for i in range(18)], "Wood", seg=7, flat=0.7)
    k.tube([p + Vector((0, 0, -0.07)), p + Vector((0, 0, 0.07))], [0.026, 0.026], "Leather", seg=8)
    k.tube([up_l[-1], dn_l[-1]], [0.003, 0.003], "Cloth", seg=4)
    for lp in (up_l, dn_l):
        for i in range(2, 8):
            q = lp[i] + Vector((0.016 * (1 if i % 2 else -1), 0.008, 0))
            k.octa(q, 0.007, 0.018 if lp is up_l else 0.006, 0.006 if lp is up_l else 0.018, "Wood")
        k.sphere(lp[5] + Vector((0.012, 0.01, 0)), 0.012, "Glow", u=8, v=6)
    k.finish(rig, "bow")


# ---------------------------------------------------------------- clips

def animate(rig, spec):
    slots = spec["slot_clips"]
    feet = ck.rest_feet(rig)
    rest = dict(upper_arm_r=(6, 0, 4), forearm_r=(-8, 0, 0), upper_arm_l=(8, 0, -4), forearm_l=(0, 0, 0), bow=(0, 0, 0))

    def b(**over):
        d = dict(rest)
        d.update(over)
        return base(NAMES, **d)

    # The shooting pose: the bow arm straight out ahead, the draw hand at the
    # cheek, the body turned side-on.
    aim = dict(spine=(0, 0, 30), chest=(0, 0, 20), head=(0, 0, -40), upper_arm_l=(88, 0, -40), forearm_l=(-30, 0, 0), bow=(-58, 0, 0),
               upper_arm_r=(85, -25, -30), forearm_r=(-20, 0, 110), hand_r=(0, 0, 0))
    drawn = {"l": (feet["l"][0] - 0.04, feet["l"][1] + 0.12, feet["l"][2]), "r": (feet["r"][0] + 0.04, feet["r"][1] - 0.12, feet["r"][2])}

    ck.idle_clip(rig, 2.4, lambda t, s: (b(spine=(2 * s, 0, 0), chest=(-1 * s, 0, 2 * s), head=(2 * s, 0, 6 * math.sin(t / 2.4 * TAU)),
                                            upper_arm_r=(6 + 2 * s, 0, 4), bow=(2 * s, 0, 0), cape=(1.5 * s, 0, 0)),
                                          {"hips": (0, 0, -0.015 - 0.008 * s)}))

    def upper(t, s, c2):
        rots = b(hips=(0, 0, 9 * s), spine=(-12, 0, -5 * s), chest=(-4, 0, -6 * s), head=(12, 0, 3 * s),
                 upper_arm_r=(-35 * s + 8, 0, 8), forearm_r=(-40 - 15 * s, 0, 0),
                 upper_arm_l=(30 * s + 6, 0, -6), forearm_l=(-20 + 10 * s, 0, 0), bow=(-15, 0, 0),
                 skirt_f=(-14 - 8 * c2, 0, 0), skirt_b=(26 + 6 * c2, 0, 0), cape=(30 + 6 * c2, 0, 0))
        return rots, {}
    ck.run_clip(rig, spec["move_speed_mps"], upper, cycle=0.6, stance=0.2, hips_drop=0.09, lift=0.25, kick=0.2)

    def shot(name, rel, rec, hold=0.0, up=0.0):
        a = dict(aim)
        a["upper_arm_l"] = (88 + up, 0, -40)
        a["upper_arm_r"] = (85 + up, -25, -30)
        a["head"] = (-up * 0.6, 0, -40)
        loose = dict(a, upper_arm_r=(80 + up, -30, -50), forearm_r=(-10, 0, 60))
        keys = [(0, b(), (0, 0, -0.015)),
                (rel * 0.35 if hold else rel * 0.55, b(**dict(a, forearm_r=(-40, 0, 60), upper_arm_r=(85 + up, -15, 10))), (0, 0, -0.03))]
        if hold:
            keys.append((rel * 0.6, b(**a), (0, 0, -0.035)))
            keys.append((rel * 0.95, b(**dict(a, spine=(0, 0, 32), upper_arm_r=(86 + up, -26, -34))), (0, 0, -0.035)))
        else:
            keys.append((rel * 0.85, b(**a), (0, 0, -0.035)))
        keys += [(rel, b(**loose), (0, 0, -0.035)),
                 (rel + rec * 0.6, b(**dict(loose, upper_arm_l=(80 + up, 0, -40))), (0, 0, -0.03)),
                 (rel + rec, b(), (0, 0, -0.015))]
        ck.cast_clip(rig, name, rel, rec, keys, drawn)

    c = slots["attack"]
    shot("attack", c["release_s"], c["recovery_s"])
    c = slots["ability_1"]
    shot("ability_1", c["release_s"], c["recovery_s"], hold=1.0)

    # Bramble: an underhand toss of a seed with the right hand.
    c = slots["ability_2"]
    rel, rec = c["release_s"], c["recovery_s"]
    ck.cast_clip(rig, "ability_2", rel, rec, [
        (0, b(), (0, 0, -0.015)),
        (rel * 0.6, b(spine=(10, 0, -10), chest=(4, 0, -14), upper_arm_r=(-40, 0, 10), forearm_r=(-20, 0, 0)), (0, -0.04, -0.06)),
        (rel, b(spine=(-6, 0, 10), chest=(-4, 0, 12), upper_arm_r=(95, 0, -4), forearm_r=(-10, 0, 0), hand_r=(-20, 0, 0)), (0, 0.06, -0.04)),
        (rel + rec * 0.5, b(spine=(-4, 0, 8), upper_arm_r=(85, 0, -4), forearm_r=(-12, 0, 0)), (0, 0.05, -0.04)),
        (rel + rec, b(), (0, 0, -0.015))], feet)

    # Thornstorm: a shot loosed high into the sky.
    c = slots["ability_3"]
    shot("ability_3", c["release_s"], c["recovery_s"], up=45.0)

    ck.death_clip(rig, NAMES, lambda t: {"bow": (-40 * min(1.0, t / 0.6), 0, 0)})


def main():
    import sys
    out = ck.out_path(sys.argv, "/tmp/thornwright.blend")
    spec = ck.load_spec("thornwright")
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
