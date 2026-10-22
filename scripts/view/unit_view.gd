class_name UnitView
extends Node3D
## Primitive placeholder model plus hit flash and windup glow. Reads Unit
## state only. Model faces -Z (Godot forward); feet at the origin; 1 unit = 1 m.

var unit: Unit
var _materials: Array[StandardMaterial3D] = []
var _focus: MeshInstance3D  # the part that glows during windups
var _focus_mat: StandardMaterial3D
var _flash: float = 0.0
## Camera fade (towers and cores between the camera and the champion).
var _fade_hold := 0.0
var _alpha := 1.0


func fade_for_camera() -> void:
	_fade_hold = 0.15
## Presentation (view only, the sim never reads it): every part sits under
## `_body`, which leans with movement, bobs at a walking rhythm and falls over
## on death. The Ruinscribe's staff hangs from `_arm`, a pivot at the
## shoulder, so a cast swings the staff forward and the focus stone ends up
## where the sim fires the bolt from.
var _body: Node3D
var _arm: Node3D
var _skirt: MeshInstance3D
## Oathwarden and Ashrunner: weapon pivots and leg pivots, same rules.
enum Swing { NONE, STAFF, MAUL, BLADES }
var _swing: Swing = Swing.NONE
var _weapon_r: Node3D   # maul arm, or right blade
var _weapon_l: Node3D   # shield arm, or left blade
var _legs: Array[Node3D] = []
var _weapon_r_home := Vector3.ZERO
var _anim_t: float = 0.0
var _death_t: float = -1.0   # seconds since death, -1 while alive
var _recoil: float = 0.0
var _step_phase: float = 0.0
var _lean := Vector2.ZERO    # smoothed (side, forward) lean
var _spin: Node3D            # towers and cores: the rune ring that turns slowly


func launch_point() -> Vector3:
	return _focus.global_position if _focus and is_instance_valid(_focus) and visible else unit.muzzle_position()


func _init(u: Unit) -> void:
	unit = u


func _ready() -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
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
	unit.cast_released.connect(func(_slot: int, _a: AbilityDef, _t: Vector3) -> void: _recoil = 1.0)
	if unit.def.kind == ChampionDef.Kind.STRUCTURE:
		unit.died.connect(func(_k: Unit) -> void: _ruin())
	else:
		unit.died.connect(func(_k: Unit) -> void: _death_t = 0.0)
		unit.respawned.connect(func() -> void:
			_death_t = -1.0
			visible = true
			_body.rotation = Vector3.ZERO
			_body.position = Vector3.ZERO)


func _part(mesh: Mesh, m: StandardMaterial3D, pos: Vector3, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = rot_deg
	(_body if _body else self).add_child(mi)
	if not _materials.has(m):
		_materials.append(m)
	return mi


## A pivot node in body space; parts attached to it keep their body-space
## placement and then turn about the pivot.
func _pivot_at(pos: Vector3, nm: String) -> Node3D:
	var p := Node3D.new()
	p.name = nm
	p.position = pos
	_body.add_child(p)
	return p


func _attach(part: Node3D, pivot: Node3D) -> Node3D:
	part.position -= pivot.position
	part.reparent(pivot, false)
	return part


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
	_skirt = _part(_cyl(0.24, 0.46, 1.05), robe, Vector3(0, 0.53, 0))  # skirt of the robe
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
	# The staff arm: a pivot at the right shoulder. Children are placed
	# relative to it (shoulder at 0.26, 1.50, 0.0 in body space).
	_arm = Node3D.new()
	_arm.name = "Arm"
	_arm.position = Vector3(0.26, 1.50, 0.0)
	_body.add_child(_arm)
	var hold := _part(_cyl(0.07, 0.08, 0.5), robe, Vector3(0.04, -0.22, -0.12), Vector3(60, 0, -10))  # upper arm
	hold.reparent(_arm, false)
	var staff := _part(_cyl(0.025, 0.03, 2.0), wood, Vector3(0.16, -0.50, -0.30))   # staff, hand at the pivot height
	staff.reparent(_arm, false)
	var setting := _part(_cyl(0.05, 0.05, 0.08), brass, Vector3(0.16, 0.48, -0.30))
	setting.reparent(_arm, false)
	_focus_mat = Palette.glow(unit.def.accent_color, 1.2)
	var stone := PrismMesh.new()
	stone.size = Vector3(0.14, 0.24, 0.14)
	_focus = _part(stone, _focus_mat, Vector3(0.16, 0.64, -0.30))
	_focus.reparent(_arm, false)


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
	ring.position = Vector3(0, 0.03 + Palette.DECAL_LIFT, 0)
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
	for x: float in [-0.17, 0.17]:  # legs, hung from hip pivots so they stride
		var hip := _pivot_at(Vector3(x, 0.8, 0), "Hip")
		_attach(_part(_cyl(0.20, 0.24, 0.8), leather, Vector3(x, 0.4, 0)), hip)
		_legs.append(hip)
	_part(_cyl(0.34, 0.40, 0.42), team, Vector3(0, 0.95, 0))            # tabard skirt in team colour
	_part(_box(Vector3(0.78, 0.62, 0.46)), plate, Vector3(0, 1.38, 0))  # breastplate
	_part(_sphere(0.24), plate, Vector3(-0.48, 1.62, 0)).scale = Vector3(1.0, 0.7, 1.0)  # pauldrons
	_part(_sphere(0.24), plate, Vector3(0.48, 1.62, 0)).scale = Vector3(1.0, 0.7, 1.0)
	_part(_box(Vector3(0.80, 0.10, 0.48)), team, Vector3(0, 1.66, 0))   # team sash across the shoulders
	_part(_sphere(0.19), plate, Vector3(0, 1.86, 0))                    # helm
	_part(_box(Vector3(0.26, 0.05, 0.05)), Palette.mat(Color(0.08, 0.08, 0.08)), Vector3(0, 1.86, -0.18))  # visor slit
	_weapon_l = _pivot_at(Vector3(-0.48, 1.55, 0), "ShieldArm")
	_attach(_part(_box(Vector3(0.10, 1.05, 0.72)), plate, Vector3(-0.62, 1.15, -0.12)), _weapon_l)  # tower shield
	_attach(_part(_box(Vector3(0.12, 0.8, 0.10)), team, Vector3(-0.68, 1.15, -0.12)), _weapon_l)    # shield stripe
	_weapon_r = _pivot_at(Vector3(0.58, 1.0, -0.25), "MaulGrip")  # the hand on the haft
	_attach(_part(_cyl(0.035, 0.04, 1.3), wood, Vector3(0.58, 1.0, -0.25), Vector3(-15, 0, 0)), _weapon_r)  # maul haft
	_attach(_part(_box(Vector3(0.36, 0.26, 0.26)), Palette.mat(Palette.STONE_DARK), Vector3(0.58, 1.68, -0.43)), _weapon_r)  # maul head
	_focus_mat = Palette.glow(unit.def.accent_color, 1.0)
	_focus = _attach(_part(_cyl(0.11, 0.11, 0.05, 16), _focus_mat, Vector3(-0.69, 1.4, -0.12), Vector3(0, 0, 90)), _weapon_l)  # shield boss
	_attach(_part(_cyl(0.13, 0.13, 0.03, 16), brass, Vector3(-0.68, 1.4, -0.12), Vector3(0, 0, 90)), _weapon_l)
	_swing = Swing.MAUL
	_weapon_r_home = _weapon_r.position
	_team_ring(0.72)


## Ashrunner: lean, hooded, two short blades held low. Light silhouette with
## a long scarf in team colour that streams behind it.
func _build_skirmisher() -> void:
	var cloth := Palette.mat(unit.def.primary_color)
	var leather := Palette.mat(Palette.LEATHER_DARK)
	var steel := Palette.mat(Palette.IRON, 0.35, 0.8)
	var skin := Palette.mat(Color(0.70, 0.55, 0.44))
	var team := _team_mat()
	for x: float in [-0.12, 0.12]:  # legs on hip pivots
		var hip := _pivot_at(Vector3(x, 0.8, 0), "Hip")
		_attach(_part(_cyl(0.11, 0.13, 0.8), leather, Vector3(x, 0.4, 0)), hip)
		_legs.append(hip)
	_part(_cyl(0.18, 0.22, 0.6), cloth, Vector3(0, 1.1, 0.05), Vector3(15, 0, 0))     # torso, leaning in
	_part(_box(Vector3(0.40, 0.07, 0.26)), leather, Vector3(0, 0.84, 0.02))          # belt
	_part(_sphere(0.13), skin, Vector3(0, 1.5, -0.06))                                # face
	_part(_sphere(0.17), cloth, Vector3(0, 1.53, 0.0))                                # hood
	_part(_box(Vector3(0.36, 0.12, 0.30)), team, Vector3(0, 1.36, 0.04))             # scarf wrap
	_part(_box(Vector3(0.14, 0.05, 0.75)), team, Vector3(0.05, 1.32, 0.48), Vector3(-15, 0, 0))  # scarf tail
	_weapon_l = _pivot_at(Vector3(-0.30, 1.0, 0), "BladeL")
	_attach(_part(_box(Vector3(0.04, 0.03, 0.6)), steel, Vector3(-0.32, 0.95, -0.30)), _weapon_l)  # blades
	_weapon_r = _pivot_at(Vector3(0.30, 1.0, 0), "BladeR")
	_attach(_part(_box(Vector3(0.04, 0.03, 0.6)), steel, Vector3(0.32, 0.95, -0.30)), _weapon_r)
	_swing = Swing.BLADES
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


## Warden Tower: a crystal shrine. A stepped flagstone base, four corner
## posts, a masonry shaft bound with brass, and a cradle of brass prongs
## holding the team crystal, with a slow rune ring round it and team banners
## on the lane faces. Footprint 4.4 m, crystal at 7 m so it reads from down
## the lane. A faint ring on the ground shows exactly how far it shoots.
func _build_tower() -> void:
	var col := Palette.team_color(unit.team)
	var plaza := Art.stone("plaza", Color(0.92, 0.9, 0.86)).duplicate() as StandardMaterial3D
	var wall := Art.stone("wall", Color(1.02, 0.96, 0.88)).duplicate() as StandardMaterial3D
	var slate := Art.stone("slate", Color(0.8, 0.78, 0.74)).duplicate() as StandardMaterial3D
	var brass := Palette.mat(Palette.BRASS, 0.38, 0.85)
	var cloth := Palette.mat(col.darkened(0.35), 0.95)
	_part(_box(Vector3(4.4, 0.45, 4.4)), slate, Vector3(0, 0.22, 0))
	_part(_box(Vector3(3.7, 0.5, 3.7)), plaza, Vector3(0, 0.7, 0))
	_part(_box(Vector3(2.9, 0.35, 2.9)), slate, Vector3(0, 1.12, 0))
	for cx in [-1.55, 1.55]:
		for cz in [-1.55, 1.55]:
			_part(_cyl(0.2, 0.24, 1.9, 10), wall, Vector3(cx, 1.9, cz))
			_part(_cyl(0.3, 0.26, 0.14, 10), brass, Vector3(cx, 2.9, cz))
			_part(_sphere(0.13), brass, Vector3(cx, 3.05, cz))
	_part(_cyl(0.78, 1.02, 4.2, 10), wall, Vector3(0, 3.4, 0))
	for y in [1.7, 3.3, 5.35]:
		_part(_cyl(0.9 if y < 3.0 else 0.84, 0.92 if y < 3.0 else 0.86, 0.14, 12), brass, Vector3(0, y, 0))
	_part(_cyl(1.25, 0.85, 0.45, 10), slate, Vector3(0, 5.72, 0))
	for i in 4:
		var a := TAU * i / 4.0 + PI * 0.25
		var d := Vector3(cos(a), 0, sin(a))
		var prong := _part(_box(Vector3(0.1, 1.5, 0.16)), brass, d * 0.95 + Vector3(0, 6.55, 0))
		prong.rotation = Vector3(0, -a, deg_to_rad(18.0))
	# Banners on the two lane faces (the axis the tower is approached along).
	for fz in [-1.0, 1.0]:
		_part(_box(Vector3(1.2, 0.06, 0.06)), brass, Vector3(0, 5.2, fz * 0.98))
		_part(_box(Vector3(1.0, 2.3, 0.04)), cloth, Vector3(0, 4.0, fz * 0.97))
		var tail := PrismMesh.new()
		tail.size = Vector3(1.0, 0.45, 0.04)
		_part(tail, cloth, Vector3(0, 2.63, fz * 0.97), Vector3(0, 0, 180))
		_part(_cyl(0.24, 0.24, 0.02, 16), brass, Vector3(0, 4.3, fz * 1.0), Vector3(90, 0, 0))
	_focus_mat = _crystal_mat(col, 2.5)
	_focus = _part(_octahedron(0.6, 1.0, 0.9), _focus_mat, Vector3(0, 7.15, 0))
	_spin = _pivot_at(Vector3(0, 7.15, 0), "RuneRing")
	var rune := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 1.05
	t.outer_radius = 1.12
	t.rings = 48
	t.ring_segments = 6
	rune.mesh = t
	rune.material_override = Palette.glow(col, 2.2)
	rune.rotation_degrees = Vector3(14, 0, 0)
	rune.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spin.add_child(rune)
	for i in 3:
		var a := TAU * i / 3.0
		var mote := MeshInstance3D.new()
		mote.mesh = _octahedron(0.09, 0.16, 0.12)
		mote.material_override = rune.material_override
		mote.position = Vector3(cos(a) * 1.08, 0, sin(a) * 1.08)
		rune.add_child(mote)
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 2.2
	light.omni_range = 10.0
	light.position = Vector3(0, 7.0, 0)
	_body.add_child(light)
	var ring := MeshInstance3D.new()
	var rt := TorusMesh.new()
	var r := unit.def.basic_attack.range
	rt.inner_radius = r - 0.15
	rt.outer_radius = r
	rt.rings = 64
	rt.ring_segments = 4
	ring.mesh = rt
	ring.scale = Vector3(1, 0.05, 1)
	ring.position.y = 0.03 + Palette.DECAL_LIFT
	ring.material_override = Palette.ground_decal(col, 0.35)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.name = "RangeRing"
	add_child(ring)


## Oathstone: the end goal of the lane. A round dais of flagstones, a ring of
## six standing stones, and the great team crystal floating above a brass
## cradle with two rune rings.
func _build_core() -> void:
	var col := Palette.team_color(unit.team)
	var plaza := Art.stone("plaza", Color(0.92, 0.9, 0.86)).duplicate() as StandardMaterial3D
	var wall := Art.stone("wall", Color(1.0, 0.95, 0.88)).duplicate() as StandardMaterial3D
	var slate := Art.stone("slate", Color(0.8, 0.78, 0.74)).duplicate() as StandardMaterial3D
	var brass := Palette.mat(Palette.BRASS, 0.38, 0.85)
	_part(_cyl(3.1, 3.45, 0.5, 16), slate, Vector3(0, 0.25, 0))
	_part(_cyl(2.55, 2.85, 0.5, 16), plaza, Vector3(0, 0.75, 0))
	_part(_cyl(1.3, 1.5, 0.5, 12), slate, Vector3(0, 1.25, 0))
	_part(_cyl(1.0, 1.25, 0.12, 12), brass, Vector3(0, 1.56, 0))
	for i in 6:
		var a := TAU * i / 6.0 + 0.3
		var h := 2.3 + 0.35 * float(i % 2)
		var st := _part(_box(Vector3(0.55, h, 0.4)), wall, Vector3(cos(a) * 2.75, 1.0 + h * 0.5, sin(a) * 2.75))
		st.rotation = Vector3(0, -a, deg_to_rad(4.0 if i % 2 == 0 else -3.0))
		_part(_box(Vector3(0.62, 0.12, 0.47)), slate, Vector3(cos(a) * 2.75, 1.06 + h, sin(a) * 2.75)).rotation.y = -a
	_focus_mat = _crystal_mat(col, 1.8)
	_focus = _part(_octahedron(1.05, 1.9, 1.5), _focus_mat, Vector3(0, 3.6, 0))
	_spin = _pivot_at(Vector3(0, 3.6, 0), "RuneRing")
	for k in 2:
		var rune := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 1.75 + k * 0.45
		t.outer_radius = 1.83 + k * 0.45
		t.rings = 64
		t.ring_segments = 6
		rune.mesh = t
		rune.material_override = Palette.glow(col, 2.0)
		rune.rotation_degrees = Vector3(10 - 22 * k, 0, 8 * k)
		rune.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_spin.add_child(rune)
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 2.6
	light.omni_range = 12.0
	light.position = Vector3(0, 4.0, 0)
	_body.add_child(light)


## A glassy, self lit crystal: the team colour glows from inside, the faces
## stay sharp and catch the sky.
static func _crystal_mat(col: Color, energy: float) -> StandardMaterial3D:
	var m := Palette.glow(col, energy * 0.7)
	m.albedo_color = col
	m.roughness = 0.08
	m.metallic = 0.3
	m.rim_enabled = true
	m.rim = 0.6
	m.rim_tint = 0.2
	return m


## A double pyramid with flat faces: `w` half width, `up` and `down` the
## heights of the top and bottom points. Built here, faces -Z like the rest.
static func _octahedron(w: float, up: float, down: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3(0, up, 0)
	var bot := Vector3(0, -down, 0)
	var ring: Array[Vector3] = []
	for i in 6:
		var a := TAU * i / 6.0
		ring.append(Vector3(cos(a) * w, 0, sin(a) * w))
	for i in 6:
		var a := ring[i]
		var b := ring[(i + 1) % 6]
		for tri: Array in [[top, b, a], [bot, a, b]]:
			var n: Vector3 = ((tri[1] as Vector3) - tri[0]).cross((tri[2] as Vector3) - tri[0]).normalized()
			for v: Vector3 in tri:
				st.set_normal(n)
				st.add_vertex(v)
	return st.commit()


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
	for c in _body.get_children():
		if c is MeshInstance3D and c != _focus and c.name != "RangeRing":
			(c as MeshInstance3D).scale.y *= 0.5
			(c as MeshInstance3D).position.y *= 0.5
		elif c is Node3D:
			(c as Node3D).visible = false
	_focus = null


func _process(delta: float) -> void:
	_fade_hold = maxf(0.0, _fade_hold - delta)
	var want_a := 0.28 if _fade_hold > 0.0 else 1.0
	if absf(_alpha - want_a) > 0.001:
		_alpha = move_toward(_alpha, want_a, delta * 5.0)
		for m in _materials:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if _alpha < 0.999 else BaseMaterial3D.TRANSPARENCY_DISABLED
			m.albedo_color.a = _alpha
	# Hit flash: brief warm white on every part.
	_flash = maxf(0.0, _flash - delta * 6.0)
	for m in _materials:
		if m == _focus_mat:
			continue
		m.emission_enabled = _flash > 0.0
		m.emission = Color(1.0, 0.95, 0.85)
		m.emission_energy_multiplier = _flash * 0.7  # was 1.5: the body went white and lost its silhouette
	# Windup tell: the focus swells and brightens until release.
	var charge := 0.0
	if unit.cast_phase == Unit.CastPhase.WINDUP:
		var a := unit.cast_ability()
		charge = 1.0 - clampf(unit.cast_timer / maxf(a.cast_time, 0.01), 0.0, 1.0)
	if _focus:
		_focus_mat.emission_energy_multiplier = 1.2 + charge * 6.0
		_focus.scale = Vector3.ONE * (1.0 + charge * 0.9)
	if unit.def.kind != ChampionDef.Kind.STRUCTURE:
		_pose(delta, charge)
	elif _spin and _spin.visible:
		_spin.rotation.y += delta * (0.5 + charge * 3.0)


## Locomotion, cast and death poses from public unit state. Timing comes from
## the sim (cast_phase, cast_timer, velocity, alive); this only draws it.
func _pose(delta: float, charge: float) -> void:
	_anim_t += delta
	if _death_t >= 0.0:
		# Fall: tip over backwards and sink, then hide until the respawn.
		_death_t += delta
		var k := clampf(_death_t / 0.55, 0.0, 1.0)
		var e := 1.0 - (1.0 - k) * (1.0 - k)
		_body.rotation.x = e * deg_to_rad(80.0)
		_body.position.y = -e * 0.25
		if _death_t > 1.4:
			visible = false
		return
	var v := Vector3(unit.velocity.x, 0.0, unit.velocity.z)
	var top := maxf(unit.def.move_speed, 0.1)
	var speed := clampf(v.length() / top, 0.0, 1.5)
	# Movement relative to the facing: forward lean when walking forward,
	# side lean when strafing, a slight lean back when backpedalling.
	var fwd := unit.forward()
	var right := Vector3(cos(unit.aim_yaw), 0.0, -sin(unit.aim_yaw))
	var want := Vector2(v.dot(right), v.dot(fwd)) / top
	_lean = _lean.lerp(want, 1.0 - exp(-10.0 * delta))
	var prev_phase := _step_phase
	_step_phase += delta * (1.0 + speed * 9.0)
	if speed > 0.3 and unit.def.kind == ChampionDef.Kind.CHAMPION and floori(prev_phase / PI) != floori(_step_phase / PI):
		_footstep()
	var bob := sin(_step_phase) * (0.012 + speed * 0.03) if speed > 0.05 else sin(_anim_t * 2.0) * 0.012
	_body.rotation.x = -_lean.y * deg_to_rad(9.0)
	_body.rotation.z = _lean.x * deg_to_rad(7.0)
	_body.position.y = bob
	if _skirt:
		_skirt.rotation.z = sin(_step_phase) * speed * deg_to_rad(4.0)
	for i in _legs.size():
		var side := 1.0 if i == 0 else -1.0
		_legs[i].rotation.x = sin(_step_phase) * side * speed * deg_to_rad(28.0)
	if _swing == Swing.MAUL or _swing == Swing.BLADES:
		_weapon_pose(delta, charge, speed)
	if _arm:
		# Rest: staff upright, held out to the right. Windup: the arm swings
		# the staff forward and down so the stone leads toward the target.
		# Release: a short recoil back, then settle.
		_recoil = maxf(0.0, _recoil - delta * 5.0)
		var cast := charge
		if unit.cast_phase == Unit.CastPhase.RECOVERY:
			cast = 0.6
		var pitch := -cast * deg_to_rad(62.0) + _recoil * deg_to_rad(18.0)
		var yaw := -cast * deg_to_rad(20.0)
		var sway := sin(_anim_t * 1.7) * deg_to_rad(2.0) + sin(_step_phase) * speed * deg_to_rad(5.0)
		_arm.rotation.x = lerp_angle(_arm.rotation.x, pitch + sway, 1.0 - exp(-14.0 * delta))
		_arm.rotation.y = lerp_angle(_arm.rotation.y, yaw, 1.0 - exp(-14.0 * delta))
		_body.rotation.y = lerp_angle(_body.rotation.y, -cast * deg_to_rad(12.0), 1.0 - exp(-10.0 * delta))


## Melee weapon poses. Windup draws the weapon back, release swings it
## through, recovery holds the follow-through and eases home. All timing is
## the sim's cast_phase and cast_timer.
func _weapon_pose(delta: float, charge: float, speed: float) -> void:
	_recoil = maxf(0.0, _recoil - delta * 4.0)
	var follow := 0.0
	if unit.cast_phase == Unit.CastPhase.RECOVERY:
		var a := unit.cast_ability()
		follow = clampf(unit.cast_timer / maxf(a.recovery, 0.01), 0.0, 1.0) if a else 0.0
	var k := 1.0 - exp(-18.0 * delta)
	var sway := sin(_step_phase) * speed * deg_to_rad(10.0)
	if _swing == Swing.MAUL:
		# Two handed overhead: the grip rises to the shoulder and the head
		# tips back behind it, then the head comes down in front.
		var pitch := charge * deg_to_rad(110.0) - follow * deg_to_rad(85.0) + sway
		_weapon_r.rotation.x = lerp_angle(_weapon_r.rotation.x, pitch, k)
		var lift := Vector3(-0.2, 0.5, 0.15) * charge + Vector3(-0.1, -0.1, -0.2) * follow
		_weapon_r.position = _weapon_r.position.lerp(_weapon_r_home + lift, k)
		# The shield comes forward while casting (Warding Stand, Shield Slam).
		var guard := maxf(charge, follow) * deg_to_rad(-30.0) - sway * 0.5
		_weapon_l.rotation.x = lerp_angle(_weapon_l.rotation.x, guard, k)
		_body.rotation.y = lerp_angle(_body.rotation.y, (charge - follow) * deg_to_rad(14.0), 1.0 - exp(-10.0 * delta))
	else:
		# Blades: draw both back and out, then cross them in front.
		var out := charge * deg_to_rad(80.0) - follow * deg_to_rad(80.0)
		_weapon_r.rotation.y = lerp_angle(_weapon_r.rotation.y, -out, k)
		_weapon_l.rotation.y = lerp_angle(_weapon_l.rotation.y, out, k)
		var raise := charge * deg_to_rad(45.0) - sway
		_weapon_r.rotation.x = lerp_angle(_weapon_r.rotation.x, raise, k)
		_weapon_l.rotation.x = lerp_angle(_weapon_l.rotation.x, charge * deg_to_rad(45.0) + sway, k)


## Footsteps: four short original taps (tools/mksounds.py), one per half
## stride, quiet and local so a fight is never drowned by walking.
const STEPS := [
	preload("res://assets/sounds/step_0.wav"), preload("res://assets/sounds/step_1.wav"),
	preload("res://assets/sounds/step_2.wav"), preload("res://assets/sounds/step_3.wav"),
]
var _step_player: AudioStreamPlayer3D
var _step_i := 0
func _footstep() -> void:
	if _step_player == null:
		_step_player = AudioStreamPlayer3D.new()
		_step_player.max_distance = 18.0
		_step_player.unit_size = 3.0
		_step_player.volume_db = -10.0
		add_child(_step_player)
	_step_i = (_step_i + 1 + (randi() % 3)) % STEPS.size()
	_step_player.stream = STEPS[_step_i]
	_step_player.pitch_scale = randf_range(0.9, 1.1)
	_step_player.play()
