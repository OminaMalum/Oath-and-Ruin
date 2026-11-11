# SPDX-License-Identifier: GPL-2.0-or-later
# (Uses Blender's Python API. This is a build tool, not part of the game.)
"""Build the Banneret (Dain Arclow) champion model, rig and clips, from code.

  /opt/bpyenv/bin/python tools/blender/build_banneret.py OUT.blend

A human spear fighter, a deserted officer: the CC0 Blender Studio male body
(tools/blender/body_fit.py) for his head, torso and legs. An open kettle hat
over a weathered face and short beard, a mail shirt under a riveted
brigandine, a team tabard with its badge cut away, a steel gorget, plain
vambraces, a round buckler on the left arm, mail chausses and boots. The
spear is long, with a leaf blade and a short team pennon below it.
Everything other than the body is original geometry written as code.
"""
import math

import bpy  # noqa: F401,I001  (bpy first: it makes mathutils importable)
from mathutils import Vector

import body_fit as bf
import champion_kit as ck
from champion_kit import TAU, Kit, base

S = 1.055
W = 1.06
NAMES = ck.BODY
GIRTH = {"hips": (1.05, 1.0), "spine": (1.05, 1.02), "chest": (1.08, 1.04), "neck": (1.06, 1.04), "head": (1.0, 1.0),
         "thigh_l": (1.06, 1.06), "thigh_r": (1.06, 1.06), "shin_l": (1.02, 1.02), "shin_r": (1.02, 1.02)}
EYES = [(-0.0416, 0.0561, 1.6338), (0.0416, 0.0561, 1.6338)]


def build_model(rig, M):
    bn = rig.data.bones
    fitted = bf.fit(rig, GIRTH, body="male", points=EYES)
    torso = ("hips", "spine", "chest", "neck")
    hz = bn["head"].head_local.z
    hy = bn["head"].head_local.y
    nz = bn["neck"].head_local.z
    cz = bn["chest"].head_local.z
    hipz = bn["hips"].head_local.z
    top = max(p.z for i, p in enumerate(fitted[0]) if fitted[3][i] == "head")
    front = lambda x, zz, owners=torso: bf.surface_y(fitted, x, zz, owners, True)  # noqa: E731

    # Head: his own face, a short dark beard on the jaw, an open kettle hat.
    k = Kit("Head", M)
    bf.add_faces(k, fitted, bf.region(fitted, lambda i, o, p: o in ("head", "neck") and p.z > nz + 0.01), "Skin", uv_scale=2.0)
    for c in fitted[4]:
        k.sphere(c, 0.019, "Paper", u=10, v=6)
        k.sphere(c + Vector((0, 0.015, 0)), 0.008, "Hair", scale=(1.2, 0.5, 1.2), u=8, v=6)
    eye_z = fitted[4][0].z
    beard = bf.region(fitted, lambda i, o, p: o == "head" and p.z < eye_z - 0.06 and p.y > hy - 0.03 and p.z > hz - 0.0)
    bf.add_faces(k, fitted, beard, "Hair", offset=0.008, uv_scale=2.0)
    scalp = bf.region(fitted, lambda i, o, p: o == "head" and p.y < hy - 0.04 and hz + 0.03 < p.z < top - 0.06)
    bf.add_faces(k, fitted, scalp, "Hair", offset=0.006, uv_scale=2.0)
    k.finish(rig, ["head", "neck"], subsurf=1)
    k = Kit("Helm", M)
    rim_z = top - 0.085
    k.lathe([(0.0, top + 0.03), (0.06, top + 0.02), (0.1, top - 0.02), (0.118, rim_z + 0.01), (0.12, rim_z)],
            "Steel", seg=28, sx=1.0, sy=1.12, center=(0, hy - 0.01))
    k.lathe([(0.12, rim_z + 0.005), (0.2, rim_z - 0.035), (0.205, rim_z - 0.045), (0.12, rim_z - 0.005)],
            "Steel", seg=32, sx=1.0, sy=1.08, center=(0, hy - 0.01))
    k.lathe([(0.205, rim_z - 0.048), (0.21, rim_z - 0.04)], "Trim", seg=32, sx=1.0, sy=1.08, center=(0, hy - 0.01))
    k.tube([Vector((0, hy - 0.01 + 0.12 * 1.12, rim_z)), Vector((0, hy - 0.01 + 0.05, top + 0.035)), Vector((0, hy - 0.01 - 0.12 * 1.12, rim_z))],
           [0.008, 0.012, 0.008], "Iron", seg=6)
    k.finish(rig, "head")

    # Mail shirt to mid thigh, the brigandine over it with rows of rivets,
    # a gorget at the throat.
    k = Kit("Mail", M)
    bf.add_faces(k, fitted, bf.region(fitted, lambda i, o, p: o in torso and hipz - 0.1 < p.z < nz + 0.01), "Mail", offset=0.012, uv_scale=4.0)
    rows = []
    for i in range(4):
        f = i / 3
        rows.append([Vector((math.sin(t) * (0.17 + 0.03 * f) * 1.12, math.cos(t) * (0.15 + 0.03 * f) * 0.95, hipz - 0.08 - 0.18 * f))
                     for t in [j / 24 * TAU for j in range(25)]])
    k.ring_grid(rows, "Mail", closed=False, u_scale=4.0, v_scale=2.0)
    k.finish(rig, ["chest", "spine", "hips", "neck", "thigh_l", "thigh_r", "skirt_f", "skirt_b"], solidify=0.006)
    k = Kit("Brigandine", M)
    brig = bf.region(fitted, lambda i, o, p: o in ("chest", "spine", "hips") and hipz - 0.02 < p.z < cz + 0.17)
    for loop in bf.add_faces(k, fitted, brig, "Leather", offset=0.03, uv_scale=3.0):
        bf.rim(k, loop, 0.008, "Leather")
    for zz in [hipz + 0.04 + j * 0.07 for j in range(6)]:
        for x in [-0.12 + 0.04 * j for j in range(7)]:
            y = front(x, zz)
            if y is not None:
                k.sphere(Vector((x, y + 0.03, zz)), 0.007, "Brass", u=6, v=4)
    k.finish(rig, ["chest", "spine", "hips"], solidify=0.008)
    k = Kit("Gorget", M)
    k.lathe([(0.1, nz - 0.04), (0.095, nz), (0.083, nz + 0.05)], "Steel", seg=24, sx=1.15, sy=1.05, center=(0, 0.005))
    k.lathe([(0.1, nz - 0.045), (0.104, nz - 0.035)], "Trim", seg=24, sx=1.15, sy=1.05, center=(0, 0.005))
    k.finish(rig, ["neck", "chest"])

    # Tabard: front and back panels in the team colour, the badge on the
    # chest cut away (a paler patch with loose stitching).
    k = Kit("Tabard", M)
    for sy in (1.0, -1.0):
        rows = []
        for i in range(8):
            f = i / 7
            zz = cz + 0.12 - (cz + 0.12 - (hipz - 0.32)) * f
            half = 0.11 + 0.03 * f
            row = []
            for j in range(5):
                x = -half + half * 2 * j / 4
                y = bf.surface_y(fitted, x, zz, torso, sy > 0) if zz > hipz - 0.05 else None
                if y is None:
                    y = sy * (0.125 + 0.02 * f)
                row.append(Vector((x, y + sy * 0.04, zz)))
            rows.append(row if sy > 0 else row[::-1])
        k.ring_grid(rows, "Team", closed=False)
    py = front(0.0, cz + 0.02) or 0.12
    k.box(Vector((0, py + 0.046, cz + 0.02)), (0.09, 0.006, 0.1), "Cloth")
    k.finish(rig, ["chest", "spine", "hips", "skirt_f", "skirt_b"], solidify=0.006)
    k = Kit("Belt", M)
    k.lathe([(0.17, hipz - 0.03), (0.172, hipz + 0.01)], "Leather", seg=28, sx=1.12, sy=0.98)
    k.box(Vector((0, 0.172 * 0.98 + 0.006, hipz - 0.01)), (0.05, 0.012, 0.045), "Iron")
    k.finish(rig, ["hips"])

    # Arms: mail sleeves, steel spaulders and vambraces, leather gloves.
    for side in ("r", "l"):
        sx = 1.0 if side == "r" else -1.0
        ck.sleeve(rig, M, side, "Mail", radii=(0.07, 0.064, 0.058, 0.054, 0.052))
        sh = bn["upper_arm_" + side].head_local
        el = bn["forearm_" + side].head_local
        wr = bn["hand_" + side].head_local
        d = (wr - el).normalized()
        k = Kit("Spaulder_" + side, M)
        k.sphere(sh + Vector((sx * 0.025, 0, 0.03)), 0.1, "Steel", scale=(1.0, 1.1, 0.62), u=16, v=8)
        k.sphere(sh + Vector((sx * 0.045, 0, -0.03)), 0.088, "Steel", scale=(0.9, 1.0, 0.5), u=16, v=8)
        k.finish(rig, "shoulder_" + side)
        k = Kit("Vambrace_" + side, M)
        k.tube([el + d * 0.04, el.lerp(wr, 0.6), wr + d * 0.005], [0.058, 0.06, 0.054], "Steel", seg=12)
        k.finish(rig, "forearm_" + side, subsurf=1)
        ck.hand(rig, M, side, "Leather", fist=True)
    # Buckler on the left forearm.
    el = bn["forearm_l"].head_local
    wr = bn["hand_l"].head_local
    d = (wr - el).normalized()
    out = d.cross(Vector((0, 0, 1))).normalized()
    if out.x > 0:
        out = -out
    c = el.lerp(wr, 0.5) + out * 0.08
    k = Kit("Buckler", M)
    rot = out.to_track_quat("Z", "Y")
    prof = [(0.0, 0.035), (0.05, 0.03), (0.17, 0.01), (0.19, 0.0), (0.19, -0.012), (0.0, -0.012)]
    bm_start = len(k.bm.verts)
    k.lathe(prof, "Wood", seg=28)
    k.lathe([(0.188, 0.004), (0.196, 0.0), (0.196, -0.012), (0.188, -0.012)], "Iron", seg=28)
    k.lathe([(0.0, 0.05), (0.04, 0.04), (0.05, 0.02), (0.0, 0.02)], "Steel", seg=16)
    for v in k.bm.verts[bm_start:]:
        v.co = c + rot @ v.co
    k.finish(rig, "forearm_l")

    # The spear: an ash shaft through the right fist along the forearm, a
    # leaf blade, a team pennon below it and an iron butt cap.
    el = bn["forearm_r"].head_local
    wr = bn["hand_r"].head_local
    d = (wr - el).normalized()
    grip = wr + (bn["hand_r"].tail_local - wr).normalized() * 0.05
    k = Kit("Spear", M)
    a, b = grip - d * 0.75, grip + d * 0.85
    k.tube([a, grip, b], [0.018, 0.018, 0.016], "Wood", seg=8)
    k.tube([a - d * 0.06, a + d * 0.02], [0.022, 0.02], "Iron", seg=8)
    k.tube([b - d * 0.02, b + d * 0.06], [0.022, 0.018], "Iron", seg=8)
    side = d.cross(Vector((0, 0, 1))).normalized()
    blade = [b + d * (0.06 + 0.26 * f) for f in (0.0, 0.25, 0.55, 0.85, 1.0)]
    k.tube(blade, [0.012, 0.035, 0.032, 0.014, 0.001], "Steel", seg=8, flat=0.25, twist=0.0)
    up = side.cross(d).normalized()
    p0 = b - d * 0.08
    rows = [[p0 - d * 0.0 + up * 0.0 + side * 0.0, p0 - up * 0.2], [p0 - d * 0.3 - up * 0.005, p0 - d * 0.36 - up * 0.17]]
    k.ring_grid(rows, "Team", closed=False)
    k.finish(rig, "hand_r")

    # Legs: mail chausses, boots, wrapped cuffs.
    bf.legs(rig, M, fitted, "Mail", "Leather", 1.05, cuff="Leather", offset=0.012)
    return grip + d * 0.2


# ---------------------------------------------------------------- clips

def animate(rig, spec):
    slots = spec["slot_clips"]
    feet = ck.rest_feet(rig)
    # Guard: spear levelled low and forward, buckler up.
    rest = dict(upper_arm_r=(25, 0, 14), forearm_r=(-10, 0, 0), upper_arm_l=(30, 0, -20), forearm_l=(-70, 0, 40), spine=(4, 0, 10),
                chest=(0, 0, 4))

    def b(**over):
        d = dict(rest)
        d.update(over)
        return base(NAMES, **d)

    stance = {"l": (feet["l"][0] - 0.04, feet["l"][1] + 0.16, feet["l"][2]), "r": (feet["r"][0] + 0.05, feet["r"][1] - 0.14, feet["r"][2])}

    ck.idle_clip(rig, 2.6, lambda t, s: (b(spine=(4 + 1.2 * s, 0, 10), head=(-4, 0, -8 + 3 * math.sin(t / 2.6 * TAU)),
                                            upper_arm_r=(25 + 2 * s, 0, 14)),
                                          {"hips": (0, 0, -0.04 - 0.008 * s)}), step=4)

    def upper(t, s, c2):
        rots = b(hips=(0, 0, 8 * s), spine=(-10, 0, -4 * s), chest=(-4, 0, -5 * s), head=(8, 0, 3 * s),
                 upper_arm_r=(-20 * s + 15, 0, 14), forearm_r=(-30, 0, 0), upper_arm_l=(30 * s + 20, 0, -18), forearm_l=(-70, 0, 30),
                 skirt_f=(-16 - 6 * c2, 0, 0), skirt_b=(22 + 6 * c2, 0, 0))
        return rots, {}
    ck.run_clip(rig, spec["move_speed_mps"], upper, cycle=0.6, stance=0.2, hips_drop=0.09, lift=0.24, kick=0.2)

    def move(name, wind, hit, hip, feet_=stance):
        c = slots[name]
        rel, rec = c["release_s"], c["recovery_s"]
        ck.cast_clip(rig, name, rel, rec, [
            (0, b(), (0, 0, -0.04)),
            (rel * 0.6, b(**wind), (0, -0.06, -0.06)),
            (rel, b(**hit), hip),
            (rel + max(rec, 0.1) * 0.5, b(**hit), hip),
            (rel + max(rec, 0.1), b(), (0, 0, -0.04))], feet_)

    # Soldier's Reach: drawn back, then a straight thrust.
    # The spear runs along the forearm, so spine + upper arm + forearm pitch
    # near 19 degrees keeps it level.
    move("attack", dict(spine=(0, 0, -6), upper_arm_r=(5, 0, 20), forearm_r=(14, 0, 0)),
         dict(spine=(12, 0, 16), chest=(0, 0, 8), upper_arm_r=(50, 0, 6), forearm_r=(-43, 0, 0)), (0, 0.12, -0.08))
    # Driving Thrust: a deeper lunge.
    lunge = {"l": (feet["l"][0] - 0.04, feet["l"][1] + 0.36, feet["l"][2]), "r": (feet["r"][0] + 0.05, feet["r"][1] - 0.24, feet["r"][2])}
    move("ability_1", dict(spine=(-6, 0, -10), upper_arm_r=(10, 0, 24), forearm_r=(15, 0, 0)),
         dict(spine=(22, 0, 18), chest=(0, 0, 8), head=(-16, 0, 0), upper_arm_r=(56, 0, 4), forearm_r=(-59, 0, 0), upper_arm_l=(-20, 0, -30),
              forearm_l=(-30, 0, 0)), (0, 0.26, -0.16), lunge)
    # Rally Standard: the spear raised high and driven down.
    move("ability_2", dict(spine=(-10, 0, 0), upper_arm_r=(150, 0, 10), forearm_r=(-30, 0, 0)),
         dict(spine=(14, 0, 0), upper_arm_r=(80, 0, 10), forearm_r=(-80, 0, 0), head=(-6, 0, 0)), (0, 0.04, -0.12))
    # Break Their Line: shoulder down behind the buckler, charging.
    move("ability_3", dict(spine=(10, 0, -20), upper_arm_l=(60, 0, -10), forearm_l=(-90, 0, 50)),
         dict(spine=(26, 0, -24), chest=(6, 0, -10), head=(-14, 0, 14), upper_arm_l=(70, 0, 0), forearm_l=(-90, 0, 60),
              upper_arm_r=(10, 0, 20), forearm_r=(-40, 0, 0)), (0, 0.16, -0.14), lunge)
    # Ordered Retreat: a quick step back, guard high.
    move("ability_4", dict(spine=(-4, 0, 0)), dict(spine=(-10, 0, 6), head=(6, 0, 0), upper_arm_l=(50, 0, -20), forearm_l=(-80, 0, 50)),
         (0, -0.1, -0.04), feet)

    ck.death_clip(rig, NAMES)


def main():
    import sys
    out = ck.out_path(sys.argv, "/tmp/banneret.blend")
    spec = ck.load_spec("banneret")
    # Ordered Retreat releases at 0.05 s: 30 fps cannot place that.
    ck.FPS = 60
    ck.reset()
    rig = ck.make_rig(ck.humanoid_bones(S, W))
    M = ck.Mats()
    tip = build_model(rig, M)
    ck.socket("Muzzle", rig, "hand_r", tip)
    ox, oy, oz = spec["sockets"]["Overhead"]
    ck.socket("Overhead", rig, "root", (ox, -oz, oy))
    animate(rig, spec)
    ck.save(out)


if __name__ == "__main__":
    main()
