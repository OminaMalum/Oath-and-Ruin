# SPDX-License-Identifier: GPL-2.0-or-later
# (Uses Blender's Python API. This is a build tool, not part of the game.)
"""Build the Thornwright champion model, rig and clips, all from code.

  /opt/bvenv/bin/python tools/blender/build_thornwright.py OUT.blend

Saela Briar, a wood elf ranger: her hood up over copper hair, with a plait
falling out of it over her left shoulder, a laced leather jerkin over linen
sleeves and a green split tunic, a team cape, a quiver of fletched arrows and
a recurve bow wound with living vine. Her head, arms and hands are the CC0 Blender Studio body
(figure_kit.py); everything else is geometry written here, and every surface
carries baked shading and wear in its vertex colours.
"""
import math
import os

import bpy  # noqa: F401,I001  (bpy first: it makes mathutils importable)
from mathutils import Vector, noise

import body_fit as bf
import champion_kit as ck
import figure_kit as fk
from champion_kit import TAU, Kit, base

S = 0.95
W = 1.0
HEAD = 0.82  # the base mesh's head is a cartoon's; hers is nearer an adult's

NAMES = ck.BODY + ["bow", "plait"]
# The braid's path: from behind the hood's edge, over the collar and down the cowl.
BRAID = [(-0.097, 0.026, 1.5), (-0.09, 0.058, 1.462), (-0.07, 0.08, 1.427), (-0.08, 0.108, 1.39), (-0.083, 0.128, 1.345),
         (-0.08, 0.137, 1.3), (-0.076, 0.141, 1.255), (-0.073, 0.14, 1.215)]
PARTS = set(filter(None, os.environ.get("TW_PARTS", "").split(",")))  # build only these (for quick looks)


def want(part):
    return not PARTS or part in PARTS


def bones():
    b = ck.humanoid_bones(S, W)
    h, t = Vector(b["hand_l"][0]), Vector(b["hand_l"][1])
    palm = h + (t - h).normalized() * 0.07
    # Re-seated in the fist once the fingers are curled (build_model).
    b["bow"] = (tuple(palm), tuple(palm + Vector((0, 0.27, 0.13))), "hand_l")
    # The braid that falls out of the hood over her left shoulder.
    b["plait"] = (BRAID[3], BRAID[-1], "chest")
    return b


def hairline(az):
    """Elevation of the hairline (degrees round the head, 0 is the face)."""
    a = abs(az)
    if a < 40:
        return 37.0 - 8.0 * (a / 40.0) ** 2
    if a < 52:
        return 29.0 - 24.0 * (a - 40) / 12.0
    if a < 118:
        return 5.0 - 3.0 * fk.smooth(52, 62, a)
    return 2.0 - 40.0 * fk.smooth(118, 132, a)


def build_head(rig, M, fig, painters):
    k = Kit("Head", M)

    def skin(i, o, p):
        if o in ("head", "neck"):
            return True
        return o == "chest" and p.z > 1.24 and p.y > -0.02 and abs(p.x) < 0.1  # the throat inside the collar
    fig.add(k, "Skin", skin)
    fig.skin_head(k.finish(rig, ["neck", "chest"]))
    painters.append(fig.face_paint(lips=(0.94, 0.66, 0.64), blush=(1.05, 0.9, 0.88)))

    k, eye_paint = fig.eyes(M, iris=(0.2, 0.55, 0.22))
    painters.append(eye_paint)
    fig.brows(k, "HairCopper")
    k.finish(rig, "head")["ao"] = 0.35  # lids sit deep in the sockets; keep them skin, not shadow

    # Hair: a close cap, then locks swept back from the hairline to a tie at
    # the back of the crown, a second layer over the top, and the nape drawn up.
    k = Kit("Hair", M)
    fig.scalp(k, "HairCopper", hairline, offset=0.008)
    tie = (180.0, 40.0)
    seed = 0
    for sx in (-1, 1):
        for a in range(3 if sx > 0 else 10, 84, 7):  # further back it is all under the hood
            seed += 1
            el = hairline(a) - 1.0
            if a < 40:
                via = (sx * a * 0.7, 80.0)
            elif a < 125:
                via = (sx * (a + (180 - a) * 0.5), 50.0)
            else:
                via = None
            fig.lock(k, "HairCopper", (sx * a, el), tie, via=via, width=0.04, n=11, seed=seed, thick=0.36, lift=0.007,
                     body=0.007 if via is None else 0.011)
        for a in (20, 62):  # an upper layer, for depth
            seed += 1
            fig.lock(k, "HairCopper", (sx * a, 48.0), tie, via=(sx * (a + (180 - a) * 0.6), 66.0), width=0.034, lift=0.014,
                     body=0.007, n=8, seed=seed, thick=0.4)
        # A loose strand in front of each ear, curling in at the jaw.
        pts = [fig.on_head(fig.direction(sx * (51.0 - 1.2 * i), 9.0 - 8.5 * i), 0.004 + 0.0012 * i) for i in range(6)]
        fk.strand(k, pts, [0.003, 0.006, 0.006, 0.005, 0.0035, 0.001], "HairCopper", seed=seed + 40, thick=0.6, seg=6)
    k.finish(rig, "head")

    # The braid: three strands crossing over each other, tied near the end.
    k = Kit("Braid", M)
    path = [Vector(p) for p in BRAID]
    fine = []
    for i in range(len(path) - 1):
        p0, p1, p2, p3 = path[max(i - 1, 0)], path[i], path[i + 1], path[min(i + 2, len(path) - 1)]
        for j in range(6):
            t = j / 6.0
            fine.append(0.5 * ((2 * p1) + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (3 * p1 - p0 - 3 * p2 + p3) * t ** 3))
    fine.append(path[-1])
    n = len(fine)
    for j in range(3):
        pts, rad = [], []
        for i, p in enumerate(fine):
            f = i / (n - 1.0)
            tan = (fine[min(i + 1, n - 1)] - fine[max(i - 1, 0)]).normalized()
            side = Vector((1, 0, 0))
            side = (side - tan * side.dot(tan)).normalized()
            out = side.cross(tan)
            if out.y < 0:
                out = -out
            ph = f * 27.0 + j * TAU / 3.0
            amp = 0.0105 * (1.0 - 0.45 * fk.smooth(0.8, 1.0, f))
            pts.append(p + side * math.sin(ph) * amp + out * math.sin(2.0 * ph) * amp * 0.5)
            rad.append(0.0098 * (1.0 - 0.5 * fk.smooth(0.82, 1.0, f)))
        fk.sweep(k, pts, rad, rad, "HairCopper", seg=7)
    # The tie, and the loose end below it.
    ti = n - 5
    tan = (fine[ti + 1] - fine[ti - 1]).normalized()
    side = (Vector((1, 0, 0)) - tan * tan.x).normalized()
    out = side.cross(tan)
    ring = [fine[ti] + (side * math.cos(i / 10 * TAU) + out * math.sin(i / 10 * TAU)) * 0.0155 for i in range(11)]
    fk.sweep(k, ring, 0.0045, 0.0045, "Leather", seg=6, cap=False)
    for j in range(5):
        a = j / 5 * TAU
        d = (side * math.cos(a) + out * math.sin(a)) * 0.006
        pts = [fine[-1] - tan * 0.012 + d, fine[-1] + tan * 0.02 + d * 1.9, fine[-1] + tan * 0.05 + d * 2.3 + Vector((0, 0.004, 0)),
               fine[-1] + tan * 0.075 + d * 1.6 + Vector((0, 0.006, 0))]
        fk.strand(k, pts, [0.007, 0.0075, 0.005, 0.001], "HairCopper", seed=70 + j, thick=0.7, seg=6)
    k.finish(rig, ["plait"])


def build_body(rig, M, fig):
    bn = rig.data.bones

    # Jerkin: fitted leather over the chest and waist, open in a V at the
    # throat, flared a little below the belt, laced down the front.
    k = Kit("Jerkin", M)

    def jerkin(i, o, p):
        if o not in fk.TORSO or p.z < 0.975:
            return False
        return not (p.y > 0 and p.z > 1.31 + abs(p.x) * 1.25)

    def flare(i, p):
        return 0.013 + 0.014 * (1.0 - fk.smooth(0.975, 1.07, p.z)) + 0.0025 * noise.noise(p * 14.0)
    for loop in fig.add(k, "Leather", jerkin, offset=flare):
        bf.rim(k, loop, 0.007, "Leather")
    for sx in (-1, 1):  # the welts the laces run through
        pts = [fig.onto((sx * 0.021, 0.5, z), (sx * 0.021, 0.0, z), 0.017, fk.TORSO) for z in (1.262, 1.22, 1.18, 1.14, 1.1)]
        fk.tint(fk.sweep(k, pts, 0.0065, 0.004, "Leather", seg=6, side=Vector((1, 0, 0))), -0.25, k)
    for i in range(5):
        z0 = 1.25 - i * 0.036
        for sx in (-1, 1):
            a = fig.onto((sx * 0.021, 0.5, z0), (sx * 0.021, 0.0, z0), 0.023, fk.TORSO)
            b = fig.onto((-sx * 0.021, 0.5, z0 - 0.03), (-sx * 0.021, 0.0, z0 - 0.03), 0.023, fk.TORSO)
            fk.sweep(k, [a, a.lerp(b, 0.5) + Vector((0, 0.003, 0)), b], 0.003, 0.003, "Cloth", seg=5)
    k.finish(rig, ["chest", "spine", "hips"])

    # Belt at the waist with a brass buckle and a hanging tail, and the
    # baldric that carries the quiver, from the right shoulder to the left hip.
    k = Kit("Straps", M)
    fig.strap(k, "Leather", (0, -0.01, 1.085), (0, 1, 0), (1, 0, 0), width=0.042, lift=0.02, n=40, tint_by=-0.12)
    sling = fig.strap(k, "Leather", (-0.005, -0.01, 1.21), (0.105, 0, 0.19), (0, 1, 0), width=0.04, lift=0.018, n=44, tint_by=-0.35,
                      owners=fk.TORSO + ("thigh_l", "thigh_r"))
    k.finish(rig, ["chest", "spine", "hips"], solidify=0.005)
    k = Kit("Gear", M)
    bk = fig.around(1.085, 0.0, 0.026, centre=(0, -0.01))
    for dx, dz, sx_, sz_ in ((0, 0.024, 0.056, 0.008), (0, -0.024, 0.056, 0.008), (-0.024, 0, 0.008, 0.056), (0.024, 0, 0.008, 0.056)):
        k.box(bk + Vector((dx, 0.002, dz)), (sx_, 0.009, sz_), "Brass")
    k.box(bk + Vector((0.004, 0.004, 0)), (0.04, 0.005, 0.006), "Brass")
    tail = [bk + Vector(d) for d in ((0.03, 0.0, 0.0), (0.075, -0.012, -0.012), (0.095, -0.02, -0.06), (0.098, -0.022, -0.12))]
    fk.sweep(k, tail, 0.016, 0.0035, "Leather", seg=6, side=Vector((0, -0.3, 1)))
    # A pouch on the right hip and a knife at the left.
    hip = fig.around(1.03, math.radians(62), 0.03, centre=(0, -0.01))
    k.sphere(hip + Vector((0.012, 0.01, -0.04)), 0.045, "Leather", scale=(0.8, 0.62, 1.0), u=12, v=8)
    k.box(hip + Vector((0.012, 0.016, -0.012)), (0.07, 0.05, 0.036), "Leather", rot=(8, 0, -62))
    k.sphere(hip + Vector((0.028, 0.034, -0.03)), 0.008, "Brass", u=8, v=6)
    kn = fig.around(1.04, math.radians(-68), 0.03, centre=(0, -0.01))
    d = Vector((-0.02, 0.1, -0.99)).normalized()
    fk.sweep(k, [kn + d * 0.0, kn + d * 0.13, kn + d * 0.2], [0.02, 0.016, 0.004], [0.01, 0.008, 0.003], "Leather", seg=8,
             side=Vector((0, 1, 0)))
    fk.sweep(k, [kn - d * 0.005, kn - d * 0.075], [0.011, 0.012], [0.009, 0.01], "Wood", seg=8, side=Vector((0, 1, 0)))
    k.box(kn - d * 0.004, (0.012, 0.05, 0.008), "Brass", rot=(0, 0, 20))
    k.sphere(kn - d * 0.082, 0.012, "Brass", u=8, v=6)
    # A buckle on the baldric, over the heart.
    k.box(sling[13] + Vector((0, 0.006, 0)), (0.03, 0.008, 0.05), "Brass", rot=(0, -61, 0))
    k.finish(rig, ["chest", "spine", "hips"])

    # Tunic skirt: green wool from under the jerkin to mid thigh, split at the
    # sides, with a leaf cut hem and a pale stripe above a dark border.
    k = Kit("Tunic", M)
    seg = 48
    cen = (0, -0.01)
    cv = Vector((cen[0], cen[1], 0))
    levels = (1.0, 0.95, 0.885, 0.81, 0.735, 0.675, 0.648, 0.628)
    rows = []

    def body_r(th, z):
        c = Vector((cen[0], cen[1], z))
        hit = fig.onto(c + Vector((math.sin(th), math.cos(th), 0)) * 0.6, c, 0.0, ("hips", "spine", "thigh_l", "thigh_r"))
        return (hit - c).length if hit is not None else 0.0
    last = [0.0] * seg
    for j, zz in enumerate(levels):
        t = j / (len(levels) - 1.0)
        row = []
        for i in range(seg):
            th = i / seg * TAU
            # It never tucks in: each row clears the body beside it and the row above.
            r = max(body_r(th, zz), body_r(th, zz + 0.03), body_r(th, zz - 0.03), last[i] - 0.014) + 0.014
            last[i] = r
            r += 0.05 * t + 0.02 * t * max(0.0, math.cos(th)) + t * (0.013 * math.sin(th * 9.0 + 0.4) + 0.008 * math.sin(th * 14.0 + 1.3))
            z = zz - (0.03 * abs(math.sin(th * 6.0)) if j == len(levels) - 1 else 0.0)
            row.append(cv + Vector((math.sin(th) * r, math.cos(th) * r, z)))
        rows.append(row)
    fk.tint(k.ring_grid(rows[:3], "Robe", u_scale=2.0), 0.0, k)
    q = seg // 4
    for i0, i1 in ((-q + 2, q - 2), (q + 2, 3 * q - 2)):
        idx = [i % seg for i in range(i0, i1 + 1)]
        vs = k.ring_grid([[r[i] for i in idx] for r in rows[2:]], "Robe", closed=False, u_scale=2.0)
        fk.tint([vs[-3]], 0.4, k)
        fk.tint(vs[-2:], -0.38, k)
    k.finish(rig, ["hips", "thigh_l", "thigh_r", "skirt_f", "skirt_b"], subsurf=1, solidify=0.008)

    # Breeches and tall boots.
    k = Kit("Breeches", M)
    fig.add(k, "ClothDark", lambda i, o, p: o == "hips" and p.z < 1.0, offset=0.005)
    k.finish(rig, ["hips", "thigh_l", "thigh_r", "spine"])
    bf.legs(rig, M, fig.fitted, "ClothDark", "Leather", 1.0, cuff="Leather", boot=boot)
    k = Kit("BootStraps", M)
    for side in ("l", "r"):
        knee, ankle = bn["shin_" + side].head_local, bn["foot_" + side].head_local
        ax = (ankle - knee).normalized()
        for f, tn in ((0.5, -0.25), (0.74, -0.25)):
            ring = fig.strap(k, "Leather", knee.lerp(ankle, f), ax.cross(Vector((0, 1, 0))), ax.cross(ax.cross(Vector((0, 1, 0)))),
                             width=0.018, lift=0.022, owners=("shin_" + side,), n=16, tint_by=tn)
            p = max(ring, key=lambda v: v.y)
            fk.slab(k, p + Vector((-0.011, 0.001, -0.011)), (0.022, 0, 0), (0, 0.006, 0), (0, 0, 0.022), "Brass")
    k.finish(rig, ["shin_l", "shin_r", "thigh_l", "thigh_r"], solidify=0.004)


def boot(rig, M, side, mname):
    """A soft leather boot: a low pointed toe, a round heel, a dark sole."""
    a = rig.data.bones["foot_" + side].head_local
    k = Kit("Boot_" + side, M)
    # along the foot from the ankle, half width, half height, height of the middle
    prof = [(-0.062, 0.02, 0.026, 0.034), (-0.045, 0.035, 0.046, 0.05), (-0.005, 0.04, 0.052, 0.054), (0.04, 0.042, 0.044, 0.046),
            (0.085, 0.046, 0.033, 0.035), (0.125, 0.043, 0.025, 0.027), (0.158, 0.031, 0.018, 0.02), (0.176, 0.012, 0.009, 0.012)]
    vs = fk.sweep(k, [(a.x, a.y + y, cz) for y, _, _, cz in prof], [w for _, w, _, _ in prof], [h for _, _, h, _ in prof], mname, seg=12,
                  side=Vector((1, 0, 0)))
    for ring, (_, _, h, cz) in zip(vs, prof):
        for v in ring:
            if v.co.z < cz:  # a flat sole
                v.co.z = cz - h * min(1.0, (cz - v.co.z) / h * 1.7)
            if v.co.z < 0.014:
                v[k.tint] = -0.5
    fk.tint(fk.slab(k, (a.x - 0.03, a.y - 0.06, 0.0), (0.06, 0, 0), (0, 0.05, 0), (0, 0, 0.016), mname), -0.5, k)
    k.finish(rig, "foot_" + side, subsurf=1)


def build_arms(rig, M, fig):
    bn = rig.data.bones
    for side in ("r", "l"):
        sh = bn["upper_arm_" + side].head_local
        el = bn["forearm_" + side].head_local
        wr = bn["hand_" + side].head_local
        dd = (wr - el).normalized()
        flen = (wr - el).length
        arm = ("upper_arm_" + side, "forearm_" + side)
        k = Kit("Arm_" + side, M)

        # Linen sleeve: loose, gathered in folds at the elbow, full at the shoulder.
        def loose(i, p, sh=sh, el=el):
            if fig.owner[i] == "chest":  # the shoulder, tucked under the jerkin
                return 0.004
            d = (p - el).length
            fold = math.exp(-(d / 0.075) ** 2)
            return (0.008 + 0.006 * fold * math.sin(d * 150.0) + 0.006 * (1.0 - fk.smooth(0.0, 0.14, (p - sh).length))
                    + 0.003 * noise.noise(p * 30.0))
        sx = 1.0 if side == "r" else -1.0
        fig.add(k, "Cloth", lambda i, o, p: (o in arm and (p - el).dot(dd) < flen * 0.3) or (o == "chest" and p.x * sx > 0.12 and p.z > 1.24),
                offset=loose, tint=0.25)

        # Bracer: stiff leather from below the elbow to the wrist, two straps.
        def on_bracer(i, o, p):
            return o == arm[1] and flen * 0.16 < (p - el).dot(dd) < flen * 0.93
        for loop in fig.add(k, "Leather", on_bracer, offset=0.016):
            bf.rim(k, loop, 0.0055, "Leather", step=1)
        x = dd.cross(Vector((0, 0, 1))).normalized()
        y = dd.cross(x)
        for f in (0.36, 0.74):
            ring = fig.strap(k, "Leather", el + dd * (flen * f), x, y, width=0.016, lift=0.021, owners=(arm[1],), n=14,
                             crown=0.002, tint_by=-0.3)
            p = max(ring, key=lambda v: (v - el).dot(x) * (1.0 if side == "r" else -1.0))
            k.sphere(p, 0.008, "Brass", u=8, v=6)
        if side == "l":
            # Living vine wound up the bow arm, with three leaves.
            vine, lf = [], []
            for i in range(25):
                f = i / 24.0
                a = f * TAU * 2.5 + 0.6
                c = el + dd * (flen * (0.14 + 0.82 * f))
                p = fig.onto(c + (x * math.cos(a) + y * math.sin(a)) * 0.3, c, 0.022, (arm[1],))
                vine.append(p if p is not None else c + (x * math.cos(a) + y * math.sin(a)) * 0.06)
                if i in (4, 12, 20):
                    lf.append((vine[-1], (x * math.cos(a) + y * math.sin(a))))
            fk.sweep(k, vine, 0.0048, 0.0048, "Wood", seg=5)
            for p, nrm in lf:
                leaf(k, p + nrm * 0.004, (dd * 0.6 + nrm.cross(dd) * 0.8).normalized(), nrm, 0.038)

        # The hand: bare on the draw side, gloved on the bow side.
        if side == "r":
            fig.add(k, "Skin", lambda i, o, p: o == "hand_r")
        else:
            fig.add(k, "Leather", lambda i, o, p: o == "hand_l", offset=0.0022)
        obj = k.finish(rig, ["upper_arm_" + side, "forearm_" + side, "shoulder_" + side, "chest", "hand_" + side])
        fig.pin(obj, ("hand_" + side,))


def leaf(k, base_p, along, nrm, size, mname="Moss"):
    """A small pointed leaf, creased along its midrib."""
    along, nrm = Vector(along).normalized(), Vector(nrm).normalized()
    side = along.cross(nrm).normalized()
    bm = k.bm
    mi = k._mi(mname)
    mid = base_p + along * size * 0.42
    pts = [base_p, mid + side * size * 0.27 + nrm * size * 0.09, base_p + along * size + nrm * size * 0.12,
           mid - side * size * 0.27 + nrm * size * 0.09, mid - nrm * size * 0.02, mid + nrm * size * 0.045]
    v = [bm.verts.new(p) for p in pts]
    for i in range(4):
        j = (i + 1) % 4
        for f in (bm.faces.new((v[i], v[j], v[5])), bm.faces.new((v[j], v[i], v[4]))):
            f.material_index = mi
    for x in v:
        x[k.tint] = 0.25


def build_cloth(rig, M, fig):
    owners = fk.TORSO + bf.ARMS

    # Cowl: dark green wool draped over the shoulders with a thick rolled
    # collar, hanging to a point on the chest. Its hood is build_hood.
    k = Kit("Cowl", M)
    c0 = Vector((0, -0.01, 1.235))
    seg = 44
    ths = [i / seg * TAU for i in range(seg)]

    def ring_smooth(vals, passes=2):
        for _ in range(passes):
            vals = [(vals[i - 1] + 2 * vals[i] + vals[(i + 1) % seg]) / 4.0 for i in range(seg)]
        return vals
    rows = []
    # The collar: a soft roll standing round the neck, lower at the throat.
    for rad, dz in ((0.074, 0.02), (0.089, 0.032), (0.103, 0.016), (0.1, -0.006)):
        rows.append([Vector((math.sin(th) * (rad + 0.004 * math.sin(th * 5.0 + 1.0)),
                             0.002 + math.cos(th) * (rad + 0.006 + 0.004 * math.sin(th * 5.0 + 1.0)),
                             1.408 - 0.05 * math.cos(th) + dz + 0.004 * math.sin(th * 3.0))) for th in ths])
    # The yoke lies on the shoulders.
    rr, zz = [], []
    for el in (57.0, 47.0, 38.0):
        row = []
        for th in ths:
            d = Vector((math.sin(th) * math.cos(math.radians(el)), math.cos(th) * math.cos(math.radians(el)), math.sin(math.radians(el))))
            hit = fig.onto(c0 + d * 0.7, c0, 0.042 + 0.022 * max(0.0, -math.cos(th)) ** 2, owners)
            row.append(hit if hit is not None else c0 + d * 0.16)
        raw = [math.hypot(p.x - c0.x, p.y - c0.y) for p in row]
        rr = [max(a, b) for a, b in zip(ring_smooth(raw, 1), raw)]
        zz = [max(a, b) for a, b in zip(ring_smooth([p.z for p in row], 1), [p.z for p in row])]
        rows.append([Vector((c0.x + math.sin(th) * rr[i], c0.y + math.cos(th) * rr[i], zz[i])) for i, th in enumerate(ths)])
    # From there it hangs: straight down off the shoulders, to a point on the chest.
    for j in range(3):
        t = (j + 1) / 3.0
        nz = ring_smooth([zz[i] - 0.02 * (1.0 + 1.3 * max(0.0, math.cos(th)) ** 10 + 0.6 * max(0.0, -math.cos(th)) ** 4)
                          for i, th in enumerate(ths)], 1)
        nr, floor = [], []
        for i, th in enumerate(ths):
            body = fig.around(nz[i], th, 0.034 + 0.03 * max(0.0, -math.cos(th)) ** 2, centre=(c0.x, c0.y), owners=owners)
            floor.append(math.hypot(body.x - c0.x, body.y - c0.y))
            nr.append(max(rr[i] + 0.003, floor[i]) + t * (0.006 * math.sin(th * 7.0 + j * 0.9) + 0.003 * math.sin(th * 15.0 + j)))
        rr = [max(a, b) for a, b in zip(ring_smooth(nr), floor)]
        zz = nz
        rows.append([Vector((c0.x + math.sin(th) * rr[i], c0.y + math.cos(th) * rr[i], zz[i])) for i, th in enumerate(ths)])
    vs = k.ring_grid(rows, "RobeDark", u_scale=2.0)
    fk.tint(vs[-1:], -0.3, k)
    # A linen shirt collar inside it, round the base of the neck.
    fig.strap(k, "Cloth", (0, 0.0, 1.378), (0, 1, 0.22), (1, 0, 0), width=0.06, lift=0.011, owners=("neck", "chest"), n=28, tint_by=0.25)
    k.finish(rig, ["chest", "neck", "shoulder_l", "shoulder_r", "spine"], subsurf=1, solidify=0.006)

    # Team cape, from under the cowl to mid thigh, heavier folds toward a
    # leaf cut hem.
    k = Kit("Cape", M)
    rows = []
    nj, ni = 9, 15
    for j in range(nj):
        t = j / (nj - 1.0)
        zz = 1.385 - t * 0.7
        w = 0.14 + 0.12 * t
        row = []
        for i in range(ni):
            u = (i / (ni - 1.0)) * 2.0 - 1.0
            x = u * w
            if j < 2:
                hit = fig.onto((x, -0.6, zz), (x, 0.0, zz), 0.02, owners)
                y = hit.y if hit is not None else -0.13
            else:
                y = -0.142 - 0.02 * (1 - u * u) - (t - 0.14) * 0.085
            y += t * (0.038 * math.sin(u * 8.5 + 0.6) + 0.012 * math.sin(u * 17.0 + j * 0.7))
            hz = zz - (0.045 * abs(math.sin(u * 5.5)) if j == nj - 1 else 0.0)
            row.append(Vector((x, y, hz)))
        rows.append(row)
    vs = k.ring_grid(rows, "Team", closed=False)
    fk.tint(vs[-2:-1], 0.3, k)
    fk.tint(vs[-1:], -0.3, k)
    k.finish(rig, ["chest", "cape", "spine"], subsurf=1, solidify=0.008)


def build_hood(rig, M, fig):
    """The cowl's hood, worn up: deep enough to shade her brow, open round the
    face and throat, gathered into the collar, with a soft point at the back."""
    k = Kit("Hood", M)
    c0 = Vector((0.0, -0.004, 1.556))
    ax, up, down, back = 0.138, 0.15, 0.186, 0.142
    seg = 40
    phis = [i / seg * TAU for i in range(seg)]  # 0 over the crown, pi under the chin
    head = fig.bvh(("head", "neck"))

    def point(phi, y, sc, shift=Vector((0, 0, 0))):
        c, sn = math.cos(phi), math.sin(phi)
        z = (up if c > 0 else down) * c * sc
        if c < 0:  # it falls from the widest part of the head rather than tucking under the jaw
            sn = math.copysign(abs(sn) ** 0.8, sn)
        # Folds where the cloth gathers toward the collar.
        fold = 1.0 + 0.035 * math.sin(phi * 9.0 + y * 30.0) * fk.smooth(-0.25, -0.8, c)
        return c0 + shift + Vector((ax * sn * sc * fold, y, z))

    def rim_y(phi):
        c = math.cos(phi)
        return 0.06 + 0.06 * max(0.0, c) ** 1.4 + 0.03 * max(0.0, -c) ** 3

    rows = []
    # The edge is turned back on itself, then the cloth runs back over the head.
    for fy, dy, sc in ((1.0, -0.012, 1.0), (1.0, 0.002, 1.005), (1.0, 0.006, 0.975), (0.93, 0.0, 0.955), (0.62, 0.0, 0.985), (0.22, 0.0, 1.0)):
        rows.append([point(phi, rim_y(phi) * fy + dy, sc) for phi in phis])
    for psi in (10.0, 24.0, 38.0, 52.0, 64.0, 74.0, 82.0, 87.0):
        r = math.radians(psi)
        tip = fk.smooth(35.0, 90.0, psi)
        rows.append([point(phi, -back * math.sin(r), math.cos(r), Vector((0, -0.035 * tip, -0.065 * tip))) for phi in phis])
    # Never closer to her head, ears and hair than a finger's width.
    for row in rows:
        grow = []
        for p in row:
            d = p - c0
            g = 1.0
            if p.z > 1.475:
                hit = head.ray_cast(c0 + d.normalized() * 0.6, -d.normalized())
                if hit[0] is not None and (hit[0] - c0).dot(d) > 0:
                    g = max(1.0, ((hit[0] - c0).length + 0.038) / d.length)
            grow.append(g)
        for _ in range(2):
            grow = [max(grow[i], (grow[i - 1] + 2 * grow[i] + grow[(i + 1) % seg]) / 4.0) for i in range(seg)]
        for i, p in enumerate(row):
            row[i] = c0 + (p - c0) * grow[i]
    vs = k.ring_grid(rows, "RobeDark", cap_top=True, u_scale=2.0)
    fk.tint(vs[1:3], 0.12, k)
    k.finish(rig, ["head", "neck"], subsurf=1, solidify=0.007)


def build_quiver(rig, M):
    # Quiver over the cape, angled up to the right shoulder, full of arrows.
    k = Kit("Quiver", M)
    q0 = Vector((-0.085, -0.225, 0.95))
    q1 = Vector((0.165, -0.2, 1.475))
    d = (q1 - q0).normalized()
    side = d.cross(Vector((0, 1, 0))).normalized()
    fk.sweep(k, [q0 - d * 0.012, q0, q0.lerp(q1, 0.5), q1], [0.026, 0.04, 0.045, 0.05], [0.022, 0.034, 0.038, 0.043], "Leather", seg=14,
             side=side)
    for f, r, mname in ((1.0, 0.053, "Brass"), (0.62, 0.049, "Leather"), (0.2, 0.045, "Leather")):
        c = q0.lerp(q1, f)
        vs = fk.sweep(k, [c - d * 0.014, c + d * 0.004], r, r * 0.865, mname, seg=14, side=side, cap=False)
        if mname == "Leather":
            fk.tint(vs, -0.3, k)
    seam = [q0.lerp(q1, f) - Vector((0, 1, 0)) * (0.035 + 0.006 * f) for f in (0.04, 0.3, 0.6, 0.94)]
    fk.sweep(k, seam, 0.004, 0.003, "Cloth", seg=5)
    back = Vector((0, 1, 0))
    for i in range(8):
        a = i / 8 * TAU + 0.3
        off = (side * math.cos(a) + back * math.sin(a) * 0.85) * (0.027 if i else 0.0)
        base_p = q1 + off - d * 0.05
        lean = (d + off * 1.6).normalized()
        nock = base_p + lean * (0.21 + 0.022 * (i % 3))
        fk.sweep(k, [base_p, nock], 0.0048, 0.0048, "Wood", seg=5)
        k.sphere(nock, 0.0062, "Bone", u=6, v=4)
        r0 = lean.cross(Vector((0.3, 0.2, 1))).normalized()
        for v in range(3):
            rr = (r0 * math.cos(v * TAU / 3) + lean.cross(r0) * math.sin(v * TAU / 3))
            # A vane: low at the front, full toward the nock, cut square behind.
            hw = [0.001, 0.006, 0.0085, 0.0095, 0.008, 0.004]
            pts = [nock - lean * (0.088 - 0.014 * j) + rr * (0.004 + hw[j]) for j in range(6)]
            fk.tint(fk.sweep(k, pts, hw, 0.0011, "Feather", seg=4, side=rr), (0.5 if i % 3 == 0 else -0.1), k)
    k.finish(rig, ["chest", "spine"])


def build_bow(rig, M, fig):
    # A recurve of dark wood: a leather grip bound with cord, limbs that
    # sweep back and curl forward at bone tips, a taut string, and a living
    # vine wound up each limb with leaves and glowing buds.
    g, up, hollow = fig.grip["l"]
    hb = rig.data.bones["hand_l"]
    u = (hb.tail_local - hb.head_local).normalized()
    n = u.cross(up).normalized()
    if n.dot(fk.hand_frame(hb.head_local, hb.tail_local, "l")[1]) < 0:
        n = -n
    # The limbs bend in the plane of `up` and `fwd`: forward is along the
    # arm, turned so the string clears the bracer.
    fwd = (u * math.cos(math.radians(24)) - n * math.sin(math.radians(24)))
    fwd = (fwd - up * fwd.dot(up)).normalized()
    wide = up.cross(fwd).normalized()
    k = Kit("Bow", M)

    def limb(sd, steps=13):
        pts = []
        for i in range(steps):
            f = i / (steps - 1.0)
            pts.append(g + up * (sd * (0.075 + 0.61 * f)) + fwd * (0.012 - 0.25 * f ** 1.35 + 0.12 * fk.smooth(0.62, 1.0, f) ** 1.5))
        return pts

    up_l, dn_l = limb(1.0), limb(-1.0)
    riser = [g + up * s + fwd * (0.012 * (abs(s) / 0.075) ** 2) for s in (-0.075, -0.05, -0.025, 0.0, 0.025, 0.05, 0.075)]
    path = list(reversed(dn_l[1:])) + riser + up_l[1:]
    m = len(path)
    widths, thicks = [], []
    for i in range(m):
        f = abs(i - (m - 1) / 2.0) / ((m - 1) / 2.0)
        widths.append(0.02 - 0.009 * f ** 1.5)
        thicks.append(0.015 - 0.0098 * f ** 0.7)
    fk.sweep(k, path, widths, thicks, "Wood", seg=8, side=wide)
    r = max(hollow, 0.012)
    vs = fk.sweep(k, [g + up * s for s in (-0.058, -0.03, 0.0, 0.03, 0.058)], [r * 1.25, r * 1.18, r * 1.1, r * 1.18, r * 1.25],
                  [r * 1.2, r * 1.12, r * 1.05, r * 1.12, r * 1.2], "Leather", seg=10, side=wide)
    fk.tint(vs, -0.15, k)
    for s in (-0.064, -0.056, 0.056, 0.064):
        c = g + up * s + fwd * (0.012 * (abs(s) / 0.075) ** 2)
        fk.sweep(k, [c - up * 0.003, c + up * 0.003], r * 1.38, r * 1.32, "Cloth", seg=10, side=wide, cap=False)
    for lp, sd in ((up_l, 1.0), (dn_l, -1.0)):
        tip = lp[-1]
        td = (lp[-1] - lp[-2]).normalized()
        fk.sweep(k, [tip - td * 0.02, tip + td * 0.012, tip + td * 0.03], [0.0085, 0.0075, 0.003], [0.0065, 0.006, 0.003], "Bone", seg=6,
                 side=wide)
        # Vine: a helix up the limb, thinning toward the tip.
        vine = []
        for i in range(37):
            f = i / 36.0
            j = f * (len(lp) - 2.2) + 0.2
            a = lp[int(j)].lerp(lp[min(int(j) + 1, len(lp) - 1)], j - int(j))
            t = (lp[min(int(j) + 1, len(lp) - 1)] - lp[int(j)]).normalized()
            nn = t.cross(wide).normalized()
            ang = f * TAU * 4.0 + (0.0 if sd > 0 else 1.7)
            rad = 0.0155 - 0.006 * f
            vine.append(a + (wide * math.cos(ang) * 1.25 + nn * math.sin(ang)) * rad)
            if i in (5, 14, 23, 31):
                out = (wide * math.cos(ang) + nn * math.sin(ang)).normalized()
                leaf(k, vine[-1], (t * sd * 0.55 + out).normalized(), t.cross(out), 0.05 - 0.012 * f)
            if i in (10, 27):
                out = (wide * math.cos(ang) + nn * math.sin(ang)).normalized()
                k.sphere(vine[-1] + out * 0.006, 0.0105, "Glow", u=8, v=6)
        fk.sweep(k, vine, [0.0042 - 0.002 * i / 36.0 for i in range(37)], [0.0042 - 0.002 * i / 36.0 for i in range(37)], "Wood", seg=5)
    a, b = up_l[-1] - fwd * 0.004, dn_l[-1] - fwd * 0.004
    fk.sweep(k, [a, a.lerp(b, 0.5), b], 0.0022, 0.0022, "Cloth", seg=4)
    k.finish(rig, "bow")


def build_model(rig, M):
    slim = {"hips": (0.93, 0.95), "thigh_l": (0.86, 0.9), "thigh_r": (0.86, 0.9), "shin_l": (0.9, 0.92), "shin_r": (0.9, 0.92)}
    fig = fk.Figure(rig, body="female", girth=slim, ears=1.0, fists={"l": 2.2, "r": 0.55}, head=HEAD, mature=1.0)
    g, up, _ = fig.grip["l"]
    fk.move_bone(rig, "bow", g, g + up * 0.3)
    painters = []
    if want("head"):
        build_head(rig, M, fig, painters)
    if want("body"):
        build_body(rig, M, fig)
    if want("arms"):
        build_arms(rig, M, fig)
    if want("cloth"):
        build_cloth(rig, M, fig)
        build_hood(rig, M, fig)
    if want("quiver"):
        build_quiver(rig, M)
    if want("bow"):
        build_bow(rig, M, fig)
    if not os.environ.get("TW_NOBAKE"):
        fk.bake(rig, painters)


# ---------------------------------------------------------------- clips

def animate(rig, spec):
    slots = spec["slot_clips"]
    feet = ck.rest_feet(rig)
    # The bow lies along the fist at rest (a low ready carry), so `bow` only
    # trims it; the wrist does the rest.
    rest = dict(upper_arm_r=(6, 0, 4), forearm_r=(-8, 0, 0), upper_arm_l=(8, 0, -4), forearm_l=(0, 0, 0), hand_l=(18, 0, 0),
                bow=(10, 0, 0), plait=(0, 0, 0))

    def b(**over):
        d = dict(rest)
        d.update(over)
        return base(NAMES, **d)

    # The shooting pose: the bow arm straight out ahead, the draw hand at the
    # cheek, the body turned side-on, the bow upright.
    aim = dict(spine=(0, 0, 30), chest=(0, 0, 20), head=(0, 0, -40), upper_arm_l=(88, 0, -40), forearm_l=(-30, 0, 0), hand_l=(0, 0, 0),
               bow=(AIM_BOW, 0, 0), upper_arm_r=(85, -25, -30), forearm_r=(-20, 0, 110), hand_r=(0, 0, 0))
    drawn = {"l": (feet["l"][0] - 0.04, feet["l"][1] + 0.12, feet["l"][2]), "r": (feet["r"][0] + 0.04, feet["r"][1] - 0.12, feet["r"][2])}

    ck.idle_clip(rig, 2.4, lambda t, s: (b(spine=(2 * s, 0, 0), chest=(-1 * s, 0, 2 * s), head=(2 * s, 0, 6 * math.sin(t / 2.4 * TAU)),
                                            upper_arm_r=(6 + 2 * s, 0, 4), bow=(10 + 2 * s, 0, 0), cape=(1.5 * s, 0, 0),
                                            plait=(1.5 + 1.5 * s, 0, 1.5 * math.sin(t / 2.4 * TAU))),
                                          {"hips": (0, 0, -0.015 - 0.008 * s)}))

    def upper(t, s, c2):
        rots = b(hips=(0, 0, 9 * s), spine=(-12, 0, -5 * s), chest=(-4, 0, -6 * s), head=(12, 0, 3 * s),
                 upper_arm_r=(-35 * s + 8, 0, 8), forearm_r=(-40 - 15 * s, 0, 0),
                 upper_arm_l=(30 * s + 6, 0, -6), forearm_l=(-20 + 10 * s, 0, 0), hand_l=(10, 0, 0), bow=(8, 0, 0),
                 skirt_f=(-14 - 8 * c2, 0, 0), skirt_b=(26 + 6 * c2, 0, 0), cape=(30 + 6 * c2, 0, 0), plait=(7 + 6 * c2, 0, 4 * s))
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

    ck.death_clip(rig, NAMES, lambda t: {"bow": (10 - 25 * min(1.0, t / 0.6), 0, 0), "hand_l": (18, 0, 0), "plait": (0, 0, 0)})


AIM_BOW = 0.0  # set in main(): the trim that stands the bow upright in the shooting pose


def main():
    global AIM_BOW
    import sys
    out = ck.out_path(sys.argv, "/tmp/thornwright.blend")
    spec = ck.load_spec("thornwright")
    ck.reset()
    rig = ck.make_rig(bones())
    M = ck.Mats()
    build_model(rig, M)
    # The old bow stood upright in the hand and the shooting pose tipped it
    # back 58 degrees; the new one lies along the fist, so trim by the rest.
    bb = rig.data.bones["bow"]
    d = (bb.tail_local - bb.head_local).normalized()
    AIM_BOW = math.degrees(math.atan2(d.y, d.z)) - 58.0
    hr = rig.data.bones["hand_r"]
    ck.socket("Muzzle", rig, "hand_r", hr.head_local + (hr.tail_local - hr.head_local).normalized() * 0.11)
    ox, oy, oz = spec["sockets"]["Overhead"]
    ck.socket("Overhead", rig, "root", (ox, -oz, oy))
    if not os.environ.get("TW_NOANIM"):
        animate(rig, spec)
    ck.save(out)


if __name__ == "__main__":
    main()
