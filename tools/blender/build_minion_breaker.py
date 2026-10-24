# SPDX-License-Identifier: GPL-2.0-or-later
# (Uses Blender's Python API. This is a build tool, not part of the game.)
"""Build the Breaker, the siege minion: a hulking brute in leather and an
iron chest plate with team war paint, a horned helm, and a great stone maul
banded in brass with a glowing team rune. Original geometry.

  /opt/bpyenv/bin/python tools/blender/build_minion_breaker.py OUT.blend
"""
import math

import bpy  # noqa: F401,I001  (bpy first: it makes mathutils importable)
from mathutils import Vector

import champion_kit as ck
import minion_kit
from champion_kit import Kit

S = 0.86
W = 1.5

NAMES = ck.BODY + ["maul"]


def bones():
    b = ck.humanoid_bones(S, W)
    h, t = Vector(b["hand_r"][0]), Vector(b["hand_r"][1])
    palm = h + (t - h).normalized() * 0.06
    b["maul"] = (tuple(palm), tuple(palm + Vector((0, 0, 0.3))), "hand_r")
    return b


def build_model(rig, M):
    bn = rig.data.bones
    z = lambda v: v * S  # noqa: E731

    k = Kit("Body", M)
    prof = [(0.26, 0.9), (0.28, 1.02), (0.3, 1.15), (0.34, 1.28), (0.34, 1.38), (0.28, 1.47), (0.15, 1.53)]
    k.lathe([(r * S, z(h)) for r, h in prof], "Leather", seg=18, sx=1.25, sy=0.9)
    k.lathe([(0.3 * S, z(0.86)), (0.36 * S, z(0.72)), (0.38 * S, z(0.6))], "ClothDark", seg=18, sx=1.2, sy=0.95)
    front = 0.34 * 0.9 * S
    k.box(Vector((0, front + 0.01, z(1.3))), (0.36, 0.04, 0.26), "Iron", rot=(-6, 0, 0))
    for sd in (-1.0, 1.0):
        k.box(Vector((0, front + 0.032, z(1.3))), (0.3, 0.006, 0.04), "Team", rot=(-6, sd * 20, 0))
    k.lathe([(0.3 * S, z(0.88)), (0.31 * S, z(0.96))], "Iron", seg=18, sx=1.26, sy=0.92)
    k.finish(rig, ["chest", "spine", "hips", "skirt_f", "skirt_b", "thigh_l", "thigh_r"])

    for side, sx in (("r", 1.0), ("l", -1.0)):
        k = Kit("Pauldron_" + side, M)
        top = bn["upper_arm_" + side].head_local
        k.sphere(top + Vector((sx * 0.03, 0, 0.04)), 0.13, "Iron", scale=(1.0, 1.1, 0.7), u=12, v=8)
        k.finish(rig, "shoulder_" + side)

    hz = bn["head"].head_local.z
    hy = bn["head"].head_local.y + 0.05
    k = Kit("Head", M)
    k.sphere((0, hy, hz + 0.05), 0.1, "Iron", scale=(1.0, 1.05, 0.95), u=14, v=8)
    k.box(Vector((0, hy + 0.1, hz + 0.045)), (0.12, 0.02, 0.02), "RobeInner")
    for sx in (-1.0, 1.0):
        k.sphere((sx * 0.03, hy + 0.105, hz + 0.045), 0.009, "TeamGlow", u=6, v=4)
        base_p = Vector((sx * 0.08, hy, hz + 0.09))
        k.tube([base_p, base_p + Vector((sx * 0.1, 0.02, 0.06)), base_p + Vector((sx * 0.14, 0.06, 0.17))], [0.03, 0.02, 0.003], "Bone", seg=6)
    k.finish(rig, "head")

    for side in ("r", "l"):
        ck.sleeve(rig, M, side, "Skin", radii=(0.085, 0.08, 0.072, 0.07, 0.062), smooth=0)
        el = bn["forearm_" + side].head_local
        wr = bn["hand_" + side].head_local
        d = (wr - el).normalized()
        k = Kit("Bracer_" + side, M)
        k.tube([wr - d * 0.12, wr], [0.072, 0.07], "Leather", seg=10)
        k.finish(rig, "forearm_" + side)
        ck.hand(rig, M, side, "Skin", fist=True)
    ck.limbs(rig, M, legs="Leather", boots="Iron", hands=None, leg_r=(0.1, 0.09, 0.075, 0.068), boot_scale=1.15, cuff="Leather", smooth=0)

    # Great stone maul.
    p = bn["maul"].head_local
    up = Vector((0, 0, 1))
    k = Kit("Maul", M)
    k.tube([p - up * 0.22, p + up * 0.55], [0.028, 0.03], "Wood", seg=6)
    hc = p + up * 0.63
    k.box(hc, (0.2, 0.34, 0.19), "Stone")
    for dy in (-0.1, 0.1):
        k.box(hc + Vector((0, dy, 0)), (0.212, 0.035, 0.202), "Brass")
    for sd in (-1.0, 1.0):
        k.box(hc + Vector((sd * 0.102, 0, 0)), (0.004, 0.1, 0.07), "TeamGlow")
    k.finish(rig, "maul")


def main():
    import sys
    out = ck.out_path(sys.argv, "/tmp/minion_breaker.blend")
    spec = ck.load_spec("minion_breaker")
    ck.reset()
    rig = ck.make_rig(bones())
    M = ck.Mats()
    build_model(rig, M)
    # The slam lands in front of the chest, so the Muzzle sits there, not in the hand.
    mx, my, mz = spec["sockets"]["Muzzle"]
    ck.socket("Muzzle", rig, "chest", (mx, -mz - 0.05, my))
    ox, oy, oz = spec["sockets"]["Overhead"]
    ck.socket("Overhead", rig, "root", (ox, -oz, oy))
    rest = dict(upper_arm_r=(25, 0, 10), forearm_r=(-60, 0, 0), maul=(70, 0, 0), upper_arm_l=(10, 0, -10), forearm_l=(-15, 0, 0), spine=(10, 0, 0),
                head=(-10, 0, 0))

    def run(t, s, c2):
        return dict(hips=(0, 0, 8 * s), spine=(-4, 0, -5 * s), chest=(-2, 0, -6 * s), head=(4, 0, 3 * s),
                    upper_arm_r=(-10 * s + 22, 0, 10), forearm_r=(-60, 0, 0), maul=(75, 0, 0),
                    upper_arm_l=(30 * s + 6, 0, -12), forearm_l=(-40, 0, 0), skirt_f=(-12 - 6 * c2, 0, 0), skirt_b=(20 + 5 * c2, 0, 0))

    def attack(rel, rec):
        # The maul hauled overhead and slammed down in front.
        return [(0, {}, (0, 0, -0.02)),
                (rel * 0.65, dict(spine=(-8, 0, 0), chest=(-8, 0, 0), head=(-14, 0, 0), upper_arm_r=(160, 0, 10), forearm_r=(-40, 0, 0),
                                  maul=(-140, 0, 0), upper_arm_l=(150, 0, -16), forearm_l=(-40, 0, 0)), (0, -0.04, 0.02)),
                (rel, dict(spine=(30, 0, 0), chest=(12, 0, 0), head=(4, 0, 0), upper_arm_r=(70, 0, -10), forearm_r=(-10, 0, 0), maul=(60, 0, 0),
                           upper_arm_l=(70, 0, 20), forearm_l=(-30, 0, 0)), (0, 0.08, -0.18)),
                (rel + rec * 0.5, dict(spine=(26, 0, 0), upper_arm_r=(60, 0, -10), maul=(60, 0, 0), upper_arm_l=(60, 0, 20)), (0, 0.06, -0.16)),
                (rel + rec, {}, (0, 0, -0.02))]
    minion_kit.clips(rig, spec, NAMES, rest, run, attack, cycle=0.62, lift=0.2, kick=0.16, wide=0.05)
    ck.save(out)


if __name__ == "__main__":
    main()
