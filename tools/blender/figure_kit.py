# SPDX-License-Identifier: GPL-2.0-or-later
# (Uses Blender's Python API. This is a build tool, not part of the game.)
"""Faces, hands, hair and baked shading for champions built from code.

A Figure is the CC0 Blender Studio body (body_fit.py) fitted to a champion's
rig with its head, arms and hands kept. On top of that this module builds what
makes a face read: a head reshaped from the base mesh's cartoon proportions
toward an adult's, eyeballs with a painted iris, lids, a lash line and brows;
pointed ears; fingers that curl round a grip; hair as chunky locks swept over
the skull. All of it is geometry written here.

bake() then paints every mesh's vertices with what a texture artist would
bake: ambient occlusion from the whole figure (ray cast here, in Python), wear
on raised edges, grime in creases and toward the ground, and any paint a build
asks for (lips, a blush, an iris). The game multiplies its materials by these
colours (ChampionModel), so they cost nothing at run time.

Landmark numbers (eye, mouth, ear positions) were measured on the female body
fitted to the Thornwright rig; Figure.at() moves them to any other head.
"""
import math
import random

import bpy  # noqa: I001  (bpy first: it makes bmesh importable)
import bmesh
from mathutils import Matrix, Vector, kdtree, noise
from mathutils.bvhtree import BVHTree

import body_fit as bf
import champion_kit as ck

TAU = math.tau
## Vertex colour of an untouched surface. The game multiplies albedo by
## colour / NEUTRAL, so worn edges can come out lighter than the material.
NEUTRAL = 0.8
## Head bone the landmarks were measured on (Thornwright: S = 0.95).
REF_HEAD = Vector((0.0, 0.019, 1.4915))
REF_LEN = 0.2185
## On that head: the middle of each eye's opening, the ears' root, and where
## the skull turns into the neck.
EYE = Vector((0.0585, 0.105, 1.563))
EAR_X = 0.108  # with z below EAR_TOP: the skull is wider than this higher up
EAR_TOP = 1.595
NECK = Vector((0.0, 0.0, 1.425))
TORSO = ("hips", "spine", "chest")


def smooth(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a))) if a != b else float(x >= a)
    return t * t * (3.0 - 2.0 * t)


def hand_frame(wrist, tail, side):
    """(along the hand, out of the palm, toward the thumb) for a hand bone."""
    u = (Vector(tail) - Vector(wrist)).normalized()
    sa, sb = (Vector(x) for x in bf.SRC["hand_" + side])
    rot = (sb - sa).normalized().rotation_difference(u)
    # On the source body the palms face the thighs and the thumbs point ahead.
    n = rot @ Vector((-1.0 if side == "r" else 1.0, 0, 0))
    n = (n - u * n.dot(u)).normalized()
    t = u.cross(n).normalized()
    if (rot @ Vector((0, 1, 0))).dot(t) < 0:
        t = -t
    return u, n, t


def move_bone(rig, name, head, tail):
    """Re-seats a prop bone once the figure says where the hand grips."""
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    b = rig.data.edit_bones[name]
    b.head, b.tail = head, tail
    b.roll = 0.0
    bpy.ops.object.mode_set(mode="OBJECT")


class Figure:
    def __init__(self, rig, body="female", girth=None, ears=0.0, fists=None, head=1.0, mature=0.0):
        """ears: how far the ear tips are drawn out (0 round, 1 a long elf ear).
        fists: side -> curl of the fingers (0 open, 1 a loose hand, 2.2 a grip).
        head: scale of the whole head (the base mesh's is large).
        mature: 0 keeps the base mesh's young face, 1 gives smaller eyes, a
        longer jaw and a lower crown."""
        self.rig = rig
        f = bf.fit(rig, girth, body, keep=bf.KEEP + bf.ARMS)
        self.vs, self.ts, self.fs, self.owner = list(f[0]), f[1], f[2], f[3]
        hb = rig.data.bones["head"]
        self.h0 = hb.head_local.copy()
        self.bs = (hb.tail_local - hb.head_local).length / REF_LEN
        self.head_scale = head
        self.mature = mature
        self.ear_amount = ears
        self.hs = self.bs * head  # sizes of things on the face
        self.ear = set()
        for i, p in enumerate(self.vs):
            if self.owner[i] not in ("head", "neck"):
                continue
            r = REF_HEAD + (p - self.h0) / self.bs
            if abs(r.x) > EAR_X and r.z < EAR_TOP:
                self.ear.add(i)
                r = self._ear(r)
            self.vs[i] = self._unref(self._warp(r))
        self.grip = {}
        for side, amount in (fists or {}).items():
            self._curl(side, amount)
        self.fitted = (self.vs, self.ts, self.fs, self.owner)
        self._bvh = {}
        self._kd = None

    def _unref(self, r):
        return self.h0 + (r - REF_HEAD) * self.bs

    def _ear(self, r):
        """Lays the base mesh's round ear back against the head and draws its
        top out to a point."""
        sx = 1.0 if r.x > 0 else -1.0
        out = abs(r.x) - 0.104
        a = self.ear_amount
        q = Vector((sx * (0.104 + out * (1.0 - 0.38 * min(a, 1.0))), r.y - out * 0.25 * min(a, 1.0), r.z))
        # The upper half is drawn up and back, more the higher it started.
        w = smooth(1.52, 1.59, r.z) ** 1.3 * a * smooth(0.003, 0.02, out)
        if w > 0.0:
            mid = -0.005
            q = Vector((q.x + sx * 0.01 * w, mid + (q.y - mid) * (1.0 - 0.5 * w) - 0.085 * w, q.z + 0.11 * w))
        return q

    def _warp(self, r, pinch=True):
        """Reference head -> the reshaped head, still in reference coordinates."""
        m = self.mature
        q = r.copy()
        if m > 0.0:
            if pinch:
                # Smaller eyes: the face round each eye is drawn in toward it.
                k = 1.0 - 0.32 * m
                rad = 0.066
                d = Vector((0, 0, 0))
                for sx in (-1.0, 1.0):
                    v = r - Vector((sx * EYE.x, EYE.y, EYE.z))
                    t = v.length / rad
                    if t < 1.0:
                        d += v * ((k + (1.0 - k) * t * t) - 1.0)
                q += d
            if q.z < 1.535:  # a longer lower face
                q.z -= (1.535 - q.z) * 0.13 * m * smooth(1.34, 1.41, q.z)
            if q.z > 1.6:  # a lower, narrower crown
                t = smooth(1.6, 1.71, q.z)
                q.x *= 1.0 - 0.05 * m * t
                q.y *= 1.0 - 0.05 * m * t
                q.z = 1.6 + (q.z - 1.6) * (1.0 - 0.07 * m)
            # A narrower jaw and flatter cheeks.
            t = smooth(1.38, 1.46, q.z) * (1.0 - smooth(1.5, 1.57, q.z)) * smooth(-0.02, 0.05, q.y)
            q.x *= 1.0 - 0.13 * m * t
        w = smooth(1.36, 1.42, q.z)
        return NECK + (q - NECK) * (1.0 - (1.0 - self.head_scale) * w)

    def at(self, x, y, z, pinch=False):
        """A point given in the reference head's coordinates, on this head."""
        return self._unref(self._warp(Vector((x, y, z)), pinch))

    def _curl(self, side, amount):
        """Bends the four fingers toward the palm about the knuckle line, and
        the thumb in over them."""
        b = self.rig.data.bones["hand_" + side]
        wrist = b.head_local.copy()
        u, n, t = hand_frame(wrist, b.tail_local, side)
        idx = [i for i, o in enumerate(self.owner) if o == "hand_" + side]
        if not idx:
            return
        length = max((self.vs[i] - wrist).dot(u) for i in idx)
        u0 = length * 0.5
        k = amount * (math.pi * 0.5) / max(length - u0, 1e-4)
        if k <= 0.0:
            return
        radius = 1.0 / k
        c0 = 0.024 * (length / 0.155)
        phi = math.radians(25.0) * amount
        for i in idx:
            rel = self.vs[i] - wrist
            a, c, h = rel.dot(u), rel.dot(t), rel.dot(n)
            if c > c0:  # the thumb folds in over the palm
                w = smooth(c0, c0 + 0.012, c)
                cc, hh = c - c0, h
                c2 = c0 + cc * math.cos(phi * w) - hh * math.sin(phi * w)
                h2 = cc * math.sin(phi * w) + hh * math.cos(phi * w)
                self.vs[i] = wrist + u * a + t * c2 + n * h2
                continue
            if a <= u0:  # the palm stays
                continue
            th = k * (a - u0)
            rho = radius - h
            self.vs[i] = wrist + u * (u0 + rho * math.sin(th)) + t * c + n * (radius - rho * math.cos(th))
        # What the fingers now wrap: (centre, axis, radius of the hollow).
        self.grip[side] = (wrist + u * u0 + n * radius - t * 0.008, t, max(0.008, radius - 0.011))

    # ------------------------------------------------------------ body parts

    def faces(self, test):
        return bf.region(self.fitted, test)

    def add(self, kit, mname, test, offset=0.0, uv_scale=3.0, tint=0.0):
        """Adds the body faces passing test(index, owner, position) to a Kit,
        pushed out by offset (a distance or fn(index, position)). Returns the
        open edges as ordered loops."""
        return bf.add_faces(kit, self.fitted, self.faces(test), mname, offset=offset, uv_scale=uv_scale, tint=tint)

    def bvh(self, owners, ears=True):
        """BVH of the body faces owned by `owners`."""
        key = (tuple(owners), ears)
        if key not in self._bvh:
            idx = {}
            verts, polys = [], []
            for f in self.fs:
                if all(self.owner[vi] in owners and (ears or vi not in self.ear) for vi, _ in f):
                    poly = []
                    for vi, _ in f:
                        if vi not in idx:
                            idx[vi] = len(verts)
                            verts.append(self.vs[vi])
                        poly.append(idx[vi])
                    polys.append(poly)
            self._bvh[key] = BVHTree.FromPolygons(verts, polys)
        return self._bvh[key]

    def skull(self):
        """The head without its ears, for laying hair and brows on."""
        return self.bvh(("head", "neck"), ears=False)

    def on_head(self, direction, lift=0.0, centre=None):
        """The point where a ray from far out along `direction` meets the head,
        lifted off the surface by `lift`."""
        c = centre if centre is not None else self.at(0, 0.0, 1.6)
        d = Vector(direction).normalized()
        hit = self.skull().ray_cast(c + d * 0.6, -d)
        if hit[0] is None or (hit[0] - c).dot(d) < 0.03 * self.hs:
            return c + d * (0.105 * self.hs + lift)
        return hit[0] + d * lift

    def front(self, x, z, lift=0.0):
        """The face's surface straight in front of (x, z) in reference coordinates."""
        p = self.at(x, 0.0, z, pinch=True)
        p.y = self.h0.y + 0.5
        hit = self.skull().ray_cast(p, Vector((0, -1, 0)))
        if hit[0] is None:
            return self.at(x, 0.12, z)
        return hit[0] + Vector((0, lift, 0))

    def onto(self, p, toward, lift=0.0, owners=TORSO + ("neck",) + bf.ARMS):
        """Where a ray from p toward the point `toward` meets the body, lifted
        back out by `lift`. None if it misses."""
        p, toward = Vector(p), Vector(toward)
        d = (toward - p).normalized()
        hit = self.bvh(owners).ray_cast(p, d)
        if hit[0] is None:
            return None
        return hit[0] - d * lift

    def around(self, z, th, lift=0.0, centre=(0.0, 0.0), owners=TORSO, far=0.6):
        """The torso's surface at height z in direction th (0 front, + toward
        +X), lifted out by `lift`."""
        c = Vector((centre[0], centre[1], z))
        d = Vector((math.sin(th), math.cos(th), 0.0))
        p = self.onto(c + d * far, c, lift, owners)
        return p if p is not None else c + d * (0.12 + lift)

    # ------------------------------------------------------------ skinning

    def skin_head(self, obj):
        """Everything above the jaw moves with the head alone; below it the
        bones the object was finished with (neck, chest) take over smoothly."""
        head = obj.vertex_groups.new(name="head")
        bs = self.bs
        for v in obj.data.vertices:
            r = REF_HEAD + (v.co - self.h0) / bs
            # The jaw line, higher at the nape than under the chin.
            w = smooth(-0.03, 0.012, r.z - (1.435 - 0.55 * r.y))
            if w <= 0.0:
                continue
            for g in obj.vertex_groups:
                if g.index != head.index:
                    try:
                        cur = g.weight(v.index)
                    except RuntimeError:
                        continue
                    if w >= 1.0:
                        g.remove([v.index])
                    else:
                        g.add([v.index], cur * (1.0 - w), "REPLACE")
            head.add([v.index], w, "REPLACE")

    def pin(self, obj, owners):
        """Vertices made from body parts in `owners` move with that one bone
        (a hand keeps its shape)."""
        if self._kd is None:
            self._kd = kdtree.KDTree(len(self.vs))
            for i, p in enumerate(self.vs):
                self._kd.insert(p, i)
            self._kd.balance()
        groups = {g.name: g for g in obj.vertex_groups}
        for v in obj.data.vertices:
            _, i, _ = self._kd.find(v.co)
            o = self.owner[i]
            if o not in owners:
                continue
            for g in obj.vertex_groups:
                g.remove([v.index])
            if o not in groups:
                groups[o] = obj.vertex_groups.new(name=o)
            groups[o].add([v.index], 1.0, "REPLACE")

    # ------------------------------------------------------------ face

    def eyes(self, M, iris=(0.2, 0.42, 0.16), lid=0.2, lower=0.44, white="EyeWhite", skin="Skin", lash="Hair",
             radius=0.0232, depth=0.0195, tilt=5.0):
        """Eyeballs with a painted iris, lids and a lash line. Returns the Kit
        (finish it on the head bone) and a painter for bake().
        lid, lower: how far the upper and lower lids close (sine of the angle
        from the eye's level). tilt: degrees the outer corners sit higher."""
        k = ck.Kit("Eyes", M)
        r = radius * self.hs
        centres = []
        for sx in (-1.0, 1.0):
            c = self.at(sx * EYE.x, EYE.y, EYE.z) - Vector((0, depth * self.hs, 0))
            centres.append(c)
            # Rings round the line of sight, close together where the pupil
            # and the iris end, so their painted edges come out crisp.
            rings = []
            for ang in (112, 95, 78, 62, 48, 38, 31, 28, 26, 23, 19, 15, 11.5, 9.5, 6, 2.5):
                a = math.radians(ang)
                rings.append([c + Vector((math.sin(a) * math.cos(i / 24 * TAU), math.cos(a), math.sin(a) * math.sin(i / 24 * TAU))) * r
                              for i in range(24)])
            k.ring_grid(rings, white, cap_top=True)
            roll = Matrix.Rotation(math.radians(-tilt * sx), 3, "Y")

            def ball(az, el, rr, c=c, roll=roll):
                return c + roll @ (Vector((math.sin(az) * math.cos(el), math.cos(az) * math.cos(el), math.sin(el))) * rr)
            # Lids: the top and bottom front of a slightly larger ball.
            r2 = r * 1.06
            for lo, hi in ((math.asin(lid), math.radians(88)), (-math.radians(88), -math.asin(lower))):
                rows = []
                for j in range(6):
                    el = lo + (hi - lo) * j / 5.0
                    rows.append([ball(math.radians(-100 + 200 * i / 16.0), el, r2) for i in range(17)])
                k.ring_grid(rows, skin, closed=False)
            # Lash line along the upper lid's edge, flicked out at the outer corner.
            pts, rad = [], []
            n = 12
            for i in range(n + 1):
                az = math.radians(-84 + 168 * i / n)
                pts.append(ball(az, math.asin(lid) - 0.02, r2 * 1.012))
                outer = (i / n) if sx > 0 else 1.0 - i / n
                rad.append(0.0017 * self.hs * (0.5 + 0.5 * math.sin(math.pi * i / n)) * (0.7 + 0.6 * outer))
            flick = Vector((sx * 0.007, -0.003, 0.004)) * self.hs
            if sx > 0:
                pts.append(pts[-1] + flick)
                rad.append(0.0004)
            else:
                pts.insert(0, pts[0] + flick)
                rad.insert(0, 0.0004)
            k.tube(pts, rad, lash, seg=5)
        ir = Vector(iris)

        def paint(p, nrm, mat, col):
            if mat != white:
                return col
            c = min(centres, key=lambda q: (q - p).length_squared)
            d = (p - c).normalized()
            ang = math.degrees(math.acos(max(-1.0, min(1.0, d.dot(Vector((0, 1, 0)))))))
            if ang < 10.5:
                return Vector((0.02, 0.02, 0.02))
            if ang < 27.0:
                # A dark rim, a paler ring round the pupil, and more light in
                # the lower half, where it gathers in an iris.
                return ir * (1.0 + 0.5 * (1.0 - smooth(11.0, 20.0, ang))) * (1.0 - 0.6 * smooth(22.0, 26.5, ang)) * (1.0 + 0.5 * max(0.0, -d.z) / 0.4)
            # The white, shaded toward the lids so it is never a flat disc.
            return Vector((0.9, 0.88, 0.84)) * (1.0 - 0.35 * smooth(27.0, 75.0, ang))
        return k, paint

    def brows(self, kit, mname="Hair", arch=0.003, width=0.0044, z=1.59, tilt=0.009):
        """Brows laid on the brow ridge: thick by the nose, tapering out."""
        for sx in (-1.0, 1.0):
            pts, rad = [], []
            for i in range(9):
                t = i / 8.0
                x = sx * (0.02 + 0.074 * t)
                zz = z + tilt * t + arch * math.sin(math.pi * min(1.0, t * 1.3)) - 0.012 * max(0.0, t - 0.6) ** 2 / 0.16
                pts.append(self.front(x, zz, 0.0))
                rad.append(width * self.hs * (0.8 + 0.3 * math.sin(math.pi * min(1.0, t + 0.3))) * (1.0 - 0.8 * t * t))
            sweep(kit, pts, rad, [x * 0.45 for x in rad], mname, seg=6, side=Vector((0, 0, 1)))
        return kit

    def face_paint(self, lips=(1.0, 0.56, 0.52), blush=(1.08, 0.86, 0.84), shadow=0.84):
        """Painter for the head mesh: lips, the inside of the mouth and sockets,
        a blush on the cheeks, nose and ears, and a soft dark round the eyes."""
        mouth = self.at(0, 0.13, 1.4705)
        hs = self.hs
        eyes = [self.at(sx * EYE.x, EYE.y, EYE.z) for sx in (-1.0, 1.0)]
        cheeks = [self.at(sx * 0.066, 0.11, 1.512) for sx in (-1.0, 1.0)]
        nose = self.at(0, 0.15, 1.512)
        lipc, blushc = Vector(lips), Vector(blush)
        ear_x = (EAR_X + 0.01) * hs
        skull = self.skull()

        def mul(col, k, w):
            return Vector((col.x * (1 + (k.x - 1) * w), col.y * (1 + (k.y - 1) * w), col.z * (1 + (k.z - 1) * w)))

        def paint(p, nrm, mat, col):
            if mat != "Skin":
                return col
            d = p - mouth
            # Inside of the mouth (anything with the lips in front of it): nearly black.
            if abs(d.x) < 0.05 * hs and abs(d.z) < 0.035 * hs and -0.12 * hs < d.y < -0.012 * hs:
                if skull.ray_cast(p + Vector((0, 0.003, 0)), Vector((0, 1, 0)), 0.1)[0] is not None:
                    return Vector((0.12, 0.05, 0.05))
            out = col.copy()
            # Lips: fuller in the middle, thinning to the corners.
            half = (0.026 - 0.017 * (abs(d.x) / (0.047 * hs)) ** 2) * hs
            if abs(d.x) < 0.047 * hs and half > 0 and d.y > -0.022 * hs:
                up = half * 0.8 if d.z > 0 else half
                out = mul(out, lipc, 1.0 - smooth(up * 0.55, up, abs(d.z)))
            w = 0.0
            for c in cheeks:
                w = max(w, 1.0 - smooth(0.0, 0.042 * hs, (p - c).length))
            w = max(w, 0.7 * (1.0 - smooth(0.0, 0.022 * hs, (p - nose).length)))
            if abs(p.x - self.h0.x) > ear_x:
                w = max(w, 0.6)
            out = mul(out, blushc, w)
            for e in eyes:
                de = p - e
                if de.y > -0.02 * hs:
                    out *= 1.0 - (1.0 - shadow) * (1.0 - smooth(0.02 * hs, 0.05 * hs, Vector((de.x, de.z * 1.25)).length))
            return out
        return paint

    # ------------------------------------------------------------ hair

    def scalp(self, kit, mname, hairline, offset=0.004, seg=40, rows=8):
        """A close cap of hair from the crown down to `hairline(azimuth_deg) ->
        elevation_deg`, so no skin shows between the locks."""
        rings = []
        for j in range(rows):
            ring = []
            for i in range(seg):
                az = -180.0 + 360.0 * i / seg
                lim = hairline(az)
                el = lim + (87.0 - lim) * (j / (rows - 1.0)) ** 0.85
                ring.append(self.on_head(self.direction(az, el), offset * self.hs))
            rings.append(ring)
        return kit.ring_grid(rings, mname, cap_top=True)

    @staticmethod
    def angles(p, c):
        d = p - c
        az = math.degrees(math.atan2(d.x, d.y))  # 0 front, +-180 back
        el = math.degrees(math.atan2(d.z, math.hypot(d.x, d.y)))
        return az, el

    @staticmethod
    def direction(az, el):
        a, e = math.radians(az), math.radians(el)
        return Vector((math.sin(a) * math.cos(e), math.cos(a) * math.cos(e), math.sin(e)))

    def lock(self, kit, mname, start, end, width=0.03, lift=0.008, body=0.012, n=9, seed=0, thick=0.45, taper=0.55,
             via=None):
        """A lock of hair laid over the skull from direction `start` to
        direction `end` (each (azimuth, elevation) in degrees), by way of `via`."""
        stops = [self.direction(*start)] + ([self.direction(*via)] if via else []) + [self.direction(*end)]
        pts, rad, nrm = [], [], []
        for i in range(n):
            t = i / (n - 1.0)
            if len(stops) == 3:
                d = stops[0].slerp(stops[1], t * 2.0) if t < 0.5 else stops[1].slerp(stops[2], t * 2.0 - 1.0)
            else:
                d = stops[0].slerp(stops[1], t)
            pts.append(self.on_head(d, (lift + body * math.sin(math.pi * t)) * self.hs))
            nrm.append(d)
            rad.append(width * 0.5 * self.hs * (1.0 - (1.0 - taper) * t) * (0.3 + 0.7 * smooth(0.0, 0.22, t)))
        strand(kit, pts, rad, mname, seed=seed, thick=thick, normals=nrm)
        return pts

    def strap(self, kit, mname, centre, a, b, width=0.03, lift=0.012, owners=TORSO, n=36, crown=0.003, far=0.5, tint_by=0.0):
        """A band lying on the body round `centre`, in the plane of the
        directions a and b. Returns the ring down its middle."""
        centre, a, b = Vector(centre), Vector(a).normalized(), Vector(b).normalized()
        across = a.cross(b).normalized()
        rows = [[], [], []]
        for i in range(n):
            ph = i / n * TAU
            d = a * math.cos(ph) + b * math.sin(ph)
            for w in (-1, 0, 1):
                o = centre + across * (w * width * 0.5)
                hit = self.onto(o + d * far, o, lift + (crown if w == 0 else 0.0), owners)
                rows[w + 1].append(hit if hit is not None else o + d * 0.1)
        vs = kit.ring_grid(rows, mname, closed=True)
        if tint_by:
            tint(vs, tint_by, kit)
        return rows[1]


def sweep(kit, pts, rx, ry, mname, seg=8, side=None, cap=True):
    """A tube along pts with an oval section: rx across (along `side`, one
    vector or one per point), ry through. Frames are carried along the path,
    so it does not twist where a path turns straight up or down."""
    pts = [Vector(p) for p in pts]
    n = len(pts)
    rx = rx if isinstance(rx, (list, tuple)) else [rx] * n
    ry = ry if isinstance(ry, (list, tuple)) else [ry] * n
    rings = []
    x = None
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
        hint = side[i] if isinstance(side, (list, tuple)) else side
        if hint is not None:
            x = Vector(hint)
        elif x is None:
            x = Vector((1, 0, 0)) if abs(t.x) < 0.9 else Vector((0, 1, 0))
        x = (x - t * x.dot(t)).normalized()
        y = t.cross(x)
        rings.append([p + x * (math.cos(k / seg * TAU) * rx[i]) + y * (math.sin(k / seg * TAU) * ry[i]) for k in range(seg)])
    return kit.ring_grid(rings, mname, cap_bottom=cap, cap_top=cap)


def strand(kit, pts, rad, mname, seed=0, thick=0.45, seg=10, depth=0.3, normals=None):
    """A flattened tube tinted in streaks that run its length, so a lock reads
    as many hairs. normals: the surface it lies on, per point (its flat side
    faces them)."""
    rnd = random.Random(seed * 7919 + 17)
    streak = [(rnd.random() - 0.6) * depth * 2.0 for _ in range(seg)]
    side = None
    if normals is not None:
        side = []
        for i in range(len(pts)):
            t = (Vector(pts[min(i + 1, len(pts) - 1)]) - Vector(pts[max(i - 1, 0)])).normalized()
            side.append(t.cross(Vector(normals[i])))
    vs = sweep(kit, pts, list(rad), [r * thick for r in rad], mname, seg=seg, side=side)
    for ring in vs:
        for i, v in enumerate(ring):
            v[kit.tint] = streak[i % seg]
    return vs


def slab(kit, origin, ex, ey, ez, mname):
    """A box from a corner and its three edges."""
    ex, ey, ez = Vector(ex), Vector(ey), Vector(ez)
    c = Vector(origin) + (ex + ey + ez) * 0.5
    m = Matrix(((ex.x, ey.x, ez.x, c.x), (ex.y, ey.y, ez.y, c.y), (ex.z, ey.z, ez.z, c.z), (0, 0, 0, 1)))
    mi = kit._mi(mname)
    res = bmesh.ops.create_cube(kit.bm, size=1.0, matrix=m, calc_uvs=True)
    for v in res["verts"]:
        for f in v.link_faces:
            f.material_index = mi
    return res["verts"]


def tint(verts, amount, kit):
    """Tints BMVerts (as returned by Kit.ring_grid / tube: lists of rings)."""
    for ring in verts:
        for v in (ring if isinstance(ring, (list, tuple)) else [ring]):
            v[kit.tint] = amount


# ---------------------------------------------------------------- baking

def _apply_modifiers(obj, depsgraph):
    """Bakes every modifier but the armature into the mesh (rest pose)."""
    arm = [m for m in obj.modifiers if m.type == "ARMATURE"]
    if len(arm) == len(obj.modifiers):
        return
    for m in arm:
        m.show_viewport = False
    depsgraph.update()
    ev = obj.evaluated_get(depsgraph)
    me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=depsgraph)
    old = obj.data
    name = old.name
    for m in list(obj.modifiers):
        if m.type != "ARMATURE":
            obj.modifiers.remove(m)
    obj.data = me
    bpy.data.meshes.remove(old)
    me.name = name
    for m in arm:
        m.show_viewport = True


## Per material: (edge wear, crease grime, ground grime, noise). Wear lightens
## raised edges, grime darkens.
SURFACE = {
    "Leather": (0.5, 0.45, 0.3, 0.1), "Wood": (0.35, 0.4, 0.2, 0.12), "Brass": (0.5, 0.5, 0.1, 0.06),
    "Steel": (0.55, 0.5, 0.15, 0.06), "Iron": (0.5, 0.5, 0.15, 0.08), "Trim": (0.5, 0.45, 0.1, 0.05),
    "Skin": (0.0, 0.12, 0.0, 0.0), "EyeWhite": (0.0, 0.0, 0.0, 0.0), "Hair": (0.15, 0.3, 0.0, 0.0),
    "HairCopper": (0.25, 0.35, 0.0, 0.0), "Glow": (0.0, 0.0, 0.0, 0.0), "Eyes": (0.0, 0.0, 0.0, 0.0),
    "Feather": (0.1, 0.2, 0.0, 0.05), "Moss": (0.2, 0.3, 0.0, 0.12),
}
DEFAULT_SURFACE = (0.22, 0.35, 0.35, 0.1)  # cloth
AO_FLOOR = {"Skin": 0.5, "EyeWhite": 0.6, "Glow": 1.0, "Eyes": 1.0}


def bake(rig, painters=(), rays=32, reach=0.3, ao_strength=0.85, seed=3):
    """Paints the "Col" colour attribute on every mesh under rig. painters:
    fn(position, normal, material name, colour) -> colour, run before the
    shading is multiplied in. Call in the rest pose, before the clips."""
    dg = bpy.context.evaluated_depsgraph_get()
    objs = [o for o in bpy.data.objects if o.type == "MESH" and o.parent == rig]
    for o in objs:
        _apply_modifiers(o, dg)
    # One BVH of the whole figure, so parts shade each other.
    verts, polys = [], []
    for o in objs:
        base = len(verts)
        verts.extend(v.co.copy() for v in o.data.vertices)
        polys.extend([base + i for i in p.vertices] for p in o.data.polygons)
    tree = BVHTree.FromPolygons(verts, polys)
    rnd = random.Random(seed)
    dirs = []
    while len(dirs) < rays:
        v = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(0.02, 1)))
        if 0.05 < v.length <= 1.0:
            dirs.append(v.normalized())
    total = 0
    for o in objs:
        me = o.data
        n = len(me.vertices)
        total += n
        tint_attr = me.attributes.get("Tint")
        tints = [d.value for d in tint_attr.data] if tint_attr is not None and len(tint_attr.data) == n else None
        mats = [m.name if m else "" for m in me.materials] or [""]
        vmat = [""] * n
        for p in me.polygons:
            for vi in p.vertices:
                vmat[vi] = mats[min(p.material_index, len(mats) - 1)]
        nbr = [[] for _ in range(n)]
        for e in me.edges:
            a, b = e.vertices
            nbr[a].append(b)
            nbr[b].append(a)
        co = [v.co.copy() for v in me.vertices]
        nr = [v.normal.copy() for v in me.vertices]
        ao = [1.0] * n
        curv = [0.0] * n
        for i in range(n):
            nrm = nr[i]
            # A frame round the normal for the hemisphere of rays.
            ref = Vector((0, 0, 1)) if abs(nrm.z) < 0.9 else Vector((1, 0, 0))
            tx = nrm.cross(ref).normalized()
            ty = nrm.cross(tx)
            org = co[i] + nrm * 0.004
            occ = 0.0
            tot = 0.0
            for d in dirs:
                hit = tree.ray_cast(org, tx * d.x + ty * d.y + nrm * d.z, reach)
                tot += d.z
                if hit[0] is not None:
                    occ += d.z * (1.0 - hit[3] / reach) ** 0.7
            ao[i] = 1.0 - occ / tot
            if nbr[i]:
                c = 0.0
                for j in nbr[i]:
                    e = co[j] - co[i]
                    ln = e.length
                    if ln > 1e-6:
                        c += nrm.dot(e) / ln
                curv[i] = c / len(nbr[i])
        for _ in range(2):  # soften ray noise
            ao = [0.5 * ao[i] + 0.5 * (sum(ao[j] for j in nbr[i]) / len(nbr[i])) if nbr[i] else ao[i] for i in range(n)]
        cols = []
        for i in range(n):
            mat = vmat[i]
            wear, grime, ground, grain = SURFACE.get(mat, DEFAULT_SURFACE)
            g = NEUTRAL * (1.0 + (tints[i] if tints else 0.0))
            col = Vector((g, g, g))
            for fn in painters:
                col = fn(co[i], nr[i], mat, col)
            s = 1.0
            if grain:
                s *= 1.0 + grain * (noise.noise(co[i] * 9.0) + 0.5 * noise.noise(co[i] * 31.0))
            c = curv[i]
            if c < 0:
                s *= 1.0 + wear * min(1.0, -c * 2.2)
            else:
                s *= 1.0 - grime * min(1.0, c * 2.0)
            if ground:
                s *= 1.0 - ground * (1.0 - smooth(0.0, 0.55, co[i].z))
            s *= max(AO_FLOOR.get(mat, 0.3), 1.0 - ao_strength * float(o.get("ao", 1.0)) * (1.0 - ao[i]) * 1.15)
            col = col * s
            cols.append((min(1.0, max(0.0, col.x)), min(1.0, max(0.0, col.y)), min(1.0, max(0.0, col.z)), 1.0))
        if tint_attr is not None:
            me.attributes.remove(me.attributes.get("Tint"))
        attr = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
        attr.data.foreach_set("color", [x for c in cols for x in c])
        me.color_attributes.active_color = attr
        me.color_attributes.render_color_index = me.color_attributes.find("Col")
    print("baked", len(objs), "meshes,", total, "vertices")
