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


func _ready() -> void:
	_rng.seed = 21
	_stone_mats = [_stone(Palette.STONE), _stone(Palette.STONE_DARK), _stone(Palette.STONE_WARM)]
	_environment()
	_static_box(Vector3(90, FLOOR_THICK, 175), Vector3(0, -FLOOR_THICK * 0.5, 0), _stone_mats[0])
	_lane_floor()
	for side in [-1.0, 1.0]:
		_lane_walls(side)
		_outer_wall(side)
	for team_sign in [1.0, -1.0]:
		_base(team_sign)
	_camp_pocket()
	_lane_dressing()
	_art_section(1.0, 18.0, 36.0)   # Oath tower approach
	_art_section(-1.0, 18.0, 36.0)  # Ruin tower approach, the same dressing mirrored


## A slightly warmer worn path down the lane so the route reads at a glance.
func _lane_floor() -> void:
	var path := BoxMesh.new()
	path.size = Vector3(LANE_HALF * 2.0 - 2.0, 0.02, BASE_Z * 2.0 + 20.0)
	_deco(path, _stone_mats[2], Vector3(0, 0.01, 0))


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
		_static_box(Vector3(WALL_IN - LANE_HALF, h, next - z), Vector3(x, h * 0.5, (z + next) * 0.5), _stone_mats[_rng.randi() % 3])
		if _rng.randf() < 0.35:
			var moss := SphereMesh.new()
			moss.radius = 0.6
			moss.height = 1.2
			_deco(moss, Palette.mat(Palette.MOSS), Vector3(x, h, (z + next) * 0.5), Vector3(2.5, 0.25, (next - z) * 0.6))
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
		_static_box(Vector3(2.0, h, next - z), Vector3(x, h * 0.5, (z + next) * 0.5), _stone_mats[_rng.randi() % 3])
		z = next
	# Close the flank ends against the bases.
	for zs in [-1.0, 1.0]:
		_static_box(Vector3(FLANK_OUT - WALL_IN, 3.5, 1.5), Vector3(side * (WALL_IN + FLANK_OUT) * 0.5, 1.75, zs * (BASE_Z + 0.75)), _stone_mats[1])


func _base(s: float) -> void:
	var team := 0 if s > 0.0 else 1
	var col := Palette.team_color(team)
	# Walls round the plaza, open toward the lane.
	_static_box(Vector3(42, 4.5, 2), Vector3(0, 2.25, s * END_Z), _stone_mats[1])
	for side in [-1.0, 1.0]:
		_static_box(Vector3(2, 4.5, END_Z - BASE_Z), Vector3(side * (FLANK_OUT + 1.0), 2.25, s * (BASE_Z + END_Z) * 0.5), _stone_mats[0])
		_static_box(Vector3(FLANK_OUT - LANE_HALF - 1.0, 3.8, 1.6), Vector3(side * (LANE_HALF + 1.0 + FLANK_OUT) * 0.5, 1.9, s * BASE_Z), _stone_mats[2])
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
		_static_box(Vector3(1.4, 6.0, 1.4), Vector3(x, 3.0, s * BASE_Z), _stone_mats[0])
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
	_static_box(Vector3(x0 - x1, 4.5, 2.0), Vector3((x0 + x1) * 0.5, 2.25, -11.0), _stone_mats[1])
	_static_box(Vector3(x0 - x1, 4.5, 2.0), Vector3((x0 + x1) * 0.5, 2.25, 11.0), _stone_mats[1])
	_static_box(Vector3(2.0, 4.5, 24.0), Vector3(x1, 2.25, 0.0), _stone_mats[0])
	_static_box(Vector3(5.0, 0.6, 5.0), CAMP + Vector3(0, 0.3, 0), _stone_mats[2])
	_static_box(Vector3(3.4, 0.6, 3.4), CAMP + Vector3(0, 0.9, 0), _stone_mats[0])


## Rubble kept to the wall feet so the fighting space stays clear.
func _lane_dressing() -> void:
	for i in 40:
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var x := side * _rng.randf_range(LANE_HALF - 0.6, LANE_HALF + 0.2)
		var z := _rng.randf_range(-BASE_Z, BASE_Z)
		var s := _rng.randf_range(0.25, 0.6)
		_deco(BoxMesh.new(), _stone_mats[_rng.randi() % 3], Vector3(x, s * 0.35, z),
			Vector3(s, s * 0.7, s * 1.2), Vector3(_rng.randf() * 30, _rng.randf() * 180, _rng.randf() * 30))
	# Two autumn trees per flank for orientation from inside the corridors.
	var bark := Palette.mat(Palette.WOOD.darkened(0.2))
	for p in [Vector3(15, 0, 24), Vector3(-15, 0, -24), Vector3(15, 0, -20), Vector3(-15, 0, 20)]:
		var trunk := CylinderMesh.new()
		trunk.top_radius = 0.2
		trunk.bottom_radius = 0.35
		trunk.height = 4.5
		_deco(trunk, bark, p + Vector3(0, 2.25, 0))
		var crown := SphereMesh.new()
		crown.radius = 1.8
		crown.height = 2.6
		_deco(crown, Palette.mat(Palette.AUTUMN if p.z > 0 else Palette.AUTUMN_DEEP), p + Vector3(0, 5.2, 0))


## Art pass for one short lane stretch (decoration only, no collision, the
## fighting space stays clear): flagstones with worn joints, a capped wall
## course with buttresses and moss at the feet, team banners either side of
## the tower, two braziers for warm light, grass tufts and a broken column
## drum against the wall. Original code built shapes. `s` is the team sign.
func _art_section(s: float, z0: float, z1: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	var dark := _stone(Palette.STONE_DARK.darkened(0.25))
	var joint := _stone(Palette.STONE_DARK.darkened(0.45))
	var moss := Palette.mat(Palette.MOSS)
	var grass := Palette.mat(Palette.MOSS.lightened(0.12))
	var team := 0 if s > 0.0 else 1
	var cloth := Palette.mat(Palette.team_color(team).darkened(0.3))
	var brass := Palette.mat(Palette.BRASS, 0.45, 0.8)
	# Flagstones: a grid of slightly uneven slabs, three stone tones, with a
	# darker joint plane under them so the gaps read as cracks.
	var tile := 1.5
	var cols := int((LANE_HALF * 2.0 - 1.0) / tile)
	var rows := int((z1 - z0) / tile)
	# The joint plane's top sits 1 cm above the lane floor (top at 0.02):
	# level with it, the two faces z-fought and flickered through the gaps.
	_deco(BoxMesh.new(), joint, Vector3(0, 0.025, s * (z0 + z1) * 0.5), Vector3(cols * tile, 0.01, rows * tile))
	for i in cols:
		for j in rows:
			if rng.randf() < 0.08:
				continue  # a missing slab now and then
			var x := -cols * tile * 0.5 + (i + 0.5) * tile
			var z := z0 + (j + 0.5) * tile
			var gap := rng.randf_range(0.06, 0.14)
			var h := rng.randf_range(0.02, 0.05)
			var m: Material = _stone_mats[rng.randi() % 3]
			if rng.randf() < 0.12:
				m = dark  # a scorched or wet slab
			_deco(BoxMesh.new(), m, Vector3(x, h * 0.5 + 0.03, s * z), Vector3(tile - gap, h, tile - gap),
				Vector3(0, rng.randf_range(-1.5, 1.5), 0))
	# A worn ring round the tower foot and a cracked line across the lane.
	var ring := TorusMesh.new()
	ring.inner_radius = 3.2
	ring.outer_radius = 3.5
	ring.rings = 48
	_deco(ring, dark, Vector3(0, 0.085, s * TOWER_Z), Vector3(1, 0.04, 1))  # just above the tallest slab
	for k in 5:
		var zc := z0 + rng.randf_range(1.0, z1 - z0 - 1.0)
		_deco(BoxMesh.new(), joint, Vector3(rng.randf_range(-3.0, 3.0), 0.085, s * zc), Vector3(rng.randf_range(2.0, 5.0), 0.01, 0.06),
			Vector3(0, rng.randf_range(-25.0, 25.0), 0))
	for side: float in [-1.0, 1.0]:
		var xw: float = side * (LANE_HALF + 0.5)  # lane wall face is at 7.0; cap sits on the wall top
		# Cap course and buttresses along the wall top and face.
		var z := z0
		while z < z1:
			var len := minf(rng.randf_range(2.0, 3.5), z1 - z)
			if not _in_gap(z + len * 0.5):
				_deco(BoxMesh.new(), _stone_mats[2], Vector3(side * (LANE_HALF + WALL_IN) * 0.5, 3.7, s * (z + len * 0.5)),
					Vector3(WALL_IN - LANE_HALF + 0.3, 0.25, len - 0.12))
				_deco(BoxMesh.new(), dark, Vector3(xw - side * 0.3, 1.4, s * (z + len)), Vector3(0.5, 2.8, 0.35))  # buttress rib
			z += len
		# Moss and grass at the wall foot, kept against the wall.
		for k in 10:
			var zm := z0 + rng.randf_range(0.5, z1 - z0 - 0.5)
			if _in_gap(zm):
				continue
			var w := rng.randf_range(0.6, 1.6)
			var mossb := SphereMesh.new()
			mossb.radius = 0.5
			mossb.height = 1.0
			_deco(mossb, moss, Vector3(side * (LANE_HALF - 0.1), 0.05, s * zm), Vector3(w * 0.5, 0.12, w))
			var tuft := SphereMesh.new()
			tuft.radius = 0.25
			tuft.height = 0.5
			_deco(tuft, grass, Vector3(side * (LANE_HALF - 0.35), 0.1, s * (zm + 0.6)), Vector3(0.5, 0.45, 0.5))
		# Team banner on a pole beside the tower, and a brazier on a plinth.
		var bx: float = side * (LANE_HALF - 0.6)
		_deco(CylinderMesh.new(), Palette.mat(Palette.WOOD), Vector3(bx, 2.6, s * (TOWER_Z - 2.5)), Vector3(0.08, 5.2, 0.08))
		_deco(BoxMesh.new(), cloth, Vector3(bx - side * 0.6, 3.9, s * (TOWER_Z - 2.5)), Vector3(1.1, 2.4, 0.06))
		_deco(BoxMesh.new(), brass, Vector3(bx - side * 0.6, 5.12, s * (TOWER_Z - 2.5)), Vector3(1.3, 0.08, 0.1))
		var pz := s * (TOWER_Z + 4.5)
		_deco(BoxMesh.new(), _stone_mats[1], Vector3(bx, 0.45, pz), Vector3(0.9, 0.9, 0.9))
		var bowl := CylinderMesh.new()
		bowl.top_radius = 0.42
		bowl.bottom_radius = 0.25
		bowl.height = 0.35
		_deco(bowl, Palette.mat(Palette.IRON, 0.5, 0.7), Vector3(bx, 1.07, pz))
		var flame := SphereMesh.new()
		flame.radius = 0.22
		flame.height = 0.6
		_deco(flame, Palette.glow(Palette.AMBER, 4.0), Vector3(bx, 1.4, pz))
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.7, 0.4)
		light.light_energy = 1.6
		light.omni_range = 7.0
		light.position = Vector3(bx, 1.9, pz)
		add_child(light)
	# A broken column drum against the east wall, out of the lane proper.
	var drum := CylinderMesh.new()
	drum.top_radius = 0.55
	drum.bottom_radius = 0.55
	drum.height = 1.8
	_deco(drum, _stone_mats[2], Vector3(LANE_HALF - 0.7, 0.55, s * (z0 + 3.0)), Vector3.ONE, Vector3(0, 20, 90))
