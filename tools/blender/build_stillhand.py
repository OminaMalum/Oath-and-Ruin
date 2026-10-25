# SPDX-License-Identifier: GPL-2.0-or-later
# (Uses Blender's Python API. This is a build tool, not part of the game.)
"""Build the Stillhand (Keeper of the Quiet Bell) champion model, rig and clips.

  /opt/bpyenv/bin/python tools/blender/build_stillhand.py OUT.blend

A human monk: the CC0 Blender Studio male body (tools/blender/body_fit.py) for
his head, torso and legs. Shaved head with a small topknot, a wrapped gi
crossed over the chest and tied with a long sash, short wide sleeves over
bare forearms bound in cloth, wooden prayer beads, wrapped shins and plain
sandals. The quiet bell rides on his back in a rope cradle. Everything other
than the body is original geometry written as code.
"""
import math

import bpy  # noqa: F401,I001  (bpy first: it makes mathutils importable)
from mathutils import Vector

import body_fit as bf
import champion_kit as ck
from champion_kit import TAU, Kit, base

S = 0.955
W = 1.0

NAMES = ck.BODY + ["sash"]
GIRTH = {"hips": (1.0, 1.0), "spine": (0.98, 1.0), "chest": (1.0, 1.0), "neck": (1.0, 1.0), "head": (1.0, 1.0),
         "thigh_l": (1.14, 1.12), "thigh_r": (1.14, 1.12), "shin_l": (1.0, 1.0), "shin_r": (1.0, 1.0)}
# The male body file's eye centres (the base mesh's eye objects, turned like the body).
EYES = [(-0.0416, 0.0561, 1.6338), (0.0416, 0.0561, 1.6338)]


def bones():
    b = ck.humanoid_bones(S, W)
    # The sash tails hang from the knot on his left hip.
    b["sash"] = ((-0.1 * S, 0.13 * S, 0.98 * S), (-0.12 * S, 0.15 * S, 0.66 * S), "hips")
    return b


def build_model(rig, M):
    bn = rig.data.bones
    z = lambda v: v * S  # noqa: E731
    fitted = bf.fit(rig, GIRTH, body="male", points=EYES)
    torso = ("hips", "spine", "chest", "neck")
    hz = bn["head"].head_local.z
    hy = bn["head"].head_local.y
    nz = bn["neck"].head_local.z

    # Head: his own head, shaved, with a small topknot, eyes in the sockets
    # and a short dark beard line on the jaw.
    k = Kit("Head", M)
    bf.add_faces(k, fitted, bf.region(fitted, lambda i, o, p: o in ("head", "neck") and p.z > nz + 0.01), "Skin", uv_scale=2.0)
    for c in fitted[4]:
        k.sphere(c, 0.018, "Paper", u=10, v=6)
        k.sphere(c + Vector((0, 0.014, 0)), 0.008, "Hair", scale=(1.2, 0.5, 1.2), u=8, v=6)
    top = max(p.z for i, p in enumerate(fitted[0]) if fitted[3][i] == "head")
    back = bf.surface_y(fitted, 0.0, top - 0.06, ("head",), False) or hy - 0.08
    k.sphere(Vector((0, back + 0.035, top - 0.01)), 0.032, "Hair", scale=(1.0, 1.0, 0.8), u=12, v=8)
    k.lathe([(0.012, top - 0.035), (0.016, top - 0.025), (0.016, top - 0.015)], "Team", seg=10, center=(0, back + 0.035))
    k.finish(rig, ["head", "neck"], subsurf=1)

    # Gi: wrapped cloth over the torso, the left lapel crossing over the
    # right, its hem flaring below the sash. A darker under layer at the neck.
    k = Kit("Gi", M)
    bf.add_faces(k, fitted, bf.region(fitted, lambda i, o, p: o in torso and z(0.88) < p.z < nz + 0.03), "Robe", offset=0.016, uv_scale=3.0)
    chest_y = lambda x, zz: (bf.surface_y(fitted, x, zz, torso, True) or 0.12) + 0.026  # noqa: E731
    lapel = []
    for i in range(9):
        f = i / 8
        x = 0.07 - 0.17 * f
        zz = nz - 0.01 - (nz - z(1.0)) * f
        lapel.append(Vector((x, chest_y(x, zz), zz)))
    k.tube(lapel, [0.016] * len(lapel), "RobeDark", seg=6, flat=0.4)
    neck_l = [Vector((-0.07 + 0.14 * i / 6, chest_y(-0.07 + 0.14 * i / 6, nz - 0.03 - 0.06 * math.sin(i / 6 * math.pi)) - 0.004,
                      nz - 0.03 - 0.06 * math.sin(i / 6 * math.pi))) for i in range(7)]
    k.tube(neck_l, [0.012] * len(neck_l), "RobeInner", seg=6, flat=0.4)
    k.finish(rig, ["chest", "spine", "hips", "neck"], solidify=0.008)
    k = Kit("Beads", M)
    for i in range(24):
        a = i / 24 * TAU
        # A loop of beads round the neck, lying on the gi and dipping to a
        # brass bead at the front.
        dip = 0.09 * max(0.0, math.cos(a)) ** 2
        x, zz = math.sin(a) * 0.105, nz - 0.01 - dip
        y = chest_y(x, zz) + 0.012 if math.cos(a) > 0.2 else hy + math.cos(a) * 0.1
        k.sphere(Vector((x, y, zz)), 0.016 if i else 0.026, "Wood" if i else "Brass", u=8, v=6)
    k.finish(rig, ["chest", "neck"])
    k = Kit("GiHem", M)
    rows = []
    for i in range(5):
        f = i / 4
        rz = z(0.93) - 0.2 * f
        rows.append([Vector((math.sin(t) * (0.17 + 0.05 * f) * 1.14, math.cos(t) * (0.16 + 0.05 * f) * 0.92, rz))
                     for t in [0.25 + j / 20 * (TAU - 0.5) for j in range(21)]])
    k.ring_grid(rows, "Robe", closed=False)
    k.finish(rig, ["hips", "thigh_l", "thigh_r", "skirt_f", "skirt_b"], solidify=0.008)

    # Sash: a wide band in the team colour, knotted on the left hip with two
    # long tails.
    k = Kit("Sash", M)
    k.lathe([(0.17, z(0.93)), (0.175, z(0.96)), (0.172, z(1.0))], "Team", seg=28, sx=1.14, sy=0.92)
    knot = Vector((-0.1, 0.152, z(0.965)))
    k.sphere(knot, 0.03, "Team", scale=(1.0, 0.7, 1.0), u=10, v=6)
    s0, s1 = bn["sash"].head_local, bn["sash"].tail_local
    for dx, ln in ((-0.015, 1.0), (0.02, 0.8)):
        k.tube([s0 + Vector((dx, 0.01, -0.02)), s0.lerp(s1, 0.5 * ln) + Vector((dx * 1.5, 0.012, 0)), s0.lerp(s1, ln) + Vector((dx * 2, 0.01, 0))],
               [0.022, 0.024, 0.026], "Team", seg=6, flat=0.25)
    k.finish(rig, ["hips", "sash"])

    # The quiet bell on his back, in a rope cradle over the shoulders.
    k = Kit("Bell", M)
    by = (bf.surface_y(fitted, 0.0, z(1.3), torso, False) or -0.13) - 0.12
    bz = z(1.27)
    k.lathe([(0.0, bz + 0.17), (0.03, bz + 0.165), (0.07, bz + 0.15), (0.095, bz + 0.1), (0.105, bz + 0.03), (0.125, bz - 0.06),
             (0.15, bz - 0.12), (0.155, bz - 0.135), (0.13, bz - 0.13), (0.11, bz - 0.06), (0.09, bz + 0.03), (0.0, bz + 0.1)],
            "Brass", seg=24, center=(0, by))
    k.lathe([(0.157, bz - 0.11), (0.16, bz - 0.095)], "Trim", seg=24, center=(0, by))
    k.box(Vector((0, by, bz + 0.19)), (0.05, 0.05, 0.04), "Wood")
    k.sphere(Vector((0, by, bz - 0.1)), 0.03, "Iron", u=8, v=6)
    for sx in (-1.0, 1.0):
        sh = bn["upper_arm_" + ("r" if sx > 0 else "l")].head_local
        k.tube([Vector((sx * 0.03, by + 0.02, bz + 0.18)), Vector((sx * 0.1, by + 0.07, bz + 0.21)),
                Vector((sx * abs(sh.x) * 0.75, sh.y - 0.06, sh.z + 0.045)), Vector((sx * abs(sh.x) * 0.7, sh.y + 0.08, sh.z + 0.02)),
                Vector((sx * 0.06, chest_y(sx * 0.06, z(1.2)) + 0.004, z(1.2))), Vector((-sx * 0.05, chest_y(-sx * 0.05, z(1.02)) + 0.004, z(1.02)))],
               [0.011] * 6, "Cloth", seg=6)
    k.finish(rig, ["chest", "spine"])

    # Arms: short wide sleeves, bare forearms bound in cloth to the knuckles.
    for side in ("r", "l"):
        sh = bn["upper_arm_" + side].head_local
        el = bn["forearm_" + side].head_local
        wr = bn["hand_" + side].head_local
        d = (wr - el).normalized()
        k = Kit("Sleeve_" + side, M)
        k.tube([sh + Vector((0, 0, 0.02)), sh.lerp(el, 0.5), el + (el - sh).normalized() * 0.03], [0.064, 0.068, 0.08], "Robe", seg=12, cap=False)
        k.finish(rig, ["upper_arm_" + side, "shoulder_" + side, "chest"], subsurf=1, solidify=0.006)
        k = Kit("Forearm_" + side, M)
        k.tube([el - d * 0.03, el.lerp(wr, 0.5), wr + d * 0.01], [0.048, 0.044, 0.036], "Skin", seg=12)
        for j in range(6):
            a = el.lerp(wr, 0.45 + j * 0.1)
            k.tube([a - d * 0.012, a + d * 0.012], [0.045 - j * 0.0015, 0.045 - j * 0.0015], "Cloth", seg=12, cap=False)
        k.finish(rig, "forearm_" + side, subsurf=1)
        ck.hand(rig, M, side, "Skin")

    # Legs: loose dark trousers, shins wrapped in cloth, plain sandals.
    bf.legs(rig, M, fitted, "ClothDark", "Leather", 0.85, cuff="Cloth", offset=0.028)


# ---------------------------------------------------------------- clips

def animate(rig, spec):
    slots = spec["slot_clips"]
    feet = ck.rest_feet(rig)
    rest = dict(upper_arm_r=(15, 0, 12), forearm_r=(-40, 0, 0), upper_arm_l=(15, 0, -12), forearm_l=(-40, 0, 0),
                spine=(2, 0, 0), sash=(0, 0, 0))

    def b(**over):
        d = dict(rest)
        d.update(over)
        return base(NAMES, **d)

    stance = {"l": (feet["l"][0] - 0.05, feet["l"][1] + 0.12, feet["l"][2]), "r": (feet["r"][0] + 0.05, feet["r"][1] - 0.1, feet["r"][2])}

    # Idle: a low, settled stance, the right palm up before the chest, the
    # left hand loose; breathing slow.
    ck.idle_clip(rig, 3.0, lambda t, s: (b(spine=(3 + 1.5 * s, 0, 6), chest=(-1.5 * s, 0, 4), head=(-2, 0, -8),
                                            upper_arm_r=(40 + 2 * s, 0, 18), forearm_r=(-75, 0, -10), upper_arm_l=(12, 0, -14),
                                            forearm_l=(-30, 0, 0), sash=(3 * s, 0, 4 * math.sin(t / 3.0 * TAU))),
                                          {"hips": (0, 0, -0.05 - 0.008 * s)}), step=4)

    def upper(t, s, c2):
        rots = b(hips=(0, 0, 8 * s), spine=(-14, 0, -6 * s), chest=(-4, 0, -6 * s), head=(12, 0, 3 * s),
                 upper_arm_r=(-40 * s + 10, 0, 12), forearm_r=(-80, 0, 0), upper_arm_l=(40 * s + 10, 0, -12), forearm_l=(-80, 0, 0),
                 skirt_f=(-16 - 6 * c2, 0, 0), skirt_b=(24 + 6 * c2, 0, 0), sash=(40 + 8 * c2, 0, 8 * s))
        return rots, {}
    ck.run_clip(rig, spec["move_speed_mps"], upper, cycle=0.54, stance=0.2, hips_drop=0.09, lift=0.24, kick=0.2)

    def strike(name, wind, hit, hip_hit, feet_=stance):
        c = slots[name]
        rel, rec = c["release_s"], c["recovery_s"]
        ck.cast_clip(rig, name, rel, rec, [
            (0, b(), (0, 0, -0.05)),
            (rel * 0.6, b(**wind), (0, -0.05, -0.08)),
            (rel, b(**hit), hip_hit),
            (rel + max(rec, 0.1) * 0.5, b(**hit), hip_hit),
            (rel + max(rec, 0.1), b(), (0, 0, -0.05))], feet_)

    # Open Palm: the right palm driven straight out from the hip.
    strike("attack", dict(spine=(0, 0, -16), chest=(0, 0, -10), upper_arm_r=(-15, 0, 30), forearm_r=(-90, 0, 0)),
           dict(spine=(10, 0, 14), chest=(4, 0, 10), upper_arm_r=(48, 0, 4), forearm_r=(0, 0, 0), upper_arm_l=(20, 0, -30),
                forearm_l=(-100, 0, 0)), (0, 0.08, -0.08))
    # Bellbreaker: both palms gathered at the hip, then pushed together.
    strike("ability_1", dict(spine=(-4, 0, -22), chest=(0, 0, -12), upper_arm_r=(-20, 0, 40), forearm_r=(-95, 0, 0), upper_arm_l=(-20, 0, -40),
                             forearm_l=(-95, 0, 0)),
           dict(spine=(16, 0, 8), chest=(8, 0, 6), upper_arm_r=(46, 0, 14), forearm_r=(0, 0, 0), upper_arm_l=(46, 0, -14),
                forearm_l=(0, 0, 0)), (0, 0.14, -0.14))
    # Reed Step: a low lean into the step, arms trailing.
    strike("ability_2", dict(spine=(10, 0, 0), upper_arm_r=(-20, 0, 20), upper_arm_l=(-20, 0, -20)),
           dict(spine=(28, 0, 0), chest=(8, 0, 0), head=(-18, 0, 0), upper_arm_r=(-50, 0, 30), forearm_r=(-20, 0, 0), upper_arm_l=(-50, 0, -30),
                forearm_l=(-20, 0, 0), sash=(50, 0, 0), skirt_b=(30, 0, 0)), (0, 0.06, -0.16))
    # Empty the Courtyard: arms sweep wide and down as he stamps.
    strike("ability_3", dict(spine=(-10, 0, 0), chest=(-8, 0, 0), head=(-10, 0, 0), upper_arm_r=(150, 0, 30), forearm_r=(-30, 0, 0),
                             upper_arm_l=(150, 0, -30), forearm_l=(-30, 0, 0)),
           dict(spine=(18, 0, 0), chest=(6, 0, 0), upper_arm_r=(40, 0, 75), forearm_r=(-5, 0, 0), upper_arm_l=(40, 0, -75),
                forearm_l=(-5, 0, 0), sash=(-20, 0, 0)), (0, 0.04, -0.2),
           {"l": (feet["l"][0] - 0.12, feet["l"][1] + 0.04, feet["l"][2]), "r": (feet["r"][0] + 0.12, feet["r"][1] - 0.04, feet["r"][2])})
    # Still Water: palms pressed together before the face.
    strike("ability_4", dict(upper_arm_r=(50, 0, 30), forearm_r=(-100, 0, 0), upper_arm_l=(50, 0, -30), forearm_l=(-100, 0, 0)),
           dict(spine=(-2, 0, 0), head=(6, 0, 0), upper_arm_r=(55, 0, -4), forearm_r=(-115, 0, -30), upper_arm_l=(55, 0, 4),
                forearm_l=(-115, 0, 30)), (0, 0, -0.06), feet)

    ck.death_clip(rig, NAMES, lambda t: {"sash": (30 * min(1.0, t / 0.8), 0, 0)})


def main():
    import sys
    out = ck.out_path(sys.argv, "/tmp/stillhand.blend")
    spec = ck.load_spec("stillhand")
    # Reed Step and Still Water release at 0.05 s: 30 fps cannot place that.
    ck.FPS = 60
    ck.reset()
    rig = ck.make_rig(bones())
    M = ck.Mats()
    build_model(rig, M)
    hr = rig.data.bones["hand_r"]
    ck.socket("Muzzle", rig, "hand_r", hr.head_local + (hr.tail_local - hr.head_local).normalized() * 0.1)
    ox, oy, oz = spec["sockets"]["Overhead"]
    ck.socket("Overhead", rig, "root", (ox, -oz, oy))
    animate(rig, spec)
    ck.save(out)


if __name__ == "__main__":
    main()
