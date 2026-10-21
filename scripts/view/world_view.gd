class_name WorldView
extends Node3D
## Visuals for projectiles, ground areas, windup telegraphs and impacts.
## Listens to the authority's signals; owns no gameplay state.

var authority: CombatAuthority
## The unit the local player controls; decides ally/enemy colouring.
var viewer: Unit

var _projectiles := {}  # SimProjectile -> Node3D
var _areas := {}        # SimArea -> Node3D
var _tells := {}        # Unit -> Node3D
var _effects: Array[Dictionary] = []
var _preview: Node3D


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func setup(a: CombatAuthority, local_unit: Unit) -> void:
	authority = a
	viewer = local_unit
	a.projectile_spawned.connect(_on_projectile_spawned)
	a.projectile_ended.connect(_on_projectile_ended)
	a.area_spawned.connect(_on_area_spawned)
	a.area_detonated.connect(_on_area_detonated)
	a.unit_damaged.connect(_on_unit_damaged)
	a.melee_swung.connect(_on_melee_swung)
	a.unit_removed.connect(func(u: Unit) -> void:
		var t: Node3D = _tells.get(u)
		if t:
			t.queue_free()
		_tells.erase(u)
		var m: Node3D = _stun_marks.get(u)
		if m:
			m.queue_free()
		_stun_marks.erase(u))


func _team_color(u: Unit) -> Color:
	if viewer and u.team == viewer.team:
		return Palette.ALLY
	return Palette.ENEMY


func _disc(radius: float, m: Material, h := 0.02) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = h
	c.radial_segments = 40
	mi.mesh = c
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _ring(radius: float, width: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = radius - width
	t.outer_radius = radius
	t.rings = 48
	t.ring_segments = 4
	mi.mesh = t
	mi.scale = Vector3(1, 0.05, 1)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _on_projectile_spawned(p: CombatAuthority.SimProjectile) -> void:
	var n := Node3D.new()
	var col := p.source.def.accent_color
	var core := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = maxf(p.ability.projectile_radius * 0.7, 0.12)
	s.height = s.radius * 2.0
	core.mesh = s
	core.material_override = Palette.glow(col, 4.0)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(core)
	var trail := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = s.radius * 0.7
	c.bottom_radius = 0.0
	c.height = 1.2
	trail.mesh = c
	trail.rotation_degrees = Vector3(-90, 0, 0)
	trail.position = Vector3(0, 0, 0.6)
	var tm := Palette.glow(col, 2.0)
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.albedo_color = Color(col, 0.5)
	trail.material_override = tm
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(trail)
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 1.5
	light.omni_range = 3.0
	n.add_child(light)
	add_child(n)
	n.global_position = p.position
	n.look_at(p.position + p.direction, Vector3.UP)
	_projectiles[p] = n


func _on_projectile_ended(p: CombatAuthority.SimProjectile, at: Vector3) -> void:
	var n: Node3D = _projectiles.get(p)
	if n:
		n.queue_free()
		_projectiles.erase(p)
	_spawn_burst(at, p.source.def.accent_color, 0.6, 0.18)


func _on_area_spawned(ar: CombatAuthority.SimArea) -> void:
	if ar.ability.delivery == AbilityDef.Delivery.WARD:
		_spawn_ward(ar)
		return
	var n := Node3D.new()
	var col := _team_color(ar.source)
	var r := ar.ability.area_radius
	# Harmful circle: a thick edge plus a thin inner ring (two rings read as
	# danger even in greyscale); a ward is a single ring under a dome.
	var edge := _ring(r, 0.14, Palette.ground_decal(col, 0.95))
	var inner := _ring(r * 0.78, 0.05, Palette.ground_decal(col, 0.8))
	var base := _disc(r, Palette.ground_decal(col, 0.10))
	var fill := _disc(r, Palette.ground_decal(col, 0.30), 0.03)
	fill.name = "Fill"
	n.add_child(base)
	n.add_child(fill)
	n.add_child(edge)
	n.add_child(inner)
	add_child(n)
	n.global_position = ar.center + Vector3(0, 0.03, 0)
	fill.scale = Vector3(0.01, 1, 0.01)
	_areas[ar] = n


## A ward: a solid ring and a faint dome in the caster's team colour, with an
## inner disc that shrinks as its time runs out.
func _spawn_ward(ar: CombatAuthority.SimArea) -> void:
	var n := Node3D.new()
	var col := _team_color(ar.source)
	var r := ar.ability.area_radius
	n.add_child(_ring(r, 0.16, Palette.ground_decal(col, 0.95)))
	var fill := _disc(r, Palette.ground_decal(col, 0.18), 0.03)
	fill.name = "Fill"
	n.add_child(fill)
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.is_hemisphere = true
	dome.mesh = sm
	var dm := Palette.ground_decal(col, 0.10)
	dome.material_override = dm
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dome.scale = Vector3(1, 0.45, 1)
	n.add_child(dome)
	add_child(n)
	n.global_position = ar.center + Vector3(0, 0.03, 0)
	_areas[ar] = n


func _on_area_detonated(ar: CombatAuthority.SimArea) -> void:
	var n: Node3D = _areas.get(ar)
	if n:
		n.queue_free()
		_areas.erase(ar)
	if ar.ability.delivery == AbilityDef.Delivery.WARD:
		return
	_spawn_burst(ar.center + Vector3(0, 0.3, 0), ar.source.def.accent_color, ar.ability.area_radius, 0.3)


func _on_unit_damaged(target: Unit, _amount: float, source: Unit) -> void:
	# Impact mark: small, warm, short. Bigger for hits the viewer deals or
	# takes; a faint one for everyone else, so fights read without going white.
	var mine := viewer != null and (target == viewer or source == viewer)
	_spawn_burst(target.global_position + Vector3(0, target.def.height * 0.6, 0), Color(1, 0.9, 0.7), 0.3 if mine else 0.18, 0.1)


func _spawn_burst(at: Vector3, col: Color, size: float, life: float) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	mi.mesh = s
	var m := Palette.glow(col, 3.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at
	mi.scale = Vector3.ONE * 0.1
	_effects.append({"node": mi, "mat": m, "t": 0.0, "life": life, "size": size * 2.0})


func _process(delta: float) -> void:
	if authority == null:
		return
	var frac := Engine.get_physics_interpolation_fraction()
	var dt := 1.0 / Engine.physics_ticks_per_second
	for p: CombatAuthority.SimProjectile in _projectiles:
		var n: Node3D = _projectiles[p]
		n.global_position = p.position + p.direction * p.ability.projectile_speed * dt * frac
	for ar: CombatAuthority.SimArea in _areas:
		var fill: Node3D = _areas[ar].get_node("Fill")
		var k := 1.0 - clampf(ar.timer / maxf(ar.ability.area_delay, 0.01), 0.0, 1.0)
		if ar.ability.delivery == AbilityDef.Delivery.WARD:
			k = clampf(ar.timer / maxf(ar.ability.ward_duration, 0.01), 0.0, 1.0)  # time left
		fill.scale = Vector3(maxf(k, 0.01), 1, maxf(k, 0.01))
	_update_tells()
	_update_stun_marks()
	_update_preview()
	for e in _effects:
		e.t += delta
		var k: float = e.t / e.life
		var mi: MeshInstance3D = e.node
		if e.size > 0.0:
			mi.scale = Vector3.ONE * lerpf(0.1, e.size, minf(k, 1.0))
		(e.mat as StandardMaterial3D).albedo_color.a = (1.0 - k) * (0.7 if e.size < 0.0 else 1.0)
		if k >= 1.0:
			mi.queue_free()
	_effects = _effects.filter(func(e: Dictionary) -> bool: return e.t < e.life)


## Local player's ground-target preview while Q is held: exactly where the
## glyph will land (already clamped to range), before committing.
func _update_preview() -> void:
	var hc := viewer.controller as HumanController if viewer and is_instance_valid(viewer) else null
	var active := hc != null and hc.preview_slot > 0 and viewer.alive \
			and viewer.get_slot(hc.preview_slot) and viewer.get_slot(hc.preview_slot).delivery == AbilityDef.Delivery.GROUND_AREA
	if not active:
		if _preview:
			_preview.visible = false
		return
	var a := viewer.get_slot(hc.preview_slot)
	if _preview == null:
		_preview = Node3D.new()
		var ready_col := Color(0.95, 0.95, 0.9)
		_preview.add_child(_ring(a.area_radius, 0.08, Palette.ground_decal(ready_col, 0.9)))
		_preview.add_child(_disc(a.area_radius, Palette.ground_decal(ready_col, 0.08)))
		add_child(_preview)
	_preview.visible = true
	var p := viewer.clamp_target(a, hc.rig.get_aim_point(viewer))
	_preview.global_position = Vector3(p.x, 0.05, p.z)


## Windup telegraphs: a lane on the ground for projectiles, a circle for
## ground targets. Shown for every unit, so enemy attacks are readable.
func _update_tells() -> void:
	for u in authority.units:
		var tell: Node3D = _tells.get(u)
		var active := u.alive and u.cast_phase == Unit.CastPhase.WINDUP
		if not active:
			if tell:
				tell.visible = false
			continue
		var a := u.cast_ability()
		if tell == null or tell.get_meta("ability") != a:
			if tell:
				tell.queue_free()
			tell = _make_tell(u, a)
			_tells[u] = tell
		tell.visible = true
		if a.delivery == AbilityDef.Delivery.MELEE_ARC:
			tell.global_position = u.get_global_transform_interpolated().origin + Vector3(0, 0.04, 0)
			tell.rotation.y = u.aim_yaw
		elif a.delivery == AbilityDef.Delivery.PROJECTILE or a.delivery == AbilityDef.Delivery.DASH:
			var from := u.get_global_transform_interpolated().origin
			var flat := Vector3(u.cast_target.x - from.x, 0, u.cast_target.z - from.z)
			if flat.length() > 0.01:
				tell.global_position = from + Vector3(0, 0.04, 0)
				tell.look_at(tell.global_position + flat, Vector3.UP)
		else:
			tell.global_position = Vector3(u.cast_target.x, 0.04, u.cast_target.z)


## Stun marker: a slow ring of small lights over a stunned unit's head.
var _stun_marks := {}  # Unit -> Node3D


func _update_stun_marks() -> void:
	for u in authority.units:
		var m: Node3D = _stun_marks.get(u)
		if u.alive and u.is_stunned():
			if m == null:
				m = Node3D.new()
				for i in 3:
					var mi := MeshInstance3D.new()
					var sm := SphereMesh.new()
					sm.radius = 0.08
					sm.height = 0.16
					mi.mesh = sm
					mi.material_override = Palette.glow(Color(1.0, 0.75, 0.4), 2.0)
					mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					mi.position = Vector3(0.35, 0, 0).rotated(Vector3.UP, TAU * i / 3.0)
					m.add_child(mi)
				add_child(m)
				_stun_marks[u] = m
			m.global_position = u.get_global_transform_interpolated().origin + Vector3(0, u.def.height + 0.15, 0)
			m.rotation.y += 0.08
		elif m:
			m.queue_free()
			_stun_marks.erase(u)


## Flat circle sector on the ground, pointing along -Z.
func _sector(radius: float, degrees: float, m: Material) -> MeshInstance3D:
	var verts := PackedVector3Array()
	var steps := 16
	var half := deg_to_rad(degrees * 0.5)
	for i in steps:
		var a0 := -half + (2.0 * half) * i / steps
		var a1 := -half + (2.0 * half) * (i + 1) / steps
		verts.append(Vector3.ZERO)
		verts.append(Vector3(-sin(a0), 0, -cos(a0)) * radius)
		verts.append(Vector3(-sin(a1), 0, -cos(a1)) * radius)
	var am := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## The swing itself: a bright sector that fades in a fifth of a second.
func _on_melee_swung(caster: Unit, a: AbilityDef) -> void:
	var m := Palette.ground_decal(caster.def.accent_color, 0.7)
	var mi := _sector(a.range, a.arc_degrees, m)
	add_child(mi)
	mi.global_position = caster.global_position + Vector3(0, 0.06, 0)
	mi.rotation.y = caster.aim_yaw
	_effects.append({"node": mi, "mat": m, "t": 0.0, "life": 0.2, "size": -1.0})


func _make_tell(u: Unit, a: AbilityDef) -> Node3D:
	var n := Node3D.new()
	n.set_meta("ability", a)
	var col := _team_color(u)
	if a.delivery == AbilityDef.Delivery.MELEE_ARC:
		n.add_child(_sector(a.range, a.arc_degrees, Palette.ground_decal(col, 0.30)))
		add_child(n)
		return n
	if a.delivery == AbilityDef.Delivery.DASH:
		var lane := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(u.def.radius * 2.0, 0.02, a.dash_distance)
		lane.mesh = b
		lane.position = Vector3(0, 0, -a.dash_distance * 0.5)
		lane.material_override = Palette.ground_decal(col, 0.4)
		lane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(lane)
		add_child(n)
		return n
	if a.delivery == AbilityDef.Delivery.PROJECTILE:
		var lane := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(maxf(a.projectile_radius * 2.0, 0.3), 0.02, a.range)
		lane.mesh = b
		lane.position = Vector3(0, 0, -a.range * 0.5)
		lane.material_override = Palette.ground_decal(col, 0.28)
		lane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(lane)
	else:
		n.add_child(_ring(a.area_radius, 0.1, Palette.ground_decal(col, 0.8)))
		n.add_child(_disc(a.area_radius, Palette.ground_decal(col, 0.1)))
	add_child(n)
	return n
