class_name SummonModel
extends Node3D
## Simple built models for summons (Look SENTRY, BANNER and SPIRIT), added by
## the world view when a summon appears. Primitive shapes only, like the
## champion fallbacks; the graphics side can replace them with real models.

var unit: Unit


func _init(u: Unit) -> void:
	unit = u
	name = "SummonModel"


func _ready() -> void:
	# A summon with a modelled body (assets/units/<id>.glb) is drawn like a
	# minion: clips, cloth, ragdoll. The built shapes below stay the fallback.
	if not ChampionModel.path_for(unit.def.id).is_empty():
		unit.add_child.call_deferred(UnitView.new(unit))
		queue_free()
		return
	match unit.def.look:
		ChampionDef.Look.SENTRY:
			_sentry()
		ChampionDef.Look.BANNER:
			_banner()
		ChampionDef.Look.SPIRIT:
			_spirit()


func _process(_dt: float) -> void:
	if is_queued_for_deletion():
		return
	if unit.def.look == ChampionDef.Look.SPIRIT:
		position.y = 0.15 + sin(Time.get_ticks_msec() * 0.004 + unit.net_id) * 0.08  # it floats


func _part(mesh: Mesh, m: Material, pos: Vector3, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = rot_deg
	add_child(mi)
	return mi


## A brass repeater on a tripod, barrel along -Z (where the unit faces).
func _sentry() -> void:
	var iron := Palette.mat(Palette.IRON, 0.5, 0.6)
	var brass := Palette.mat(Palette.BRASS, 0.4, 0.7)
	var wood := Palette.mat(Palette.WOOD)
	for i in 3:
		var leg := _part(UnitView._cyl(0.04, 0.05, 1.0), wood, Vector3.ZERO)
		var ang := TAU * i / 3.0
		leg.position = Vector3(sin(ang) * 0.28, 0.45, cos(ang) * 0.28)
		leg.rotation = Vector3(cos(ang) * 0.35, 0.0, -sin(ang) * 0.35)
	_part(UnitView._box(Vector3(0.5, 0.36, 0.6)), brass, Vector3(0, 1.0, 0))
	_part(UnitView._cyl(0.07, 0.07, 0.8), iron, Vector3(0, 1.05, -0.6), Vector3(90, 0, 0))
	_part(UnitView._box(Vector3(0.52, 0.06, 0.62)), Palette.mat(Palette.team_color(unit.team)), Vector3(0, 0.84, 0))
	_part(UnitView._sphere(0.08), Palette.glow(unit.def.accent_color, 1.5), Vector3(0, 1.25, 0.1))


## A tall standard: pole, crossbar and a team cloth, a brass finial on top.
func _banner() -> void:
	var wood := Palette.mat(Palette.WOOD)
	_part(UnitView._cyl(0.05, 0.06, 2.8), wood, Vector3(0, 1.4, 0))
	_part(UnitView._cyl(0.03, 0.03, 0.9), wood, Vector3(0, 2.55, 0), Vector3(0, 0, 90))
	_part(UnitView._box(Vector3(0.85, 1.1, 0.04)), Palette.mat(Palette.team_color(unit.team).darkened(0.15)), Vector3(0, 1.95, 0))
	_part(UnitView._box(Vector3(0.3, 0.3, 0.05)), Palette.mat(Palette.BRASS, 0.4, 0.7), Vector3(0, 2.0, 0.01))
	_part(UnitView._sphere(0.08), Palette.mat(Palette.BRASS, 0.4, 0.7), Vector3(0, 2.86, 0))
	_part(UnitView._cyl(0.25, 0.3, 0.1), Palette.mat(Palette.IRON, 0.6, 0.4), Vector3(0, 0.05, 0))


## A willing dead: a shrouded figure in funeral cords, hem dissolving into
## violet light. Serious, not a cartoon skeleton.
func _spirit() -> void:
	var shroud := StandardMaterial3D.new()
	shroud.albedo_color = Color(unit.def.primary_color, 0.82)
	shroud.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shroud.roughness = 0.9
	shroud.emission_enabled = true
	shroud.emission = unit.def.accent_color * 0.25
	var cord := Palette.mat(Color(0.88, 0.85, 0.78), 0.8)
	_part(UnitView._cyl(0.12, 0.42, 1.2), shroud, Vector3(0, 0.75, 0))
	_part(UnitView._cyl(0.2, 0.14, 0.32), shroud, Vector3(0, 1.48, 0))
	_part(UnitView._sphere(0.15), Palette.mat(Color(0.82, 0.8, 0.74), 0.7), Vector3(0, 1.5, -0.05))
	for side in [-1.0, 1.0]:
		_part(UnitView._cyl(0.05, 0.07, 0.7), shroud, Vector3(side * 0.24, 1.0, -0.12), Vector3(-35, 0, side * 12))
		_part(UnitView._sphere(0.03), Palette.glow(unit.def.accent_color, 2.0), Vector3(side * 0.05, 1.52, -0.18))
	_part(UnitView._cyl(0.17, 0.17, 0.04), cord, Vector3(0, 1.12, 0))
	_part(UnitView._cyl(0.27, 0.27, 0.04), cord, Vector3(0, 0.62, 0))
	_part(UnitView._cyl(0.44, 0.5, 0.03), Palette.glow(Palette.team_color(unit.team), 0.8), Vector3(0, 0.12, 0))
