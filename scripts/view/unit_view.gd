class_name UnitView
extends Node3D
## Primitive placeholder model plus hit flash and windup glow. Reads Unit
## state only. Model faces -Z (Godot forward); feet at the origin; 1 unit = 1 m.

var unit: Unit
var _materials: Array[StandardMaterial3D] = []
var _focus: MeshInstance3D  # the part that glows during windups
var _focus_mat: StandardMaterial3D
var _flash: float = 0.0


func _init(u: Unit) -> void:
	unit = u


func _ready() -> void:
	match unit.def.look:
		ChampionDef.Look.SPELLCASTER:
			_build_spellcaster()
		ChampionDef.Look.TRAINING_DUMMY:
			_build_dummy()
	unit.damaged.connect(func(_a: float, _s: Unit) -> void: _flash = 1.0)
	unit.died.connect(func(_k: Unit) -> void: visible = false)
	unit.respawned.connect(func() -> void: visible = true)


func _part(mesh: Mesh, m: StandardMaterial3D, pos: Vector3, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = rot_deg
	add_child(mi)
	if not _materials.has(m):
		_materials.append(m)
	return mi


static func _cyl(top: float, bottom: float, h: float, sides := 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = sides
	return c


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 16
	s.rings = 8
	return s


## Ruinscribe: hooded scholar in a long travel-worn robe, a satchel of
## folios and a tall staff with a teal focus stone held out to the right.
## The silhouette reads as tall cone + hood + staff from any distance.
func _build_spellcaster() -> void:
	var robe := Palette.mat(unit.def.primary_color)
	var leather := Palette.mat(Palette.LEATHER_DARK)
	var cloth := Palette.mat(Palette.LEATHER)
	var wood := Palette.mat(Palette.WOOD)
	var brass := Palette.mat(Palette.BRASS, 0.45, 0.8)
	var skin := Palette.mat(Color(0.78, 0.62, 0.50))
	_part(_cyl(0.24, 0.46, 1.05), robe, Vector3(0, 0.53, 0))           # skirt of the robe
	_part(_cyl(0.20, 0.25, 0.55), robe, Vector3(0, 1.3, 0))            # torso
	_part(_box(Vector3(0.52, 0.08, 0.30)), leather, Vector3(0, 1.08, 0))  # belt
	_part(_cyl(0.30, 0.38, 0.22), cloth, Vector3(0, 1.52, 0.02))       # mantle
	_part(_sphere(0.15), skin, Vector3(0, 1.72, -0.02))                # face
	_part(_sphere(0.20), robe, Vector3(0, 1.76, 0.05))                 # hood
	_part(_cyl(0.0, 0.12, 0.28), robe, Vector3(0, 1.9, 0.16), Vector3(-40, 0, 0))  # hood point
	_part(_box(Vector3(0.22, 0.28, 0.12)), leather, Vector3(-0.32, 1.0, 0.08))     # satchel
	_part(_box(Vector3(0.16, 0.20, 0.03)), Palette.mat(Color(0.86, 0.80, 0.66)), Vector3(-0.32, 1.12, 0.0))  # folio
	_part(_cyl(0.07, 0.08, 0.5), robe, Vector3(0.30, 1.28, -0.12), Vector3(60, 0, -10))   # staff arm
	_part(_cyl(0.025, 0.03, 2.0), wood, Vector3(0.42, 1.0, -0.30))                     # staff
	_part(_cyl(0.05, 0.05, 0.08), brass, Vector3(0.42, 1.98, -0.30))                   # setting
	_focus_mat = Palette.glow(unit.def.accent_color, 1.2)
	var stone := PrismMesh.new()
	stone.size = Vector3(0.14, 0.24, 0.14)
	_focus = _part(stone, _focus_mat, Vector3(0.42, 2.14, -0.30))


## Training dummy: straw body on a post with a painted target shield.
func _build_dummy() -> void:
	var wood := Palette.mat(Palette.WOOD)
	var straw := Palette.mat(unit.def.primary_color)
	var rope := Palette.mat(Palette.LEATHER)
	_part(_cyl(0.08, 0.10, 1.9), wood, Vector3(0, 0.95, 0))
	_part(_box(Vector3(0.9, 0.12, 0.12)), wood, Vector3(0, 1.35, 0))
	_part(_cyl(0.30, 0.36, 0.8), straw, Vector3(0, 1.2, 0))
	_part(_sphere(0.22), straw, Vector3(0, 1.8, 0))
	_part(_cyl(0.32, 0.32, 0.05), rope, Vector3(0, 1.0, 0))
	_part(_cyl(0.32, 0.32, 0.05), rope, Vector3(0, 1.45, 0))
	_part(_cyl(0.42, 0.42, 0.06, 20), Palette.mat(Palette.IRON, 0.6, 0.5), Vector3(0, 1.2, -0.38), Vector3(90, 0, 0))
	_part(_cyl(0.28, 0.28, 0.07, 20), Palette.mat(Palette.STONE_WARM), Vector3(0, 1.2, -0.40), Vector3(90, 0, 0))
	_focus_mat = Palette.glow(unit.def.accent_color, 1.0)
	_focus = _part(_cyl(0.12, 0.12, 0.08, 16), _focus_mat, Vector3(0, 1.2, -0.43), Vector3(90, 0, 0))


func _process(delta: float) -> void:
	# Hit flash: brief warm white on every part.
	_flash = maxf(0.0, _flash - delta * 6.0)
	for m in _materials:
		if m == _focus_mat:
			continue
		m.emission_enabled = _flash > 0.0
		m.emission = Color(1.0, 0.95, 0.85)
		m.emission_energy_multiplier = _flash * 1.5
	# Windup tell: the focus swells and brightens until release.
	var charge := 0.0
	if unit.cast_phase == Unit.CastPhase.WINDUP:
		var a := unit.cast_ability()
		charge = 1.0 - clampf(unit.cast_timer / maxf(a.cast_time, 0.01), 0.0, 1.0)
	if _focus:
		_focus_mat.emission_energy_multiplier = 1.2 + charge * 6.0
		_focus.scale = Vector3.ONE * (1.0 + charge * 0.9)
