# SPDX-License-Identifier: GPL-2.0-or-later
# (Uses Blender's Python API. This is a build tool, not part of the game.)
"""Fit the CC0 Blender Studio body to the shared champion skeleton.

assets/source/hbm_body_{male,female}_stylized.obj are GEO-body_*_stylized from
Blender Studio's Human Base Meshes v1.4.1 (CC0), turned to face +Y with its
feet on the ground; nothing else changed. See ASSET_MANIFEST.csv.

The body stands in an A pose with its own joint positions, so each vertex is
moved with the bone it is nearest to: along the bone it is stretched to the
champion bone's length, across it scaled by a girth, and the whole frame is
turned onto the champion bone. Weights blend the three nearest bones so the
surface stays smooth across joints. Arms, hands and the head are dropped
(armour, sleeves and helms cover them; a build can keep the head); the torso and legs are kept and give
armour shells real anatomy instead of lathed cylinders.
"""
import os

import bpy  # noqa: F401,I001  (bpy first: it makes mathutils importable)
from mathutils import Vector

import champion_kit as ck

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(HERE, "..", "..", "assets", "source")
# The joints below were measured on the male body; the female body is scaled
# to the same height first (its joints then land close to them).
BODIES = {"male": ("hbm_body_male_stylized.obj", 1.0), "female": ("hbm_body_female_stylized.obj", 1.798 / 1.617)}

# The body's own joints (metres, facing +Y), measured from the mesh.
SRC = {
    "hips": ((0, -0.015, 0.90), (0, -0.015, 1.07)),
    "spine": ((0, -0.015, 1.07), (0, -0.02, 1.26)),
    "chest": ((0, -0.02, 1.26), (0, -0.02, 1.45)),
    "neck": ((0, -0.02, 1.45), (0, -0.0, 1.56)),
    "head": ((0, 0.0, 1.56), (0, 0.0, 1.79)),
    "thigh_l": ((-0.09, -0.01, 0.90), (-0.08, -0.027, 0.50)),
    "shin_l": ((-0.08, -0.027, 0.50), (-0.095, -0.045, 0.08)),
    "thigh_r": ((0.09, -0.01, 0.90), (0.08, -0.027, 0.50)),
    "shin_r": ((0.08, -0.027, 0.50), (0.095, -0.045, 0.08)),
    # Only used to tell arm and foot vertices apart; they are not kept.
    "upper_arm_l": ((-0.17, -0.03, 1.43), (-0.29, -0.04, 1.14)),
    "forearm_l": ((-0.29, -0.04, 1.14), (-0.38, -0.02, 0.88)),
    "hand_l": ((-0.38, -0.02, 0.88), (-0.41, 0.0, 0.74)),
    "upper_arm_r": ((0.17, -0.03, 1.43), (0.29, -0.04, 1.14)),
    "forearm_r": ((0.29, -0.04, 1.14), (0.38, -0.02, 0.88)),
    "hand_r": ((0.38, -0.02, 0.88), (0.41, 0.0, 0.74)),
    "foot_l": ((-0.095, -0.045, 0.08), (-0.1, 0.12, 0.02)),
    "foot_r": ((0.095, -0.045, 0.08), (0.1, 0.12, 0.02)),
}
KEEP = ("hips", "spine", "chest", "neck", "head", "thigh_l", "shin_l", "thigh_r", "shin_r")


def load(body="male"):
    """Returns (verts, uvs, faces) with faces as [(vi, ti), ...]."""
    vs, ts, fs = [], [], []
    name, scale = BODIES[body]
    with open(os.path.join(SOURCE, name)) as f:
        for line in f:
            if line.startswith("v "):
                vs.append(Vector(tuple(float(x) for x in line.split()[1:4])) * scale)
            elif line.startswith("vt "):
                ts.append(tuple(float(x) for x in line.split()[1:3]))
            elif line.startswith("f "):
                fs.append([(int(a.split("/")[0]) - 1, int(a.split("/")[1]) - 1) for a in line.split()[1:]])
    return vs, ts, fs


def _nearest(p, names):
    best = []
    for n in names:
        a, b = (Vector(x) for x in SRC[n])
        best.append((ck.seg_dist(p, a, b), n))
    best.sort()
    return best


def fit(rig, girth=None, body="male", points=()):
    """Returns (verts, uvs, faces, owner) for the kept torso and legs, moved onto
    the rig. girth: bone -> (x, y) scale across the bone (default 1)."""
    girth = girth or {}
    vs, ts, fs = load(body)
    n_body = len(vs)
    # Extra points (in the body file's own coordinates) ride along and come
    # back moved, in fitted[4].
    vs = vs + [Vector(p) * BODIES[body][1] for p in points]
    bones = rig.data.bones
    owner = []
    xf = {}
    for n in KEEP:
        sa, sb = (Vector(x) for x in SRC[n])
        ta, tb = bones[n].head_local.copy(), bones[n].tail_local.copy()
        sd, td = (sb - sa), (tb - ta)
        xf[n] = (sa, sd.normalized(), sd.length, ta, td.normalized(), td.length, sd.normalized().rotation_difference(td.normalized()),
                 girth.get(n, (1.0, 1.0)))
    out = []
    for p in vs:
        near = _nearest(p, SRC.keys())
        own = near[0][1]
        # The deltoid and the side of the chest sit closer to the A pose arm
        # than to the spine; keep anything inside the torso's width.
        if own.startswith("upper_arm") and abs(p.x) < 0.165:
            own = "chest"
        owner.append(own)
        kept = [(d, n) for d, n in near if n in KEEP][:3]
        acc = Vector((0, 0, 0))
        tot = 0.0
        for d, n in kept:
            sa, sdir, slen, ta, tdir, tlen, rot, (gx, gy) = xf[n]
            rel = p - sa
            a = rel.dot(sdir)
            r = rel - sdir * a
            r = Vector((r.x * gx, r.y * gy, r.z))
            q = ta + tdir * (a * tlen / slen) + rot @ r
            w = 1.0 / (d + 0.03) ** 4
            acc += q * w
            tot += w
        out.append(acc / tot)
    return out[:n_body], ts, fs, owner[:n_body], out[n_body:]


def region(fitted, test):
    """Faces whose every corner passes test(index, owner, position). Returns a
    list of faces in the same [(vi, ti)] form."""
    vs, ts, fs, owner = fitted[:4]
    keep = []
    for f in fs:
        if all(test(vi, owner[vi], vs[vi]) for vi, _ in f):
            keep.append(f)
    return keep


def add_faces(kit, fitted, faces, mname, offset=0.0, uv_scale=1.0):
    """Adds faces to a champion_kit.Kit, each vertex pushed out along its normal
    by offset. Returns the new BMVerts on the boundary, as ordered loops."""
    vs, ts, fs, owner = fitted[:4]
    used = sorted({vi for f in faces for vi, _ in f})
    # Vertex normals from the kept faces.
    nrm = {vi: Vector((0, 0, 0)) for vi in used}
    for f in faces:
        p = [vs[vi] for vi, _ in f]
        n = (p[1] - p[0]).cross(p[2] - p[0])
        for vi, _ in f:
            nrm[vi] += n
    bm = kit.bm
    mi = kit._mi(mname)
    made = {vi: bm.verts.new(vs[vi] + nrm[vi].normalized() * offset) for vi in used}
    for f in faces:
        try:
            face = bm.faces.new([made[vi] for vi, _ in f])
        except ValueError:
            continue
        face.material_index = mi
        face.smooth = True
        for loop, (_, ti) in zip(face.loops, f):
            u, v = ts[ti]
            loop[kit.uv].uv = (u * uv_scale, v * uv_scale)
    bm.edges.ensure_lookup_table()
    return boundary_loops([made[vi] for vi in used])


def boundary_loops(verts):
    """Ordered loops of the open edges among verts (each a list of Vector)."""
    vset = set(verts)
    edges = [e for v in verts for e in v.link_edges if e.is_boundary and e.verts[0] in vset and e.verts[1] in vset]
    adj = {}
    for e in set(edges):
        a, b = e.verts
        adj.setdefault(a, []).append(b)
        adj.setdefault(b, []).append(a)
    loops, seen = [], set()
    for start in adj:
        if start in seen:
            continue
        loop = [start]
        seen.add(start)
        prev, cur = None, start
        while True:
            nxt = [x for x in adj[cur] if x is not prev and x not in seen]
            if not nxt:
                break
            prev, cur = cur, nxt[0]
            loop.append(cur)
            seen.add(cur)
        if len(loop) > 4:
            loops.append([v.co.copy() for v in loop])
    return loops


def smooth_loop(pts, passes=3):
    n = len(pts)
    for _ in range(passes):
        pts = [(pts[(i - 1) % n] + pts[i] * 2 + pts[(i + 1) % n]) / 4 for i in range(n)]
    return pts


def rim(kit, loop, radius, mname, seg=6, step=2):
    """A rolled edge along a boundary loop (closed)."""
    pts = smooth_loop(loop)[::step]
    if len(pts) < 4:
        return
    pts = pts + pts[:1]
    kit.tube(pts, [radius] * len(pts), mname, seg=seg, cap=False)



def surface_y(fitted, x, zz, owners, front=True, reach=0.03):
    """The body's surface in front of (or behind) the point (x, zz): the largest
    (or smallest) y among kept vertices of the given owners near that x and z."""
    vs, _, _, owner = fitted[:4]
    ys = [p.y for i, p in enumerate(vs) if owner[i] in owners and abs(p.x - x) < reach and abs(p.z - zz) < reach]
    if not ys:
        return None
    return max(ys) if front else min(ys)


def legs(rig, M, fitted, mname, boots, boot_scale=1.0, cuff=None, offset=0.006):
    """The body's legs as trousers (mname), with a wrapped cuff from mid shin to
    the ankle and champion_kit boots. Stands in for champion_kit.limbs legs."""
    bn = rig.data.bones
    for side in ("l", "r"):
        knee = bn["shin_" + side].head_local
        ankle = bn["foot_" + side].head_local
        names = ("thigh_" + side, "shin_" + side)
        k = ck.Kit("Leg_" + side, M)
        add_faces(k, fitted, region(fitted, lambda i, o, p: o in names and p.z > ankle.z - 0.02), mname, offset=offset, uv_scale=3.0)
        if cuff:
            # Wrapped from mid shin down, following the calf.
            top = knee.lerp(ankle, 0.45).z
            wrap = region(fitted, lambda i, o, p: o == "shin_" + side and ankle.z - 0.02 < p.z < top)
            for loop in add_faces(k, fitted, wrap, cuff, offset=offset + 0.012, uv_scale=3.0):
                rim(k, loop, 0.008, cuff)
        k.finish(rig, ["thigh_" + side, "shin_" + side])
        ck.boot(rig, M, side, boots, boot_scale)
