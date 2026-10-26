class_name ThreeLaneDressing
extends RefCounted
## Set dressing for the three lane map, in the same kit as EnvDressing on the
## lane map: forest round the valley, trees and plants in the jungle, lanterns
## and carved runes along the lane walls, braziers and banners at the towers,
## the camp fire and the wild magic. Decoration only (no collision), kept to
## wall feet and pillar feet so the fighting space stays clear. Its own RNG.

const L := preload("res://scripts/arena/three_lane_builder.gd")

var _root: ThreeLaneBuilder
var _rng: RandomNumberGenerator
var _grass: Array[Transform3D] = []


func _init(root: ThreeLaneBuilder, rng: RandomNumberGenerator) -> void:
	_root = root
	_rng = rng


func build() -> void:
	_wall_feet()
	_pillar_feet()
	_trees()
	_lanterns()
	_towers()
	_bases()
	_camp()
	_magic()
	_plant_grass()


func _p(model: String, part: String, pos: Vector3, yaw := -1.0, scale := 1.0, shadows := true) -> MeshInstance3D:
	return EnvDressing.prop(_root, model, part, pos, _rng.randf() * 360.0 if yaw < 0.0 else yaw, scale, shadows)


func _in_gap(z: float, pad := 0.0) -> bool:
	for g: float in L.GAPS:
		if absf(absf(z) - g) < L.GAP_HALF + pad:
			return true
	return false


## The lane faces of every wall run: [x of the face, the x direction it looks].
func _lane_faces() -> Array:
	var out := []
	var mid := L.LANE_HALF
	var inner := absf(L.LANES[0]) - L.LANE_HALF
	for side: float in [-1.0, 1.0]:
		out.append([side * mid, -side])
		out.append([side * inner, side])
	return out


## The jungle faces of the lane walls and the inside of the outer walls:
## [x of the wall foot, the x direction into open ground, is a lane wall].
func _foot_lines() -> Array:
	var out := []
	var mid := L.LANE_HALF + 1.5
	var inner := absf(L.LANES[0]) - L.LANE_HALF - 1.5
	for side: float in [-1.0, 1.0]:
		out.append([side * mid, side, true])
		out.append([side * inner, -side, true])
		out.append([side * L.OUTER, -side, false])
	return out


func _wall_feet() -> void:
	var plants := [["fern_02", "fern_02_a"], ["fern_02", "fern_02_b"], ["fern_02", "fern_02_c"], ["fern_02", "fern_02_d"],
		["shrub_04", ""], ["shrub_02", "shrub_02_a"], ["shrub_02", "shrub_02_c"]]
	var rocks := ["rock_moss_set_01_rock01", "rock_moss_set_01_rock02", "rock_moss_set_01_rock03",
		"rock_moss_set_01_rock04", "rock_moss_set_01_rock05", "rock_moss_set_01_rock06"]
	for f: Array in _foot_lines():
		var wx: float = f[0]
		var n: float = f[1]
		var lane_wall: bool = f[2]
		var z := -L.BASE_Z + 1.5
		while z < L.BASE_Z - 1.5:
			z += _rng.randf_range(1.8, 3.6)
			if lane_wall and _in_gap(z, 0.8):
				continue
			var x := wx + n * _rng.randf_range(0.35, 0.8)
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
			for k in 5:
				_grass.append(_grass_xf(Vector3(x + _rng.randf_range(-0.6, 0.6), 0, z + _rng.randf_range(-1.0, 1.0))))
		# Short grass right along the foot.
		z = -L.BASE_Z
		while z < L.BASE_Z:
			z += _rng.randf_range(0.3, 0.75)
			if not (lane_wall and _in_gap(z, 0.3)):
				_grass.append(_grass_xf(Vector3(wx + n * _rng.randf_range(0.05, 0.4), 0, z)))
	# The lane side of every lane wall gets a thinner line of grass.
	for f: Array in _lane_faces():
		var z := -L.BASE_Z
		while z < L.BASE_Z:
			z += _rng.randf_range(0.4, 1.0)
			if not _in_gap(z, 0.3):
				_grass.append(_grass_xf(Vector3(f[0] + f[1] * _rng.randf_range(0.05, 0.3), 0, z)))


## Rocks, ferns and grass round the foot of the jungle blocks, so they sit
## in the ground instead of standing on it.
func _pillar_feet() -> void:
	var rocks := ["rock_moss_set_02_rock08", "rock_moss_set_02_rock09", "rock_moss_set_02_rock10", "rock_moss_set_02_rock11", "rock_moss_set_02_rock12"]
	for b: AABB in _root.pillars:
		var c := b.get_center()
		var hx := b.size.x * 0.5
		var hz := b.size.z * 0.5
		for k in 3:
			var corner := Vector3(c.x + hx * (1.0 if _rng.randf() < 0.5 else -1.0), 0, c.z + hz * (1.0 if _rng.randf() < 0.5 else -1.0))
			var roll := _rng.randf()
			if roll < 0.45:
				_p("rock_moss_set_02", rocks[_rng.randi() % rocks.size()], corner, -1.0, _rng.randf_range(0.3, 0.5))
			elif roll < 0.85:
				_p("fern_02", "fern_02_%s" % ["a", "b", "c", "d"][_rng.randi() % 4], corner, -1.0, _rng.randf_range(0.7, 1.1), false)
			for j in 6:
				_grass.append(_grass_xf(corner + Vector3(_rng.randf_range(-0.7, 0.7), 0, _rng.randf_range(-0.7, 0.7))))


## Trees: the graybox's jungle trees (now real trees, mirrored), a forest
## round the outside of the walls and four glowing spirit trees.
func _trees() -> void:
	var spots: Array[Vector3] = [Vector3(20, 0, 0), Vector3(-20, 0, 14), Vector3(-20, 0, -14),
		Vector3(24, 0, 38), Vector3(-24, 0, -38), Vector3(24, 0, -38), Vector3(-24, 0, 38)]
	var inside := spots.size()
	for zs in range(-96, 97, 9):
		for side: float in [-1.0, 1.0]:
			spots.append(Vector3(side * _rng.randf_range(L.OUTER + 6.0, L.OUTER + 12.0), 0, zs + _rng.randf_range(-3.0, 3.0)))
	for xs in range(-44, 45, 8):
		for zsgn: float in [-1.0, 1.0]:
			spots.append(Vector3(xs + _rng.randf_range(-2.5, 2.5), 0, zsgn * _rng.randf_range(L.END_Z + 4.5, L.END_Z + 8.5)))
	for k in 40:
		var a := TAU * k / 40.0 + _rng.randf_range(-0.05, 0.05)
		spots.append(Vector3(cos(a) * 66.0, 0, sin(a) * 110.0) * _rng.randf_range(1.0, 1.2))
	for p: Vector3 in [Vector3(-L.OUTER - 9.0, 0, -6.0), Vector3(L.OUTER + 9.0, 0, 7.0), Vector3(30.0, 0, L.END_Z + 9.0), Vector3(-30.0, 0, -L.END_Z - 9.0)]:
		ForestTree.add(_root, p, _rng.randf_range(10.0, 12.0), _rng, ForestTree.SPIRIT)
	var i := 0
	for p in spots:
		ForestTree.add(_root, p, _rng.randf_range(5.0, 8.5) * (0.85 if i < inside else 1.0), _rng)
		i += 1


## Lanterns on iron brackets along every lane face: warm pools of light down
## all three lanes that also mark the gaps into the jungle.
func _lanterns() -> void:
	var iron := Palette.mat(Palette.IRON, 0.5, 0.8)
	var glow_mat := Palette.glow(Color(1.0, 0.72, 0.38), 5.0)
	for f: Array in _lane_faces():
		var fx: float = f[0]
		var n: float = f[1]
		for z: float in [-45.0, -23.0, -4.5, 4.5, 23.0, 45.0]:
			var a := MeshInstance3D.new()
			a.mesh = ThreeLaneBuilder._box_mesh(Vector3(0.6, 0.06, 0.06))
			a.material_override = iron
			a.position = Vector3(fx + n * 0.28, 2.56, z)
			_root.add_child(a)
			var lx := fx + n * 0.52
			var lantern := _p("wooden_lantern_01", "wooden_lantern_01", Vector3(lx, 1.85, z), 0.0, 1.1, false)
			_p("wooden_lantern_01", "wooden_lantern_01_handle", Vector3(lx, 1.85 + 0.35 * 1.1, z), 0.0, 1.1, false)
			if lantern:
				var glow := MeshInstance3D.new()
				var s := SphereMesh.new()
				s.radius = 0.07
				s.height = 0.14
				glow.mesh = s
				glow.material_override = glow_mat
				glow.position = Vector3(lx, 1.85 + 0.17, z)
				glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_root.add_child(glow)
			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.72, 0.42)
			light.light_energy = 1.1
			light.omni_range = 6.0
			light.position = Vector3(fx + n * 0.6, 2.2, z)
			_root.add_child(light)


## Each tower: a team banner either side in front of it and two braziers
## behind it at the lane edges.
func _towers() -> void:
	var brass := Palette.mat(Palette.BRASS, 0.4, 0.85)
	var iron := Palette.mat(Palette.IRON, 0.55, 0.75)
	var wood := Palette.mat(Palette.WOOD, 0.8)
	for s: float in [1.0, -1.0]:
		var cloth := Palette.mat(Palette.team_color(0 if s > 0.0 else 1).darkened(0.3), 0.95)
		for lane: float in L.LANES:
			for side: float in [-1.0, 1.0]:
				var bx := lane + side * (L.LANE_HALF - 0.6)
				var bz := s * (L.TOWER_Z - 2.5)
				var pole := CylinderMesh.new()
				pole.top_radius = 0.06
				pole.bottom_radius = 0.08
				pole.height = 5.4
				_deco(pole, wood, Vector3(bx, 2.7, bz))
				_deco(ThreeLaneBuilder._box_mesh(Vector3(1.3, 0.07, 0.07)), brass, Vector3(bx - side * 0.6, 5.15, bz))
				_deco(ThreeLaneBuilder._box_mesh(Vector3(1.1, 2.4, 0.04)), cloth, Vector3(bx - side * 0.6, 3.9, bz))
				var tail := PrismMesh.new()
				tail.size = Vector3(1.1, 0.5, 0.04)
				_deco(tail, cloth, Vector3(bx - side * 0.6, 2.45, bz), Vector3(0, 0, 180))
				var sig := CylinderMesh.new()
				sig.top_radius = 0.26
				sig.bottom_radius = 0.26
				sig.height = 0.02
				for dz: float in [0.03, -0.03]:
					_deco(sig, brass, Vector3(bx - side * 0.6, 4.2, bz + dz), Vector3(90, 0, 0))
				var pz := s * (L.TOWER_Z + 4.5)
				_deco(ThreeLaneBuilder._box_mesh(Vector3(0.9, 0.85, 0.9)), _root._plinth, Vector3(bx, 0.42, pz))
				_deco(ThreeLaneBuilder._box_mesh(Vector3(1.05, 0.12, 1.05)), _root._slate, Vector3(bx, 0.91, pz))
				var bowl := CylinderMesh.new()
				bowl.top_radius = 0.45
				bowl.bottom_radius = 0.22
				bowl.height = 0.35
				_deco(bowl, iron, Vector3(bx, 1.14, pz))
				Fire.add(_root, Vector3(bx, 1.3, pz), 0.8)


func _deco(mesh: Mesh, m: Material, pos: Vector3, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = rot
	_root.add_child(mi)


## Barrels and crates in the base corners, out of the walking lines.
func _bases() -> void:
	for s: float in [-1.0, 1.0]:
		for side: float in [-1.0, 1.0]:
			var z := s * _rng.randf_range(60.0, 70.0)
			var x := side * (L.OUTER - 0.9)
			_p("wooden_barrels_01", "wooden_barrels_01_barrel01", Vector3(x, 0, z), -1.0, 1.0)
			_p("wooden_barrels_01", "wooden_barrels_01_barrel02", Vector3(x, 0, z + 1.1), -1.0, 1.0)
			_p("wooden_crate_01", "wooden_crate_01", Vector3(x - side * 0.2, 0, z - 1.3), -1.0, 1.2)
			_p("wooden_crate_01", "wooden_crate_01_lid", Vector3(x - side * 0.2, 0, z - 1.3), -1.0, 1.2)
			for k in 10:
				_grass.append(_grass_xf(Vector3(x - side * _rng.randf_range(0.0, 0.8), 0, z + _rng.randf_range(-3.0, 3.0))))
		# Grass along the back wall foot.
		var x := -L.OUTER
		while x < L.OUTER:
			x += _rng.randf_range(0.4, 0.9)
			_grass.append(_grass_xf(Vector3(x, 0, s * (L.END_Z - 1.0 - _rng.randf_range(0.05, 0.4)))))


## The camp clearing: a fire pit at its edge and tumbled rocks round it.
func _camp() -> void:
	var c := L.CAMP
	_p("stone_fire_pit", "", c + Vector3(-5.0, 0, 6.0), -1.0, 1.0)
	Fire.add(_root, c + Vector3(-5.0, 0.25, 6.0), 0.9, 6.0, 1.4)
	for k in 7:
		var a := TAU * k / 7.0 + 0.4
		var p := c + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(7.0, 8.2)
		_p("rock_moss_set_01", "rock_moss_set_01_rock0%d" % (1 + _rng.randi() % 6), p, -1.0, _rng.randf_range(0.45, 0.7))
		for j in 6:
			_grass.append(_grass_xf(p + Vector3(_rng.randf_range(-0.8, 0.8), 0, _rng.randf_range(-0.8, 0.8))))


## Runes on the lane faces, amethyst crystals over the walls by every gap,
## growths in the jungle, motes over the lanes and islands over the valley.
func _magic() -> void:
	var rune_col := Color(0.95, 0.66, 0.3)
	var edges: Array[float] = [-L.BASE_Z]
	for g: float in [-L.GAPS[1], -L.GAPS[0], L.GAPS[0], L.GAPS[1]]:
		edges.append_array([g - L.GAP_HALF, g + L.GAP_HALF])
	edges.append(L.BASE_Z)
	for f: Array in _lane_faces():
		for i in range(0, edges.size(), 2):
			var z0: float = edges[i] + 0.8
			var z1: float = edges[i + 1] - 0.8
			if z1 - z0 < 2.0:
				continue
			Runes.band(_root, Vector3(f[0], 1.65, (z0 + z1) * 0.5), Vector3(f[1], 0, 0), z1 - z0, 0.3, rune_col, _rng.randf())
	var amethyst := Palette.NEUTRAL
	var wall_x := [L.LANE_HALF + 0.75, absf(L.LANES[0]) - L.LANE_HALF - 0.75]
	for g: float in L.GAPS:
		for zs: float in [-1.0, 1.0]:
			for side: float in [-1.0, 1.0]:
				for wx: float in wall_x:
					Magic.crystals(_root, Vector3(side * wx, 4.6, zs * (g + L.GAP_HALF + 1.2)), amethyst, 0.75, _rng)
	var c := L.CAMP
	for p: Vector3 in [Vector3(-6.0, 2.2, -7.0), Vector3(5.5, 2.6, 7.2), Vector3(6.4, 2.0, -4.0)]:
		Magic.crystals(_root, c + p, amethyst, 1.1, _rng)
	for p: Vector3 in [Vector3(-7.0, 0, 5.0), Vector3(6.6, 0, -6.0), Vector3(1.0, 0, 7.6)]:
		Magic.growth(_root, c + p, amethyst, 1.3, _rng)
	for side: float in [-1.0, 1.0]:
		for z: float in [-46.0, -24.0, 24.0, 46.0]:
			Magic.growth(_root, Vector3(side * (L.LANE_HALF + 1.9), 0, z * side), amethyst, _rng.randf_range(0.8, 1.2), _rng)
	for k in 10:
		var a := TAU * k / 10.0 + 0.3
		var pos := Vector3(cos(a) * _rng.randf_range(85.0, 105.0), _rng.randf_range(16.0, 28.0), sin(a) * _rng.randf_range(130.0, 160.0))
		Magic.island(_root, pos, _rng.randf_range(3.0, 5.0), amethyst if k % 3 else Color(0.55, 0.9, 0.85), _rng)
	for lane: float in L.LANES:
		Magic.motes(_root, Vector3(lane, 2.5, 0), Vector3(6.0, 2.0, L.BASE_Z), Color(1.0, 0.85, 0.55), 80)
	for side: float in [-1.0, 1.0]:
		Magic.motes(_root, Vector3(side * 18.0, 2.0, 0), Vector3(9.0, 1.8, L.BASE_Z), Color(0.8, 0.7, 1.0), 70)
	Magic.motes(_root, c + Vector3(0, 2.0, 0), Vector3(7.0, 1.8, 7.0), Color(0.8, 0.7, 1.0), 40)


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
