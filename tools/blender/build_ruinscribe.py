# SPDX-License-Identifier: GPL-2.0-or-later
# (Uses Blender's Python API. This is a build tool, not part of the game.)
"""Build the Ruinscribe champion model, rig and clips, all from code.

  /opt/bpyenv/bin/python tools/blender/build_ruinscribe.py OUT.blend

Then export it with tools/blender/export_champion.py and check it with
tools/check_assets.gd. Everything here is original geometry written as code:
lathed robe and hood, tube limbs, a twisted staff with a brass cage and a
floating crystal, a floating grimoire. No scans, no generated art.

Blender axes: X right, Y forward (the champion faces +Y), Z up, metres.
Poses are written as rotations about the armature's own X/Y/Z axes as they
are at rest, so "thigh_l": (30, 0, 0) swings the left thigh forward 30
degrees whatever the bone's roll is.
"""
import json
import math
import os
import sys

import bpy  # noqa: I001  (bpy first: it makes bmesh importable)
import bmesh
from mathutils import Matrix, Quaternion, Vector

FPS = 30
TAU = math.tau
HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = os.path.join(HERE, "..", "..", "assets", "specs", "ruinscribe.json")

# ---------------------------------------------------------------- skeleton

# name: (head, tail, parent)
BONES = {
    "root": ((0, 0, 0), (0, 0.25, 0), None),
    "hips": ((0, 0, 0.96), (0, 0, 1.10), "root"),
    "spine": ((0, 0, 1.10), (0, 0.01, 1.28), "hips"),
    "chest": ((0, 0.01, 1.28), (0, 0, 1.47), "spine"),
    "neck": ((0, 0, 1.47), (0, 0.02, 1.57), "chest"),
    "head": ((0, 0.02, 1.57), (0, 0.02, 1.80), "neck"),
    "shoulder_r": ((0.04, 0, 1.43), (0.17, 0, 1.44), "chest"),
    "upper_arm_r": ((0.17, 0, 1.44), (0.25, 0.05, 1.19), "shoulder_r"),
    "forearm_r": ((0.25, 0.05, 1.19), (0.22, 0.30, 1.10), "upper_arm_r"),
    "hand_r": ((0.22, 0.30, 1.10), (0.21, 0.42, 1.09), "forearm_r"),
    "shoulder_l": ((-0.04, 0, 1.43), (-0.17, 0, 1.44), "chest"),
    "upper_arm_l": ((-0.17, 0, 1.44), (-0.27, 0.03, 1.20), "shoulder_l"),
    "forearm_l": ((-0.27, 0.03, 1.20), (-0.31, 0.16, 1.01), "upper_arm_l"),
    "hand_l": ((-0.31, 0.16, 1.01), (-0.32, 0.20, 0.93), "forearm_l"),
    "staff": ((-0.33, 0.19, 0.97), (-0.33, 0.19, 1.30), "hand_l"),
    "thigh_l": ((-0.10, 0, 0.96), (-0.11, 0.05, 0.53), "hips"),
    "shin_l": ((-0.11, 0.05, 0.53), (-0.11, 0, 0.09), "thigh_l"),
    "foot_l": ((-0.11, 0, 0.09), (-0.11, 0.17, 0.03), "root"),
    "thigh_r": ((0.10, 0, 0.96), (0.11, 0.05, 0.53), "hips"),
    "shin_r": ((0.11, 0.05, 0.53), (0.11, 0, 0.09), "thigh_r"),
    "foot_r": ((0.11, 0, 0.09), (0.11, 0.17, 0.03), "root"),
    "skirt_f": ((0, 0.14, 0.90), (0, 0.18, 0.40), "hips"),
    "skirt_b": ((0, -0.15, 0.90), (0, -0.22, 0.40), "hips"),
    "cape": ((0, -0.17, 1.42), (0, -0.25, 0.80), "chest"),
    "book": ((0.40, -0.10, 1.02), (0.40, -0.10, 1.14), "root"),
}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    s = bpy.context.scene
    s.render.fps = FPS
    s.render.fps_base = 1.0
    return s


def make_rig():
    arm = bpy.data.armatures.new("Rig")
    rig = bpy.data.objects.new("Rig", arm)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for name, (h, t, parent) in BONES.items():
        b = arm.edit_bones.new(name)
        b.head, b.tail = h, t
        b.roll = 0.0
    for name, (h, t, parent) in BONES.items():
        if parent:
            arm.edit_bones[name].parent = arm.edit_bones[parent]
    bpy.ops.object.mode_set(mode="POSE")
    for side in ("l", "r"):
        ik = rig.pose.bones["shin_" + side].constraints.new("IK")
        ik.target = rig
        ik.subtarget = "foot_" + side
        ik.chain_count = 2
        ik.use_tail = True
        ik.use_stretch = False
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


# ---------------------------------------------------------------- materials

def mat(name, rgb, rough=0.8, metal=0.0, emit=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = (*rgb, 1.0)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    if emit:
        p.inputs["Emission Color"].default_value = (*emit, 1.0)
        p.inputs["Emission Strength"].default_value = 2.0
    return m


def materials():
    return {
        "Robe": mat("Robe", (0.36, 0.11, 0.10), 0.9),
        "RobeInner": mat("RobeInner", (0.16, 0.06, 0.06), 0.95),
        "Team": mat("Team", (0.15, 0.55, 0.55), 0.85),
        "Leather": mat("Leather", (0.22, 0.13, 0.08), 0.65),
        "Cloth": mat("Cloth", (0.30, 0.26, 0.20), 0.9),
        "Skin": mat("Skin", (0.62, 0.45, 0.36), 0.6),
        "Wood": mat("Wood", (0.30, 0.20, 0.12), 0.75),
        "Brass": mat("Brass", (0.78, 0.58, 0.28), 0.35, 1.0),
        "Paper": mat("Paper", (0.86, 0.80, 0.64), 0.9),
        "Trim": mat("Trim", (0.85, 0.65, 0.3), 0.45, 0.6),
        "Glow": mat("Glow", (0.25, 0.8, 0.78), 0.3, 0.0, (0.25, 0.8, 0.78)),
        "Eyes": mat("Eyes", (0.4, 0.95, 0.9), 0.3, 0.0, (0.4, 0.95, 0.9)),
    }


# ---------------------------------------------------------------- mesh kit

class Kit:
    """Accumulates geometry for one object, each piece with its material."""

    def __init__(self, name, mats):
        self.name = name
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.mats = []
        self.mat_lookup = mats

    def _mi(self, mname):
        m = self.mat_lookup[mname]
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def ring_grid(self, rings, mname, closed=True, cap_bottom=False, cap_top=False, u_scale=1.0, v_scale=1.0):
        """rings: list of lists of Vector (same count). Builds quads between them with UVs."""
        bm = self.bm
        mi = self._mi(mname)
        vs = [[bm.verts.new(p) for p in r] for r in rings]
        n = len(rings[0])
        seg = n if closed else n - 1
        vlen = [0.0]
        for i in range(1, len(rings)):
            d = sum((rings[i][k] - rings[i - 1][k]).length for k in range(n)) / n
            vlen.append(vlen[-1] + d)
        for i in range(len(rings) - 1):
            for k in range(seg):
                k2 = (k + 1) % n
                f = bm.faces.new((vs[i][k], vs[i][k2], vs[i + 1][k2], vs[i + 1][k]))
                f.material_index = mi
                f.smooth = True
                for loop, (uu, vv) in zip(f.loops, ((k, i), (k + 1, i), (k + 1, i + 1), (k, i + 1))):
                    loop[self.uv].uv = (uu / seg * u_scale, vlen[vv] * v_scale)
        if cap_bottom:
            f = bm.faces.new(list(reversed(vs[0])))
            f.material_index = mi
            f.smooth = True
        if cap_top:
            f = bm.faces.new(vs[-1])
            f.material_index = mi
            f.smooth = True
        return vs

    def lathe(self, profile, mname, seg=24, sx=1.0, sy=1.0, center=(0, 0), fold=None, **kw):
        """profile: list of (radius, z). fold(theta, z, r) -> new radius."""
        rings = []
        for r, z in profile:
            ring = []
            for k in range(seg):
                th = k / seg * TAU
                rr = fold(th, z, r) if fold else r
                ring.append(Vector((center[0] + math.sin(th) * rr * sx, center[1] + math.cos(th) * rr * sy, z)))
            rings.append(ring)
        return self.ring_grid(rings, mname, u_scale=sx * 2.0, **kw)

    def tube(self, points, radii, mname, seg=10, twist=0.0, flat=1.0, cap=True):
        """A tube along a polyline. radii per point; flat squashes the local X."""
        rings = []
        up = Vector((0, 0, 1))
        for i, p in enumerate(points):
            p = Vector(p)
            a = Vector(points[max(i - 1, 0)])
            b = Vector(points[min(i + 1, len(points) - 1)])
            t = (b - a).normalized()
            ref = up if abs(t.dot(up)) < 0.95 else Vector((0, 1, 0))
            x = t.cross(ref).normalized()
            y = t.cross(x).normalized()
            ring = []
            for k in range(seg):
                th = k / seg * TAU + twist * i
                ring.append(p + (x * math.cos(th) * flat + y * math.sin(th)) * radii[i])
            rings.append(ring)
        return self.ring_grid(rings, mname, cap_bottom=cap, cap_top=cap)

    def box(self, center, size, mname, rot=(0, 0, 0)):
        mi = self._mi(mname)
        m = Matrix.Translation(center) @ euler(rot) @ Matrix.Diagonal((*size, 1))
        res = bmesh.ops.create_cube(self.bm, size=1.0, matrix=m, calc_uvs=True)
        for v in res["verts"]:
            for f in v.link_faces:
                f.material_index = mi
        return res["verts"]

    def sphere(self, center, radius, mname, scale=(1, 1, 1), u=16, v=10):
        mi = self._mi(mname)
        m = Matrix.Translation(center) @ Matrix.Diagonal((*scale, 1))
        res = bmesh.ops.create_uvsphere(self.bm, u_segments=u, v_segments=v, radius=radius, matrix=m, calc_uvs=True)
        for vv in res["verts"]:
            for f in vv.link_faces:
                f.material_index = mi
                f.smooth = True
        return res["verts"]

    def octa(self, center, w, up, down, mname):
        mi = self._mi(mname)
        c = Vector(center)
        ring = [self.bm.verts.new(c + Vector((math.cos(a) * w, math.sin(a) * w, 0))) for a in (0, TAU / 4, TAU / 2, TAU * 3 / 4)]
        top = self.bm.verts.new(c + Vector((0, 0, up)))
        bot = self.bm.verts.new(c - Vector((0, 0, down)))
        for i in range(4):
            j = (i + 1) % 4
            self.bm.faces.new((ring[i], ring[j], top)).material_index = mi
            self.bm.faces.new((ring[j], ring[i], bot)).material_index = mi

    def finish(self, rig, weights, subsurf=0, solidify=0.0):
        me = bpy.data.meshes.new(self.name)
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts[:], dist=0.0005)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces[:])
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(m)
        obj = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(obj)
        obj.parent = rig
        skin(obj, rig, weights)
        if solidify > 0.0:
            s = obj.modifiers.new("Solid", "SOLIDIFY")
            s.thickness = solidify
            s.offset = -1.0
        if subsurf:
            s = obj.modifiers.new("Smooth", "SUBSURF")
            s.levels = subsurf
            s.render_levels = subsurf
        a = obj.modifiers.new("Rig", "ARMATURE")
        a.object = rig
        return obj


def euler(rot):
    rx, ry, rz = (math.radians(a) for a in rot)
    return (Matrix.Rotation(rz, 4, "Z") @ Matrix.Rotation(ry, 4, "Y") @ Matrix.Rotation(rx, 4, "X"))


# ---------------------------------------------------------------- skinning

def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (a + ab * t - p).length


def skin(obj, rig, weights):
    """weights: a bone name (rigid) or a list of bones blended by distance."""
    if isinstance(weights, str):
        vg = obj.vertex_groups.new(name=weights)
        vg.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
        return
    bones = rig.data.bones
    groups = {b: obj.vertex_groups.new(name=b) for b in weights}
    segs = {b: (bones[b].head_local.copy(), bones[b].tail_local.copy()) for b in weights}
    for v in obj.data.vertices:
        p = v.co
        ws = []
        for b in weights:
            d = seg_dist(p, *segs[b])
            ws.append((1.0 / (d + 0.03) ** 4, b))
        ws.sort(reverse=True)
        ws = ws[:3]
        tot = sum(w for w, _ in ws)
        for w, b in ws:
            if w / tot > 0.02:
                groups[b].add([v.index], w / tot, "REPLACE")


# ---------------------------------------------------------------- the model

def robe_fold(th, z, r):
    # Deep vertical folds that fade toward the waist, a front panel that
    # hangs straighter, a ragged travel-worn hem.
    depth = max(0.0, (0.95 - z) / 0.85)
    fold = 0.022 * math.sin(th * 9.0 + 0.6) + 0.012 * math.sin(th * 17.0 + 1.3)
    front = math.cos(th)  # +1 at the front
    return r + fold * depth * (0.6 + 0.4 * (1 - abs(front)))


def build_model(rig, M):
    # Robe: a long lathed coat from shoulders to a ragged hem, wider at the
    # skirt, its back hanging longer than the front.
    k = Kit("Robe", M)
    prof = [(0.37, 0.06), (0.345, 0.16), (0.30, 0.36), (0.25, 0.62), (0.205, 0.86), (0.175, 0.98),
            (0.17, 1.06), (0.19, 1.18), (0.215, 1.30), (0.20, 1.40), (0.12, 1.49)]
    rings = []
    seg = 32
    for r, z in prof:
        ring = []
        for i in range(seg):
            th = i / seg * TAU
            rr = robe_fold(th, z, r)
            zz = z
            if z < 0.1:
                zz = z + 0.035 * math.sin(th * 5.0 + 0.4) - 0.04 * (1 - math.cos(th)) * 0.5
            ring.append(Vector((math.sin(th) * rr * 1.08, math.cos(th) * rr * 0.92, zz)))
        rings.append(ring)
    k.ring_grid(rings, "Robe", u_scale=2.0)
    k.finish(rig, ["hips", "spine", "chest", "thigh_l", "thigh_r", "skirt_f", "skirt_b", "shin_l", "shin_r"], subsurf=1, solidify=0.012)

    # Team sash across the waist and a hem band, so the team reads from the
    # camera, plus the capelet over the shoulders and a cape down the back.
    k = Kit("TeamCloth", M)
    k.lathe([(0.178, 1.00), (0.182, 1.07)], "Team", seg=28, sx=1.08, sy=0.94, cap_bottom=False)
    k.lathe([(0.385, 0.03), (0.378, 0.11)], "Team", seg=32, sx=1.08, sy=0.92,
            fold=lambda th, z, r: robe_fold(th, 0.1, r))
    cape = Kit("Cape", M)
    # Capelet: broad over the shoulders with a scalloped edge and a gold band.
    seg = 36
    rings = []
    for r, z in ((0.29, 1.23), (0.28, 1.31), (0.235, 1.41), (0.15, 1.49), (0.11, 1.53)):
        ring = []
        for i in range(seg):
            th = i / seg * TAU
            zz = z - (0.03 * abs(math.sin(th * 4.0)) if z < 1.24 else 0.0)
            rr = r + 0.008 * math.sin(th * 7.0)
            ring.append(Vector((math.sin(th) * rr * 1.22, math.cos(th) * rr * 0.95, zz)))
        rings.append(ring)
    cape.ring_grid(rings, "Team", u_scale=2.0)
    band = [[Vector((p.x * 1.012, p.y * 1.012, p.z + dz)) for p in rings[0]] for dz in (-0.002, 0.03)]
    cape.ring_grid(band, "Trim")
    # Back cape: a curved hanging panel from the shoulders to the calves,
    # gold banded at the hem.
    rows = []
    for j in range(9):
        z = 1.40 - j * 0.115
        w = 0.26 + j * 0.02
        row = []
        for i in range(11):
            u = (i / 10.0) * 2.0 - 1.0
            y = -0.21 - 0.06 * (1 - u * u) - j * 0.012
            zz = z - (0.04 * abs(math.sin(u * 4.7)) if j == 8 else 0.0)
            row.append(Vector((u * w, y + 0.012 * math.sin(u * 9.0 + j), zz)))
        rows.append(row)
    cape.ring_grid(rows, "Team", closed=False)
    hem = [[Vector((p.x, p.y - 0.004, p.z + dz)) for p in rows[-1]] for dz in (0.0, 0.05)]
    cape.ring_grid(hem, "Trim", closed=False)
    k.finish(rig, ["hips", "spine"], subsurf=1, solidify=0.01)
    cape.finish(rig, ["chest", "cape", "spine"], subsurf=1, solidify=0.01)

    # Hood: a deep cowl with a peak, open at the front and pulled forward at
    # the rim, so the face sits back in shadow and only the eyes show.
    k = Kit("Hood", M)
    rings = []
    for j in range(11):
        a = math.pi * (0.06 + j / 10.0 * 0.86)
        g = math.pi * 0.66 * min(1.0, max(0.0, (j - 2) / 4.0)) ** 0.8
        ring = []
        for i in range(25):
            u = i / 24.0
            th = g * 0.5 + u * (TAU - g)
            r = 0.19 * math.sin(a) + 0.018
            z = 1.645 + 0.205 * math.cos(a)
            x = math.sin(th) * r * 1.04
            y = math.cos(th) * r + 0.012 + 0.04 * max(0.0, math.cos(th)) * min(1.0, j / 4.0)
            if j <= 3 and math.cos(th) < 0.0:
                z += 0.02 * (1 - j / 3.0) * -math.cos(th)
                y -= 0.035 * (1 - j / 3.0) * -math.cos(th)
            ring.append(Vector((x, y, z)))
        rings.append(ring)
    k.ring_grid(rings, "Robe", closed=False)
    k.tube([(0, -0.13, 1.80), (0, -0.20, 1.73), (0, -0.25, 1.62)], [0.06, 0.035, 0.004], "Robe", seg=8, cap=False)
    k.lathe([(0.15, 1.47), (0.172, 1.52), (0.155, 1.57)], "RobeInner", seg=20, sx=1.05, sy=1.0)
    k.finish(rig, ["head", "neck"], subsurf=1, solidify=0.014)

    # Head inside the hood: a narrow face in shadow with glowing eyes.
    k = Kit("Head", M)
    k.sphere((0, 0.0, 1.655), 0.1, "RobeInner", scale=(0.88, 0.95, 1.12))
    k.sphere((0.036, 0.088, 1.68), 0.014, "Eyes", scale=(1.5, 0.6, 0.55), u=8, v=6)
    k.sphere((-0.036, 0.088, 1.68), 0.014, "Eyes", scale=(1.5, 0.6, 0.55), u=8, v=6)
    k.finish(rig, "head")

    # Sleeves: wide at the wrist, lined inside, each split over two bones.
    for side, sx in (("r", 1.0), ("l", -1.0)):
        b = rig.data.bones
        sh = b["upper_arm_" + side].head_local
        el = b["forearm_" + side].head_local
        wr = b["hand_" + side].head_local
        k = Kit("Sleeve_" + side, M)
        pts = [sh + Vector((0, 0, 0.02)), sh.lerp(el, 0.5), el, el.lerp(wr, 0.6), wr + (wr - el).normalized() * 0.02]
        k.tube(pts, [0.085, 0.075, 0.07, 0.085, 0.105], "Robe", seg=12, cap=False)
        k.tube([wr - (wr - el).normalized() * 0.04, wr + (wr - el).normalized() * 0.015], [0.09, 0.095], "Team", seg=12, cap=False)
        k.finish(rig, ["upper_arm_" + side, "forearm_" + side, "shoulder_" + side, "chest"], subsurf=1, solidify=0.008)
        # Hand: palm, four fingers in pairs and a thumb.
        h = Kit("Hand_" + side, M)
        d = (b["hand_" + side].tail_local - wr).normalized()
        palm = wr + d * 0.05
        h.sphere(palm, 0.045, "Skin", scale=(0.75, 1.0, 0.55))
        for f in (-1.0, 1.0):
            off = Vector((0.018 * f, 0, 0))
            h.tube([palm + d * 0.03 + off, palm + d * 0.075 + off + Vector((0, 0, -0.012)), palm + d * 0.1 + off + Vector((0, 0, -0.03))],
                   [0.016, 0.014, 0.011], "Skin", seg=6)
        h.tube([palm + Vector((-0.03 * sx, 0, 0)), palm + Vector((-0.05 * sx, 0.03, -0.01))], [0.015, 0.012], "Skin", seg=6)
        h.finish(rig, "hand_" + side)

    # Bracelet of glowing runes on the casting (right) wrist.
    k = Kit("Bracelet", M)
    wr = rig.data.bones["hand_r"].head_local
    el = rig.data.bones["forearm_r"].head_local
    dd = (wr - el).normalized()
    k.tube([wr - dd * 0.035, wr - dd * 0.012], [0.052, 0.052], "Brass", seg=14, cap=False)
    for i in range(6):
        a = i / 6 * TAU
        x = dd.cross(Vector((0, 0, 1))).normalized()
        y = dd.cross(x)
        p = wr - dd * 0.024 + (x * math.cos(a) + y * math.sin(a)) * 0.056
        k.box(p, (0.012, 0.012, 0.012), "Glow")
    k.finish(rig, "forearm_r")

    # Legs under the robe: trousers and boots, so the run reads.
    for side, x in (("l", -0.11), ("r", 0.11)):
        b = rig.data.bones
        hip = b["thigh_" + side].head_local
        knee = b["shin_" + side].head_local
        ankle = b["foot_" + side].head_local
        k = Kit("Leg_" + side, M)
        k.tube([hip, hip.lerp(knee, 0.5), knee, knee.lerp(ankle, 0.5)], [0.085, 0.075, 0.06, 0.055], "Cloth", seg=10)
        k.tube([knee.lerp(ankle, 0.45), ankle + Vector((0, 0, 0.02))], [0.065, 0.062], "Leather", seg=10)
        k.finish(rig, ["thigh_" + side, "shin_" + side], subsurf=1)
        f = Kit("Boot_" + side, M)
        f.tube([Vector((x, -0.05, 0.05)), Vector((x, 0.06, 0.045)), Vector((x, 0.15, 0.035))], [0.05, 0.048, 0.038],
               "Leather", seg=10, flat=1.0)
        f.box(Vector((x, 0.04, 0.008)), (0.09, 0.24, 0.016), "Leather")
        f.finish(rig, "foot_" + side, subsurf=1)

    # Belt, buckle, satchel with folios, scroll case.
    k = Kit("Gear", M)
    k.lathe([(0.205, 0.97), (0.21, 1.02)], "Leather", seg=28, sx=1.08, sy=0.94)
    k.box(Vector((0, 0.2, 0.995)), (0.07, 0.02, 0.06), "Brass")
    k.box(Vector((-0.25, 0.02, 0.88)), (0.06, 0.2, 0.22), "Leather", rot=(0, 0, 8))
    k.box(Vector((-0.255, 0.05, 1.0)), (0.02, 0.15, 0.08), "Paper", rot=(0, 8, 8))
    k.box(Vector((-0.26, -0.03, 1.01)), (0.02, 0.13, 0.07), "Paper", rot=(0, -6, 8))
    k.tube([Vector((0.17, -0.16, 0.78)), Vector((0.22, -0.13, 1.12))], [0.035, 0.035], "Leather", seg=10)
    k.tube([Vector((0.165, -0.165, 0.76)), Vector((0.172, -0.162, 0.79))], [0.04, 0.04], "Brass", seg=10)
    k.finish(rig, ["hips", "spine"])
    # Tabard: a team coloured panel hanging from the belt to the hem at the
    # front, gold edged, with a line of glowing glyphs down its centre.
    k = Kit("Tabard", M)
    rows, edge_l, edge_r = [], [], []
    for j in range(8):
        z = 0.98 - j * 0.12
        w = 0.085 + j * 0.008
        y = 0.19 + j * 0.016 + 0.012 * j * j / 8.0
        rows.append([Vector((u * w, y + 0.006 * (1 - u * u), z)) for u in (-1.0, -0.5, 0.0, 0.5, 1.0)])
    k.ring_grid(rows, "Team", closed=False)
    for sd in (-1.0, 1.0):
        strip = [[Vector((r[0 if sd < 0 else 4].x + sd * dx, r[0].y + 0.003, r[0].z)) for dx in (-0.012, 0.012)] for r in rows]
        k.ring_grid(strip, "Trim", closed=False)
    hem = [[Vector((p.x, p.y + 0.003, p.z + dz)) for p in rows[-1]] for dz in (0.0, 0.03)]
    k.ring_grid(hem, "Trim", closed=False)
    for j in range(1, 7):
        r = rows[j]
        k.box(Vector((0, r[2].y + 0.008, r[2].z)), (0.03, 0.004, 0.05), "Glow", rot=(0, 45, 0))
    k.finish(rig, ["skirt_f", "hips", "thigh_l", "thigh_r"], subsurf=0, solidify=0.006)

    # Staff: twisted dark wood, brass collars, a brass cage of three prongs
    # holding a floating crystal.
    k = Kit("Staff", M)
    sx, sy = -0.33, 0.19
    pts = [Vector((sx, sy, 0.03 + i * 0.105)) for i in range(17)]
    k.tube(pts, [0.024 + 0.006 * math.sin(i * 1.7) + (0.01 if i > 14 else 0.0) for i in range(17)], "Wood", seg=7, twist=0.35)
    top = Vector((sx, sy, 1.71))
    for z in (0.58, 1.12, 1.66):
        k.tube([Vector((sx, sy, z)), Vector((sx, sy, z + 0.04))], [0.036, 0.036], "Brass", seg=10)
    for i in range(3):
        a = i / 3 * TAU
        d = Vector((math.cos(a), math.sin(a), 0))
        k.tube([top, top + d * 0.07 + Vector((0, 0, 0.08)), top + d * 0.06 + Vector((0, 0, 0.19)), top + d * 0.02 + Vector((0, 0, 0.25))],
               [0.012, 0.011, 0.009, 0.004], "Brass", seg=6)
    k.finish(rig, "staff")
    k = Kit("Crystal", M)
    k.octa(top + Vector((0, 0, 0.13)), 0.045, 0.1, 0.07, "Glow")
    k.finish(rig, "staff")

    # Floating grimoire at the right hip, open, its pages glowing.
    k = Kit("Grimoire", M)
    c = rig.data.bones["book"].head_local
    for sd in (-1.0, 1.0):
        k.box(c + Vector((sd * 0.075, 0.0, -0.012 + 0.0)), (0.15, 0.21, 0.014), "Leather", rot=(0, sd * -14, 0))
        k.box(c + Vector((sd * 0.07, 0.0, 0.006)), (0.135, 0.19, 0.022), "Paper", rot=(0, sd * -14, 0))
        k.box(c + Vector((sd * 0.07, 0.0, 0.026)), (0.09, 0.14, 0.002), "Glow", rot=(0, sd * -14, 0))
    k.box(c + Vector((0, 0.0, -0.022)), (0.03, 0.215, 0.02), "Trim")
    k.finish(rig, "book")


# ---------------------------------------------------------------- sockets

def socket(name, rig, bone, world):
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = 0.06
    bpy.context.scene.collection.objects.link(e)
    e.parent = rig
    e.parent_type = "BONE"
    e.parent_bone = bone
    bpy.context.view_layer.update()
    e.matrix_world = Matrix.Translation(Vector(world))
    return e


# ---------------------------------------------------------------- posing

def q_arm(rot):
    rx, ry, rz = (math.radians(a) for a in rot)
    return (Quaternion((0, 0, 1), rz) @ Quaternion((0, 1, 0), ry) @ Quaternion((1, 0, 0), rx))


def pose(rig, frame, rots, locs=None, feet=None):
    """rots: bone -> (x, y, z) degrees about the armature axes at rest.
    locs: bone -> armature-space offset. feet: side -> armature-space ankle."""
    for name, rot in rots.items():
        pb = rig.pose.bones[name]
        r = pb.bone.matrix_local.to_3x3().to_quaternion()
        pb.rotation_quaternion = r.inverted() @ q_arm(rot) @ r
        pb.keyframe_insert("rotation_quaternion", frame=frame)
    for name, off in (locs or {}).items():
        pb = rig.pose.bones[name]
        r = pb.bone.matrix_local.to_3x3()
        pb.location = r.inverted() @ Vector(off)
        pb.keyframe_insert("location", frame=frame)
    for side, p in (feet or {}).items():
        pb = rig.pose.bones["foot_" + side]
        rest = pb.bone.matrix_local
        pb.location = rest.to_3x3().inverted() @ (Vector(p) - rest.translation)
        pb.keyframe_insert("location", frame=frame)


REST_FEET = {"l": (-0.11, 0, 0.09), "r": (0.11, 0, 0.09)}
ALL = ["hips", "spine", "chest", "neck", "head", "shoulder_r", "upper_arm_r", "forearm_r", "hand_r",
       "shoulder_l", "upper_arm_l", "forearm_l", "hand_l", "staff", "skirt_f", "skirt_b", "cape", "book", "root"]


def base(**over):
    d = {b: (0, 0, 0) for b in ALL}
    d.update(over)
    return d


def fcurves(act):
    if hasattr(act, "layers") and len(act.layers):
        for layer in act.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    yield from bag.fcurves
    elif hasattr(act, "fcurves"):
        yield from act.fcurves


def clip(rig, name, length_s, release_s=None):
    act = bpy.data.actions.new(name)
    rig.animation_data_create()
    rig.animation_data.action = act
    end = max(1, round(length_s * FPS))
    act.frame_range = (0, end)
    act.use_frame_range = True
    if release_s is not None:
        act.pose_markers.new("release").frame = round(release_s * FPS)
    return act, end


def close_clip(rig, act, track, interp=None):
    if interp:
        for fc in fcurves(act):
            for kp in fc.keyframe_points:
                kp.interpolation = interp
    for pb in rig.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
    ad = rig.animation_data
    t = ad.nla_tracks.new()
    t.name = track
    t.strips.new(track, 0, act)
    ad.action = None


def book_bob(t):
    return {"book": (0, 0, 8 * math.sin(t * TAU * 0.5))}, {"book": (0, 0, 0.03 * math.sin(t * TAU * 0.8))}


def animate(rig, spec):
    v = spec["move_speed_mps"]
    slots = spec["slot_clips"]

    # Idle: slow breath, the staff sways, the head looks a little, the book
    # turns and bobs. Knees soften as the hips settle (feet stay planted).
    act, end = clip(rig, "idle", 2.4)
    for f in range(0, end + 1, 6):
        t = f / FPS
        s = math.sin(t / 2.4 * TAU)
        br, bl = book_bob(t)
        rots = base(spine=(2 * s, 0, 0), chest=(-1.5 * s, 0, 1.5 * s), head=(2 * math.sin(t / 2.4 * TAU * 2), 0, 6 * math.sin(t / 2.4 * TAU)),
                    upper_arm_r=(4 + 2 * s, 0, 4), forearm_r=(-6, 0, 0), staff=(2 * s, 2 * s, 0),
                    upper_arm_l=(2, 0, -2), skirt_f=(-1 * s, 0, 0), skirt_b=(1 * s, 0, 0), cape=(1.5 * s, 0, 0), **br)
        pose(rig, f, rots, {"hips": (0, 0, -0.012 - 0.008 * s), **bl}, REST_FEET)
    close_clip(rig, act, "idle-loop")

    # Run: 0.6 s cycle, each foot planted 20% of it and slid back under the
    # body at the run speed (so in the game the feet do not slide), a flight
    # phase between steps, lean forward, the casting arm pumping, the staff
    # carried at an angle, the robe and cape streaming back.
    cycle = 0.6
    stance = 0.2
    stride = v * cycle * stance
    act, end = clip(rig, "run", cycle)
    for f in range(0, end + 1):
        t = f / end
        feet = {}
        for side, x, ph in (("l", -0.11, 0.0), ("r", 0.11, 0.5)):
            u = (t + ph) % 1.0
            if u < stance:
                y, z = stride * 0.5 - stride * (u / stance), 0.09
            else:
                w = (u - stance) / (1 - stance)
                y = -stride * 0.5 + stride * (0.5 - 0.5 * math.cos(math.pi * w))
                y -= 0.22 * math.sin(math.pi * w)  # the heel kicks up behind
                z = 0.09 + 0.26 * math.sin(math.pi * w) ** 1.5
            feet[side] = (x, y + 0.08, z)
        s = math.sin(t * TAU)
        c2 = math.cos(t * TAU * 2)
        br, bl = book_bob(t * 2)
        rots = base(hips=(0, 0, 9 * s), spine=(-12, 0, -5 * s), chest=(-4, 0, -6 * s), head=(10, 0, 3 * s),
                    upper_arm_r=(-35 * s + 10, 0, 8), forearm_r=(-40 - 15 * s, 0, 0),
                    upper_arm_l=(18, 0, -6), forearm_l=(-10, 0, 0), staff=(-35, 0, -8),
                    skirt_f=(-14 - 8 * c2, 0, 0), skirt_b=(28 + 6 * c2, 0, 0), cape=(32 + 6 * c2, 0, 0), **br)
        pose(rig, f, rots, {"hips": (0, 0.06, -0.09 + 0.035 * c2), **bl}, feet)
    close_clip(rig, act, "run-loop", "LINEAR")

    # Attack (Arcane Bolt): the casting hand draws back past the shoulder,
    # then snaps forward palm out on the release frame.
    c = slots["attack"]
    rel, rec = c["release_s"], c["recovery_s"]
    act, end = clip(rig, "attack", rel + rec, rel)
    keys = [(0, base(upper_arm_r=(4, 0, 4))),
            (rel * 0.6, base(chest=(0, 0, 18), upper_arm_r=(-30, 0, 35), forearm_r=(-80, 0, 0), hand_r=(0, 0, 20), upper_arm_l=(4, 0, -3))),
            (rel, base(chest=(-4, 0, -12), spine=(-4, 0, -4), upper_arm_r=(30, 0, -6), forearm_r=(10, 0, 0), hand_r=(25, 0, 0))),
            (rel + rec * 0.4, base(chest=(-3, 0, -10), upper_arm_r=(26, 0, -4), forearm_r=(6, 0, 0), hand_r=(20, 0, 0))),
            (rel + rec, base(upper_arm_r=(4, 0, 4)))]
    for t, rots in keys:
        pose(rig, round(t * FPS), rots, {"hips": (0, 0, -0.015)}, REST_FEET)
    close_clip(rig, act, "attack")

    # Binding Glyph: the hand rises and sweeps a circle, then points down at
    # the ground on release while the staff is planted forward.
    c = slots["ability_1"]
    rel, rec = c["release_s"], c["recovery_s"]
    act, end = clip(rig, "ability_1", rel + rec, rel)
    keys = [(0, base(upper_arm_r=(4, 0, 4))),
            (rel * 0.45, base(spine=(4, 0, 0), chest=(4, 0, 10), upper_arm_r=(110, 0, 20), forearm_r=(-20, 0, 0), hand_r=(-20, 0, 0), staff=(10, 0, 0))),
            (rel * 0.75, base(chest=(0, 0, -6), upper_arm_r=(95, 0, -30), forearm_r=(-10, 0, 0), staff=(10, 0, 0))),
            (rel, base(spine=(-10, 0, 0), chest=(-8, 0, -4), head=(14, 0, 0), upper_arm_r=(40, 0, -10), forearm_r=(-5, 0, 0), hand_r=(-35, 0, 0),
                       upper_arm_l=(14, 0, 0), staff=(-6, 0, 0))),
            (rel + rec, base(upper_arm_r=(4, 0, 4)))]
    for t, rots in keys:
        pose(rig, round(t * FPS), rots, {"hips": (0, 0, -0.03)}, REST_FEET)
    close_clip(rig, act, "ability_1")

    # Unmaking Lance: both hands gather at the chest as the body leans back,
    # then a lunge with both hands thrust forward on release.
    c = slots["ability_2"]
    rel, rec = c["release_s"], c["recovery_s"]
    act, end = clip(rig, "ability_2", rel + rec, rel)
    keys = [(0, base(upper_arm_r=(4, 0, 4))),
            (rel * 0.5, base(spine=(10, 0, 8), chest=(6, 0, 10), upper_arm_r=(20, 0, 50), forearm_r=(-95, 0, 0),
                             upper_arm_l=(30, 0, -20), forearm_l=(-50, 0, 0), staff=(-20, 0, 25))),
            (rel * 0.9, base(spine=(14, 0, 10), chest=(8, 0, 14), upper_arm_r=(10, 0, 60), forearm_r=(-110, 0, 0),
                             upper_arm_l=(26, 0, -24), forearm_l=(-55, 0, 0), staff=(-22, 0, 28))),
            (rel, base(spine=(-16, 0, -6), chest=(-8, 0, -10), upper_arm_r=(80, 0, -8), forearm_r=(0, 0, 0), hand_r=(20, 0, 0),
                       upper_arm_l=(60, 0, 10), forearm_l=(-10, 0, 0), staff=(-50, 0, -10))),
            (rel + rec * 0.5, base(spine=(-12, 0, -4), upper_arm_r=(70, 0, -6), forearm_r=(-4, 0, 0), upper_arm_l=(50, 0, 8), staff=(-40, 0, -8))),
            (rel + rec, base(upper_arm_r=(4, 0, 4)))]
    hips = {0: (0, 0, -0.01), rel * 0.5: (0, -0.06, -0.04), rel * 0.9: (0, -0.08, -0.05), rel: (0, 0.1, -0.09),
            rel + rec * 0.5: (0, 0.08, -0.07), rel + rec: (0, 0, -0.01)}
    for t, rots in keys:
        pose(rig, round(t * FPS), rots, {"hips": hips[t]}, REST_FEET)
    close_clip(rig, act, "ability_2")

    # Unmaking Word (ultimate): the staff is raised high in both hands and
    # driven down onto the ground on release; the body drops with it.
    c = slots["ability_3"]
    rel, rec = c["release_s"], c["recovery_s"]
    act, end = clip(rig, "ability_3", rel + rec, rel)
    keys = [(0, base(upper_arm_r=(4, 0, 4))),
            (rel * 0.7, base(spine=(10, 0, 0), chest=(8, 0, 0), head=(-12, 0, 0), upper_arm_l=(150, 0, 10), forearm_l=(-10, 0, 0), staff=(0, 0, 0),
                             upper_arm_r=(140, 0, -20), forearm_r=(-20, 0, 0), cape=(-10, 0, 0))),
            (rel, base(spine=(-22, 0, 0), chest=(-10, 0, 0), head=(10, 0, 0), upper_arm_l=(60, 0, 15), forearm_l=(-20, 0, 0), staff=(-10, 0, 0),
                       upper_arm_r=(50, 0, -30), forearm_r=(-30, 0, 0), cape=(30, 0, 0), skirt_b=(10, 0, 0))),
            (rel + rec * 0.6, base(spine=(-18, 0, 0), chest=(-8, 0, 0), upper_arm_l=(55, 0, 12), staff=(-8, 0, 0),
                                   upper_arm_r=(40, 0, -20), forearm_r=(-25, 0, 0), cape=(20, 0, 0))),
            (rel + rec, base(upper_arm_r=(4, 0, 4)))]
    hips = {0: (0, 0, -0.01), rel * 0.7: (0, -0.02, 0.0), rel: (0, 0.05, -0.18), rel + rec * 0.6: (0, 0.04, -0.15), rel + rec: (0, 0, -0.01)}
    for t, rots in keys:
        pose(rig, round(t * FPS), rots, {"hips": hips[t]}, REST_FEET)
    close_clip(rig, act, "ability_3")

    # Death: knees give, the body folds forward, then falls to the ground.
    act, end = clip(rig, "death", 1.2)
    keys = [(0.0, base(), (0, 0, -0.01), REST_FEET),
            (0.25, base(spine=(18, 0, 0), chest=(10, 0, 0), head=(-20, 0, 0), upper_arm_r=(-10, 0, 20), upper_arm_l=(-10, 0, -20), staff=(20, 0, -20)),
             (0, -0.05, -0.12), REST_FEET),
            (0.55, base(spine=(-30, 0, 6), chest=(-20, 0, 0), head=(25, 0, 0), upper_arm_r=(30, 0, 30), upper_arm_l=(20, 0, -40), staff=(-30, 0, -60),
                        skirt_f=(-20, 0, 0)), (0, 0.05, -0.45), REST_FEET),
            (0.9, base(hips=(-70, 0, 8), spine=(-14, 0, 4), chest=(-6, 0, 0), head=(10, 0, 20), upper_arm_r=(120, 0, 20), upper_arm_l=(100, 0, -30),
                       staff=(-50, 0, -80), skirt_f=(-30, 0, 0), cape=(40, 0, 0)),
             (0, 0.35, -0.72), {"l": (-0.13, -0.15, 0.09), "r": (0.12, -0.2, 0.12)}),
            (1.2, base(hips=(-82, 0, 10), spine=(-8, 0, 4), head=(14, 0, 24), upper_arm_r=(130, 0, 24), upper_arm_l=(110, 0, -30),
                       staff=(-50, 0, -85), skirt_f=(-30, 0, 0), cape=(40, 0, 0)),
             (0, 0.42, -0.8), {"l": (-0.13, -0.2, 0.08), "r": (0.12, -0.25, 0.1)})]
    for t, rots, hp, feet in keys:
        pose(rig, round(t * FPS), rots, {"hips": hp}, feet)
    close_clip(rig, act, "death")


def main():
    args = sys.argv[1:]
    if "--" in sys.argv:
        args = sys.argv[sys.argv.index("--") + 1:]
    out = args[0] if args else "/tmp/ruinscribe.blend"
    with open(SPEC) as f:
        spec = json.load(f)
    reset()
    rig = make_rig()
    M = materials()
    build_model(rig, M)
    mx, my, mz = spec["sockets"]["Muzzle"]
    hr = rig.data.bones["hand_r"]
    palm = hr.head_local + (hr.tail_local - hr.head_local).normalized() * 0.11
    socket("Muzzle", rig, "hand_r", palm)
    ox, oy, oz = spec["sockets"]["Overhead"]
    socket("Overhead", rig, "root", (ox, -oz, oy))
    socket("Focus", rig, "staff", (-0.33, 0.19, 1.84))
    animate(rig, spec)
    bpy.context.view_layer.update()
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(out))
    print("saved", out)


if __name__ == "__main__":
    main()
