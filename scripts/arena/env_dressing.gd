class_name EnvDressing
extends RefCounted
## Set dressing for the match map: trees, plants, scanned rocks, grass at the
## wall feet, wall lanterns and base clutter. Decoration only (no collision),
## kept out of the lane and the middle of the flank corridors so the
## fighting space stays clear. Uses its own seeded RNG, never the one that
## lays out the walls.


var _root: Node3D
var _rng: RandomNumberGenerator
var _grass: Array[Transform3D] = []


func _init(root: Node3D, rng: RandomNumberGenerator) -> void:
	_root = root
	_rng = rng


func build() -> void:
	_flanks()
	_trees()
	_lanterns()
	_bases()
	_camp()
	_magic()
	_grass_at_wall_feet()
	_plant_grass()


## One piece of a Poly Haven model, placed on the ground.
static func prop(root: Node3D, model: String, part: String, pos: Vector3, yaw_deg := 0.0, scale := 1.0,
		shadows := true) -> MeshInstance3D:
	var mesh := Art.mesh(model, part)
	if mesh == null:
		push_warning("missing prop %s/%s" % [model, part])
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees.y = yaw_deg
	mi.scale = Vector3.ONE * scale
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi


func _p(model: String, part: String, pos: Vector3, yaw := -1.0, scale := 1.0, shadows := true) -> MeshInstance3D:
	return prop(_root, model, part, pos, _rng.randf() * 360.0 if yaw < 0.0 else yaw, scale, shadows)


func _in_gap(z: float, pad := 0.0) -> bool:
	for g: float in LaneMapBuilder.GAPS:
		if absf(absf(z) - g) < LaneMapBuilder.GAP_HALF + pad:
			return true
	return false


## Flank corridors (11 to 19 m off centre): ferns, shrubs, fallen branches
## and mossy rocks along both walls, the middle 4 m left open.
func _flanks() -> void:
	var plants := [["fern_02", "fern_02_a"], ["fern_02", "fern_02_b"], ["fern_02", "fern_02_c"], ["fern_02", "fern_02_d"],
		["shrub_04", ""], ["shrub_02", "shrub_02_a"], ["shrub_02", "shrub_02_c"]]
	var rocks := ["rock_moss_set_01_rock01", "rock_moss_set_01_rock02", "rock_moss_set_01_rock03",
		"rock_moss_set_01_rock04", "rock_moss_set_01_rock05", "rock_moss_set_01_rock06"]
	for side: float in [-1.0, 1.0]:
		for wall_x: float in [LaneMapBuilder.WALL_IN + 0.55, LaneMapBuilder.FLANK_OUT - 0.55]:
			var z := -LaneMapBuilder.BASE_Z + 1.5
			while z < LaneMapBuilder.BASE_Z - 1.5:
				z += _rng.randf_range(1.6, 3.4)
				var inner := wall_x < 15.0
				if inner and _in_gap(z, 0.8):
					continue
				if not inner and side < 0.0 and absf(z) < 6.5:
					continue  # the camp pocket opening
				var x := side * (wall_x + _rng.randf_range(-0.2, 0.25) * (1.0 if inner else -1.0))
				var roll := _rng.randf()
				if roll < 0.55:
					var pl: Array = plants[_rng.randi() % plants.size()]
					_p(pl[0], pl[1], Vector3(x, 0, z), -1.0, _rng.randf_range(0.8, 1.25), false)
				elif roll < 0.8:
					_p("rock_moss_set_01", rocks[_rng.randi() % rocks.size()], Vector3(x, -0.05, z), -1.0, _rng.randf_range(0.35, 0.6))
				elif roll < 0.9:
					_p("dry_branches_medium_01", ["dry_branches_medium_01_a", "dry_branches_medium_01_b", "dry_branches_medium_01_c"][_rng.randi() % 3],
						Vector3(x, 0, z), -1.0, _rng.randf_range(0.9, 1.3), false)
				else:
					_p("tree_stump_01", "", Vector3(x, 0, z), -1.0, _rng.randf_range(0.6, 0.85))
				for k in 6:
					_grass.append(_grass_xf(Vector3(x + _rng.randf_range(-0.6, 0.6), 0, z + _rng.randf_range(-1.0, 1.0))))


## Trees: four inside the flanks against the outer wall (orientation from
## inside the corridors, canopy above head height) and a ring outside the
## walls so the map sits in a forest rather than in empty space.
func _trees() -> void:
	var spots: Array[Vector3] = [Vector3(17.6, 0, 24), Vector3(-17.6, 0, -24), Vector3(17.6, 0, -20), Vector3(-17.6, 0, 20)]
	for zs in range(-90, 91, 9):
		for side: float in [-1.0, 1.0]:
			var x := side * _rng.randf_range(24.0, 30.0)
			if side < 0.0 and absf(float(zs)) < 14.0:
				x = side * _rng.randf_range(38.5, 43.0)  # behind the camp pocket
			spots.append(Vector3(x, 0, zs + _rng.randf_range(-3.0, 3.0)))
	for xs in range(-36, 37, 8):
		for zsgn: float in [-1.0, 1.0]:
			spots.append(Vector3(xs + _rng.randf_range(-2.5, 2.5), 0, zsgn * _rng.randf_range(82.5, 86.0)))
	for k in 34:
		var a := TAU * k / 34.0 + _rng.randf_range(-0.05, 0.05)
		var e := Vector3(cos(a) * 46.0, 0, sin(a) * 100.0) * _rng.randf_range(1.0, 1.25)
		spots.append(e)
	# Spirit trees: amethyst crowns that glow faintly, behind the camp and
	# beside each base, so the wild magic has a home.
	for p: Vector3 in [Vector3(-40.0, 0, -6.0), Vector3(-41.0, 0, 7.0), Vector3(25.0, 0, 52.0), Vector3(-25.0, 0, -52.0)]:
		ForestTree.add(_root, p, _rng.randf_range(9.0, 11.0), _rng, ForestTree.SPIRIT)
	var i := 0
	for p in spots:
		ForestTree.add(_root, p, _rng.randf_range(5.0, 8.5) * (0.8 if i < 4 else 1.0), _rng)
		i += 1


## Lanterns on iron brackets along the lane walls: warm pools of light that
## mark the route and the gaps into the flanks.
func _lanterns() -> void:
	var iron := Palette.mat(Palette.IRON, 0.5, 0.8)
	for side: float in [-1.0, 1.0]:
		for z: float in [-43.0, -27.0, -15.0, -3.5, 3.5, 15.0, 27.0, 43.0]:
			if _in_gap(z, 0.5):
				continue
			var x := side * (LaneMapBuilder.LANE_HALF - 0.05)
			var arm := BoxMesh.new()
			arm.size = Vector3(0.6, 0.06, 0.06)
			var a := MeshInstance3D.new()
			a.mesh = arm
			a.material_override = iron
			a.position = Vector3(x - side * 0.28, 2.45, z)
			_root.add_child(a)
			var lantern := _p("wooden_lantern_01", "wooden_lantern_01", Vector3(x - side * 0.52, 1.85, z), 0.0, 1.1, false)
			_p("wooden_lantern_01", "wooden_lantern_01_handle", Vector3(x - side * 0.52, 1.85 + 0.35 * 1.1, z), 0.0, 1.1, false)
			if lantern:
				var glow := MeshInstance3D.new()
				var s := SphereMesh.new()
				s.radius = 0.07
				s.height = 0.14
				glow.mesh = s
				glow.material_override = Palette.glow(Color(1.0, 0.72, 0.38), 5.0)
				glow.position = Vector3(x - side * 0.52, 1.85 + 0.17, z)
				glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_root.add_child(glow)
			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.72, 0.42)
			light.light_energy = 1.1
			light.omni_range = 6.0
			light.position = Vector3(x - side * 0.6, 2.2, z)
			_root.add_child(light)


## Barrels and crates against the base walls, out of the walking lines.
func _bases() -> void:
	for s: float in [-1.0, 1.0]:
		for side: float in [-1.0, 1.0]:
			var z := s * _rng.randf_range(60.0, 66.0)
			var x := side * (LaneMapBuilder.FLANK_OUT - 0.9)
			_p("wooden_barrels_01", "wooden_barrels_01_barrel01", Vector3(x, 0, z), -1.0, 1.0)
			_p("wooden_barrels_01", "wooden_barrels_01_barrel02", Vector3(x, 0, z + 1.1), -1.0, 1.0)
			_p("wooden_crate_01", "wooden_crate_01", Vector3(x - side * 0.2, 0, z - 1.3), -1.0, 1.2)
			_p("wooden_crate_01", "wooden_crate_01_lid", Vector3(x - side * 0.2, 0, z - 1.3), -1.0, 1.2)
			for k in 10:
				_grass.append(_grass_xf(Vector3(x - side * _rng.randf_range(0.0, 0.8), 0, z + _rng.randf_range(-3.0, 3.0))))


## The camp pocket: a fire pit and tumbled rocks round its walls.
func _camp() -> void:
	var c := LaneMapBuilder.CAMP
	_p("stone_fire_pit", "", c + Vector3(-5.5, 0, 6.5), -1.0, 1.0)
	Fire.add(_root, c + Vector3(-5.5, 0.25, 6.5), 0.9, 6.0, 1.4)
	for p: Vector3 in [Vector3(-6.5, 0, -8.8), Vector3(6.0, 0, -8.9), Vector3(-6.8, 0, 0.5), Vector3(3.0, 0, 8.9)]:
		_p("rock_moss_set_01", "rock_moss_set_01_rock0%d" % (1 + _rng.randi() % 6), c + p, -1.0, _rng.randf_range(0.45, 0.7))


## The fantasy layer: a band of pale gold runes carved along both lane wall
## faces, amethyst crystal clusters floating over the walls by the flank
## gaps and in the camp, and drifting motes of light. Wild magic colours only
## (gold, amethyst), so team colours stay on team things.
func _magic() -> void:
	var rune_col := Color(0.95, 0.66, 0.3)
	for side: float in [-1.0, 1.0]:
		# Runs of wall between the gaps.
		var edges: Array[float] = [-LaneMapBuilder.BASE_Z]
		for g: float in [-39.0, -9.0, 9.0, 39.0]:
			edges.append_array([g - LaneMapBuilder.GAP_HALF, g + LaneMapBuilder.GAP_HALF])
		edges.append(LaneMapBuilder.BASE_Z)
		for i in range(0, edges.size(), 2):
			var z0: float = edges[i] + 0.8
			var z1: float = edges[i + 1] - 0.8
			if z1 - z0 < 2.0:
				continue
			var face := Vector3(-side, 0, 0)
			Runes.band(_root, Vector3(side * LaneMapBuilder.LANE_HALF, 1.65, (z0 + z1) * 0.5), face, z1 - z0, 0.3,
				rune_col, _rng.randf())
	var amethyst := Palette.NEUTRAL
	for g: float in LaneMapBuilder.GAPS:
		for zs: float in [-1.0, 1.0]:
			for side: float in [-1.0, 1.0]:
				var z := zs * (g + LaneMapBuilder.GAP_HALF + 1.2)
				Magic.crystals(_root, Vector3(side * (LaneMapBuilder.LANE_HALF + LaneMapBuilder.WALL_IN) * 0.5, 4.6, z),
					amethyst, 0.8, _rng)
	var c := LaneMapBuilder.CAMP
	for p: Vector3 in [Vector3(-6.0, 2.2, -7.5), Vector3(5.5, 2.6, 7.8), Vector3(-6.4, 2.0, 4.0)]:
		Magic.crystals(_root, c + p, amethyst, 1.1, _rng)
	# Crystal growths at the flank wall feet and round the camp.
	for side: float in [-1.0, 1.0]:
		for z: float in [-30.0, -17.0, 4.5, 21.0, 33.0]:
			var x := side * (LaneMapBuilder.FLANK_OUT - 0.4) if int(z) % 2 == 0 else side * (LaneMapBuilder.WALL_IN + 0.4)
			if side < 0.0 and absf(z) < 7.0:
				continue
			Magic.growth(_root, Vector3(x, 0, z * side), amethyst, _rng.randf_range(0.8, 1.2), _rng)
	for p: Vector3 in [Vector3(-7.0, 0, 9.5), Vector3(6.8, 0, -9.6), Vector3(-7.2, 0, -3.0)]:
		Magic.growth(_root, c + p, amethyst, 1.3, _rng)
	# Floating islands out over the valley, the strongest sign that this is
	# not our world. Far enough out to never meet the camera arm.
	for k in 9:
		var a := TAU * k / 9.0 + 0.3
		var pos := Vector3(cos(a) * _rng.randf_range(65.0, 85.0), _rng.randf_range(14.0, 26.0), sin(a) * _rng.randf_range(110.0, 140.0))
		Magic.island(_root, pos, _rng.randf_range(2.5, 4.5), amethyst if k % 3 else Color(0.55, 0.9, 0.85), _rng)
	Magic.motes(_root, Vector3(0, 2.5, 0), Vector3(7.0, 2.0, 46.0), Color(1.0, 0.85, 0.55), 110)
	for side: float in [-1.0, 1.0]:
		Magic.motes(_root, Vector3(side * 15.0, 2.0, 0), Vector3(4.0, 1.8, 45.0), Color(0.8, 0.7, 1.0), 70)
	Magic.motes(_root, c + Vector3(0, 2.0, 0), Vector3(7.0, 1.8, 9.0), Color(0.8, 0.7, 1.0), 50)


## Short grass against every wall foot inside the map.
func _grass_at_wall_feet() -> void:
	for side: float in [-1.0, 1.0]:
		var z := -LaneMapBuilder.BASE_Z
		while z < LaneMapBuilder.BASE_Z:
			z += _rng.randf_range(0.25, 0.7)
			if not _in_gap(z, 0.3):
				_grass.append(_grass_xf(Vector3(side * (LaneMapBuilder.LANE_HALF - _rng.randf_range(0.05, 0.35)), 0, z)))
				_grass.append(_grass_xf(Vector3(side * (LaneMapBuilder.WALL_IN + _rng.randf_range(0.05, 0.4)), 0, z)))
			if not (side < 0.0 and absf(z) < 6.0):
				_grass.append(_grass_xf(Vector3(side * (LaneMapBuilder.FLANK_OUT - _rng.randf_range(0.05, 0.45)), 0, z)))


func _grass_xf(p: Vector3) -> Transform3D:
	var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.7, 1.25))
	return Transform3D(b, p)


func _plant_grass() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = Grass.clump_mesh()
	mm.instance_count = _grass.size()
	for i in _grass.size():
		mm.set_instance_transform(i, _grass[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = Grass.material()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(mmi)
