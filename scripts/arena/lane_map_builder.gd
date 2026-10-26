class_name LaneMapBuilder
extends ArenaBuilder
## The first match map: one lane, two small flank corridors, a neutral camp
## pocket on the west side, and a base at each end. Mirrored across z = 0:
## Oath (team 0) in the south (+z), Ruin (team 1) in the north (-z).
## About 42 x 160 m inside the outer walls.

const LANE_HALF := 7.0
const WALL_IN := 11.0     # lane wall from 7 to 11 m off centre
const FLANK_OUT := 19.0   # flank corridor from 11 to 19 m
const BASE_Z := 46.0      # bases start here
const END_Z := 79.0
const TOWER_Z := 32.0
const CORE_Z := 56.0
const FOUNTAIN_Z := 72.0
const GAPS := [9.0, 39.0]  # openings between lane and flanks, both sides, both halves
const GAP_HALF := 3.0
const CAMP := Vector3(-28.0, 0.0, 0.0)

var _rng := RandomNumberGenerator.new()


var _drng := RandomNumberGenerator.new()  # dressing only, so the wall layout never moves
var _slate: StandardMaterial3D
var _plinth: StandardMaterial3D
var _wall_boxes: Array[AABB] = []
## Wall kit (string courses, pilasters, merlons): decoration boxes gathered
## into one mesh per material, so the extra masonry costs a few draw calls
## for the whole map. Its own RNG, so neither the layout nor the dressing moves.
var _kit := {}  # Material -> SurfaceTool
var _krng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 21
	_drng.seed = 77
	_krng.seed = 5
	_stone_mats = [Art.stone("wall"), Art.stone("wall", Color(0.82, 0.80, 0.78)), Art.stone("wall", Color(1.05, 0.97, 0.86))]
	_slate = Art.stone("slate", Color(0.95, 0.92, 0.86))
	_plinth = Art.stone("slate", Color(0.62, 0.60, 0.56))
	_environment()
	var floor := _static_box(Vector3(90, FLOOR_THICK, 175), Vector3(0, -FLOOR_THICK * 0.5, 0), _stone_mats[0])
	for mi in floor.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = Art.ground()
	# Ground outside the walls (no collision), so the map sits in a valley
	# instead of floating; same shader, so it joins the floor without a seam.
	for o: Array in [[Vector3(400, 1, 150), Vector3(0, -0.5, 162.5)], [Vector3(400, 1, 150), Vector3(0, -0.5, -162.5)],
			[Vector3(155, 1, 175), Vector3(122.5, -0.5, 0)], [Vector3(155, 1, 175), Vector3(-122.5, -0.5, 0)]]:
		_deco(_box_mesh(o[0]), Art.ground(), o[1])
	for side in [-1.0, 1.0]:
		_lane_walls(side)
		_outer_wall(side)
	for team_sign in [1.0, -1.0]:
		_base(team_sign)
	_camp_pocket()
	_lane_dressing()
	_art_section(1.0, 18.0, 36.0)   # Oath tower approach
	_art_section(-1.0, 18.0, 36.0)  # Ruin tower approach, the same dressing mirrored
	_kit_commit()
	EnvDressing.new(self, _drng).build()


func _environment() -> void:
	Art.environment(self)


## Every wall block gets a slate cap with a small overhang and a darker plinth
## course at its foot, so the walls read as built masonry, not boxes.
func _wall(size: Vector3, pos: Vector3, m: Material, lane_side := 0.0, merlons := false) -> StaticBody3D:
	var body := _static_box(size, pos, m)
	_wall_kit(size, pos, lane_side, merlons)
	# Where walls meet at corners their outer faces lie in one plane and,
	# with different stone tints, z-fought. Each block's visible mesh (not
	# its collision) is grown by its own few millimetres, so no two coincide.
	var vis := _wall_grow(size, pos)
	for mi in body.find_children("*", "MeshInstance3D", false, false):
		((mi as MeshInstance3D).mesh as BoxMesh).size = vis
	var top := pos.y + size.y * 0.5
	var over := _drng.randf_range(0.10, 0.18)
	_deco(_box_mesh(Vector3(size.x + over * 2.0, 0.26, size.z + over * 2.0)), _slate,
		Vector3(pos.x, top + 0.11 + 0.006 * (_wall_boxes.size() % 4), pos.z), Vector3.ONE, Vector3(0, _drng.randf_range(-0.6, 0.6), 0))
	# The plinth stands proud of the wall on every side, so none of its faces
	# lies in a wall face (that z-fought at every wall end). Where two plinths
	# overlap they share one material and one world-space texture, so the
	# overlap cannot flicker; heights vary so their tops never line up.
	var thick := Vector3(0.16, 0.0, 0.16)
	var ph := _drng.randf_range(0.45, 0.62)
	_deco(_box_mesh(Vector3(size.x, ph, size.z) + thick), _plinth, Vector3(pos.x, ph * 0.5 - 0.04, pos.z))
	return body


## Masonry detail on a wall block: a string course round it at about head
## height, pilasters on the face toward the fighting (lane_side is the x
## direction that face looks), and merlons along the top of outer walls.
## All of it stands at least 4 cm off the wall faces, so nothing z-fights.
func _wall_kit(size: Vector3, pos: Vector3, lane_side: float, merlons: bool) -> void:
	var top := pos.y + size.y * 0.5
	var band_y := minf(1.75, top - 0.7) + _krng.randf_range(-0.03, 0.03)
	_kit_box(_plinth, Vector3(size.x + 0.1, 0.16, size.z + 0.1), Vector3(pos.x, band_y, pos.z))
	if lane_side != 0.0:
		var face := pos.x + lane_side * size.x * 0.5
		var n := maxi(1, int(size.z / 2.6))
		for i in n:
			var pz := pos.z - size.z * 0.5 + size.z * (i + 0.5) / n
			var ph := top - 0.25
			_kit_box(_plinth, Vector3(0.24, ph, 0.5), Vector3(face + lane_side * 0.12, ph * 0.5, pz))
			_kit_box(_slate, Vector3(0.34, 0.12, 0.62), Vector3(face + lane_side * 0.15, ph + 0.02, pz))
	if merlons:
		# Along the wall's long axis, on top of its slate cap.
		var along := size.z
		var count := int(along / 1.3)
		for i in count:
			var mz := pos.z - along * 0.5 + (i + 0.5) * along / count
			var mh := _krng.randf_range(0.5, 0.65)
			_kit_box(_stone_mats[i % 3], Vector3(size.x * 0.8, mh, 0.62), Vector3(pos.x, top + 0.24 + mh * 0.5, mz))


func _kit_box(m: Material, size: Vector3, pos: Vector3) -> void:
	if not _kit.has(m):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_kit[m] = st
	var bm := _box_mesh(size)
	(_kit[m] as SurfaceTool).append_from(bm, 0, Transform3D(Basis.IDENTITY, pos))


func _kit_commit() -> void:
	for m: Material in _kit:
		var st: SurfaceTool = _kit[m]
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = m
		add_child(mi)
	_kit.clear()


## Picks the smallest growth (4 to 22 mm a side) that keeps every side face
## at least 3 mm from the side faces of the walls already placed.
func _wall_grow(size: Vector3, pos: Vector3) -> Vector3:
	var grow := 0.004
	while grow < 0.022:
		var g := Vector3(grow, 0.0, grow) * 2.0
		var box := AABB(pos - (size + g) * 0.5, size + g)
		var ok := true
		for o in _wall_boxes:
			if not box.grow(0.01).intersects(o):
				continue
			for k: int in [0, 2]:
				if absf(box.position[k] - o.position[k]) < 0.003 or absf(box.end[k] - o.end[k]) < 0.003:
					ok = false
		if ok:
			_wall_boxes.append(box)
			return size + g
		grow += 0.0035
	return size + Vector3(grow, 0.0, grow) * 2.0


static func _box_mesh(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


## Broken wall blocks between lane and flank, with openings at GAPS.
func _lane_walls(side: float) -> void:
	var starts: Array[float] = []
	for g: float in GAPS:
		starts.append(g - GAP_HALF)
		starts.append(-g - GAP_HALF)
	var z := -BASE_Z
	while z < BASE_Z - 0.01:
		if _in_gap(z + 0.01):
			z += 0.5
			continue
		var next := minf(z + _rng.randf_range(3.0, 5.0), BASE_Z)
		for g in starts:
			if z < g and next > g:
				next = g
		var h := _rng.randf_range(2.4, 3.6)
		var x := side * (LANE_HALF + WALL_IN) * 0.5
		_wall(Vector3(WALL_IN - LANE_HALF, h, next - z), Vector3(x, h * 0.5, (z + next) * 0.5), _stone_mats[_rng.randi() % 3], -side)
		if _rng.randf() < 0.35:
			pass  # was a moss blob on the wall top; the draw stays so the layout keeps its seed
		z = next


func _in_gap(z: float) -> bool:
	for g: float in GAPS:
		if absf(absf(z) - g) < GAP_HALF:
			return true
	return false


func _outer_wall(side: float) -> void:
	var x := side * (FLANK_OUT + 1.0)
	var z := -BASE_Z
	while z < BASE_Z:
		var next := minf(z + _rng.randf_range(4.0, 6.0), BASE_Z)
		# West side opens into the camp pocket.
		if side < 0.0 and z < 5.0 and next > -5.0:
			if z < -5.0:
				next = -5.0
			else:
				z = 5.0
				continue
		var h := _rng.randf_range(3.5, 5.0)
		_wall(Vector3(2.0, h, next - z), Vector3(x, h * 0.5, (z + next) * 0.5), _stone_mats[_rng.randi() % 3], -side, true)
		z = next
	# Close the flank ends against the bases.
	for zs in [-1.0, 1.0]:
		_wall(Vector3(FLANK_OUT - WALL_IN, 3.5, 1.5), Vector3(side * (WALL_IN + FLANK_OUT) * 0.5, 1.75, zs * (BASE_Z + 0.75)), _stone_mats[1])


func _base(s: float) -> void:
	var team := 0 if s > 0.0 else 1
	var col := Palette.team_color(team)
	# Walls round the plaza, open toward the lane.
	_wall(Vector3(42, 4.5, 2), Vector3(0, 2.25, s * END_Z), _stone_mats[1])
	for side in [-1.0, 1.0]:
		_wall(Vector3(2, 4.5, END_Z - BASE_Z), Vector3(side * (FLANK_OUT + 1.0), 2.25, s * (BASE_Z + END_Z) * 0.5), _stone_mats[0])
		_wall(Vector3(FLANK_OUT - LANE_HALF - 1.0, 3.8, 1.6), Vector3(side * (LANE_HALF + 1.0 + FLANK_OUT) * 0.5, 1.9, s * BASE_Z), _stone_mats[2])
	# Fountain: a ring of light the team heals in.
	var ring := TorusMesh.new()
	ring.inner_radius = 5.6
	ring.outer_radius = 6.0
	ring.rings = 48
	_deco(ring, Palette.glow(col, 1.5), Vector3(0, 0.05, s * FOUNTAIN_Z), Vector3(1, 0.06, 1))
	var pool := CylinderMesh.new()
	pool.top_radius = 5.6
	pool.bottom_radius = 5.6
	pool.height = 0.02
	_deco(pool, Palette.ground_decal(col, 0.18), Vector3(0, 0.03, s * FOUNTAIN_Z))
	# Banners on the gate posts, readable from down the lane.
	var cloth := Palette.mat(col.darkened(0.35))
	for x in [-LANE_HALF - 1.0, LANE_HALF + 1.0]:
		_wall(Vector3(1.4, 6.0, 1.4), Vector3(x, 3.0, s * BASE_Z), _stone_mats[0])
		_deco(BoxMesh.new(), cloth, Vector3(x, 3.6, s * (BASE_Z - 0.8)), Vector3(1.1, 3.0, 0.05))
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 1.5
	light.omni_range = 12.0
	light.position = Vector3(0, 3.0, s * FOUNTAIN_Z)
	add_child(light)


## West pocket for the neutral camp (filled in the next batch).
func _camp_pocket() -> void:
	var x0 := -(FLANK_OUT + 2.0)
	var x1 := CAMP.x - 8.0
	_wall(Vector3(x0 - x1, 4.5, 2.0), Vector3((x0 + x1) * 0.5, 2.25, -11.0), _stone_mats[1])
	_wall(Vector3(x0 - x1, 4.5, 2.0), Vector3((x0 + x1) * 0.5, 2.25, 11.0), _stone_mats[1])
	_wall(Vector3(2.0, 4.5, 24.0), Vector3(x1, 2.25, 0.0), _stone_mats[0])
	_static_box(Vector3(5.0, 0.6, 5.0), CAMP + Vector3(0, 0.3, 0), Art.stone("plaza", Color(0.9, 0.88, 0.84)))
	_static_box(Vector3(3.4, 0.6, 3.4), CAMP + Vector3(0, 0.9, 0), _slate)


## Rubble kept to the wall feet so the fighting space stays clear. The
## draws stay as they were so the seeded sequence does not move; the shapes
## are now scanned rocks.
func _lane_dressing() -> void:
	var rocks := ["rock_moss_set_02_rock08", "rock_moss_set_02_rock09", "rock_moss_set_02_rock10", "rock_moss_set_02_rock11", "rock_moss_set_02_rock12"]
	for i in 40:
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var _x := side * _rng.randf_range(LANE_HALF - 0.6, LANE_HALF + 0.2)
		var z := _rng.randf_range(-BASE_Z, BASE_Z)
		var s := _rng.randf_range(0.25, 0.6)
		var k := _rng.randi() % 3
		var rot := Vector3(_rng.randf() * 30, _rng.randf() * 180, _rng.randf() * 30)
		if _in_gap(z) or absf(absf(z) - TOWER_Z) < 4.0:
			continue
		EnvDressing.prop(self, "rock_moss_set_02", rocks[(i + k) % rocks.size()],
			Vector3(side * (LANE_HALF - 0.3), 0.0, z), rot.y, s * 0.8)


## Tower approach dressing (decoration only, no collision, the fighting space
## stays clear): buttresses on the wall face, team banners either side of the
## tower and two braziers for warm light. `s` is the team sign.
func _art_section(s: float, z0: float, z1: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	var team := 0 if s > 0.0 else 1
	var cloth := Palette.mat(Palette.team_color(team).darkened(0.3), 0.95)
	var brass := Palette.mat(Palette.BRASS, 0.4, 0.85)
	var iron := Palette.mat(Palette.IRON, 0.55, 0.75)
	for side: float in [-1.0, 1.0]:
		var xw: float = side * LANE_HALF
		var z := z0
		while z < z1:
			var len := minf(rng.randf_range(2.0, 3.5), z1 - z)
			if not _in_gap(z + len * 0.5) and not _in_gap(z + len):
				_deco(_box_mesh(Vector3(0.45, 2.3, 0.6)), _plinth, Vector3(xw - side * 0.2, 1.15, s * (z + len)))
				_deco(_box_mesh(Vector3(0.6, 0.18, 0.75)), _slate, Vector3(xw - side * 0.26, 2.39, s * (z + len)))
			z += len
		# Team banner on a pole beside the tower, and a brazier on a plinth.
		var bx: float = side * (LANE_HALF - 0.6)
		var bz := s * (TOWER_Z - 2.5)
		var pole := CylinderMesh.new()
		pole.top_radius = 0.06
		pole.bottom_radius = 0.08
		pole.height = 5.4
		_deco(pole, Palette.mat(Palette.WOOD, 0.8), Vector3(bx, 2.7, bz))
		_deco(_box_mesh(Vector3(1.3, 0.07, 0.07)), brass, Vector3(bx - side * 0.6, 5.15, bz))
		_deco(_box_mesh(Vector3(1.1, 2.4, 0.04)), cloth, Vector3(bx - side * 0.6, 3.9, bz))
		var tail := PrismMesh.new()
		tail.size = Vector3(1.1, 0.5, 0.04)
		_deco(tail, cloth, Vector3(bx - side * 0.6, 2.45, bz), Vector3.ONE, Vector3(0, 0, 180))
		var sig := CylinderMesh.new()
		sig.top_radius = 0.26
		sig.bottom_radius = 0.26
		sig.height = 0.02
		_deco(sig, brass, Vector3(bx - side * 0.6, 4.2, bz + 0.03), Vector3.ONE, Vector3(90, 0, 0))
		_deco(sig, brass, Vector3(bx - side * 0.6, 4.2, bz - 0.03), Vector3.ONE, Vector3(90, 0, 0))
		var pz := s * (TOWER_Z + 4.5)
		_deco(_box_mesh(Vector3(0.9, 0.85, 0.9)), _plinth, Vector3(bx, 0.42, pz))
		_deco(_box_mesh(Vector3(1.05, 0.12, 1.05)), _slate, Vector3(bx, 0.91, pz))
		var bowl := CylinderMesh.new()
		bowl.top_radius = 0.45
		bowl.bottom_radius = 0.22
		bowl.height = 0.35
		_deco(bowl, iron, Vector3(bx, 1.14, pz))
		Fire.add(self, Vector3(bx, 1.3, pz), 0.8)
	# A broken column drum against the east wall, out of the lane proper.
	var drum := CylinderMesh.new()
	drum.top_radius = 0.55
	drum.bottom_radius = 0.55
	drum.height = 1.8
	drum.radial_segments = 16
	_deco(drum, _stone_mats[2], Vector3(LANE_HALF - 0.7, 0.55, s * (z0 + 3.0)), Vector3.ONE, Vector3(0, 20, 90))
