# SPDX-License-Identifier: GPL-2.0-or-later
# (Uses Blender's Python API. This is a build tool, not part of the game.)
"""Build the Oathwarden champion model, rig and clips, all from code.

  /opt/bpyenv/bin/python tools/blender/build_oathwarden.py OUT.blend

A broad armoured knight: lathed breastplate and faulds over a mail skirt,
layered pauldrons, a great helm with a team crest, a tower shield on the
left forearm and a maul in the right hand. Original geometry written as code.
Then export with tools/blender/export_champion.py and check with
tools/check_assets.gd.
"""
import math

import bpy  # noqa: F401,I001  (bpy first: it makes mathutils importable)
from mathutils import Vector

import champion_kit as ck
from champion_kit import TAU, Kit, base, pose

S = 1.04   # height scale against the shared skeleton
W = 1.15   # shoulder and hip width

NAMES = ck.BODY + ["shield", "maul"]


def bones():
    b = ck.humanoid_bones(S, W)
    hr_h, hr_t = Vector(b["hand_r"][0]), Vector(b["hand_r"][1])
    palm = hr_h + (hr_t - hr_h).normalized() * 0.06
    fl_h, fl_t = Vector(b["forearm_l"][0]), Vector(b["forearm_l"][1])
    mid = fl_h.lerp(fl_t, 0.5)
    b["shield"] = (tuple(mid), tuple(mid + Vector((0, 0, 0.2))), "forearm_l")
    b["maul"] = (tuple(palm), tuple(palm + Vector((0, 0, 0.3))), "hand_r")
    return b


def plate_keel(th, z, r):
    # A ridge down the middle of the breastplate.
    return r + 0.014 * max(0.0, math.cos(th)) ** 10


def build_model(rig, M):
    bn = rig.data.bones
    z = lambda v: v * S  # noqa: E731

    # Breastplate over the torso, with a keel and a rolled top edge.
    k = Kit("Cuirass", M)
    prof = [(0.19, 0.95), (0.198, 1.02), (0.205, 1.12), (0.238, 1.25), (0.25, 1.34), (0.232, 1.43), (0.17, 1.495), (0.11, 1.52)]
    k.lathe([(r * S, z(h)) for r, h in prof], "Steel", seg=32, sx=1.2, sy=0.86, fold=plate_keel)
    k.lathe([(0.115 * S, z(1.515)), (0.12 * S, z(1.535)), (0.105 * S, z(1.55))], "Trim", seg=24, sx=1.2, sy=0.9)
    # A team plate on the chest with a gold seal on it.
    c = Vector((0, 0.25 * 0.86 * S + 0.012, z(1.3)))
    k.box(c, (0.17, 0.018, 0.2), "Team", rot=(-8, 0, 0))
    k.box(c + Vector((0, 0.011, 0.0)), (0.08, 0.006, 0.08), "Trim", rot=(-8, 0, 45))
    k.finish(rig, ["chest", "spine", "hips"], subsurf=1)

    # Faulds: three overlapping steel bands below the waist, each stepping out.
    k = Kit("Faulds", M)
    for i in range(3):
        top = z(0.99 - i * 0.065)
        k.lathe([(0.2 * S + i * 0.018, top), (0.214 * S + i * 0.02, top - 0.085)], "Steel", seg=32, sx=1.2, sy=0.9)
    k.lathe([(0.2 * S, z(1.0)), (0.205 * S, z(1.045))], "Leather", seg=32, sx=1.21, sy=0.88)
    k.box(Vector((0, 0.205 * 0.88 * S + 0.01, z(1.022))), (0.07, 0.02, 0.06), "Brass")
    k.finish(rig, ["hips", "spine"], subsurf=1)

    # Mail skirt to the knees.
    k = Kit("MailSkirt", M)
    k.lathe([(0.21 * S, z(0.96)), (0.25 * S, z(0.8)), (0.275 * S, z(0.64)), (0.285 * S, z(0.56))], "Mail", seg=32, sx=1.12, sy=0.95)
    k.finish(rig, ["hips", "thigh_l", "thigh_r", "skirt_f", "skirt_b"], subsurf=1, solidify=0.01)

    # Tabard: a team panel at the front from the belt to below the mail, gold
    # edged, swinging with the front skirt bone.
    k = Kit("Tabard", M)
    rows = []
    for j in range(7):
        zz = z(0.98) - j * 0.085
        f = j / 6.0
        y = (0.22 + 0.06 * f) * 0.95 * S + 0.03
        w = 0.11 + 0.02 * f
        rows.append([Vector((u * w, y + 0.01 * (1 - u * u), zz)) for u in (-1.0, -0.5, 0.0, 0.5, 1.0)])
    k.ring_grid(rows, "Team", closed=False)
    for sd in (-1.0, 1.0):
        strip = [[Vector((r[0 if sd < 0 else 4].x + sd * dx, r[0].y + 0.004, r[0].z)) for dx in (-0.014, 0.014)] for r in rows]
        k.ring_grid(strip, "Trim", closed=False)
    hem = [[Vector((p.x, p.y + 0.004, p.z + dz)) for p in rows[-1]] for dz in (0.0, 0.035)]
    k.ring_grid(hem, "Trim", closed=False)
    k.finish(rig, ["skirt_f", "hips"], solidify=0.008)

    # Cape: a team cape from under the pauldrons to the calves.
    k = Kit("Cape", M)
    rows = []
    for j in range(9):
        zz = z(1.44) - j * 0.118
        w = 0.3 + j * 0.02
        row = []
        for i in range(11):
            u = (i / 10.0) * 2.0 - 1.0
            y = -0.25 * S - 0.06 * (1 - u * u) - j * 0.014
            hz = zz - (0.035 * abs(math.sin(u * 4.7)) if j == 8 else 0.0)
            row.append(Vector((u * w, y + 0.012 * math.sin(u * 9.0 + j), hz)))
        rows.append(row)
    k.ring_grid(rows, "Team", closed=False)
    hem = [[Vector((p.x, p.y - 0.004, p.z + dz)) for p in rows[-1]] for dz in (0.0, 0.05)]
    k.ring_grid(hem, "Trim", closed=False)
    k.finish(rig, ["chest", "cape", "spine"], subsurf=1, solidify=0.01)

    # Pauldrons: three layered steel lames on each shoulder, gold rimmed.
    for side, sx in (("r", 1.0), ("l", -1.0)):
        k = Kit("Pauldron_" + side, M)
        top = bn["upper_arm_" + side].head_local
        for i, (dx, dz, r, sc) in enumerate(((0.035, 0.05, 0.15, (1.0, 1.1, 0.72)), (0.07, -0.005, 0.135, (0.9, 1.05, 0.6)),
                                             (0.09, -0.06, 0.115, (0.85, 1.0, 0.55)))):
            k.sphere(top + Vector((sx * dx, 0, dz)), r, "Steel", scale=sc, u=20, v=10)
        rim = [top + Vector((sx * 0.035 + math.cos(a) * 0.152, math.sin(a) * 0.165, 0.035)) for a in [i / 20 * TAU for i in range(21)]]
        k.tube(rim, [0.012] * len(rim), "Trim", seg=6, cap=False)
        k.finish(rig, "shoulder_" + side)

    # Arms: mail sleeves, steel vambraces and elbow cops, gauntlets.
    for side in ("r", "l"):
        ck.sleeve(rig, M, side, "Mail", radii=(0.088, 0.08, 0.072, 0.068, 0.068))
        el = bn["forearm_" + side].head_local
        wr = bn["hand_" + side].head_local
        d = (wr - el).normalized()
        k = Kit("Vambrace_" + side, M)
        k.tube([el + d * 0.05, el.lerp(wr, 0.6), wr + d * 0.01], [0.072, 0.074, 0.07], "Steel", seg=14)
        k.tube([wr - d * 0.005, wr + d * 0.045], [0.074, 0.085], "Steel", seg=14, cap=False)
        k.tube([el.lerp(wr, 0.25), el.lerp(wr, 0.25) + d * 0.02], [0.077, 0.077], "Trim", seg=14, cap=False)
        k.finish(rig, "forearm_" + side, subsurf=1)
        k = Kit("Cop_" + side, M)
        k.sphere(el + Vector((0, -0.02, 0)), 0.06, "Steel", scale=(1.0, 0.9, 1.0), u=14, v=8)
        k.finish(rig, "upper_arm_" + side)
        ck.hand(rig, M, side, "Iron", fist=True)

    # Legs: mail, steel cuisses, knee cops, greaves and sabatons.
    ck.limbs(rig, M, legs="Mail", boots="Steel", hands=None, leg_r=(0.098, 0.088, 0.072, 0.066), boot_scale=1.15, cuff="Steel")
    for side in ("l", "r"):
        hip = bn["thigh_" + side].head_local
        knee = bn["shin_" + side].head_local
        k = Kit("Cuisse_" + side, M)
        k.tube([hip.lerp(knee, 0.3), hip.lerp(knee, 0.65), knee + Vector((0, 0.01, 0.02))], [0.1, 0.095, 0.085], "Steel", seg=12)
        k.finish(rig, "thigh_" + side, subsurf=1)
        k = Kit("Knee_" + side, M)
        k.sphere(knee + Vector((0, 0.05, 0)), 0.058, "Steel", scale=(1.0, 0.8, 1.1), u=14, v=8)
        k.box(knee + Vector((0, 0.1, 0)), (0.03, 0.02, 0.03), "Trim", rot=(0, 45, 0))
        k.finish(rig, "shin_" + side)

    # Gorget and great helm: a tall rounded helm with a dark eye slit, glowing
    # eyes inside it, a gold brow band, a nose ridge and a team crest.
    hz = bn["head"].head_local.z
    hy = bn["head"].head_local.y
    k = Kit("Gorget", M)
    k.lathe([(0.15, z(1.46)), (0.125, z(1.5)), (0.1, z(1.56)), (0.095, z(1.6))], "Steel", seg=24, sx=1.15, sy=1.0)
    k.finish(rig, ["neck", "chest"], subsurf=1)
    k = Kit("Helm", M)
    hp = [(0.092, -0.06), (0.118, -0.01), (0.13, 0.07), (0.127, 0.15), (0.104, 0.215), (0.055, 0.255), (0.004, 0.265)]
    k.lathe([(r, hz + dz) for r, dz in hp], "Steel", seg=28, sx=0.94, sy=1.06, center=(0, hy))
    k.lathe([(0.133, hz + 0.115), (0.132, hz + 0.135)], "Trim", seg=28, sx=0.94, sy=1.06, center=(0, hy))
    fy = hy + 0.13 * 1.06
    k.box(Vector((0, fy - 0.002, hz + 0.08)), (0.16, 0.02, 0.022), "RobeInner")
    k.sphere((0.034, fy + 0.005, hz + 0.08), 0.011, "Eyes", scale=(1.6, 0.5, 0.6), u=8, v=6)
    k.sphere((-0.034, fy + 0.005, hz + 0.08), 0.011, "Eyes", scale=(1.6, 0.5, 0.6), u=8, v=6)
    k.tube([(0, fy - 0.004, hz - 0.05), (0, fy + 0.004, hz + 0.06), (0, fy - 0.006, hz + 0.2)], [0.012, 0.014, 0.01], "Steel", seg=6)
    crest = [(0, hy + 0.06, hz + 0.25), (0, hy - 0.02, hz + 0.3), (0, hy - 0.12, hz + 0.28), (0, hy - 0.2, hz + 0.19), (0, hy - 0.24, hz + 0.06)]
    k.tube(crest, [0.02, 0.045, 0.05, 0.04, 0.012], "Team", seg=10, flat=0.35)
    k.finish(rig, "head", subsurf=1)

    # Tower shield on the left forearm: a tall curved board, team faced, a
    # steel rim, and a gold seal with a break in it at its middle.
    fl0 = bn["forearm_l"].head_local
    fl1 = bn["forearm_l"].tail_local
    n = Vector((-0.8, 0.6, 0)).normalized()
    t = Vector((0.6, 0.8, 0)).normalized()
    up = Vector((0, 0, 1))
    c = fl0.lerp(fl1, 0.5) + n * 0.1
    c.z = z(1.0)

    def sp(u, v, lift=0.0):
        hw = 0.31 if v > -0.3 else 0.31 - (-0.3 - v) * 0.55
        return c + t * (u * hw) + up * (v * 0.56) + n * (0.08 * (1 - u * u) + lift)

    k = Kit("Shield", M)
    k.ring_grid([[sp(i / 8 * 2 - 1, -0.5 + j / 10) for i in range(9)] for j in range(11)], "Team", closed=False)
    rim = [sp(-1, -0.5 + j / 10, 0.01) for j in range(11)][::-1] + [sp(1, -0.5 + j / 10, 0.01) for j in range(11)]
    k.tube([sp(-1, 0.5, 0.01)] + [sp(i / 8 * 2 - 1, 0.5, 0.01) for i in range(9)], [0.022] * 10, "Steel", seg=6)
    k.tube(rim, [0.022] * len(rim), "Steel", seg=6)
    ring = []
    for i in range(23):
        a = 0.35 + i / 22 * (TAU - 0.7)
        ring.append(sp(math.sin(a) * 0.48, math.cos(a) * 0.26 + 0.08, 0.012))
    k.tube(ring, [0.022] * len(ring), "Trim", seg=8)
    k.sphere(sp(0, 0.08, 0.02), 0.05, "Brass", scale=(1, 1, 1))
    for v in (-0.25, -0.38):
        k.tube([sp(-0.55, v, 0.008), sp(0, v, 0.012), sp(0.55, v, 0.008)], [0.012] * 3, "Trim", seg=6)
    k.finish(rig, "shield", solidify=0.035)

    # Maul: an ash haft with a leather grip, a heavy steel head banded in
    # brass with glowing oath runes on its faces.
    p = bn["maul"].head_local
    k = Kit("Maul", M)
    k.tube([p - up * 0.4, p + up * 0.62], [0.024, 0.026], "Wood", seg=8)
    k.tube([p - up * 0.09, p + up * 0.09], [0.029, 0.029], "Leather", seg=8)
    k.sphere(p - up * 0.42, 0.04, "Brass")
    hc = p + up * 0.72
    fw = Vector((0, 1, 0))
    k.tube([hc - fw * 0.17, hc - fw * 0.15, hc + fw * 0.15, hc + fw * 0.17], [0.07, 0.088, 0.088, 0.07], "Steel", seg=8)
    for dy in (-0.15, 0.15):
        k.tube([hc + fw * (dy - 0.022), hc + fw * (dy + 0.022)], [0.094, 0.094], "Iron", seg=8, cap=False)
    for dy in (-0.06, 0.06):
        k.tube([hc + fw * (dy - 0.01), hc + fw * (dy + 0.01)], [0.091, 0.091], "Brass", seg=8, cap=False)
    for sd in (-1.0, 1.0):
        k.box(hc + Vector((sd * 0.086, 0, 0)), (0.006, 0.05, 0.05), "Glow", rot=(45, 0, 0))
        k.box(hc + Vector((0, 0, sd * 0.086)), (0.05, 0.05, 0.006), "Glow", rot=(0, 0, 45))
    k.tube([hc - up * 0.085, hc - up * 0.16], [0.04, 0.03], "Iron", seg=8)
    k.finish(rig, "maul")


# ---------------------------------------------------------------- clips

def animate(rig, spec):
    slots = spec["slot_clips"]
    feet = ck.rest_feet(rig)
    rest = dict(upper_arm_r=(6, 0, 4), forearm_r=(-4, 0, 0), upper_arm_l=(28, 0, -8), forearm_l=(-20, 0, 0), shield=(0, 0, 0))

    def b(**over):
        d = dict(rest)
        d.update(over)
        return base(NAMES, **d)

    # Idle: a heavy, settled breath; the shield held a little forward, the
    # maul hanging in the right fist, the cape stirring.
    ck.idle_clip(rig, 2.8, lambda t, s: (b(spine=(1.5 * s, 0, 0), chest=(-1 * s, 0, 1 * s), head=(1.5 * s, 0, 4 * math.sin(t / 2.8 * TAU)),
                                            upper_arm_r=(6 + 2 * s, 0, 4), upper_arm_l=(28 + 1.5 * s, 0, -8), cape=(1.5 * s, 0, 0),
                                            skirt_f=(-0.5 * s, 0, 0)),
                                          {"hips": (0, 0, -0.02 - 0.008 * s)}))

    # Run: heavy strides, the shield carried across the body, the maul at an
    # angle, the cape streaming.
    def upper(t, s, c2):
        rots = b(hips=(0, 0, 7 * s), spine=(-9, 0, -4 * s), chest=(-3, 0, -5 * s), head=(8, 0, 2 * s),
                 upper_arm_r=(-28 * s + 12, 0, 8), forearm_r=(-35 - 12 * s, 0, 0), maul=(-30, 0, 0),
                 upper_arm_l=(36 + 6 * s, 0, -10), forearm_l=(-30, 0, 0),
                 skirt_f=(-12 - 6 * c2, 0, 0), skirt_b=(22 + 5 * c2, 0, 0), cape=(28 + 6 * c2, 0, 0))
        return rots, {}
    ck.run_clip(rig, spec["move_speed_mps"], upper, cycle=0.62, stance=0.21, hips_drop=0.08, lift=0.22, kick=0.18)

    # Cleave: the maul is hauled up over the right shoulder, then swept down
    # and across the front to the left on release.
    c = slots["attack"]
    rel, rec = c["release_s"], c["recovery_s"]
    ck.cast_clip(rig, "attack", rel, rec, [
        (0, b(), (0, 0, -0.02)),
        (rel * 0.6, b(spine=(4, 0, -14), chest=(-4, 0, -26), upper_arm_r=(140, 0, -25), forearm_r=(-80, 0, 0), maul=(-90, 0, 0),
                      upper_arm_l=(45, 0, 10)), (0, -0.04, -0.05)),
        (rel, b(spine=(14, 0, 14), chest=(8, 0, 28), head=(-6, 0, -10), upper_arm_r=(60, 0, 35), forearm_r=(-20, 0, 0), maul=(80, 0, 0),
                upper_arm_l=(30, 0, -20)), (0, 0.08, -0.1)),
        (rel + rec * 0.5, b(spine=(12, 0, 16), chest=(6, 0, 30), upper_arm_r=(40, 0, 55), forearm_r=(-10, 0, 0), maul=(95, 0, 0),
                            upper_arm_l=(28, 0, -20)), (0, 0.07, -0.1)),
        (rel + rec, b(), (0, 0, -0.02))], feet)

    # Warding Stand: a wide crouch, the shield driven down in front and the
    # maul raised behind it.
    c = slots["ability_1"]
    rel, rec = c["release_s"], c["recovery_s"]
    wide = {"l": (feet["l"][0] - 0.08, feet["l"][1] + 0.12, feet["l"][2]), "r": (feet["r"][0] + 0.08, feet["r"][1] - 0.1, feet["r"][2])}
    ck.cast_clip(rig, "ability_1", rel, rec, [
        (0, b(), (0, 0, -0.02)),
        (rel * 0.6, b(spine=(-6, 0, 0), chest=(-4, 0, 6), upper_arm_l=(80, 0, 10), forearm_l=(-50, 0, 0), shield=(-10, 0, 0),
                      upper_arm_r=(100, 0, -10), forearm_r=(-40, 0, 0)), (0, -0.02, 0.02)),
        (rel, b(spine=(10, 0, 0), chest=(6, 0, 4), head=(-8, 0, 0), upper_arm_l=(55, 0, 12), forearm_l=(-35, 0, 0), shield=(5, 0, 0),
                upper_arm_r=(115, 0, -14), forearm_r=(-55, 0, 0), maul=(10, 0, 0), cape=(12, 0, 0)), (0, 0.04, -0.2)),
        (rel + rec, b(spine=(8, 0, 0), upper_arm_l=(50, 0, 10), forearm_l=(-30, 0, 0), upper_arm_r=(100, 0, -12), forearm_r=(-50, 0, 0)),
         (0, 0.03, -0.16))], wide)

    # Shield Slam: the shield is drawn back to the chest, then driven forward
    # in a lunge on release.
    c = slots["ability_2"]
    rel, rec = c["release_s"], c["recovery_s"]
    lunge = {"l": (feet["l"][0], feet["l"][1] + 0.3, feet["l"][2]), "r": (feet["r"][0], feet["r"][1] - 0.22, feet["r"][2])}
    ck.cast_clip(rig, "ability_2", rel, rec, [
        (0, b(), (0, 0, -0.02)),
        (rel * 0.65, b(spine=(-8, 0, -14), chest=(-6, 0, -18), upper_arm_l=(30, 0, 40), forearm_l=(-70, 0, 0), shield=(0, 0, 25),
                       upper_arm_r=(-10, 0, 10), forearm_r=(-20, 0, 0)), (0, -0.08, -0.06)),
        (rel, b(spine=(16, 0, 14), chest=(10, 0, 18), head=(-10, 0, -8), upper_arm_l=(85, 0, 4), forearm_l=(-15, 0, 0), shield=(0, 0, -5),
                upper_arm_r=(-20, 0, 10), forearm_r=(-30, 0, 0)), (0, 0.16, -0.14)),
        (rel + rec * 0.5, b(spine=(12, 0, 10), chest=(8, 0, 12), upper_arm_l=(78, 0, 4), forearm_l=(-18, 0, 0), upper_arm_r=(-12, 0, 8)),
         (0, 0.13, -0.12)),
        (rel + rec, b(), (0, 0, -0.02))], lunge)

    # Unbroken Oath: the maul is lifted high to the sky in the right hand,
    # the shield held across the chest, the body upright and planted.
    c = slots["ability_3"]
    rel, rec = c["release_s"], c["recovery_s"]
    ck.cast_clip(rig, "ability_3", rel, rec, [
        (0, b(), (0, 0, -0.02)),
        (rel * 0.6, b(spine=(4, 0, 0), chest=(2, 0, 0), upper_arm_r=(120, 0, -10), forearm_r=(-60, 0, 0), maul=(-40, 0, 0),
                      upper_arm_l=(50, 0, 20), forearm_l=(-60, 0, 0)), (0, 0, -0.08)),
        (rel, b(spine=(-8, 0, 0), chest=(-6, 0, 0), head=(-18, 0, 0), upper_arm_r=(168, 0, -12), forearm_r=(-12, 0, 0), maul=(-140, 0, 0),
                upper_arm_l=(60, 0, 26), forearm_l=(-70, 0, 0), cape=(-8, 0, 0)), (0, 0, 0.0)),
        (rel + rec, b(spine=(-6, 0, 0), head=(-12, 0, 0), upper_arm_r=(160, 0, -12), forearm_r=(-15, 0, 0), maul=(-136, 0, 0),
                      upper_arm_l=(58, 0, 24), forearm_l=(-70, 0, 0)), (0, 0, -0.01))], feet)

    ck.death_clip(rig, NAMES, lambda t: {"shield": (0, 0, 0), "maul": (-40 * min(1.0, t / 0.6), 0, 0)})


def main():
    import sys
    out = ck.out_path(sys.argv, "/tmp/oathwarden.blend")
    spec = ck.load_spec("oathwarden")
    ck.reset()
    rig = ck.make_rig(bones())
    M = ck.Mats()
    build_model(rig, M)
    hr = rig.data.bones["hand_r"]
    ck.socket("Muzzle", rig, "hand_r", hr.head_local + (hr.tail_local - hr.head_local).normalized() * 0.11)
    ox, oy, oz = spec["sockets"]["Overhead"]
    ck.socket("Overhead", rig, "root", (ox, -oz, oy))
    mp = rig.data.bones["maul"].head_local
    ck.socket("Focus", rig, "maul", mp + Vector((0, 0, 0.72)))
    animate(rig, spec)
    ck.save(out)


if __name__ == "__main__":
    main()
