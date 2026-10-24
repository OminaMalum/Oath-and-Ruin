# SPDX-License-Identifier: GPL-2.0-or-later
# (Uses Blender's Python API. This is a build tool, not part of the game.)
"""Shared clips for the lane minions (tools/blender/build_minion_*.py).

Minions have one slot clip (attack) plus idle, run and death. They are many
on screen, so their meshes skip the smoothing pass the champions get.
"""
import math

import champion_kit as ck
from champion_kit import TAU, base


def clips(rig, spec, names, rest, run_upper, attack_keys, cycle=0.5, lift=0.18, kick=0.14, wide=0.0):
    feet = ck.rest_feet(rig)
    stance = {"l": (feet["l"][0] - wide, feet["l"][1] + wide, feet["l"][2]),
              "r": (feet["r"][0] + wide, feet["r"][1] - wide, feet["r"][2])}

    def b(**over):
        d = dict(rest)
        d.update(over)
        return base(names, **d)

    ck.idle_clip(rig, 2.0, lambda t, s: (b(spine=(2 * s, 0, 0), chest=(-1 * s, 0, 2 * s), head=(2 * s, 0, 6 * math.sin(t / 2 * TAU))),
                                          {"hips": (0, 0, -0.01 - 0.006 * s)}))
    ck.run_clip(rig, spec["move_speed_mps"], lambda t, s, c2: (b(**run_upper(t, s, c2)), {}), cycle=cycle, stance=0.2,
                hips_drop=0.05, lift=lift, kick=kick)
    c = spec["slot_clips"]["attack"]
    rel, rec = c["release_s"], c["recovery_s"]
    ck.cast_clip(rig, "attack", rel, rec, [(t, b(**rots), hp) for t, rots, hp in attack_keys(rel, rec)], stance)
    ck.death_clip(rig, names)
