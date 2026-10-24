# SPDX-License-Identifier: GPL-2.0-or-later
# (Uses Blender's Python API. This is a build tool, not part of the game.)
"""Build the Chainbound (Veyra Sable) champion model, rig and clips, from code.

  /opt/bpyenv/bin/python tools/blender/build_chainbound.py OUT.blend

A tiefling warlock duelist: the CC0 Blender Studio female body
(tools/blender/body_fit.py) for her head, torso and legs, in a fitted
leather jack with a steel breastplate, a short split tasset, tall boots and
one steel spaulder. Swept back horns, a slim tail, and the stolen oath chain:
wrapped round the right forearm and hanging from the fist, its links lit with
runes. A broken contract seal hangs at the belt. Everything other than the
body is original geometry written as code.
"""
import math

import bpy  # noqa: F401,I001  (bpy first: it makes mathutils importable)
from mathutils import Vector

import body_fit as bf
import champion_kit as ck
from champion_kit import TAU, Kit, base

S = 1.0
W = 0.92

NAMES = ck.BODY + ["chain", "chain2", "tail", "tail2"]
GIRTH = {"hips": (1.0, 1.0), "spine": (0.98, 1.0), "chest": (1.0, 1.02), "neck": (1.0, 1.0), "head": (1.0, 1.0),
         "thigh_l": (1.0, 1.0), "thigh_r": (1.0, 1.0), "shin_l": (0.98, 0.98), "shin_r": (0.98, 0.98)}


def bones():
    b = ck.humanoid_bones(S, W)
    h, t = Vector(b["hand_r"][0]), Vector(b["hand_r"][1])
    palm = h + (t - h).normalized() * 0.05
    # The chain hangs from the fist in two parts, so lashes can whip it.
    b["chain"] = (tuple(palm), tuple(palm + Vector((0, 0.05, -0.32))), "hand_r")
    b["chain2"] = (tuple(palm + Vector((0, 0.05, -0.32))), tuple(palm + Vector((0, 0.08, -0.62))), "chain")
    b["tail"] = ((0, -0.12 * S, 0.98 * S), (0, -0.32 * S, 0.7 * S), "hips")
    b["tail2"] = ((0, -0.32 * S, 0.7 * S), (0, -0.4 * S, 0.36 * S), "tail")
    return b


def links(k, pts, r, mname, glow_every=0):
    """A chain of alternating oval links along a polyline."""
    step = r * 2.6
    path = []
    for a, b in zip(pts[:-1], pts[1:]):
        a, b = Vector(a), Vector(b)
        n = max(1, int((b - a).length / step))
        path += [a.lerp(b, i / n) for i in range(n)]
    path.append(Vector(pts[-1]))
    for i in range(len(path) - 1):
        p, q = path[i], path[i + 1]
        d = (q - p).normalized()
        side = d.cross(Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))).normalized()
        if i % 2:
            side = d.cross(side).normalized()
        c = p.lerp(q, 0.5)
        ring = [c + d * math.cos(a) * r * 1.5 + side * math.sin(a) * r for a in [j / 10 * TAU for j in range(11)]]
        lit = glow_every and i % glow_every == 0
        k.tube(ring, [r * 0.32] * len(ring), "Glow" if lit else mname, seg=5, cap=False)


def build_model(rig, M):
    bn = rig.data.bones
    z = lambda v: v * S  # noqa: E731
    # The female body file's eye centres, so the eyes sit in its sockets.
    fitted = bf.fit(rig, GIRTH, body="female", points=[(-0.0475, 0.0485, 1.4668), (0.0475, 0.0485, 1.4668)])
    torso = ("hips", "spine", "chest", "neck")

    # Head: the body's own head and neck in tiefling skin, glowing eyes in its
    # sockets, swept back dark hair at the nape.
    hz = bn["head"].head_local.z
    hy = bn["head"].head_local.y
    k = Kit("Head", M)
    bf.add_faces(k, fitted, bf.region(fitted, lambda i, o, p: o in ("head", "neck") and p.z > z(1.47)), "Tiefling", uv_scale=2.0)
    # The base mesh's eyes are separate objects we don't use: dark eyes in
    # its sockets with a glowing iris.
    for c in fitted[4]:
        k.sphere(c, 0.017, "RobeInner", u=10, v=6)
        k.sphere(c + Vector((0, 0.013, 0)), 0.007, "Eyes", scale=(1.3, 0.5, 0.9), u=8, v=6)
    front = bf.surface_y(fitted, 0.0, hz + 0.1, ("head",), True) or hy + 0.09
    # Hair: a close cap shaped on the scalp, swept back into a long tail.
    scalp = bf.region(fitted, lambda i, o, p: o == "head" and abs(p.x) < 0.075 + 0.2 * max(0.0, p.z - hz - 0.12)
                      and (p.z > hz + 0.15 or (p.y < hy - 0.02 and p.z > hz + 0.02)))
    bf.add_faces(k, fitted, scalp, "Hair", offset=0.01, uv_scale=2.0)
    k.tube([(0, hy - 0.1, hz + 0.1), (0, hy - 0.15, hz + 0.0), (0, hy - 0.16, hz - 0.12), (0, hy - 0.13, hz - 0.26)],
           [0.035, 0.032, 0.025, 0.01], "Hair", seg=8, flat=0.7)
    # Horns: restrained, rising from the brow and sweeping back over the hair.
    for sx in (-1.0, 1.0):
        base_p = Vector((sx * 0.05, front - 0.06, hz + 0.17))
        pts = [base_p, base_p + Vector((sx * 0.03, -0.06, 0.06)), base_p + Vector((sx * 0.05, -0.14, 0.075)),
               base_p + Vector((sx * 0.055, -0.22, 0.04)), base_p + Vector((sx * 0.05, -0.27, -0.01))]
        k.tube(pts, [0.024, 0.02, 0.015, 0.009, 0.002], "Horn", seg=8)
        for f in (1, 2):
            k.tube([pts[f], pts[f] + (pts[f + 1] - pts[f]) * 0.12], [0.0185 - f * 0.003] * 2, "Horn", seg=8, cap=False)
    k.finish(rig, ["head", "neck"], subsurf=1)

    # Jack: fitted leather over the whole torso, a steel breastplate over the
    # chest with a rolled edge, a high collar.
    k = Kit("Jack", M)
    bf.add_faces(k, fitted, bf.region(fitted, lambda i, o, p: o in torso and z(0.9) < p.z < z(1.5)), "Leather", offset=0.012, uv_scale=3.0)
    k.lathe([(0.075, z(1.47)), (0.08, z(1.52)), (0.085, z(1.57))], "Leather", seg=20, sx=1.15, sy=1.1, center=(0, -0.01))
    k.finish(rig, ["chest", "spine", "hips", "neck"], solidify=0.008)
    k = Kit("Breastplate", M)
    plate = bf.region(fitted, lambda i, o, p: o in ("chest", "spine") and z(1.12) < p.z < z(1.44) and p.y > 0.0 and abs(p.x) < 0.13)
    for loop in bf.add_faces(k, fitted, plate, "Steel", offset=0.026, uv_scale=3.0):
        bf.rim(k, loop, 0.008, "Trim")
    k.finish(rig, ["chest", "spine"], solidify=0.008)

    # Belt, the broken contract seal on its chain, and a split tasset of
    # leather panels over the hips.
    k = Kit("Belt", M)
    k.lathe([(0.15, z(0.93)), (0.155, z(0.985))], "Leather", seg=28, sx=1.18, sy=0.9)
    k.box(Vector((0.03, 0.155 * 0.9 + 0.01, z(0.957))), (0.05, 0.016, 0.04), "Iron")
    seal = Vector((-0.11, 0.135, z(0.86)))
    links(k, [Vector((-0.08, 0.145, z(0.95))), seal + Vector((0, 0, 0.04))], 0.008, "Iron")
    for sd, rot in ((-1.0, 12), (1.0, -16)):
        # Two halves of a cracked gold seal, pulled a little apart.
        c = seal + Vector((sd * 0.012, 0, sd * 0.004))
        k.arc_lathe([(0.0, c.z - 0.003), (0.034, c.z), (0.034, c.z + 0.006), (0.0, c.z + 0.009)], "Trim", 0 if sd > 0 else math.pi,
                    math.pi if sd > 0 else TAU, seg=8, center=(c.x, c.y))
    k.box(seal + Vector((0, 0.01, -0.05)), (0.05, 0.004, 0.07), "Paper", rot=(0, 0, 8))
    k.finish(rig, ["hips"])
    k = Kit("Tasset", M)
    for sd in (-1.0, 1.0):
        for j, a in enumerate((0.45, 0.95, 1.5)):
            th = sd * a
            rows = []
            for i in range(5):
                f = i / 4
                r = 0.165 + 0.04 * f
                rows.append([Vector((math.sin(th + du) * r * 1.15, math.cos(th + du) * r * 0.95, z(0.95) - 0.26 * f)) for du in (-0.24, 0.0, 0.24)])
            k.ring_grid(rows, "Leather" if j != 1 else "Team", closed=False)
    k.finish(rig, ["hips", "thigh_l", "thigh_r", "skirt_f", "skirt_b"], solidify=0.008)

    # Tail: slim, in skin, ending in a small spade.
    k = Kit("Tail", M)
    t0, t1, t2 = bn["tail"].head_local, bn["tail"].tail_local, bn["tail2"].tail_local
    k.tube([t0 + Vector((0, 0.03, 0.02)), t0.lerp(t1, 0.5), t1, t1.lerp(t2, 0.5), t2], [0.024, 0.02, 0.016, 0.012, 0.008], "Tiefling", seg=8)
    k.octa(t2 + Vector((0, -0.01, -0.03)), 0.03, 0.03, 0.05, "Tiefling")
    k.finish(rig, ["hips", "tail", "tail2"], subsurf=1)

    # Arms: dark sleeves, a steel spaulder and couter on the right (the
    # chain arm), leather bracers, gloves.
    for side in ("r", "l"):
        ck.sleeve(rig, M, side, "ClothDark", radii=(0.062, 0.056, 0.05, 0.046, 0.046))
        el = bn["forearm_" + side].head_local
        wr = bn["hand_" + side].head_local
        d = (wr - el).normalized()
        k = Kit("Bracer_" + side, M)
        k.tube([el + d * 0.05, el.lerp(wr, 0.6), wr + d * 0.01], [0.051, 0.053, 0.05], "Leather", seg=12)
        k.finish(rig, "forearm_" + side, subsurf=1)
        ck.hand(rig, M, side, "Leather", fist=True)
    k = Kit("Spaulder", M)
    top = bn["upper_arm_r"].head_local
    k.sphere(top + Vector((0.03, 0, 0.03)), 0.092, "Steel", scale=(1.0, 1.1, 0.68), u=16, v=8)
    k.sphere(top + Vector((0.05, 0, -0.025)), 0.078, "Steel", scale=(0.9, 1.0, 0.52), u=16, v=8)
    rim = [top + Vector((0.03 + math.cos(a) * 0.093, math.sin(a) * 0.102, 0.03)) for a in [i / 18 * TAU for i in range(19)]]
    k.tube(rim, [0.007] * len(rim), "Trim", seg=5, cap=False)
    k.finish(rig, "shoulder_r")
    # The oath chain coiled round the right forearm.
    el = bn["forearm_r"].head_local
    wr = bn["hand_r"].head_local
    d = (wr - el).normalized()
    x = d.cross(Vector((0, 0, 1))).normalized()
    y = d.cross(x).normalized()
    k = Kit("ChainWrap", M)
    coil = [el.lerp(wr, 0.15 + 0.75 * t / 40) + (x * math.cos(t / 40 * TAU * 3.2) + y * math.sin(t / 40 * TAU * 3.2)) * 0.062 for t in range(41)]
    links(k, coil, 0.011, "Iron", glow_every=5)
    k.finish(rig, "forearm_r")
    # And hanging from the fist, swinging on its own two bones.
    k = Kit("Chain", M)
    c0, c1, c2 = bn["chain"].head_local, bn["chain"].tail_local, bn["chain2"].tail_local
    links(k, [c0, c1, c2], 0.013, "Iron", glow_every=4)
    k.sphere(c2 + Vector((0, 0, -0.03)), 0.03, "Iron", scale=(1, 1, 1.3), u=10, v=6)
    k.finish(rig, ["chain", "chain2"])

    # Legs: the body's own legs in dark trousers, tall boots to the knee.
    bf.legs(rig, M, fitted, "ClothDark", "Leather", 0.88, cuff="Leather")
    for side in ("l", "r"):
        knee = bn["shin_" + side].head_local
        k = Kit("BootTop_" + side, M)
        shin = bf.region(fitted, lambda i, o, p: o == "shin_" + side and knee.z - 0.2 < p.z < knee.z - 0.06)
        for loop in bf.add_faces(k, fitted, shin, "Leather", offset=0.02, uv_scale=3.0):
            bf.rim(k, loop, 0.01, "Leather")
        k.finish(rig, "shin_" + side)


# ---------------------------------------------------------------- clips

def animate(rig, spec):
    slots = spec["slot_clips"]
    feet = ck.rest_feet(rig)
    rest = dict(upper_arm_r=(18, 0, 10), forearm_r=(-30, 0, 0), upper_arm_l=(10, 0, -8), forearm_l=(-15, 0, 0),
                chain=(0, 0, 0), chain2=(0, 0, 0), tail=(10, 0, 0), tail2=(15, 0, 0), spine=(3, 0, 0), head=(-3, 0, 0))

    def b(**over):
        d = dict(rest)
        d.update(over)
        return base(NAMES, **d)

    stance = {"l": (feet["l"][0] - 0.02, feet["l"][1] + 0.1, feet["l"][2]), "r": (feet["r"][0] + 0.03, feet["r"][1] - 0.1, feet["r"][2])}

    # Idle: a duellist's sideways stance, the chain arm forward and low, the
    # chain and tail swaying.
    ck.idle_clip(rig, 2.0, lambda t, s: (b(spine=(3 + 1.2 * s, 0, 10), chest=(0, 0, 6), head=(-3, 0, -12 + 3 * math.sin(t / 2.0 * TAU)),
                                            upper_arm_r=(24 + 2 * s, 0, 10), chain=(-6 * s, 0, 8 * math.sin(t / 2.0 * TAU)),
                                            chain2=(-8 * s, 0, 0), tail=(10, 0, 14 * math.sin(t / 2.0 * TAU)),
                                            tail2=(15, 0, 18 * math.sin(t / 2.0 * TAU + 0.8))),
                                          {"hips": (0, 0, -0.03 - 0.01 * s)}), step=4)

    # Run: quick and upright, the chain arm tucked, the chain trailing.
    def upper(t, s, c2):
        rots = b(hips=(0, 0, 8 * s), spine=(-12, 0, -5 * s), chest=(-4, 0, -6 * s), head=(10, 0, 3 * s),
                 upper_arm_r=(-35 * s + 5, 0, 10), forearm_r=(-60 - 15 * s, 0, 0), chain=(-50, 0, 0), chain2=(-30, 0, 0),
                 upper_arm_l=(35 * s + 5, 0, -10), forearm_l=(-50 + 15 * s, 0, 0),
                 skirt_f=(-14 - 6 * c2, 0, 0), skirt_b=(24 + 6 * c2, 0, 0), tail=(40 + 6 * c2, 0, 10 * s), tail2=(25, 0, 14 * s))
        return rots, {}
    ck.run_clip(rig, spec["move_speed_mps"], upper, cycle=0.56, stance=0.2, hips_drop=0.08, lift=0.24, kick=0.2)

    def lash(name, wind, crack, reach_loc):
        c = slots[name]
        rel, rec = c["release_s"], c["recovery_s"]
        ck.cast_clip(rig, name, rel, rec, [
            (0, b(), (0, 0, -0.03)),
            (rel * 0.6, b(**wind), (0, -0.04, -0.05)),
            (rel, b(**crack), reach_loc),
            (rel + max(rec, 0.1) * 0.5, b(**crack), reach_loc),
            (rel + max(rec, 0.1), b(), (0, 0, -0.03))], stance)

    # Pactlash: the chain is swung back over the shoulder, then cracked
    # straight forward.
    lash("attack", dict(spine=(-4, 0, -14), chest=(-4, 0, -16), upper_arm_r=(130, 0, -10), forearm_r=(-70, 0, 0), chain=(-120, 0, 0),
                        chain2=(-40, 0, 0)),
         dict(spine=(12, 0, 12), chest=(6, 0, 14), upper_arm_r=(85, 0, 5), forearm_r=(-5, 0, 0), chain=(80, 0, 0), chain2=(10, 0, 0),
              upper_arm_l=(-15, 0, -12)), (0, 0.08, -0.07))
    # Debt Collector: the left hand pulls the seal's power out, then the
    # chain is thrown long.
    lash("ability_1", dict(spine=(-6, 0, -20), upper_arm_r=(100, 0, -30), forearm_r=(-90, 0, 0), chain=(-90, 0, 0), upper_arm_l=(60, 0, -20),
                           forearm_l=(-60, 0, 0)),
         dict(spine=(14, 0, 18), chest=(8, 0, 16), upper_arm_r=(92, 0, 0), forearm_r=(0, 0, 0), chain=(90, 0, 0), chain2=(0, 0, 0),
              upper_arm_l=(30, 0, -20), forearm_l=(-40, 0, 0)), (0, 0.1, -0.08))
    # Chain Traverse: the arm thrown up and out to the anchor, the body
    # pulled after it.
    lash("ability_2", dict(spine=(8, 0, 0), upper_arm_r=(140, 0, 0), forearm_r=(-40, 0, 0), chain=(-60, 0, 0)),
         dict(spine=(-14, 0, 0), chest=(-8, 0, 0), head=(6, 0, 0), upper_arm_r=(150, 0, 5), forearm_r=(-5, 0, 0), chain=(30, 0, 0),
              chain2=(0, 0, 0), upper_arm_l=(-40, 0, -20), tail=(50, 0, 0), tail2=(30, 0, 0), skirt_b=(30, 0, 0)), (0, 0.12, 0.06))
    # Covenant Severed: both arms wrench apart as the chain is torn tight.
    lash("ability_3", dict(spine=(10, 0, 0), chest=(8, 0, 0), upper_arm_r=(70, 0, 30), forearm_r=(-80, 0, 0), upper_arm_l=(70, 0, -30),
                           forearm_l=(-80, 0, 0), chain=(40, 0, 0)),
         dict(spine=(-10, 0, 0), chest=(-10, 0, 0), head=(-14, 0, 0), upper_arm_r=(100, 0, -60), forearm_r=(-10, 0, 0),
              upper_arm_l=(100, 0, 60), forearm_l=(-10, 0, 0), chain=(60, 0, 40), chain2=(20, 0, 0), tail=(30, 0, 0)), (0, 0.0, 0.0))
    # Break the Seal: a short step in and an open palm driven forward.
    lash("ability_4", dict(spine=(-6, 0, -18), upper_arm_l=(40, 0, 30), forearm_l=(-100, 0, 0), upper_arm_r=(20, 0, 20)),
         dict(spine=(16, 0, 16), chest=(8, 0, 14), upper_arm_l=(88, 0, -4), forearm_l=(-5, 0, 0), upper_arm_r=(10, 0, 20),
              forearm_r=(-50, 0, 0)), (0, 0.16, -0.1))

    ck.death_clip(rig, NAMES, lambda t: {"chain": (40 * min(1.0, t / 0.6), 0, 0), "tail": (40 * min(1.0, t / 0.9), 0, 0)})


def main():
    import sys
    out = ck.out_path(sys.argv, "/tmp/chainbound.blend")
    spec = ck.load_spec("chainbound")
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
