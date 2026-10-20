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
