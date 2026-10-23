# SPDX-License-Identifier: GPL-2.0-or-later
# (Uses Blender's Python API. This is a build tool, not part of the game.)
"""Build the melee lane minion: a stocky soldier in mail and a team tabard,
a crested helm, a round team shield and a short sword. Original geometry.

  /opt/bpyenv/bin/python tools/blender/build_minion_melee.py OUT.blend
"""
import math

import bpy  # noqa: F401,I001  (bpy first: it makes mathutils importable)
from mathutils import Vector

import champion_kit as ck
import minion_kit
from champion_kit import TAU, Kit

S = 0.62
W = 1.3

NAMES = ck.BODY + ["shield", "sword"]


def bones():
    b = ck.humanoid_bones(S, W)
    fl_h, fl_t = Vector(b["forearm_l"][0]), Vector(b["forearm_l"][1])
    mid = fl_h.lerp(fl_t, 0.5)
    b["shield"] = (tuple(mid), tuple(mid + Vector((0, 0, 0.15))), "forearm_l")
    h, t = Vector(b["hand_r"][0]), Vector(b["hand_r"][1])
    palm = h + (t - h).normalized() * 0.04
    b["sword"] = (tuple(palm), tuple(palm + Vector((0, 0.15, 0))), "hand_r")
    return b


def build_model(rig, M):
    bn = rig.data.bones
    z = lambda v: v * S  # noqa: E731

    k = Kit("Body", M)
    prof = [(0.25, 0.7), (0.24, 0.85), (0.24, 1.0), (0.27, 1.2), (0.27, 1.32), (0.23, 1.42), (0.14, 1.5)]
    k.lathe([(r * S, z(h)) for r, h in prof], "Mail", seg=16, sx=1.12, sy=0.92)
    k.lathe([(0.25 * S, z(0.95)), (0.255 * S, z(1.03))], "Leather", seg=16, sx=1.13, sy=0.93)
    k.box(Vector((0, 0.255 * 0.93 * S + 0.006, z(0.99))), (0.05, 0.012, 0.04), "Brass")
    for sd in (1.0, -1.0):
        y = sd * (0.27 * 0.92 * S + 0.012)
        k.box(Vector((0, y, z(1.16))), (0.2, 0.014, 0.25), "Team")
        k.box(Vector((0, y + sd * 0.004, z(0.82))), (0.17, 0.012, 0.22), "Team")
    k.sphere(Vector((0, 0.27 * 0.92 * S + 0.022, z(1.2))), 0.03, "Brass", scale=(1, 0.4, 1), u=10, v=6)
    k.finish(rig, ["chest", "spine", "hips", "skirt_f", "skirt_b"])

    hz = bn["head"].head_local.z
    hy = bn["head"].head_local.y
    k = Kit("Head", M)
    k.sphere((0, hy + 0.01, hz + 0.06), 0.075, "Skin", scale=(0.9, 0.95, 1.0), u=12, v=8)
    for sx in (-1.0, 1.0):
        k.sphere((sx * 0.026, hy + 0.08, hz + 0.075), 0.009, "RobeInner", u=6, v=4)
    k.lathe([(0.088, hz + 0.05), (0.092, hz + 0.1), (0.08, hz + 0.15), (0.045, hz + 0.18), (0.0, hz + 0.19)], "Iron", seg=14, center=(0, hy))
    k.lathe([(0.094, hz + 0.05), (0.098, hz + 0.065)], "Iron", seg=14, center=(0, hy))
    k.box(Vector((0, hy + 0.09, hz + 0.06)), (0.016, 0.012, 0.07), "Iron")
    k.box(Vector((0, hy - 0.01, hz + 0.2)), (0.03, 0.16, 0.06), "Team")
    k.finish(rig, "head")

    for side in ("r", "l"):
        ck.sleeve(rig, M, side, "Mail", radii=(0.05, 0.046, 0.042, 0.04, 0.04), smooth=0)
        ck.hand(rig, M, side, "Leather", fist=True)
    ck.limbs(rig, M, legs="ClothDark", boots="Leather", hands=None, leg_r=(0.058, 0.052, 0.044, 0.04), boot_scale=0.8, smooth=0)

    # Round shield on the left forearm.
    fl0, fl1 = bn["forearm_l"].head_local, bn["forearm_l"].tail_local
    n = Vector((-0.75, 0.65, 0)).normalized()
    c = fl0.lerp(fl1, 0.5) + n * 0.06
    t = Vector((0.65, 0.75, 0)).normalized()
    up = Vector((0, 0, 1))
    k = Kit("Shield", M)
    rings = []
    for r, lift in ((0.0, 0.05), (0.08, 0.04), (0.17, 0.015), (0.2, 0.0)):
        rings.append([c + (t * math.cos(i / 16 * TAU) + up * math.sin(i / 16 * TAU)) * r + n * lift for i in range(16)])
    k.ring_grid(rings, "Team")
    k.tube([c + (t * math.cos(i / 16 * TAU) + up * math.sin(i / 16 * TAU)) * 0.2 for i in range(17)], [0.014] * 17, "Iron", seg=5, cap=False)
    k.sphere(c + n * 0.05, 0.035, "Brass", u=10, v=6)
    k.finish(rig, "shield", solidify=0.02)

    # Short sword.
    p = bn["sword"].head_local
    d = (bn["sword"].tail_local - p).normalized()
    k = Kit("Sword", M)
    k.tube([p - d * 0.04, p + d * 0.04], [0.014, 0.014], "Leather", seg=6)
    k.sphere(p - d * 0.05, 0.018, "Brass", u=8, v=6)
    k.box(p + d * 0.05, (0.1, 0.02, 0.02), "Brass")
    k.tube([p + d * 0.06, p + d * 0.3, p + d * 0.36], [0.022, 0.02, 0.002], "Steel", seg=4, flat=0.2)
    k.finish(rig, "sword")


def main():
    import sys
    out = ck.out_path(sys.argv, "/tmp/minion_melee.blend")
    spec = ck.load_spec("minion_melee")
    ck.reset()
    rig = ck.make_rig(bones())
    M = ck.Mats()
    build_model(rig, M)
    hr = rig.data.bones["hand_r"]
    ck.socket("Muzzle", rig, "hand_r", hr.head_local + (hr.tail_local - hr.head_local).normalized() * 0.1)
    ox, oy, oz = spec["sockets"]["Overhead"]
    ck.socket("Overhead", rig, "root", (ox, -oz, oy))
    rest = dict(upper_arm_r=(10, 0, 6), forearm_r=(-10, 0, 0), sword=(30, 0, 0), upper_arm_l=(30, 0, -6), forearm_l=(-20, 0, 0),
                spine=(4, 0, 0))

    def run(t, s, c2):
        return dict(hips=(0, 0, 8 * s), spine=(-8, 0, -4 * s), chest=(-3, 0, -5 * s), head=(8, 0, 2 * s),
                    upper_arm_r=(-30 * s + 10, 0, 8), forearm_r=(-40 - 10 * s, 0, 0), sword=(-10, 0, 0),
                    upper_arm_l=(40, 0, -8), forearm_l=(-35, 0, 0), skirt_f=(-12 - 6 * c2, 0, 0), skirt_b=(20 + 5 * c2, 0, 0))

    def attack(rel, rec):
        # An overhead chop with the sword, the shield kept up.
        return [(0, {}, (0, 0, -0.01)),
                (rel * 0.65, dict(spine=(-6, 0, -10), chest=(-4, 0, -14), upper_arm_r=(150, 0, -10), forearm_r=(-40, 0, 0), sword=(-20, 0, 0),
                                  upper_arm_l=(50, 0, 0)), (0, -0.03, -0.02)),
                (rel, dict(spine=(16, 0, 8), chest=(8, 0, 10), upper_arm_r=(60, 0, 10), forearm_r=(-10, 0, 0), sword=(40, 0, 0),
                           upper_arm_l=(40, 0, -6)), (0, 0.05, -0.06)),
                (rel + rec * 0.5, dict(spine=(12, 0, 6), upper_arm_r=(45, 0, 10), forearm_r=(-15, 0, 0), sword=(40, 0, 0)), (0, 0.04, -0.05)),
                (rel + rec, {}, (0, 0, -0.01))]
    minion_kit.clips(rig, spec, NAMES, rest, run, attack, cycle=0.5, wide=0.03)
    ck.save(out)


if __name__ == "__main__":
    main()
