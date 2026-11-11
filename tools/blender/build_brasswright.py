# SPDX-License-Identifier: GPL-2.0-or-later
# (Uses Blender's Python API. This is a build tool, not part of the game.)
"""Build the Brasswright (Nella Flint) champion model, rig and clips, from code.

  /opt/bpyenv/bin/python tools/blender/build_brasswright.py OUT.blend

A rock gnome artificer, 1.3 m: the shared skeleton with short legs and a
large head, the CC0 Blender Studio female body (tools/blender/body_fit.py)
fitted to it for her head, torso and legs. Copper hair in a bun, brass
goggles pushed up on the brow, a work shirt with rolled sleeves under a
leather apron, a tool belt, heavy gloves and boots. On her back the rebuilt
oath engine: a brass boiler with a glowing core and a stubby flue. The
repeater, a brass drum fed crossbow, is strapped along her right forearm.
Everything other than the body is original geometry written as code.
"""
import math

import bpy  # noqa: F401,I001  (bpy first: it makes mathutils importable)
from mathutils import Vector

import body_fit as bf
import champion_kit as ck
from champion_kit import TAU, Kit, base

S = 0.8
W = 1.08
LEG = 0.72  # gnome legs: this share of a human's
HEAD = 1.3  # and a larger head
NAMES = ck.BODY
GIRTH = {"hips": (1.15, 1.1), "spine": (1.12, 1.1), "chest": (1.12, 1.1), "neck": (1.1, 1.1), "head": (HEAD * 0.95, HEAD * 0.95),
         "thigh_l": (1.2, 1.2), "thigh_r": (1.2, 1.2), "shin_l": (1.16, 1.16), "shin_r": (1.16, 1.16)}
# The female body file's eye centres (as Chainbound).
EYES = [(-0.0475, 0.0485, 1.4668), (0.0475, 0.0485, 1.4668)]


def bones():
    b = ck.humanoid_bones(S, W)
    foot_z = b["foot_l"][0][2]
    hip_z = b["hips"][0][2]
    drop = (foot_z + (hip_z - foot_z) * LEG) - hip_z
    out = {}
    for n, (h, t, parent) in b.items():
        h, t = list(h), list(t)
        if n.startswith(("thigh", "shin")):
            h[2] = foot_z + (h[2] - foot_z) * LEG
            t[2] = foot_z + (t[2] - foot_z) * LEG
        elif not n.startswith("foot") and n != "root":
            h[2] += drop
            t[2] += drop
        out[n] = (tuple(h), tuple(t), parent)
    h, t, p = out["head"]
    out["head"] = (h, (t[0], t[1], h[2] + (t[2] - h[2]) * HEAD), p)
    return out


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

    # Head: her own head with bright eyes, copper hair in a bun, goggles up
    # on the brow.
    k = Kit("Head", M)
    bf.add_faces(k, fitted, bf.region(fitted, lambda i, o, p: o in ("head", "neck") and p.z > nz + 0.005), "Skin", uv_scale=2.0)
    for c in fitted[4]:
        k.sphere(c, 0.02, "Paper", u=10, v=6)
        k.sphere(c + Vector((0, 0.016, 0)), 0.01, "Hair", scale=(1.2, 0.5, 1.2), u=8, v=6)
    scalp = bf.region(fitted, lambda i, o, p: o == "head" and (p.z > top - 0.1 or (p.y < hy - 0.01 and p.z > hz + 0.04)))
    bf.add_faces(k, fitted, scalp, "HairCopper", offset=0.012, uv_scale=2.0)
    bk = behind(0.0, top - 0.06, ("head",)) or hy - 0.1
    k.sphere(Vector((0, bk - 0.03, top - 0.03)), 0.06, "HairCopper", scale=(1.0, 0.9, 0.85), u=12, v=8)
    k.lathe([(0.03, top - 0.08), (0.034, top - 0.06), (0.03, top - 0.045)], "Team", seg=12, center=(0, bk - 0.03))
    brow_z = top - 0.075
    fy = front(0.0, brow_z, ("head",)) or hy + 0.1
    for sx in (-1.0, 1.0):
        c = Vector((sx * 0.048, fy + 0.012, brow_z))
        k.lathe([(0.03, c.z - 0.016), (0.034, c.z - 0.012), (0.034, c.z + 0.012), (0.03, c.z + 0.016)], "Brass", seg=16, center=(c.x, c.y))
        k.sphere(c + Vector((0, 0.012, 0)), 0.028, "Glass", scale=(1, 0.35, 1), u=12, v=6)
    strap = [Vector((math.sin(a) * 0.1 * HEAD, hy + math.cos(a) * 0.105 * HEAD, brow_z - 0.004)) for a in [j / 24 * TAU for j in range(25)]]
    k.tube(strap, [0.008] * len(strap), "Leather", seg=5, flat=0.4, cap=False)
    k.finish(rig, ["head", "neck"], subsurf=1)

    # Shirt and apron: a work shirt over the torso, a heavy leather apron
    # from the chest to the knee with a bib and neck strap.
    k = Kit("Shirt", M)
    bf.add_faces(k, fitted, bf.region(fitted, lambda i, o, p: o in torso and hipz - 0.08 < p.z < nz + 0.02), "Robe", offset=0.014, uv_scale=3.0)
    k.lathe([(0.07 * 1.1, nz - 0.01), (0.075 * 1.1, nz + 0.03)], "Robe", seg=20, sx=1.1, sy=1.0)
    k.finish(rig, ["chest", "spine", "hips", "neck"], solidify=0.008)
    k = Kit("Apron", M)
    rows = []
    knee = bn["shin_l"].head_local.z
    for i in range(9):
        f = i / 8
        zz = cz + 0.06 - (cz + 0.06 - (knee - 0.03)) * f
        half = 0.09 + 0.08 * min(1.0, f * 2.2)
        row = []
        for j in range(7):
            x = -half + half * 2 * j / 6
            y = front(x, zz) if zz > hipz - 0.05 else None
            if y is None:
                # Below the hips it hangs free over the legs.
                y = (front(x * 0.6, hipz) or 0.14) + 0.02 * f
            row.append(Vector((x, y + 0.03, zz)))
        rows.append(row)
    k.ring_grid(rows, "Leather", closed=False)
    for sx in (-1.0, 1.0):
        sh = bn["upper_arm_" + ("r" if sx > 0 else "l")].head_local
        k.tube([Vector((sx * 0.08, (front(sx * 0.08, cz + 0.05) or 0.12) + 0.03, cz + 0.06)), Vector((sx * 0.06, (front(sx * 0.06, nz) or 0.08) + 0.02, nz)),
                Vector((sx * 0.05, hy - 0.04, nz + 0.03))], [0.01] * 3, "Leather", seg=5, flat=0.4)
    # A pocket with a stub of chalk and a rule in it.
    k.box(Vector((0.03, (front(0.03, hipz + 0.05) or 0.14) + 0.045, hipz + 0.05)), (0.09, 0.012, 0.07), "Leather")
    k.box(Vector((0.05, (front(0.05, hipz + 0.1) or 0.14) + 0.05, hipz + 0.105)), (0.012, 0.01, 0.05), "Paper", rot=(0, 10, 0))
    k.finish(rig, ["chest", "spine", "hips", "skirt_f"], solidify=0.008)

    # Tool belt: a wide belt with pouches, a wrench and a hammer hanging.
    k = Kit("Belt", M)
    k.lathe([(0.16 * GIRTH["hips"][0], hipz - 0.05), (0.165 * GIRTH["hips"][0], hipz - 0.005)], "Leather", seg=28, sx=1.08, sy=0.92)
    for a, sz in ((1.9, (0.06, 0.05, 0.07)), (-1.9, (0.06, 0.05, 0.07)), (2.6, (0.05, 0.045, 0.06))):
        r = 0.2
        k.box(Vector((math.sin(a) * r, math.cos(a) * r * 0.85, hipz - 0.05)), sz, "Leather", rot=(0, 0, -math.degrees(a)))
    w0 = Vector((0.17, 0.03, hipz - 0.05))
    k.tube([w0, w0 + Vector((0.01, 0, -0.13))], [0.011, 0.011], "Iron", seg=6)
    k.lathe([(0.0, w0.z - 0.16), (0.024, w0.z - 0.15), (0.024, w0.z - 0.13), (0.0, w0.z - 0.12)], "Iron", seg=8, center=(w0.x + 0.01, w0.y))
    k.finish(rig, ["hips"])

    # The oath engine on her back: a brass boiler with riveted bands, a
    # window on its glowing core, a stubby flue and two pipes to the shoulders.
    k = Kit("Engine", M)
    by = (behind(0.0, cz) or -0.12) - 0.13
    ez = cz + 0.02
    k.lathe([(0.0, ez - 0.2), (0.1, ez - 0.2), (0.12, ez - 0.17), (0.125, ez + 0.1), (0.11, ez + 0.15), (0.06, ez + 0.19), (0.0, ez + 0.2)],
            "Brass", seg=24, center=(0, by))
    for bz in (ez - 0.12, ez + 0.07):
        k.lathe([(0.128, bz), (0.132, bz + 0.012), (0.128, bz + 0.024)], "Iron", seg=24, center=(0, by))
    k.sphere(Vector((0, by - 0.11, ez - 0.02)), 0.05, "Glow", scale=(1, 0.45, 1), u=12, v=8)
    k.lathe([(0.055, ez - 0.035), (0.06, ez - 0.02), (0.055, ez - 0.005)], "Iron", seg=16, center=(0, by - 0.11))
    k.tube([Vector((0.05, by, ez + 0.17)), Vector((0.06, by, ez + 0.3))], [0.03, 0.026], "Iron", seg=10)
    k.lathe([(0.03, ez + 0.3), (0.042, ez + 0.31), (0.04, ez + 0.33)], "Iron", seg=10, center=(0.06, by))
    for sx in (-1.0, 1.0):
        sh = bn["upper_arm_" + ("r" if sx > 0 else "l")].head_local
        k.tube([Vector((sx * 0.09, by + 0.03, ez + 0.12)), Vector((sx * 0.14, by + 0.06, ez + 0.2)), Vector((sx * abs(sh.x) * 0.8, sh.y - 0.07, sh.z + 0.05))],
               [0.014] * 3, "Brass", seg=6)
        # Straps over the shoulders to the apron.
        k.tube([Vector((sx * 0.07, by + 0.11, ez + 0.13)), Vector((sx * abs(sh.x) * 0.6, sh.y - 0.02, sh.z + 0.04)),
                Vector((sx * abs(sh.x) * 0.6, (front(sx * abs(sh.x) * 0.6, cz + 0.02) or 0.1) + 0.02, cz + 0.02))], [0.01] * 3, "Leather", seg=5, flat=0.4)
    k.finish(rig, ["chest", "spine"])

    # Arms: rolled sleeves, bare forearms, big gloves; the repeater along
    # the right forearm.
    for side in ("r", "l"):
        sh = bn["upper_arm_" + side].head_local
        el = bn["forearm_" + side].head_local
        wr = bn["hand_" + side].head_local
        d = (wr - el).normalized()
        k = Kit("Sleeve_" + side, M)
        k.tube([sh + Vector((0, 0, 0.02)), sh.lerp(el, 0.5), el + d * 0.02], [0.062, 0.06, 0.058], "Robe", seg=12, cap=False)
        k.tube([el - (el - sh).normalized() * 0.03, el + d * 0.025], [0.062, 0.062], "Robe", seg=12, cap=False)
        k.finish(rig, ["upper_arm_" + side, "shoulder_" + side, "chest"], subsurf=1, solidify=0.006)
        k = Kit("Forearm_" + side, M)
        k.tube([el, el.lerp(wr, 0.5), wr], [0.044, 0.042, 0.038], "Skin", seg=12)
        k.tube([el.lerp(wr, 0.62), wr + d * 0.015], [0.05, 0.056], "Leather", seg=12, cap=False)
        k.finish(rig, "forearm_" + side, subsurf=1)
        ck.hand(rig, M, side, "Leather", fist=side == "r")
    el = bn["forearm_r"].head_local
    wr = bn["hand_r"].head_local
    d = (wr - el).normalized()
    up = Vector((0, 0, 1))
    side_v = d.cross(up).normalized()
    top_v = side_v.cross(d).normalized()
    k = Kit("Repeater", M)
    base_p = el.lerp(wr, 0.35) + top_v * 0.065
    tip = wr + d * 0.2 + top_v * 0.065
    k.tube([base_p, tip], [0.036, 0.03], "Brass", seg=8)
    k.tube([tip - d * 0.04, tip + d * 0.03], [0.018, 0.018], "Iron", seg=8)
    # The prod (the bow) across the front, and the drum magazine on top.
    bow = [wr + d * 0.14 + top_v * 0.07 + side_v * s * 0.16 - d * 0.05 * s * s for s in (-1.0, -0.5, 0.0, 0.5, 1.0)]
    k.tube(bow, [0.008, 0.012, 0.015, 0.012, 0.008], "Wood", seg=6)
    k.tube([bow[0], wr + d * 0.02 + top_v * 0.07, bow[-1]], [0.003] * 3, "Paper", seg=4)
    drum = el.lerp(wr, 0.75) + top_v * 0.13
    k.tube([drum - side_v * 0.04, drum + side_v * 0.04], [0.05, 0.05], "Brass", seg=14)
    k.tube([drum - side_v * 0.045, drum + side_v * 0.045], [0.02, 0.02], "Iron", seg=8)
    k.tube([el.lerp(wr, 0.2), el.lerp(wr, 0.2) + top_v * 0.06], [0.012, 0.012], "Iron", seg=6)
    for f in (0.3, 0.7):
        a = el.lerp(wr, f)
        k.tube([a - d * 0.012, a + d * 0.012], [0.05, 0.05], "Leather", seg=12, cap=False)
    k.finish(rig, "forearm_r")

    # Legs: sturdy trousers, heavy boots.
    bf.legs(rig, M, fitted, "ClothDark", "Leather", 1.05, cuff="Leather", offset=0.016)
    return tip + d * 0.03


# ---------------------------------------------------------------- clips

def animate(rig, spec):
    slots = spec["slot_clips"]
    feet = ck.rest_feet(rig)
    # Aim pose: the repeater arm held forward, the left hand steadying it.
    aim = dict(upper_arm_r=(45, 0, 6), forearm_r=(0, 0, 0), upper_arm_l=(38, 0, -30), forearm_l=(-30, 0, 40), spine=(2, 0, 8), chest=(0, 0, 6))
    rest = dict(upper_arm_r=(30, 0, 10), forearm_r=(-20, 0, 0), upper_arm_l=(10, 0, -12), forearm_l=(-30, 0, 0), spine=(2, 0, 0))

    def b(src=rest, **over):
        d = dict(src)
        d.update(over)
        return base(NAMES, **d)

    stance = {"l": (feet["l"][0] - 0.03, feet["l"][1] + 0.08, feet["l"][2]), "r": (feet["r"][0] + 0.03, feet["r"][1] - 0.06, feet["r"][2])}

    ck.idle_clip(rig, 2.4, lambda t, s: (b(spine=(3 + 1.5 * s, 0, 0), head=(-4, 0, 6 * math.sin(t / 2.4 * TAU)),
                                            upper_arm_r=(30 + 2 * s, 0, 10), upper_arm_l=(12 + 2 * s, 0, -12)),
                                          {"hips": (0, 0, -0.02 - 0.006 * s)}), step=4)

    def upper(t, s, c2):
        rots = b(hips=(0, 0, 10 * s), spine=(-10, 0, -6 * s), chest=(-4, 0, -6 * s), head=(8, 0, 4 * s),
                 upper_arm_r=(-30 * s + 20, 0, 12), forearm_r=(-50, 0, 0), upper_arm_l=(40 * s + 5, 0, -12), forearm_l=(-60, 0, 0),
                 skirt_f=(-14 - 8 * c2, 0, 0))
        return rots, {}
    ck.run_clip(rig, spec["move_speed_mps"], upper, cycle=0.42, stance=0.22, hips_drop=0.05, lift=0.15, kick=0.12)

    def shot(name, wind, fire, hip, feet_=stance):
        c = slots[name]
        rel, rec = c["release_s"], c["recovery_s"]
        ck.cast_clip(rig, name, rel, rec, [
            (0, b(), (0, 0, -0.02)),
            (rel * 0.6, b(**wind), (0, -0.02, -0.03)),
            (rel, b(**fire), hip),
            (rel + max(rec, 0.1) * 0.5, b(**fire), hip),
            (rel + max(rec, 0.1), b(), (0, 0, -0.02))], feet_)

    kick = dict(aim, upper_arm_r=(52, 0, 6), forearm_r=(-12, 0, 0), spine=(-2, 0, 8), head=(-4, 0, 0))
    # Repeater: snapped up, fired, the arm kicking back.
    shot("attack", aim, kick, (0, -0.02, -0.03))
    # Breach Bolt: braced low with both hands, a heavy kick.
    brace = dict(aim, spine=(10, 0, 10), chest=(4, 0, 6), upper_arm_l=(50, 0, -40), forearm_l=(-40, 0, 50))
    shot("ability_1", brace, dict(brace, spine=(-6, 0, 10), upper_arm_r=(62, 0, 6), forearm_r=(-25, 0, 0), head=(-10, 0, 0)),
         (0, -0.06, -0.08))
    # Field Sentry: down on one knee, the sentry set on the ground ahead.
    kneel = {"l": (feet["l"][0], feet["l"][1] + 0.16, feet["l"][2]), "r": (feet["r"][0], feet["r"][1] - 0.18, feet["r"][2] + 0.02)}
    shot("ability_2", dict(spine=(20, 0, 0), upper_arm_l=(40, 0, -10), forearm_l=(-60, 0, 0)),
         dict(spine=(34, 0, 0), chest=(10, 0, 0), head=(-20, 0, 0), upper_arm_l=(55, 0, -6), forearm_l=(-10, 0, 0), upper_arm_r=(20, 0, 20)),
         (0, 0.02, -0.16), kneel)
    # Masterwork Battery: the repeater raised over the shoulder, both hands.
    shot("ability_3", dict(aim, upper_arm_r=(90, 0, 10), forearm_r=(-40, 0, 0), upper_arm_l=(80, 0, -30), forearm_l=(-60, 0, 30)),
         dict(aim, upper_arm_r=(70, 0, 6), forearm_r=(-20, 0, 0), upper_arm_l=(60, 0, -36), forearm_l=(-40, 0, 40), spine=(-8, 0, 8),
              head=(-6, 0, 0)), (0, -0.03, -0.04))
    # Emergency Vent: hunched, arms thrown out as the boiler blows.
    shot("ability_4", dict(spine=(14, 0, 0), upper_arm_r=(20, 0, 30), upper_arm_l=(20, 0, -30)),
         dict(spine=(-12, 0, 0), chest=(-8, 0, 0), head=(-14, 0, 0), upper_arm_r=(30, 0, 80), forearm_r=(-10, 0, 0),
              upper_arm_l=(30, 0, -80), forearm_l=(-10, 0, 0)), (0, -0.02, -0.06), feet)

    ck.death_clip(rig, NAMES)


def main():
    import sys
    out = ck.out_path(sys.argv, "/tmp/brasswright.blend")
    spec = ck.load_spec("brasswright")
    ck.reset()
    rig = ck.make_rig(bones())
    M = ck.Mats()
    tip = build_model(rig, M)
    ck.socket("Muzzle", rig, "forearm_r", tip)
    ox, oy, oz = spec["sockets"]["Overhead"]
    ck.socket("Overhead", rig, "root", (ox, -oz, oy))
    animate(rig, spec)
    ck.save(out)


if __name__ == "__main__":
    main()
