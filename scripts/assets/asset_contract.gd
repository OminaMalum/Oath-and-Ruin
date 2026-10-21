class_name AssetContract
extends RefCounted
## What a champion model must satisfy to replace the primitive placeholder
## without changing gameplay. The sim is the authority: hit radius, height,
## where projectiles start and how long each windup lasts all live in the
## ChampionDef and AbilityDef files. Art adapts to those numbers, never the
## other way round. See docs/ASSET_CONTRACT.md.
##
## spec(def)            the numbers an artist needs (also written as JSON)
## check(scene, def)    measures an imported model against them
##
## Conventions (Godot): metres, +Y up, the model faces -Z (Unit.forward()),
## origin on the ground between the feet. Blender: build facing +Y; the
## glTF exporter's +Y up conversion turns Blender +Y into Godot -Z.

## Height may differ from the hit capsule by this fraction.
const HEIGHT_TOLERANCE := 0.15
## Feet within this of y = 0.
const GROUND_TOLERANCE := 0.06
## The visual muzzle may sit this far from where the sim fires (metres).
const MUZZLE_TOLERANCE := 0.35
## A windup clip may be sped up or slowed down by this much to match the
## sim's cast time before the motion reads wrong.
const MIN_SPEED := 0.8
const MAX_SPEED := 1.25
## Run cycle: playback rate needed to match move speed (foot sliding).
const MIN_STRIDE_RATE := 0.85
const MAX_STRIDE_RATE := 1.15

const SOCKETS := ["Muzzle", "Overhead"]
const LOOP_CLIPS := ["idle", "run"]
const ONE_SHOT_CLIPS := ["death"]
const SLOT_CLIPS := ["attack", "ability_1", "ability_2", "ability_3"]
const FOOT_NAMES := [["foot_l", "foot.l", "leftfoot", "left_foot"], ["foot_r", "foot.r", "rightfoot", "right_foot"]]
## Timeline marker (Blender pose marker) where the effect is released.
const RELEASE_MARKER := "release"


## Where the sim fires projectiles from, relative to the unit origin, facing -Z.
static func sim_muzzle(def: ChampionDef) -> Vector3:
	return Vector3(0.0, def.height * 0.6, -(def.radius + 0.1))


## The numbers a model has to hit, as plain data (JSON for tools and artists).
static func spec(def: ChampionDef) -> Dictionary:
	var clips := {}
	for slot in def.slot_count():
		var a := def.get_slot(slot)
		if a:
			clips[SLOT_CLIPS[slot]] = {"ability": String(a.id), "release_s": a.cast_time,
				"recovery_s": a.recovery, "min_speed": MIN_SPEED, "max_speed": MAX_SPEED}
	var m := sim_muzzle(def)
	return {
		"champion": String(def.id),
		"units": "metres, +Y up, model faces -Z in Godot (+Y in Blender), origin on the ground",
		"height_m": def.height, "height_tolerance": HEIGHT_TOLERANCE,
		"hit_radius_m": def.radius,
		"move_speed_mps": def.move_speed,
		"sockets": {"Muzzle": [snappedf(m.x, 0.001), snappedf(m.y, 0.001), snappedf(m.z, 0.001)],
			"Overhead": [0.0, snappedf(def.height + 0.3, 0.001), 0.0]},
		"muzzle_tolerance_m": MUZZLE_TOLERANCE,
		"loop_clips": LOOP_CLIPS, "one_shot_clips": ONE_SHOT_CLIPS,
		"slot_clips": clips,
		"release_marker": RELEASE_MARKER,
		"feet": ["foot_l", "foot_r"],
	}


## Playback speed that puts a clip's release marker on the sim's release.
static func windup_speed(clip_release: float, cast_time: float) -> float:
	return clip_release / maxf(cast_time, 0.001)


## Checks a model. `timing` maps clip name to release seconds (the exporter's
## sidecar JSON); a "release" marker inside the Animation wins when present.
## Returns {errors, warnings, measured}.
static func check(scene: Node, def: ChampionDef, timing: Dictionary = {}) -> Dictionary:
	var errors: PackedStringArray = []
	var warnings: PackedStringArray = []
	var measured := {}
	var root := scene as Node3D

	# Bounds at rest: every mesh in model space.
	var box := AABB()
	var have_box := false
	for mi: MeshInstance3D in _all(scene, "MeshInstance3D"):
		if mi.mesh == null:
			continue
		var b := _to_root(root, mi) * mi.mesh.get_aabb()
		box = b if not have_box else box.merge(b)
		have_box = true
	if not have_box:
		errors.append("no mesh found")
	else:
		measured.height_m = snappedf(box.size.y, 0.001)
		measured.feet_y = snappedf(box.position.y, 0.001)
		measured.half_width_m = snappedf(maxf(box.size.x, box.size.z) * 0.5, 0.001)
		if absf(box.size.y - def.height) > def.height * HEIGHT_TOLERANCE:
			errors.append("height %.2f m, the hit capsule is %.2f m (allowed +-%d%%). Check the export scale (metres, scale 1)." % [box.size.y, def.height, roundi(HEIGHT_TOLERANCE * 100)])
		if absf(box.position.y) > GROUND_TOLERANCE:
			errors.append("lowest point at y = %.2f m; the origin must sit on the ground between the feet" % box.position.y)
		if maxf(box.size.x, box.size.z) * 0.5 > def.radius * 2.5:
			warnings.append("model reaches %.2f m from its centre, the hit radius is %.2f m: players will read a bigger target than the one they can hit" % [maxf(box.size.x, box.size.z) * 0.5, def.radius])

	# Sockets.
	var want := sim_muzzle(def)
	for s: String in SOCKETS:
		var n := _find_named(scene, s)
		if n == null:
			errors.append("socket '%s' missing (an empty or bone named %s)" % [s, s])
			continue
		var p := _to_root(root, n).origin
		measured["socket_" + s] = [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]
		if s == "Muzzle":
			if p.z > 0.05 and absf(p.z) > absf(p.x):
				errors.append("Muzzle is behind the model (z = %.2f): the model faces +Z. In Blender it must face +Y, or rotate it 180 degrees" % p.z)
			elif p.distance_to(want) > MUZZLE_TOLERANCE:
				errors.append("Muzzle at %s, the sim fires from %s (%.2f m apart, allowed %.2f): shots would look like they leave from the wrong place" % [_v(p), _v(want), p.distance_to(want), MUZZLE_TOLERANCE])

	# Clips.
	var player := _first(scene, "AnimationPlayer") as AnimationPlayer
	if player == null:
		errors.append("no AnimationPlayer (export the actions or NLA tracks)")
		return {"errors": errors, "warnings": warnings, "measured": measured}
	var names := {}
	for n: StringName in player.get_animation_list():
		names[_clip_key(String(n))] = n
	measured.clips = names.keys()
	for c: String in LOOP_CLIPS:
		if not names.has(c):
			errors.append("clip '%s' missing" % c)
		elif player.get_animation(names[c]).loop_mode == Animation.LOOP_NONE:
			errors.append("clip '%s' must loop (name it %s-loop in Blender, or set loop on import)" % [c, c])
	for c: String in ONE_SHOT_CLIPS:
		if not names.has(c):
			errors.append("clip '%s' missing" % c)
	for slot in def.slot_count():
		var a := def.get_slot(slot)
		var c: String = SLOT_CLIPS[slot]
		if a == null:
			continue
		if not names.has(c):
			errors.append("clip '%s' missing (for %s)" % [c, a.display_name])
			continue
		var anim := player.get_animation(names[c])
		var release := -1.0
		if anim.has_marker(RELEASE_MARKER):
			release = anim.get_marker_time(RELEASE_MARKER)
		elif timing.has(c):
			release = float(timing[c])
		if release < 0.0:
			errors.append("clip '%s' has no '%s' marker; add a pose marker on the frame %s takes effect" % [c, RELEASE_MARKER, a.display_name])
			continue
		var speed := windup_speed(release, a.cast_time)
		measured[c + "_speed"] = snappedf(speed, 0.01)
		if speed < MIN_SPEED or speed > MAX_SPEED:
			errors.append("'%s' releases at %.2f s, the sim releases %s at %.2f s: it would play at %.2fx (allowed %.2f to %.2f). Move the marker or retime the windup" % [c, release, a.display_name, a.cast_time, speed, MIN_SPEED, MAX_SPEED])
		if anim.length < release + 0.05:
			warnings.append("'%s' ends right at its release (%.2f s); a recovery pose helps the hit read" % [c, anim.length])

	# Run cycle against move speed (foot sliding).
	if names.has("run"):
		var natural := _run_speed(player, names["run"], scene, root)
		if natural <= 0.0:
			warnings.append("could not measure the run stride (needs bones or nodes named foot_l and foot_r)")
		else:
			var rate := def.move_speed / natural
			measured.run_natural_speed_mps = snappedf(natural, 0.01)
			measured.run_rate = snappedf(rate, 0.01)
			if rate < MIN_STRIDE_RATE or rate > MAX_STRIDE_RATE:
				errors.append("run cycle covers %.2f m/s, the champion moves %.2f m/s: it would play at %.2fx and the feet would slide. Retime or restride the cycle" % [natural, def.move_speed, rate])
	return {"errors": errors, "warnings": warnings, "measured": measured}


## "Run-loop", "run_cycle", "Armature|run" all mean the clip "run".
static func _clip_key(n: String) -> String:
	var k := n.to_lower()
	if k.contains("|"):
		k = k.get_slice("|", k.get_slice_count("|") - 1)
	for suffix in ["-loop", "_loop", "-cycle", "_cycle"]:
		if k.ends_with(suffix):
			k = k.trim_suffix(suffix)
	return k


## Ground speed of a planted foot: sample the clip, keep the steps where a
## foot stays within 1 cm of its lowest point, take the median speed there
## (the median ignores the turn-around at the ends of the plant).
static func _run_speed(player: AnimationPlayer, clip: StringName, scene: Node, root: Node3D) -> float:
	var anim := player.get_animation(clip)
	var feet: Array = []
	for names: Array in FOOT_NAMES:
		var f := _find_foot(scene, names)
		if f.is_empty():
			return -1.0
		feet.append(f)
	var steps := 60
	var dt := anim.length / steps
	var tracks: Array = [[], []]
	player.play(clip)
	for i in steps + 1:
		player.seek(i * dt, true)
		for k in 2:
			tracks[k].append(_foot_pos(feet[k], root))
	player.stop()
	var speeds: Array[float] = []
	for k in 2:
		var low := INF
		for p: Vector3 in tracks[k]:
			low = minf(low, p.y)
		for i in steps:
			var a: Vector3 = tracks[k][i]
			var b: Vector3 = tracks[k][i + 1]
			if a.y < low + 0.01 and b.y < low + 0.01:
				speeds.append(Vector2(b.x - a.x, b.z - a.z).length() / dt)
	if speeds.size() < 4:
		return -1.0
	speeds.sort()
	return speeds[speeds.size() / 2]


static func _find_foot(scene: Node, names: Array) -> Dictionary:
	for sk: Skeleton3D in _all(scene, "Skeleton3D"):
		for i in sk.get_bone_count():
			if sk.get_bone_name(i).to_lower() in names:
				return {"skeleton": sk, "bone": i}
	for n: String in names:
		var node := _find_named(scene, n)
		if node:
			return {"node": node}
	return {}


static func _foot_pos(f: Dictionary, root: Node3D) -> Vector3:
	if f.has("skeleton"):
		var sk: Skeleton3D = f.skeleton
		return (_to_root(root, sk) * sk.get_bone_global_pose(f.bone)).origin
	return _to_root(root, f.node).origin


## Transform of a node relative to the model root, without needing the tree.
static func _to_root(root: Node3D, n: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur := n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


static func _all(n: Node, cls: String) -> Array:
	var out: Array = []
	if n.is_class(cls):
		out.append(n)
	for c in n.get_children():
		out.append_array(_all(c, cls))
	return out


static func _first(n: Node, cls: String) -> Node:
	var all := _all(n, cls)
	return all[0] if not all.is_empty() else null


static func _find_named(n: Node, want: String) -> Node3D:
	if n is Node3D and String(n.name).to_lower() == want.to_lower():
		return n
	for c in n.get_children():
		var f := _find_named(c, want)
		if f:
			return f
	return null


static func _v(p: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [p.x, p.y, p.z]


## Loads a .glb/.gltf from disk with the engine's glTF importer (no editor
## import needed, so it runs headless on any file an artist drops in).
static func load_gltf(path: String) -> Node:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return null
	return doc.generate_scene(state)
