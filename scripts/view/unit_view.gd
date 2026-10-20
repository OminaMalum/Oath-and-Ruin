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
		ChampionDef.Look.WARDEN:
			_build_warden()
		ChampionDef.Look.SKIRMISHER:
			_build_skirmisher()
		ChampionDef.Look.TRAINING_DUMMY:
			_build_dummy()
		ChampionDef.Look.MINION_MELEE:
			_build_minion(true)
		ChampionDef.Look.MINION_CASTER:
			_build_minion(false)
		ChampionDef.Look.BREAKER:
			_build_breaker()
		ChampionDef.Look.TOWER:
			_build_tower()
		ChampionDef.Look.CORE:
			_build_core()
		ChampionDef.Look.SHRINEBEARER:
			_build_shrinebearer()
	unit.damaged.connect(func(_a: float, _s: Unit) -> void: _flash = 1.0)
	if unit.def.kind == ChampionDef.Kind.STRUCTURE:
		unit.died.connect(func(_k: Unit) -> void: _ruin())
	else:
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
	var team_cloth := Palette.mat(Palette.team_color(unit.team).darkened(0.15)) if unit.team < 2 else cloth
	_part(_cyl(0.30, 0.40, 0.24), team_cloth, Vector3(0, 1.52, 0.02))  # mantle in team colour
	_part(_cyl(0.26, 0.47, 0.10), team_cloth, Vector3(0, 0.08, 0))     # hem band in team colour
	_team_ring(0.62)
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


## Team ring on the ground under a champion, readable from the camera.
func _team_ring(r: float) -> void:
	if unit.team >= 2:
		return
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r
	tm.outer_radius = r + 0.1
	tm.rings = 24
	ring.mesh = tm
	ring.material_override = Palette.ground_decal(Palette.team_color(unit.team), 0.7)
	ring.scale = Vector3(1, 0.05, 1)
	ring.position = Vector3(0, 0.03, 0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)


func _team_mat() -> StandardMaterial3D:
	return Palette.mat(Palette.team_color(unit.team).darkened(0.15)) if unit.team < 2 else Palette.mat(Palette.LEATHER)


## Oathwarden: broad and armoured, a tower shield on the left arm and a maul
## on the right. Wide shoulders so it reads as the frontline at a glance.
func _build_warden() -> void:
	var plate := Palette.mat(unit.def.primary_color, 0.5, 0.6)
	var leather := Palette.mat(Palette.LEATHER_DARK)
	var brass := Palette.mat(Palette.BRASS, 0.45, 0.8)
	var wood := Palette.mat(Palette.WOOD)
	var team := _team_mat()
	_part(_cyl(0.20, 0.24, 0.8), leather, Vector3(-0.17, 0.4, 0))       # legs
	_part(_cyl(0.20, 0.24, 0.8), leather, Vector3(0.17, 0.4, 0))
	_part(_cyl(0.34, 0.40, 0.42), team, Vector3(0, 0.95, 0))            # tabard skirt in team colour
	_part(_box(Vector3(0.78, 0.62, 0.46)), plate, Vector3(0, 1.38, 0))  # breastplate
	_part(_sphere(0.24), plate, Vector3(-0.48, 1.62, 0)).scale = Vector3(1.0, 0.7, 1.0)  # pauldrons
	_part(_sphere(0.24), plate, Vector3(0.48, 1.62, 0)).scale = Vector3(1.0, 0.7, 1.0)
	_part(_box(Vector3(0.80, 0.10, 0.48)), team, Vector3(0, 1.66, 0))   # team sash across the shoulders
	_part(_sphere(0.19), plate, Vector3(0, 1.86, 0))                    # helm
	_part(_box(Vector3(0.26, 0.05, 0.05)), Palette.mat(Color(0.08, 0.08, 0.08)), Vector3(0, 1.86, -0.18))  # visor slit
	_part(_box(Vector3(0.10, 1.05, 0.72)), plate, Vector3(-0.62, 1.15, -0.12))  # tower shield
	_part(_box(Vector3(0.12, 0.8, 0.10)), team, Vector3(-0.68, 1.15, -0.12))    # shield stripe
	_part(_cyl(0.035, 0.04, 1.3), wood, Vector3(0.58, 1.0, -0.25), Vector3(-15, 0, 0))  # maul haft
	_part(_box(Vector3(0.36, 0.26, 0.26)), Palette.mat(Palette.STONE_DARK), Vector3(0.58, 1.68, -0.43))  # maul head
	_focus_mat = Palette.glow(unit.def.accent_color, 1.0)
	_focus = _part(_cyl(0.11, 0.11, 0.05, 16), _focus_mat, Vector3(-0.69, 1.4, -0.12), Vector3(0, 0, 90))  # shield boss
	_part(_cyl(0.13, 0.13, 0.03, 16), brass, Vector3(-0.68, 1.4, -0.12), Vector3(0, 0, 90))
	_team_ring(0.72)


## Ashrunner: lean, hooded, two short blades held low. Light silhouette with
## a long scarf in team colour that streams behind it.
func _build_skirmisher() -> void:
	var cloth := Palette.mat(unit.def.primary_color)
	var leather := Palette.mat(Palette.LEATHER_DARK)
	var steel := Palette.mat(Palette.IRON, 0.35, 0.8)
	var skin := Palette.mat(Color(0.70, 0.55, 0.44))
	var team := _team_mat()
	_part(_cyl(0.11, 0.13, 0.8), leather, Vector3(-0.12, 0.4, 0.05), Vector3(-10, 0, 0))  # legs, mid-stride
	_part(_cyl(0.11, 0.13, 0.8), leather, Vector3(0.12, 0.4, -0.05), Vector3(10, 0, 0))
	_part(_cyl(0.18, 0.22, 0.6), cloth, Vector3(0, 1.1, 0.05), Vector3(15, 0, 0))     # torso, leaning in
	_part(_box(Vector3(0.40, 0.07, 0.26)), leather, Vector3(0, 0.84, 0.02))          # belt
	_part(_sphere(0.13), skin, Vector3(0, 1.5, -0.06))                                # face
	_part(_sphere(0.17), cloth, Vector3(0, 1.53, 0.0))                                # hood
	_part(_box(Vector3(0.36, 0.12, 0.30)), team, Vector3(0, 1.36, 0.04))             # scarf wrap
	_part(_box(Vector3(0.14, 0.05, 0.75)), team, Vector3(0.05, 1.32, 0.48), Vector3(-15, 0, 0))  # scarf tail
	_part(_box(Vector3(0.04, 0.03, 0.6)), steel, Vector3(-0.32, 0.95, -0.30))  # blades
	_part(_box(Vector3(0.04, 0.03, 0.6)), steel, Vector3(0.32, 0.95, -0.30))
	_focus_mat = Palette.glow(unit.def.accent_color, 1.0)
	_focus = _part(_sphere(0.05), _focus_mat, Vector3(0, 1.36, -0.13))  # clasp
	_team_ring(0.55)


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


## Minions: short, team-coloured. Shieldbearers carry a big square shield,
## slingers are slimmer with a hood. Both read as "small and many".
func _build_minion(melee: bool) -> void:
	var col := Palette.team_color(unit.team)
	var cloth := Palette.mat(col.darkened(0.25))
	var leather := Palette.mat(Palette.LEATHER)
	var iron := Palette.mat(Palette.IRON, 0.5, 0.6)
	var w := 0.34 if melee else 0.26
	_part(_cyl(w * 0.8, w, 0.6), cloth, Vector3(0, 0.45, 0))
	_part(_cyl(w * 0.7, w * 0.8, 0.35), leather, Vector3(0, 0.88, 0))
	_part(_sphere(0.15), iron if melee else cloth, Vector3(0, 1.12, 0))
	if melee:
		_part(_box(Vector3(0.5, 0.6, 0.06)), Palette.mat(col.darkened(0.1)), Vector3(-0.25, 0.7, -0.3))
		_part(_box(Vector3(0.06, 0.06, 0.6)), iron, Vector3(0.3, 0.8, -0.25))
	else:
		_part(_cyl(0.0, 0.14, 0.22), cloth, Vector3(0, 1.28, 0.04), Vector3(-25, 0, 0))
	_focus_mat = Palette.glow(col, 0.6)
	_focus = _part(_sphere(0.06), _focus_mat, Vector3(0.2, 0.9, -0.2))


## Breaker: a broad, stooped bearer of a stone maul, joins waves once the
## enemy tower has fallen. Bigger than a Shieldbearer so the threat reads.
func _build_breaker() -> void:
	var col := Palette.team_color(unit.team)
	var cloth := Palette.mat(col.darkened(0.3))
	var leather := Palette.mat(Palette.LEATHER)
	var iron := Palette.mat(Palette.IRON, 0.5, 0.6)
	var stone := Palette.mat(Palette.STONE_DARK)
	_part(_cyl(0.42, 0.55, 0.8), cloth, Vector3(0, 0.55, 0))
	_part(_box(Vector3(1.0, 0.5, 0.7)), leather, Vector3(0, 1.15, 0.05))
	_part(_box(Vector3(1.1, 0.12, 0.4)), iron, Vector3(0, 1.42, 0.05))
	_part(_sphere(0.2), iron, Vector3(0, 1.55, -0.12))
	_part(_box(Vector3(0.1, 0.1, 1.2)), leather, Vector3(0.5, 1.0, -0.4), Vector3(20, 0, 0))
	_part(_box(Vector3(0.45, 0.45, 0.5)), stone, Vector3(0.5, 0.75, -0.95), Vector3(20, 0, 0))
	_focus_mat = Palette.glow(col, 0.8)
	_focus = _part(_sphere(0.08), _focus_mat, Vector3(0, 1.2, -0.32))


## Warden Tower: stepped stone base, a tall shaft and a team-coloured crystal
## with its own light, visible from down the lane. A faint ring on the ground
## shows exactly how far it shoots.
func _build_tower() -> void:
	var col := Palette.team_color(unit.team)
	var stone := Palette.mat(Palette.STONE_WARM)
	var dark := Palette.mat(Palette.STONE_DARK)
	_part(_box(Vector3(4.0, 0.8, 4.0)), dark, Vector3(0, 0.4, 0))
	_part(_box(Vector3(3.0, 0.8, 3.0)), stone, Vector3(0, 1.2, 0))
	_part(_cyl(0.9, 1.2, 4.2, 8), stone, Vector3(0, 3.7, 0))
	_part(_cyl(1.3, 1.0, 0.5, 8), dark, Vector3(0, 6.0, 0))
	_focus_mat = Palette.glow(col, 2.5)
	var crystal := PrismMesh.new()
	crystal.size = Vector3(0.9, 1.6, 0.9)
	_focus = _part(crystal, _focus_mat, Vector3(0, 7.1, 0))
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 2.0
	light.omni_range = 9.0
	light.position = Vector3(0, 7.0, 0)
	add_child(light)
	var ring := MeshInstance3D.new()
	var t := TorusMesh.new()
	var r := unit.def.basic_attack.range
	t.inner_radius = r - 0.15
	t.outer_radius = r
	t.rings = 64
	t.ring_segments = 4
	ring.mesh = t
	ring.scale = Vector3(1, 0.05, 1)
	ring.position.y = 0.03
	ring.material_override = Palette.ground_decal(col, 0.35)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.name = "RangeRing"
	add_child(ring)


## Oathstone: a large crystal on a dais. The end goal of the lane.
func _build_core() -> void:
	var col := Palette.team_color(unit.team)
	_part(_cyl(3.0, 3.4, 0.8, 10), Palette.mat(Palette.STONE_DARK), Vector3(0, 0.4, 0))
	_part(_cyl(2.4, 2.8, 0.6, 10), Palette.mat(Palette.STONE_WARM), Vector3(0, 1.1, 0))
	_focus_mat = Palette.glow(col, 1.8)
	var crystal := PrismMesh.new()
	crystal.size = Vector3(2.0, 3.6, 2.0)
	_focus = _part(crystal, _focus_mat, Vector3(0, 3.2, 0))
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 2.5
	light.omni_range = 12.0
	light.position = Vector3(0, 4.0, 0)
	add_child(light)


## Shrinebearer: a huge shelled beast carrying a small ruined shrine on its
## back. Wild it is moss and old brass; claimed it flies its team's banner.
func _build_shrinebearer() -> void:
	var shell := Palette.mat(Color(0.33, 0.36, 0.22), 0.7)
	var hide := Palette.mat(Color(0.30, 0.25, 0.20))
	var stone := Palette.mat(Palette.STONE_WARM)
	var brass := Palette.mat(Palette.BRASS, 0.45, 0.8)
	_part(_sphere(1.0), shell, Vector3(0, 1.5, 0.1)).scale = Vector3(1.7, 0.8, 2.0)
	_part(_sphere(0.55), hide, Vector3(0, 1.1, -1.9))                       # head
	_part(_cyl(0.02, 0.16, 0.9), brass, Vector3(0.3, 1.25, -2.45), Vector3(-70, 0, 0))   # horn
	_part(_cyl(0.02, 0.16, 0.9), brass, Vector3(-0.3, 1.25, -2.45), Vector3(-70, 0, 0))
	for lx in [-1.2, 1.2]:
		for lz in [-1.0, 1.1]:
			_part(_cyl(0.22, 0.28, 1.0), hide, Vector3(lx, 0.5, lz))
	_part(_box(Vector3(1.2, 0.2, 1.2)), stone, Vector3(0, 2.3, 0.3))       # shrine floor
	_part(_box(Vector3(0.25, 1.1, 0.25)), stone, Vector3(-0.45, 2.95, 0.3))
	_part(_box(Vector3(0.25, 1.1, 0.25)), stone, Vector3(0.45, 2.95, 0.3))
	_part(_box(Vector3(1.2, 0.25, 0.4)), stone, Vector3(0, 3.6, 0.3))
	if unit.team <= 1:
		var flag := Palette.mat(Palette.team_color(unit.team).darkened(0.2))
		_part(_box(Vector3(0.05, 1.4, 0.05)), Palette.mat(Palette.WOOD), Vector3(0, 4.3, 0.6))
		_part(_box(Vector3(0.7, 0.5, 0.04)), flag, Vector3(0.36, 4.75, 0.6))
	_focus_mat = Palette.glow(Color(0.85, 0.75, 1.0), 1.5)
	_focus = _part(_sphere(0.18), _focus_mat, Vector3(0, 2.9, 0.3))


## Destroyed structures stay as a dark broken stump, so the map remembers.
func _ruin() -> void:
	for c in get_children():
		if c is MeshInstance3D and c != _focus and c.name != "RangeRing":
			(c as MeshInstance3D).scale.y *= 0.5
			(c as MeshInstance3D).position.y *= 0.5
		elif c is Node3D:
			(c as Node3D).visible = false
	_focus = null


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
