class_name ThreeLaneBuilder
extends ArenaBuilder
## A rough three lane test map (graybox): three straight lanes between two
## bases, jungle between the lanes with broken walls and pillars, and the
## Shrinebearer's clearing in the west jungle. Mirrored across z = 0 like
## the first map: Oath (team 0) in the south (+z), Ruin (team 1) north (-z).
## For rotation and jungle testing; the art pass stays with the lane map.

const LANES: Array[float] = [-36.0, 0.0, 36.0]  # lane centres (x)
const LANE_HALF := 6.0
const OUTER := 46.0       # outer wall line (x)
const BASE_Z := 54.0      # base front wall; lanes run between the bases
const END_Z := 88.0
const TOWER_Z := 36.0
const CORE_Z := 64.0
const FOUNTAIN_Z := 78.0
const GAPS := [12.0, 34.0]  # openings from every lane into the jungle (both halves)
const GAP_HALF := 3.0
const CAMP := Vector3(-18.0, 0.0, 0.0)

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 41
	_stone_mats = [_stone(Palette.STONE), _stone(Palette.STONE_DARK), _stone(Palette.STONE_WARM)]
	_environment()
	_static_box(Vector3(OUTER * 2.0 + 8.0, FLOOR_THICK, END_Z * 2.0 + 8.0), Vector3(0, -FLOOR_THICK * 0.5, 0), _stone_mats[0])
	for x in LANES:
		var path := BoxMesh.new()
		path.size = Vector3(LANE_HALF * 2.0 - 2.0, 0.02, BASE_Z * 2.0)
		_deco(path, _stone_mats[2], Vector3(x, 0.01, 0))
	# Lane edges toward the jungle: both sides of the mid lane, the inner side of the outer lanes.
	for side in [-1.0, 1.0]:
		_edge(side * (LANE_HALF + 0.75))
		_edge(side * (absf(LANES[0]) - LANE_HALF - 0.75))
		_static_box(Vector3(2.0, 5.0, END_Z * 2.0), Vector3(side * (OUTER + 1.0), 2.5, 0), _stone_mats[1])
	for s in [1.0, -1.0]:
		_base(s)
	_jungle()


## A broken wall along a lane edge at `x`, open at GAPS.
func _edge(x: float) -> void:
	var z := -BASE_Z
	while z < BASE_Z - 0.01:
		if _in_gap(z + 0.01):
			z += 0.5
			continue
		var next := minf(z + _rng.randf_range(3.0, 5.0), BASE_Z)
		for g: float in GAPS:
			for gz in [g - GAP_HALF, -g - GAP_HALF]:
				if z < gz and next > gz:
					next = gz
		var h := _rng.randf_range(2.4, 3.4)
		_static_box(Vector3(1.5, h, next - z), Vector3(x, h * 0.5, (z + next) * 0.5), _stone_mats[_rng.randi() % 3])
		z = next


func _in_gap(z: float) -> bool:
	for g: float in GAPS:
		if absf(absf(z) - g) < GAP_HALF:
			return true
	return false


## The jungle: pillars and wall pieces between the lanes, mirrored across
## z = 0 so neither team's side is easier; a clear ring round the camp.
func _jungle() -> void:
	for side in [-1.0, 1.0]:
		for x in [13.0, 20.0, 27.0]:
			for z in [6.0, 20.0, 28.0, 44.0]:
				var p := Vector3(side * (x + _rng.randf_range(-1.0, 1.0)), 0, z + _rng.randf_range(-1.5, 1.5))
				if Vector2(p.x - CAMP.x, p.z - CAMP.z).length() < 9.0 or Vector2(p.x + CAMP.x, p.z).length() < 6.0:
					continue
				var size := Vector3(_rng.randf_range(2.0, 3.5), _rng.randf_range(2.6, 3.6), _rng.randf_range(2.0, 4.5))
				for zs in [1.0, -1.0]:
					_static_box(size, Vector3(p.x, size.y * 0.5, zs * p.z), _stone_mats[_rng.randi() % 3])
	# The camp: a low stone dais in the west clearing.
	_static_box(Vector3(5.0, 0.6, 5.0), CAMP + Vector3(0, 0.3, 0), _stone_mats[2])
	_static_box(Vector3(3.4, 0.6, 3.4), CAMP + Vector3(0, 0.9, 0), _stone_mats[0])
	var bark := Palette.mat(Palette.WOOD.darkened(0.2))
	for p in [Vector3(20, 0, 0), Vector3(-20, 0, 14), Vector3(-20, 0, -14), Vector3(24, 0, 38), Vector3(-24, 0, -38)]:
		var trunk := CylinderMesh.new()
		trunk.top_radius = 0.2
		trunk.bottom_radius = 0.35
		trunk.height = 4.5
		_deco(trunk, bark, p + Vector3(0, 2.25, 0))
		var crown := SphereMesh.new()
		crown.radius = 1.8
		crown.height = 2.6
		_deco(crown, Palette.mat(Palette.AUTUMN if p.z >= 0 else Palette.AUTUMN_DEEP), p + Vector3(0, 5.2, 0))


func _base(s: float) -> void:
	var team := 0 if s > 0.0 else 1
	var col := Palette.team_color(team)
	_static_box(Vector3(OUTER * 2.0 + 4.0, 4.5, 2), Vector3(0, 2.25, s * END_Z), _stone_mats[1])
	# Front wall with a gate for each lane.
	var x := -OUTER
	for lx in LANES:
		var x1 := lx - LANE_HALF
		if x1 > x:
			_static_box(Vector3(x1 - x, 3.8, 1.6), Vector3((x + x1) * 0.5, 1.9, s * BASE_Z), _stone_mats[2])
		x = lx + LANE_HALF
	_static_box(Vector3(OUTER - x, 3.8, 1.6), Vector3((x + OUTER) * 0.5, 1.9, s * BASE_Z), _stone_mats[2])
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
	var cloth := Palette.mat(col.darkened(0.35))
	for lx in LANES:
		for gx in [lx - LANE_HALF - 0.7, lx + LANE_HALF + 0.7]:
			_static_box(Vector3(1.4, 6.0, 1.4), Vector3(gx, 3.0, s * BASE_Z), _stone_mats[0])
			_deco(BoxMesh.new(), cloth, Vector3(gx, 3.6, s * (BASE_Z - 0.8)), Vector3(1.1, 3.0, 0.05))
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 1.5
	light.omni_range = 12.0
	light.position = Vector3(0, 3.0, s * FOUNTAIN_Z)
	add_child(light)
