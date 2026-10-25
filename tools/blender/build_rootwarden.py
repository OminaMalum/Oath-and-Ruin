# SPDX-License-Identifier: GPL-2.0-or-later
# (Uses Blender's Python API. This is a build tool, not part of the game.)
"""Build the Rootwarden (Edda Mosswake) champion model, rig and clips.

  /opt/bpyenv/bin/python tools/blender/build_rootwarden.py OUT.blend

A firbolg druid, 2 m and broad: the CC0 Blender Studio female body
(tools/blender/body_fit.py) fitted wide for her head, torso and legs, in
grey blue firbolg skin with a broad nose and long drooping ears. A crown of
bare branches, a long braid, a robe split at the front over wrapped legs, a
moss mantle over the shoulders, a bark pauldron, a rope belt with seed
pouches. The thornstaff is gnarled, its hooked head holding a glowing seed.
Everything other than the body is original geometry written as code.
"""
import math

import bpy  # noqa: F401,I001  (bpy first: it makes mathutils importable)
from mathutils import Vector

import body_fit as bf
import champion_kit as ck
from champion_kit import TAU, Kit, base

S = 1.11
W = 1.14
NAMES = ck.BODY + ["braid"]
GIRTH = {"hips": (1.22, 1.15), "spine": (1.16, 1.0), "chest": (1.08, 0.86), "neck": (1.15, 1.1), "head": (1.08, 1.06),
         "thigh_l": (1.22, 1.2), "thigh_r": (1.22, 1.2), "shin_l": (1.15, 1.15), "shin_r": (1.15, 1.15)}
EYES = [(-0.0475, 0.0485, 1.4668), (0.0475, 0.0485, 1.4668)]


def bones():
    b = ck.humanoid_bones(S, W)
    b["braid"] = ((0, -0.1 * S, 1.66 * S), (0, -0.16 * S, 1.3 * S), "head")
    return b


def build_model(rig, M):
    bn = rig.data.bones
    fitted = bf.fit(rig, GIRTH, body="female", points=EYES)
    torso = ("hips", "spine", "chest", "neck")
    hz = bn["head"].head_local.z
    hy = bn["head"].head_local.y
    nz = bn["neck"].head_local.z
    cz = bn["chest"].head_local.z
    hipz = bn["hips"].head_local.z
    top = max(p.z for i, p in enumerate(fitted[0]) if fitted[3][i] == "head")
    front = lambda x, zz, owners=torso: bf.surface_y(fitted, x, zz, owners, True)  # noqa: E731
    behind = lambda x, zz, owners=torso: bf.surface_y(fitted, x, zz, owners, False)  # noqa: E731
    eye = fitted[4]

    # Head: firbolg skin, a broad nose, long ears drooping out and down, a
    # cap of dark hair into a long braid, and a crown of bare branches.
    k = Kit("Head", M)
    bf.add_faces(k, fitted, bf.region(fitted, lambda i, o, p: o in ("head", "neck") and p.z > nz + 0.01), "Firbolg", uv_scale=2.0)
    for c in eye:
        k.sphere(c, 0.019, "Paper", u=10, v=6)
        k.sphere(c + Vector((0, 0.015, 0)), 0.009, "Hair", scale=(1.2, 0.5, 1.2), u=8, v=6)
    ny = front(0.0, eye[0].z - 0.035, ("head",)) or hy + 0.1
    k.sphere(Vector((0, ny + 0.006, eye[0].z - 0.035)), 0.026, "Firbolg", scale=(1.15, 0.9, 0.8), u=12, v=8)
    for sx in (-1.0, 1.0):
        root = Vector((sx * 0.075 * GIRTH["head"][0], hy - 0.01, eye[0].z - 0.01))
        k.tube([root, root + Vector((sx * 0.05, -0.01, 0.0)), root + Vector((sx * 0.1, -0.02, -0.03)), root + Vector((sx * 0.13, -0.025, -0.07))],
               [0.02, 0.024, 0.016, 0.003], "Firbolg", seg=8, flat=0.35)
    scalp = bf.region(fitted, lambda i, o, p: o == "head" and (p.z > eye[0].z + 0.05 or (p.y < hy - 0.02 and p.z > eye[0].z - 0.04)))
    bf.add_faces(k, fitted, scalp, "Hair", offset=0.01, uv_scale=2.0)
    for j in range(7):
        a = (j - 3) / 3 * 1.1
        base_p = Vector((math.sin(a) * 0.085, hy + math.cos(a) * 0.08, top - 0.04 + 0.01 * math.cos(a)))
        out = Vector((math.sin(a) * 0.3, math.cos(a) * 0.2, 1.0)).normalized()
        h = 0.11 if j % 3 == 0 else 0.07
        tip = base_p + out * h
        k.tube([base_p, base_p.lerp(tip, 0.5) + Vector((math.sin(a) * 0.01, 0, 0)), tip], [0.01, 0.008, 0.002], "Wood", seg=6)
        if j % 3 == 0:
            fork = base_p.lerp(tip, 0.55)
            k.tube([fork, fork + Vector((math.sin(a + 0.8) * 0.04, 0.0, 0.03))], [0.006, 0.0015], "Wood", seg=5)
    k.lathe([(0.088, top - 0.06), (0.092, top - 0.045), (0.088, top - 0.03)], "Wood", seg=20, sx=1.05, sy=1.15, center=(0, hy - 0.01))
    k.finish(rig, ["head", "neck"], subsurf=1)
    k = Kit("Braid", M)
    b0, b1 = bn["braid"].head_local, bn["braid_1"].tail_local
    for j in range(7):
        c = b0.lerp(b1, j / 6)
        k.sphere(c, 0.032 - j * 0.002, "Hair", scale=(1.0, 0.9, 1.25), u=10, v=6)
    k.lathe([(0.02, b1.z - 0.01), (0.024, b1.z), (0.02, b1.z + 0.01)], "Moss", seg=10, center=(b1.x, b1.y))
    k.finish(rig, ["braid", "head"])

    # Robe: fitted over the torso, then a long skirt split at the front.
    k = Kit("Robe", M)
    bf.add_faces(k, fitted, bf.region(fitted, lambda i, o, p: o in torso and hipz - 0.06 < p.z < nz + 0.02), "Robe", offset=0.026, uv_scale=3.0)
    k.lathe([(0.085 * 1.15, nz - 0.01), (0.09 * 1.15, nz + 0.04)], "RobeDark", seg=20, sx=1.1, sy=1.0)
    k.finish(rig, ["chest", "spine", "hips", "neck"], solidify=0.008)
    k = Kit("Skirt", M)
    rows = []
    ankle = bn["foot_l"].head_local.z
    for i in range(8):
        f = i / 7
        zz = hipz - 0.02 - (hipz - 0.02 - (ankle + 0.12)) * f
        rr = 0.2 + 0.11 * f
        rows.append([Vector((math.sin(t) * rr * 1.12, math.cos(t) * rr * 0.95, zz - 0.03 * abs(math.sin(t * 3)) * f))
                     for t in [0.42 + j / 26 * (TAU - 0.84) for j in range(27)]])
    k.ring_grid(rows, "Robe", closed=False, v_scale=2.0)
    k.finish(rig, ["hips", "thigh_l", "thigh_r", "skirt_f", "skirt_b"], solidify=0.008)

    # Mantle: moss over the shoulders and upper back, a rolled edge.
    k = Kit("Mantle", M)
    mant = bf.region(fitted, lambda i, o, p: o in ("chest", "neck") and p.z > cz - 0.07 + 0.1 * (p.y < 0) and p.z < nz + 0.03)
    for loop in bf.add_faces(k, fitted, mant, "Moss", offset=0.05, uv_scale=3.0):
        bf.rim(k, loop, 0.014, "Moss")
    k.finish(rig, ["chest", "neck", "shoulder_l", "shoulder_r"], solidify=0.01)
    k = Kit("Pauldron", M)
    sh = bn["upper_arm_l"].head_local
    for j in range(3):
        k.sphere(sh + Vector((-0.03 - j * 0.012, 0.0, 0.06 - j * 0.045)), 0.1 - j * 0.012, "Wood", scale=(0.95, 1.1, 0.42), u=12, v=6)
    k.finish(rig, "shoulder_l")

    # Rope belt with two seed pouches and a sprig.
    k = Kit("Belt", M)
    k.lathe([(0.2, hipz - 0.03), (0.205, hipz - 0.015), (0.2, hipz)], "Cloth", seg=28, sx=1.14, sy=0.98)
    for a in (1.2, 2.2):
        p = Vector((math.sin(a) * 0.235, math.cos(a) * 0.2, hipz - 0.07))
        k.sphere(p, 0.04, "Leather", scale=(0.9, 0.7, 1.1), u=10, v=6)
        k.tube([p + Vector((0, 0, 0.04)), p + Vector((0, 0, 0.06))], [0.012, 0.016], "Cloth", seg=6)
    k.finish(rig, ["hips"])

    # Arms: wide robe sleeves to the forearm, firbolg hands.
    for side in ("r", "l"):
        ck.sleeve(rig, M, side, "Robe", radii=(0.075, 0.072, 0.07, 0.08, 0.09))
        ck.hand(rig, M, side, "Firbolg", fist=side == "r")

    # The thornstaff: gnarled, through the right fist, its hooked head
    # holding a glowing seed.
    wr = bn["hand_r"].head_local
    grip = wr + (bn["hand_r"].tail_local - wr).normalized() * 0.05
    k = Kit("Staff", M)
    pts = []
    for j in range(9):
        f = j / 8
        zz = -0.95 + 1.85 * f
        pts.append(grip + Vector((0.012 * math.sin(f * 11), 0.012 * math.cos(f * 7), zz)))
    k.tube(pts, [0.02, 0.022, 0.02, 0.021, 0.02, 0.022, 0.024, 0.022, 0.02], "Wood", seg=8)
    h = pts[-1]
    hook = [h, h + Vector((0.03, 0.0, 0.08)), h + Vector((0.1, 0.0, 0.1)), h + Vector((0.13, 0.0, 0.04)), h + Vector((0.1, 0.0, -0.01))]
    k.tube(hook, [0.02, 0.018, 0.015, 0.011, 0.006], "Wood", seg=7)
    for j in range(5):
        a = pts[2 + j]
        k.octa(a + Vector((0.018 * (1 if j % 2 else -1), 0.0, 0)), 0.01, 0.006, 0.006, "Wood")
    seed = h + Vector((0.065, 0.0, 0.04))
    k.sphere(seed, 0.035, "Glow", scale=(1, 1, 1.25), u=10, v=8)
    k.finish(rig, "hand_r")

    # Legs: wrapped in cloth under the robe, bare broad feet in wraps.
    bf.legs(rig, M, fitted, "Cloth", "Leather", 1.1, cuff="Cloth", offset=0.012)
    return grip + Vector((0, 0.08, 0.05))


# ---------------------------------------------------------------- clips

def animate(rig, spec):
    slots = spec["slot_clips"]
    feet = ck.rest_feet(rig)
    rest = dict(upper_arm_r=(18, 0, 14), forearm_r=(-30, 0, 0), upper_arm_l=(10, 0, -12), forearm_l=(-25, 0, 0), spine=(3, 0, 0),
                braid=(0, 0, 0))

    def b(**over):
        d = dict(rest)
        d.update(over)
        return base(NAMES, **d)

    stance = {"l": (feet["l"][0] - 0.04, feet["l"][1] + 0.12, feet["l"][2]), "r": (feet["r"][0] + 0.04, feet["r"][1] - 0.1, feet["r"][2])}

    ck.idle_clip(rig, 3.2, lambda t, s: (b(spine=(4 + 1.4 * s, 0, 0), chest=(-1.2 * s, 0, 0), head=(-4, 0, 5 * math.sin(t / 3.2 * TAU)),
                                            upper_arm_l=(12 + 2 * s, 0, -12), braid=(4 * s, 0, 3 * math.sin(t / 3.2 * TAU))),
                                          {"hips": (0, 0, -0.03 - 0.008 * s)}), step=4)

    def upper(t, s, c2):
        rots = b(hips=(0, 0, 7 * s), spine=(-10, 0, -5 * s), chest=(-3, 0, -5 * s), head=(8, 0, 3 * s),
                 upper_arm_r=(-15 * s + 15, 0, 14), forearm_r=(-40, 0, 0), upper_arm_l=(30 * s + 8, 0, -12), forearm_l=(-40, 0, 0),
                 skirt_f=(-18 - 6 * c2, 0, 0), skirt_b=(24 + 6 * c2, 0, 0), braid=(30 + 6 * c2, 0, 6 * s))
        return rots, {}
    ck.run_clip(rig, spec["move_speed_mps"], upper, cycle=0.64, stance=0.2, hips_drop=0.1, lift=0.24, kick=0.2)

    def move(name, wind, hit, hip, feet_=stance):
        c = slots[name]
        rel, rec = c["release_s"], c["recovery_s"]
        ck.cast_clip(rig, name, rel, rec, [
            (0, b(), (0, 0, -0.03)),
            (rel * 0.6, b(**wind), (0, -0.04, -0.05)),
            (rel, b(**hit), hip),
            (rel + max(rec, 0.1) * 0.5, b(**hit), hip),
            (rel + max(rec, 0.1), b(), (0, 0, -0.03))], feet_)

    # Thornstaff: the staff swept across from the right.
    move("attack", dict(spine=(0, 0, -24), chest=(0, 0, -14), upper_arm_r=(60, 0, 50), forearm_r=(-40, 0, 0)),
         dict(spine=(8, 0, 22), chest=(2, 0, 14), upper_arm_r=(70, 0, -30), forearm_r=(-20, 0, 0)), (0, 0.06, -0.06))
    # Grasping Root: the staff raised, then struck into the ground.
    move("ability_1", dict(spine=(-8, 0, 0), upper_arm_r=(140, 0, 10), forearm_r=(-40, 0, 0), upper_arm_l=(100, 0, -10), forearm_l=(-60, 0, 0)),
         dict(spine=(24, 0, 0), chest=(6, 0, 0), head=(-12, 0, 0), upper_arm_r=(60, 0, 10), forearm_r=(-60, 0, 0), upper_arm_l=(40, 0, -10),
              forearm_l=(-60, 0, 0)), (0, 0.06, -0.14))
    # First Grove: the staff planted, the free hand raised to the canopy.
    move("ability_2", dict(upper_arm_l=(60, 0, -20), forearm_l=(-40, 0, 0)),
         dict(spine=(-6, 0, 0), head=(-14, 0, 0), upper_arm_l=(150, 0, -20), forearm_l=(-10, 0, 0), upper_arm_r=(30, 0, 10), forearm_r=(-60, 0, 0)),
         (0, 0, -0.04), feet)
    # Elder Shape: hunched, then rearing up with both arms wide.
    move("ability_3", dict(spine=(26, 0, 0), chest=(10, 0, 0), upper_arm_r=(10, 0, 30), upper_arm_l=(10, 0, -30)),
         dict(spine=(-14, 0, 0), chest=(-10, 0, 0), head=(-20, 0, 0), upper_arm_r=(120, 0, 60), forearm_r=(-20, 0, 0),
              upper_arm_l=(120, 0, -60), forearm_l=(-20, 0, 0), braid=(-20, 0, 0)), (0, -0.02, 0.0), feet)
    # Barkskin: arms crossed before the chest, braced.
    move("ability_4", dict(spine=(6, 0, 0)), dict(spine=(10, 0, 0), head=(6, 0, 0), upper_arm_r=(50, 0, -20), forearm_r=(-100, 0, -30),
                                                  upper_arm_l=(50, 0, 20), forearm_l=(-100, 0, 30)), (0, 0, -0.08), feet)

    ck.death_clip(rig, NAMES, lambda t: {"braid": (30 * min(1.0, t / 0.8), 0, 0)})


def main():
    import sys
    out = ck.out_path(sys.argv, "/tmp/rootwarden.blend")
    spec = ck.load_spec("rootwarden")
    # Barkskin releases at 0.05 s: 30 fps cannot place that.
    ck.FPS = 60
    ck.reset()
    rig = ck.make_rig(bones())
    M = ck.Mats()
    tip = build_model(rig, M)
    ck.socket("Muzzle", rig, "hand_r", tip)
    ox, oy, oz = spec["sockets"]["Overhead"]
    ck.socket("Overhead", rig, "root", (ox, -oz, oy))
    animate(rig, spec)
    ck.save(out)


if __name__ == "__main__":
    main()
