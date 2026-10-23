# SPDX-License-Identifier: GPL-2.0-or-later
# (Uses Blender's Python API. This is a build tool, not part of the game.)
"""Shared kit for building PactFall champions from code in Blender.

Each tools/blender/build_<champion>.py imports this: a humanoid rig with leg
IK, a mesh kit (lathes, tubes, boxes, spheres) with UVs, distance skinning,
sockets, poses written as rotations about the armature's own axes, and clip
helpers that make one NLA track per clip with a release marker.

Blender axes: X right, Y forward (champions face +Y), Z up, metres.
"""
import math
import os

import bpy  # noqa: I001  (bpy first: it makes bmesh importable)
import bmesh
from mathutils import Matrix, Quaternion, Vector

FPS = 30
TAU = math.tau
HERE = os.path.dirname(os.path.abspath(__file__))
SPECS = os.path.join(HERE, "..", "..", "assets", "specs")


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    s = bpy.context.scene
    s.render.fps = FPS
    s.render.fps_base = 1.0
    return s


def humanoid_bones(s=1.0, w=1.0, extra=None):
    """The shared skeleton, scaled by s (height) and w (shoulder and hip width).
    Same names as the Ruinscribe rig; `extra` adds prop bones."""
    def P(x, y, z):
        return (x * w * s, y * s, z * s)
    b = {
        "root": ((0, 0, 0), (0, 0.25 * s, 0), None),
        "hips": (P(0, 0, 0.96), P(0, 0, 1.10), "root"),
        "spine": (P(0, 0, 1.10), P(0, 0.01, 1.28), "hips"),
        "chest": (P(0, 0.01, 1.28), P(0, 0, 1.47), "spine"),
        "neck": (P(0, 0, 1.47), P(0, 0.02, 1.57), "chest"),
        "head": (P(0, 0.02, 1.57), P(0, 0.02, 1.80), "neck"),
        "shoulder_r": (P(0.04, 0, 1.43), P(0.17, 0, 1.44), "chest"),
        "upper_arm_r": (P(0.17, 0, 1.44), P(0.25, 0.05, 1.19), "shoulder_r"),
        "forearm_r": (P(0.25, 0.05, 1.19), P(0.22, 0.30, 1.10), "upper_arm_r"),
        "hand_r": (P(0.22, 0.30, 1.10), P(0.21, 0.42, 1.09), "forearm_r"),
        "shoulder_l": (P(-0.04, 0, 1.43), P(-0.17, 0, 1.44), "chest"),
        "upper_arm_l": (P(-0.17, 0, 1.44), P(-0.27, 0.03, 1.20), "shoulder_l"),
        "forearm_l": (P(-0.27, 0.03, 1.20), P(-0.31, 0.16, 1.01), "upper_arm_l"),
        "hand_l": (P(-0.31, 0.16, 1.01), P(-0.32, 0.20, 0.93), "forearm_l"),
        "thigh_l": (P(-0.10, 0, 0.96), P(-0.11, 0.05, 0.53), "hips"),
        "shin_l": (P(-0.11, 0.05, 0.53), P(-0.11, 0, 0.09), "thigh_l"),
        "foot_l": (P(-0.11, 0, 0.09), P(-0.11, 0.17, 0.03), "root"),
        "thigh_r": (P(0.10, 0, 0.96), P(0.11, 0.05, 0.53), "hips"),
        "shin_r": (P(0.11, 0.05, 0.53), P(0.11, 0, 0.09), "thigh_r"),
        "foot_r": (P(0.11, 0, 0.09), P(0.11, 0.17, 0.03), "root"),
        "skirt_f": (P(0, 0.14, 0.90), P(0, 0.18, 0.40), "hips"),
        "skirt_b": (P(0, -0.15, 0.90), P(0, -0.22, 0.40), "hips"),
        "cape": (P(0, -0.17, 1.42), P(0, -0.25, 0.80), "chest"),
    }
    b.update(extra or {})
    return b


def make_rig(bones):
    arm = bpy.data.armatures.new("Rig")
    rig = bpy.data.objects.new("Rig", arm)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for name, (h, t, parent) in bones.items():
        b = arm.edit_bones.new(name)
        b.head, b.tail = h, t
        b.roll = 0.0
    for name, (h, t, parent) in bones.items():
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


class Mats(dict):
    """Materials made on first use; the game swaps them by name (ChampionModel.LOOKS)."""

    COLORS = {"Glow": (0.6, 0.9, 0.9), "Eyes": (0.6, 0.95, 0.9)}

    def __missing__(self, name):
        rgb = self.COLORS.get(name, (0.5, 0.5, 0.5))
        m = mat(name, rgb, 0.6, 0.0, rgb if name in ("Glow", "Eyes") else None)
        self[name] = m
        return m


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

    def arc_lathe(self, profile, mname, th0, th1, seg=16, sx=1.0, sy=1.0, center=(0, 0)):
        """A lathe over part of the circle, theta from th0 to th1 (0 is the front, +Y)."""
        rings = []
        for r, z in profile:
            rings.append([Vector((center[0] + math.sin(th) * r * sx, center[1] + math.cos(th) * r * sy, z))
                          for th in [th0 + (th1 - th0) * k / seg for k in range(seg + 1)]])
        return self.ring_grid(rings, mname, closed=False)

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


def base(names, **over):
    d = {b: (0, 0, 0) for b in names}
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




# ---------------------------------------------------------------- shared body and clips

BODY = ["hips", "spine", "chest", "neck", "head", "shoulder_r", "upper_arm_r", "forearm_r", "hand_r",
        "shoulder_l", "upper_arm_l", "forearm_l", "hand_l", "skirt_f", "skirt_b", "cape", "root"]


def rest_feet(rig):
    return {side: tuple(rig.data.bones["foot_" + side].head_local) for side in ("l", "r")}


def limbs(rig, M, legs="Cloth", boots="Leather", hands="Skin", leg_r=(0.085, 0.075, 0.06, 0.055), boot_scale=1.0,
          cuff="Leather"):
    """Legs, boots and hands for the shared skeleton."""
    b = rig.data.bones
    for side in ("l", "r"):
        hip = b["thigh_" + side].head_local
        knee = b["shin_" + side].head_local
        ankle = b["foot_" + side].head_local
        x = ankle.x
        k = Kit("Leg_" + side, M)
        k.tube([hip, hip.lerp(knee, 0.5), knee, knee.lerp(ankle, 0.5)], list(leg_r), legs, seg=10)
        k.tube([knee.lerp(ankle, 0.45), ankle + Vector((0, 0, 0.02))], [leg_r[2] * 1.1, leg_r[3] * 1.12], cuff, seg=10)
        k.finish(rig, ["thigh_" + side, "shin_" + side], subsurf=1)
        f = Kit("Boot_" + side, M)
        bs = boot_scale
        f.tube([Vector((x, -0.05 * bs, 0.05)), Vector((x, 0.06 * bs, 0.045)), Vector((x, 0.15 * bs, 0.035))],
               [0.05 * bs, 0.048 * bs, 0.038 * bs], boots, seg=10)
        f.box(Vector((x, 0.04 * bs, 0.008)), (0.09 * bs, 0.24 * bs, 0.016), boots)
        f.finish(rig, "foot_" + side, subsurf=1)
        if hands:
            hand(rig, M, side, hands)


def hand(rig, M, side, mname="Skin", fist=False):
    b = rig.data.bones
    sx = 1.0 if side == "r" else -1.0
    wr = b["hand_" + side].head_local
    d = (b["hand_" + side].tail_local - wr).normalized()
    palm = wr + d * 0.05
    h = Kit("Hand_" + side, M)
    h.sphere(palm, 0.045, mname, scale=(0.75, 1.0, 0.6))
    for f in (-1.0, 1.0):
        off = Vector((0.018 * f, 0, 0))
        curl = Vector((0, 0, -0.05)) if fist else Vector((0, 0, -0.03))
        h.tube([palm + d * 0.03 + off, palm + d * 0.075 + off + curl * 0.4, palm + d * (0.07 if fist else 0.1) + off + curl],
               [0.016, 0.014, 0.011], mname, seg=6)
    h.tube([palm + Vector((-0.03 * sx, 0, 0)), palm + Vector((-0.05 * sx, 0.03, -0.01))], [0.015, 0.012], mname, seg=6)
    h.finish(rig, "hand_" + side)


def sleeve(rig, M, side, mname, radii=(0.075, 0.068, 0.062, 0.06, 0.062), cuff=None, cuff_r=0.075):
    b = rig.data.bones
    sh = b["upper_arm_" + side].head_local
    el = b["forearm_" + side].head_local
    wr = b["hand_" + side].head_local
    k = Kit("Sleeve_" + side, M)
    pts = [sh + Vector((0, 0, 0.02)), sh.lerp(el, 0.5), el, el.lerp(wr, 0.6), wr + (wr - el).normalized() * 0.01]
    k.tube(pts, list(radii), mname, seg=12, cap=False)
    if cuff:
        dd = (wr - el).normalized()
        k.tube([wr - dd * 0.06, wr + dd * 0.005], [cuff_r, cuff_r * 1.04], cuff, seg=12, cap=False)
    k.finish(rig, ["upper_arm_" + side, "forearm_" + side, "shoulder_" + side, "chest"], subsurf=1, solidify=0.006)


def run_clip(rig, speed, upper, cycle=0.6, stance=0.2, hips_drop=0.09, lift=0.26, kick=0.22, step=1):
    """Run cycle: each foot planted for `stance` of the cycle and slid back at
    `speed` (so it does not slide in the game). upper(t, s, c2) -> (rots, locs)
    for the upper body, t in 0..1."""
    stride = speed * cycle * stance
    feet0 = rest_feet(rig)
    act, end = clip(rig, "run", cycle)
    for f in range(0, end + 1, step):
        t = f / end
        feet = {}
        for side, ph in (("l", 0.0), ("r", 0.5)):
            x, y0, z0 = feet0[side]
            u = (t + ph) % 1.0
            if u < stance:
                y, z = stride * 0.5 - stride * (u / stance), z0
            else:
                w = (u - stance) / (1 - stance)
                y = -stride * 0.5 + stride * (0.5 - 0.5 * math.cos(math.pi * w))
                y -= kick * math.sin(math.pi * w)
                z = z0 + lift * math.sin(math.pi * w) ** 1.5
            feet[side] = (x, y + 0.08, z)
        s = math.sin(t * TAU)
        c2 = math.cos(t * TAU * 2)
        rots, locs = upper(t, s, c2)
        locs = dict(locs)
        locs.setdefault("hips", (0, 0.06, -hips_drop + 0.035 * c2))
        pose(rig, f, rots, locs, feet)
    close_clip(rig, act, "run-loop", "LINEAR")


def idle_clip(rig, length, fn, step=6):
    """fn(t, s) -> (rots, locs) with s a slow sine over the loop."""
    act, end = clip(rig, "idle", length)
    feet = rest_feet(rig)
    for f in range(0, end + 1, step):
        t = f / FPS
        rots, locs = fn(t, math.sin(t / length * TAU))
        pose(rig, f, rots, locs, feet)
    close_clip(rig, act, "idle-loop")


def cast_clip(rig, name, rel, rec, keys, feet=None):
    """keys: [(time, rots, hips_offset)]; times may use rel and rel + rec."""
    act, end = clip(rig, name, rel + rec, rel)
    feet = feet or rest_feet(rig)
    for t, rots, hp in keys:
        pose(rig, round(t * FPS), rots, {"hips": hp}, feet)
    close_clip(rig, act, name)


def death_clip(rig, names, extra=None):
    """Knees give, the body folds forward, then falls. extra(t) -> rots to add."""
    s = rig.data.bones["thigh_l"].head_local.z / 0.96
    act, end = clip(rig, "death", 1.2)
    fl, fr = rest_feet(rig)["l"], rest_feet(rig)["r"]
    keys = [(0.0, {}, (0, 0, -0.01), None),
            (0.25, dict(spine=(18, 0, 0), chest=(10, 0, 0), head=(-20, 0, 0), upper_arm_r=(-10, 0, 20), upper_arm_l=(-10, 0, -20)),
             (0, -0.05, -0.12), None),
            (0.55, dict(spine=(-30, 0, 6), chest=(-20, 0, 0), head=(25, 0, 0), upper_arm_r=(30, 0, 30), upper_arm_l=(20, 0, -40),
                        skirt_f=(-20, 0, 0)), (0, 0.05, -0.45 * s), None),
            (0.9, dict(hips=(-70, 0, 8), spine=(-14, 0, 4), chest=(-6, 0, 0), head=(10, 0, 20), upper_arm_r=(120, 0, 20),
                       upper_arm_l=(100, 0, -30), skirt_f=(-30, 0, 0), cape=(40, 0, 0)),
             (0, 0.35 * s, -0.72 * s), {"l": (fl[0], -0.15, fl[2]), "r": (fr[0], -0.2, fr[2] + 0.03)}),
            (1.2, dict(hips=(-82, 0, 10), spine=(-8, 0, 4), head=(14, 0, 24), upper_arm_r=(130, 0, 24), upper_arm_l=(110, 0, -30),
                       skirt_f=(-30, 0, 0), cape=(40, 0, 0)),
             (0, 0.42 * s, -0.8 * s), {"l": (fl[0], -0.2, fl[2] - 0.01), "r": (fr[0], -0.25, fr[2] + 0.01)})]
    for t, rots, hp, feet in keys:
        r = base(names, **rots)
        if extra:
            r.update(extra(t))
        pose(rig, round(t * FPS), r, {"hips": hp}, feet or rest_feet(rig))
    close_clip(rig, act, "death")


def save(out):
    bpy.context.view_layer.update()
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(out))
    print("saved", out)


def load_spec(name):
    import json
    with open(os.path.join(SPECS, name + ".json")) as f:
        return json.load(f)


def out_path(argv, default):
    import sys
    args = sys.argv[1:]
    if "--" in sys.argv:
        args = sys.argv[sys.argv.index("--") + 1:]
    return args[0] if args else default
