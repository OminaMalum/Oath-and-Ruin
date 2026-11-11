# SPDX-License-Identifier: GPL-2.0-or-later
# (Uses Blender's Python API. This is a build tool, not part of the game.)
"""Build the caster lane minion: a small hooded acolyte in a team robe and
scarf, carrying a staff topped with a team crystal. Original geometry.

  /opt/bpyenv/bin/python tools/blender/build_minion_caster.py OUT.blend
"""
import math

import bpy  # noqa: F401,I001  (bpy first: it makes mathutils importable)
from mathutils import Vector

import champion_kit as ck
import minion_kit
from champion_kit import TAU, Kit

S = 0.58
W = 1.15

NAMES = ck.BODY + ["staff"]


def bones():
    b = ck.humanoid_bones(S, W)
    h, t = Vector(b["hand_r"][0]), Vector(b["hand_r"][1])
    palm = h + (t - h).normalized() * 0.04
    b["staff"] = (tuple(palm), tuple(palm + Vector((0, 0, 0.2))), "hand_r")
    return b


def build_model(rig, M):
    bn = rig.data.bones
    z = lambda v: v * S  # noqa: E731

    k = Kit("Robe", M)
    prof = [(0.42, 0.04), (0.38, 0.3), (0.3, 0.7), (0.24, 1.0), (0.25, 1.2), (0.26, 1.32), (0.22, 1.42), (0.13, 1.5)]
    rings = []
    for r, h in prof:
        rings.append([Vector((math.sin(i / 16 * TAU) * (r * S + (0.012 * math.sin(i * 1.7) if h < 0.5 else 0.0)) * 1.08,
                              math.cos(i / 16 * TAU) * r * S * 0.92, z(h) + (0.02 * math.sin(i * 2.3) if h < 0.1 else 0.0)))
                      for i in range(16)])
    k.ring_grid(rings, "Team", u_scale=2.0)
    k.lathe([(0.245 * S, z(0.98)), (0.25 * S, z(1.05))], "Leather", seg=16, sx=1.09, sy=0.93)
    k.finish(rig, ["hips", "spine", "chest", "thigh_l", "thigh_r", "skirt_f", "skirt_b"], solidify=0.008)

    # Scarf and hood in a dark cloth so the team robe reads as the colour.
    hz = bn["head"].head_local.z
    hy = bn["head"].head_local.y
    k = Kit("Hood", M)
    k.lathe([(0.15, z(1.42)), (0.13, z(1.5)), (0.1, z(1.55))], "ClothDark", seg=14, sx=1.1)
    # A shadowed face inside the hood, only the team eyes catch the light.
    k.sphere((0, hy - 0.005, hz + 0.06), 0.066, "RobeInner", scale=(0.9, 0.95, 1.0), u=12, v=8)
    for sx in (-1.0, 1.0):
        k.sphere((sx * 0.022, hy + 0.058, hz + 0.075), 0.009, "TeamGlow", u=6, v=4)
    rings = []
    for j in range(7):
        a = math.pi * (0.1 + j / 6 * 0.75)
        rings.append([Vector((math.sin(th) * (0.095 * math.sin(a) + 0.012), hy - 0.005 + math.cos(th) * (0.095 * math.sin(a) + 0.012),
                              hz + 0.065 + 0.1 * math.cos(a)))
                      for th in [1.1 + i / 12 * (TAU - 2.2) for i in range(13)]])
    k.ring_grid(rings, "ClothDark", closed=False)
    k.tube([(0, hy - 0.07, hz + 0.13), (0, hy - 0.14, hz + 0.1), (0, hy - 0.18, hz + 0.03)], [0.035, 0.02, 0.003], "ClothDark", seg=6)
    k.finish(rig, ["head", "neck"], solidify=0.01)

    for side in ("r", "l"):
        ck.sleeve(rig, M, side, "Team", radii=(0.048, 0.045, 0.045, 0.055, 0.065), smooth=0)
        ck.hand(rig, M, side, "Skin", fist=(side == "r"))
    ck.limbs(rig, M, legs="ClothDark", boots="Leather", hands=None, leg_r=(0.05, 0.045, 0.04, 0.036), boot_scale=0.75, smooth=0)

    p = bn["staff"].head_local
    up = Vector((0, 0, 1))
    k = Kit("Staff", M)
    k.tube([p - up * 0.4, p + up * 0.42], [0.014, 0.016], "Wood", seg=6)
    top = p + up * 0.42
    for i in range(3):
        a = i / 3 * TAU
        d = Vector((math.cos(a), math.sin(a), 0))
        k.tube([top, top + d * 0.035 + up * 0.05, top + d * 0.02 + up * 0.12], [0.008, 0.006, 0.002], "Brass", seg=4)
    k.octa(top + up * 0.075, 0.03, 0.06, 0.04, "TeamGlow")
    k.finish(rig, "staff")


def main():
    import sys
    out = ck.out_path(sys.argv, "/tmp/minion_caster.blend")
    spec = ck.load_spec("minion_caster")
    ck.reset()
    rig = ck.make_rig(bones())
    M = ck.Mats()
    build_model(rig, M)
    hr = rig.data.bones["hand_r"]
    ck.socket("Muzzle", rig, "hand_r", hr.head_local + (hr.tail_local - hr.head_local).normalized() * 0.1)
    ox, oy, oz = spec["sockets"]["Overhead"]
    ck.socket("Overhead", rig, "root", (ox, -oz, oy))
    rest = dict(upper_arm_r=(8, 0, 4), forearm_r=(-8, 0, 0), upper_arm_l=(8, 0, -4))

    def run(t, s, c2):
        return dict(hips=(0, 0, 8 * s), spine=(-10, 0, -4 * s), chest=(-3, 0, -5 * s), head=(10, 0, 2 * s),
                    upper_arm_r=(-20 * s + 10, 0, 8), forearm_r=(-35, 0, 0), staff=(-25, 0, 0),
                    upper_arm_l=(30 * s, 0, -8), forearm_l=(-30, 0, 0), skirt_f=(-12 - 6 * c2, 0, 0), skirt_b=(24 + 5 * c2, 0, 0))

    def attack(rel, rec):
        # The staff drawn back, then levelled forward on release.
        return [(0, {}, (0, 0, -0.01)),
                (rel * 0.6, dict(spine=(-4, 0, -8), chest=(0, 0, 12), upper_arm_r=(40, 0, 30), forearm_r=(-70, 0, 0), staff=(-20, 0, 0)),
                 (0, -0.02, -0.01)),
                (rel, dict(spine=(8, 0, -4), chest=(-4, 0, -10), upper_arm_r=(80, 0, -4), forearm_r=(-10, 0, 0), staff=(-60, 0, 0)),
                 (0, 0.03, -0.03)),
                (rel + rec * 0.5, dict(spine=(6, 0, -3), upper_arm_r=(70, 0, -4), forearm_r=(-14, 0, 0), staff=(-55, 0, 0)), (0, 0.02, -0.03)),
                (rel + rec, {}, (0, 0, -0.01))]
    minion_kit.clips(rig, spec, NAMES, rest, run, attack, cycle=0.5)
    ck.save(out)


if __name__ == "__main__":
    main()
