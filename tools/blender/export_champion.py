# SPDX-License-Identifier: GPL-2.0-or-later
# (Uses Blender's Python API. This is a build tool, not part of the game.)
"""Export a champion .blend to glTF for PactFall, plus its timing sidecar.

  blender -b MODEL.blend --python tools/blender/export_champion.py -- OUT.glb

or, with the bpy module (pip install bpy, same version as your Blender):

  python3 tools/blender/export_champion.py MODEL.blend OUT.glb

Writes OUT.glb with fixed settings (so every artist exports the same way) and
OUT.timing.json holding each action's "release" pose marker in seconds. glTF
has no timeline markers, so this file is how windup timing reaches the
contract check:  godot --headless --path . -s tools/check_assets.gd -- OUT.glb

Conventions: metres, scale 1, the champion faces Blender +Y, origin on the
ground between the feet. One NLA track per clip, named idle-loop, run-loop,
death, attack, ability_1, ability_2, ability_3. Sockets are empties named
Muzzle and Overhead (parent them to a bone if they should follow it).
"""
import json
import os
import sys

import bpy


def release_times():
    out = {}
    for obj in bpy.data.objects:
        ad = obj.animation_data
        if ad is None:
            continue
        for track in ad.nla_tracks:
            for strip in track.strips:
                act = strip.action
                if act is None:
                    continue
                for m in act.pose_markers:
                    if m.name.lower() == "release":
                        fps = bpy.context.scene.render.fps / bpy.context.scene.render.fps_base
                        name = track.name.lower()
                        for suffix in ("-loop", "_loop", "-cycle", "_cycle"):
                            if name.endswith(suffix):
                                name = name[: -len(suffix)]
                        # Strip time starts at the strip's frame_start.
                        out[name] = round((m.frame - act.frame_range[0]) / fps, 4)
    return out


def export(out_path):
    out_path = os.path.abspath(out_path)
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_force_sampling=True,
        export_frame_range=False,
        export_def_bones=False,
        export_extras=True,
    )
    timing = {"release": release_times(),
              "fps": bpy.context.scene.render.fps / bpy.context.scene.render.fps_base,
              "source": os.path.basename(bpy.data.filepath) or "generated"}
    with open(os.path.splitext(out_path)[0] + ".timing.json", "w") as f:
        json.dump(timing, f, indent=2, sort_keys=True)
        f.write("\n")
    print("exported", out_path, "release", timing["release"])


def main(argv):
    if "--" in argv:  # running inside blender -b ... --python
        export(argv[argv.index("--") + 1])
        return
    if len(argv) < 3:
        print(__doc__)
        sys.exit(2)
    bpy.ops.wm.open_mainfile(filepath=os.path.abspath(argv[1]))
    export(argv[2])


if __name__ == "__main__":
    main(sys.argv)
