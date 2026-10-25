class_name ThreeLaneBuilder
extends ArenaBuilder
## A rough three lane test map (graybox): three straight lanes between two
## bases, jungle between the lanes with broken walls and pillars, and the
## Shrinebearer's clearing in the west jungle. Mirrored across z = 0 like
## the first map: Oath (team 0) in the south (+z), Ruin (team 1) north (-z).
## Dressed like the lane map: masonry kit on every wall, the textured floor
## laid out for three lanes, and ThreeLaneDressing for trees, lights and
## magic. The dressing has its own RNGs, so the layout never moves.

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
var _drng := RandomNumberGenerator.new()  # dressing only
var _krng := RandomNumberGenerator.new()  # wall kit only
var _slate: StandardMaterial3D
var _plinth: StandardMaterial3D
var _wall_boxes: Array[AABB] = []
var _kit := {}  # Material -> SurfaceTool, one merged mesh per material
## Jungle blocks (centre and size), so the dressing can tuck trees against them.
var pillars: Array[AABB] = []


func _ready() -> void:
	_rng.seed = 41
	_drng.seed = 78
	_krng.seed = 6
	_stone_mats = [Art.stone("wall"), Art.stone("wall", Color(0.82, 0.80, 0.78)), Art.stone("wall", Color(1.05, 0.97, 0.86))]
	_slate = Art.stone("slate", Color(0.95, 0.92, 0.86))
	_plinth = Art.stone("slate", Color(0.62, 0.60, 0.56))
	_environment()
	var floor := _static_box(Vector3(OUTER * 2.0 + 8.0, FLOOR_THICK, END_Z * 2.0 + 8.0), Vector3(0, -FLOOR_THICK * 0.5, 0), _stone_mats[0])
	for mi in floor.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = Art.ground_three()
	# Valley floor outside the walls (no collision), same shader so no seam.
	var fx := OUTER + 4.0
	var fz := END_Z + 4.0
	for o: Array in [[Vector3(500, 1, 160), Vector3(0, -0.5, fz + 80.0)], [Vector3(500, 1, 160), Vector3(0, -0.5, -fz - 80.0)],
			[Vector3(170, 1, fz * 2.0), Vector3(fx + 85.0, -0.5, 0)], [Vector3(170, 1, fz * 2.0), Vector3(-fx - 85.0, -0.5, 0)]]:
		_deco(_box_mesh(o[0]), Art.ground_three(), o[1])
	# Lane edges toward the jungle: both sides of the mid lane, the inner side of the outer lanes.
	for side in [-1.0, 1.0]:
		_edge(side * (LANE_HALF + 0.75), -side)
		_edge(side * (absf(LANES[0]) - LANE_HALF - 0.75), side)
		_wall(Vector3(2.0, 5.0, END_Z * 2.0), Vector3(side * (OUTER + 1.0), 2.5, 0), _stone_mats[1], [Vector3(-side, 0, 0)], true)
	for s in [1.0, -1.0]:
		_base(s)
	_jungle()
	_kit_commit()
	ThreeLaneDressing.new(self, _drng).build()


func _environment() -> void:
	Art.environment(self)


## A wall block with masonry: a slate cap, a darker plinth at its foot, a
## string course, pilasters on each face in `faces` (outward normals) and
## merlons along the top. The collision box is exactly the graybox one.
func _wall(size: Vector3, pos: Vector3, m: Material, faces: Array = [], merlons := false) -> StaticBody3D:
	var body := _static_box(size, pos, m)
	var vis := _wall_grow(size, pos)
	for mi in body.find_children("*", "MeshInstance3D", false, false):
		((mi as MeshInstance3D).mesh as BoxMesh).size = vis
	var top := pos.y + size.y * 0.5
	var over := _drng.randf_range(0.10, 0.18)
	_deco(_box_mesh(Vector3(size.x + over * 2.0, 0.26, size.z + over * 2.0)), _slate,
		Vector3(pos.x, top + 0.11 + 0.006 * (_wall_boxes.size() % 4), pos.z), Vector3.ONE, Vector3(0, _drng.randf_range(-0.6, 0.6), 0))
	var ph := _drng.randf_range(0.45, 0.62)
	_deco(_box_mesh(Vector3(size.x + 0.16, ph, size.z + 0.16)), _plinth, Vector3(pos.x, ph * 0.5 - 0.04, pos.z))
	if size.y > 2.0:
		var band_y := minf(1.75, top - 0.7) + _krng.randf_range(-0.03, 0.03)
		_kit_box(_plinth, Vector3(size.x + 0.1, 0.16, size.z + 0.1), Vector3(pos.x, band_y, pos.z))
	var along_x := size.x > size.z
	for n: Vector3 in faces:
		var on_x := absf(n.x) > 0.5
		var face := pos + n * (size.x if on_x else size.z) * 0.5
		var span := size.z if on_x else size.x
		var count := maxi(1, int(span / 2.6))
		var pil := Vector3(0.24, top - 0.25, 0.5) if on_x else Vector3(0.5, top - 0.25, 0.24)
		var cap := Vector3(0.34, 0.12, 0.62) if on_x else Vector3(0.62, 0.12, 0.34)
		for i in count:
			var t := -span * 0.5 + span * (i + 0.5) / count
			var c := face + (Vector3(0, 0, t) if on_x else Vector3(t, 0, 0))
			_kit_box(_plinth, pil, Vector3(c.x, pil.y * 0.5, c.z) + n * 0.12)
			_kit_box(_slate, cap, Vector3(c.x, pil.y + 0.02, c.z) + n * 0.15)
	if merlons:
		var along := size.x if along_x else size.z
		var across := (size.z if along_x else size.x) * 0.8
		var count := int(along / 1.3)
		for i in count:
			var t := -along * 0.5 + (i + 0.5) * along / count
			var mh := _krng.randf_range(0.5, 0.65)
			var msize := Vector3(0.62, mh, across) if along_x else Vector3(across, mh, 0.62)
			var at := pos + (Vector3(t, 0, 0) if along_x else Vector3(0, 0, t))
			_kit_box(_stone_mats[i % 3], msize, Vector3(at.x, top + 0.24 + mh * 0.5, at.z))
	return body


func _kit_box(m: Material, size: Vector3, pos: Vector3) -> void:
	if not _kit.has(m):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_kit[m] = st
	(_kit[m] as SurfaceTool).append_from(_box_mesh(size), 0, Transform3D(Basis.IDENTITY, pos))


func _kit_commit() -> void:
	for m: Material in _kit:
		var mi := MeshInstance3D.new()
		mi.mesh = (_kit[m] as SurfaceTool).commit()
		mi.material_override = m
		add_child(mi)
	_kit.clear()


## The smallest growth (4 to 22 mm a side) of a block's visible mesh that
## keeps its side faces off the faces of blocks already placed (no z-fight).
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


## A broken wall along a lane edge at `x`, open at GAPS. `lane_side` is the
## x direction its lane face looks; both faces get pilasters.
func _edge(x: float, lane_side: float) -> void:
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
		_wall(Vector3(1.5, h, next - z), Vector3(x, h * 0.5, (z + next) * 0.5), _stone_mats[_rng.randi() % 3],
			[Vector3(lane_side, 0, 0), Vector3(-lane_side, 0, 0)] if next - z > 2.0 else [])
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
					var at := Vector3(p.x, size.y * 0.5, zs * p.z)
					_wall(size, at, _stone_mats[_rng.randi() % 3])
					pillars.append(AABB(at - size * 0.5, size))
	# The camp: a low stone dais in the west clearing.
	_static_box(Vector3(5.0, 0.6, 5.0), CAMP + Vector3(0, 0.3, 0), Art.stone("plaza", Color(0.9, 0.88, 0.84)))
	_static_box(Vector3(3.4, 0.6, 3.4), CAMP + Vector3(0, 0.9, 0), _slate)


func _base(s: float) -> void:
	var team := 0 if s > 0.0 else 1
	var col := Palette.team_color(team)
	_wall(Vector3(OUTER * 2.0 + 4.0, 4.5, 2), Vector3(0, 2.25, s * END_Z), _stone_mats[1], [Vector3(0, 0, -s)], true)
	# Front wall with a gate for each lane.
	var x := -OUTER
	for lx in LANES:
		var x1 := lx - LANE_HALF
		if x1 > x:
			_wall(Vector3(x1 - x, 3.8, 1.6), Vector3((x + x1) * 0.5, 1.9, s * BASE_Z), _stone_mats[2], [Vector3(0, 0, -s)], true)
		x = lx + LANE_HALF
	_wall(Vector3(OUTER - x, 3.8, 1.6), Vector3((x + OUTER) * 0.5, 1.9, s * BASE_Z), _stone_mats[2], [Vector3(0, 0, -s)], true)
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
			_wall(Vector3(1.4, 6.0, 1.4), Vector3(gx, 3.0, s * BASE_Z), _stone_mats[0])
			_deco(BoxMesh.new(), cloth, Vector3(gx, 3.6, s * (BASE_Z - 0.8)), Vector3(1.1, 3.0, 0.05))
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 1.5
	light.omni_range = 12.0
	light.position = Vector3(0, 3.0, s * FOUNTAIN_Z)
	add_child(light)
