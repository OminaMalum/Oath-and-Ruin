# SPDX-License-Identifier: GPL-2.0-or-later
# (Uses Blender's Python API. This is a build tool, not part of the game.)
"""Build a contract template rig for one champion from its spec JSON.

  python3 tools/blender/make_template_rig.py assets/specs/ruinscribe.json OUT.blend [options]

The result is a plain blockout (a capsule body, two feet, an armature, the
Muzzle and Overhead sockets, and every clip with its release marker on the
right frame, and a run cycle whose planted foot moves at the champion's run
speed). Artists open it to see the scale, facing, names and timing the game
expects, and model over it. The tests also export it to check the pipeline.
Nothing here is generated art; it is geometry from the numbers in the spec.

Options for building deliberately broken fixtures:
  --scale=F         scale the whole model (wrong export scale)
  --face-back       face Blender -Y (the usual mistake; the game expects +Y)
  --stride=F        run cycle ground speed multiplier (foot sliding)
  --release=F       multiply every release marker time (windup mismatch)
"""
import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

FPS = 30


def opt(name, default):
    for a in sys.argv:
        if a.startswith("--" + name + "="):
            return float(a.split("=", 1)[1])
    return default


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = FPS
    scene.render.fps_base = 1.0
    return scene


def make_armature(h):
    arm = bpy.data.armatures.new("Rig")
    obj = bpy.data.objects.new("Rig", arm)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    root = arm.edit_bones.new("root")
    root.head, root.tail = (0, 0, 0), (0, 0.3, 0)
    hips = arm.edit_bones.new("hips")
    hips.head, hips.tail = (0, 0, h * 0.5), (0, 0, h * 0.85)
    hips.parent = root
    for side, x in (("l", 0.12), ("r", -0.12)):
        foot = arm.edit_bones.new("foot_" + side)
        foot.head, foot.tail = (x, 0, 0.0), (x, 0.15, 0.0)
        foot.parent = root
    hand = arm.edit_bones.new("hand_r")
    hand.head, hand.tail = (-0.25, 0.2, h * 0.6), (-0.25, 0.4, h * 0.6)
    hand.parent = hips
    bpy.ops.object.mode_set(mode="OBJECT")
    return obj


def make_mesh(name, verts_fn, rig, group):
    import bmesh
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    verts_fn(bm)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    vg = obj.vertex_groups.new(name=group)
    vg.add(list(range(len(me.vertices))), 1.0, "REPLACE")
    obj.parent = rig
    mod = obj.modifiers.new("Rig", "ARMATURE")
    mod.object = rig
    return obj


def body(h, r):
    def build(bm):
        import bmesh
        bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=r * 0.9, radius2=r * 0.7,
                              depth=h * 0.8, matrix=Matrix.Translation((0, 0, h * 0.5)))
        bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=r * 0.55,
                                  matrix=Matrix.Translation((0, 0, h - r * 0.55)))
    return build


def foot(x):
    def build(bm):
        import bmesh
        bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation((x, 0.05, 0.05)) @ Matrix.Diagonal((0.12, 0.26, 0.1, 1)))
    return build


def socket(name, rig, bone, world_pos):
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = 0.08
    bpy.context.scene.collection.objects.link(e)
    e.parent = rig
    e.parent_type = "BONE"
    e.parent_bone = bone
    e.matrix_parent_inverse = Matrix.Identity(4)
    bpy.context.view_layer.update()
    e.matrix_world = Matrix.Translation(Vector(world_pos))
    return e


def key_foot(rig, side, frame, world_pos):
    pb = rig.pose.bones["foot_" + side]
    rest = pb.bone.matrix_local
    pb.matrix = Matrix.Translation(Vector(world_pos)) @ rest.to_3x3().to_4x4()
    bpy.context.view_layer.update()
    pb.keyframe_insert("location", frame=frame)


def fcurves(act):
    """F-curves of an action (Blender 4.4+ keeps them in layered channel bags)."""
    if hasattr(act, "layers") and len(act.layers):
        for layer in act.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    yield from bag.fcurves
    elif hasattr(act, "fcurves"):
        yield from act.fcurves


def new_clip(rig, name, length_s, release_s=None):
    act = bpy.data.actions.new(name)
    rig.animation_data_create()
    rig.animation_data.action = act
    end = max(1, round(length_s * FPS))
    act.frame_range = (0, end)
    act.use_frame_range = True
    if release_s is not None:
        m = act.pose_markers.new("release")
        m.frame = round(release_s * FPS)
    return act, end


def finish_clip(rig, act, track_name):
    for pb in rig.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
    ad = rig.animation_data
    track = ad.nla_tracks.new()
    track.name = track_name
    track.strips.new(track_name, 0, act)
    ad.action = None


def build(spec, out, scale, face_back, stride_mult, release_mult):
    scene = reset()
    h, r, v = spec["height_m"], spec["hit_radius_m"], spec["move_speed_mps"]
    rig = make_armature(h)
    make_mesh("Body", body(h, r), rig, "hips")
    make_mesh("Foot_L", foot(0.12), rig, "foot_l")
    make_mesh("Foot_R", foot(-0.12), rig, "foot_r")
    # Godot (x, y, z) facing -Z is Blender (x, -z, y) facing +Y.
    mx, my, mz = spec["sockets"]["Muzzle"]
    socket("Muzzle", rig, "hand_r", (mx, -mz, my))
    ox, oy, oz = spec["sockets"]["Overhead"]
    socket("Overhead", rig, "hips", (ox, -oz, oy))

    # Idle: a slow breath on the hips.
    act, end = new_clip(rig, "idle", 1.6)
    for f, z in ((0, 0.0), (end // 2, 0.015), (end, 0.0)):
        rig.pose.bones["hips"].location = (0, z, 0)
        rig.pose.bones["hips"].keyframe_insert("location", frame=f)
    finish_clip(rig, act, "idle-loop")

    # Run: each foot is planted for half the cycle and slides back under the
    # body at the run speed (so in the game it does not slide at all).
    cycle = 0.5
    speed = v * stride_mult
    stride = speed * cycle * 0.5
    act, end = new_clip(rig, "run", cycle)
    for side, x, phase in (("l", 0.12, 0.0), ("r", -0.12, 0.5)):
        for i in range(0, end + 1):
            t = (i / end + phase) % 1.0
            if t < 0.5:  # planted: front to back at ground speed
                y, z = stride * 0.5 - stride * (t / 0.5), 0.0
            else:        # swing: back to front, lifted
                u = (t - 0.5) / 0.5
                y, z = -stride * 0.5 + stride * u, 0.18 * math.sin(math.pi * u)
            key_foot(rig, side, i, (x, y, z))
    for fc in fcurves(act):
        for k in fc.keyframe_points:
            k.interpolation = "LINEAR"
    finish_clip(rig, act, "run-loop")

    act, end = new_clip(rig, "death", 1.0)
    for f, ang in ((0, 0.0), (end, 1.4)):
        rig.pose.bones["hips"].rotation_mode = "XYZ"
        rig.pose.bones["hips"].rotation_euler = (ang, 0, 0)
        rig.pose.bones["hips"].keyframe_insert("rotation_euler", frame=f)
    finish_clip(rig, act, "death")

    for clip, c in spec["slot_clips"].items():
        rel = c["release_s"] * release_mult
        act, end = new_clip(rig, clip, rel + c["recovery_s"], rel)
        hand = rig.pose.bones["hand_r"]
        for f, y in ((0, 0.0), (round(rel * FPS), 0.25), (end, 0.0)):
            hand.location = (0, y, 0)
            hand.keyframe_insert("location", frame=f)
        finish_clip(rig, act, clip)

    if face_back:
        rig.rotation_euler = (0, 0, math.pi)
    rig.scale = (scale, scale, scale)
    bpy.context.view_layer.update()
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(out))
    print("saved", out)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if "--" in sys.argv:
        args = [a for a in sys.argv[sys.argv.index("--") + 1:] if not a.startswith("--")]
    if len(args) < 2:
        print(__doc__)
        sys.exit(2)
    with open(args[0]) as f:
        spec = json.load(f)
    build(spec, args[1], opt("scale", 1.0), "--face-back" in sys.argv, opt("stride", 1.0), opt("release", 1.0))


if __name__ == "__main__":
    main()
