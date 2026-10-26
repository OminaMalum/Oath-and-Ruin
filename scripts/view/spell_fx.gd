class_name SpellFx
extends Node3D
## Spell effects layered over WorldView's projectiles and telegraphs: trails
## and spinning glyphs on bolts, a streaming lance, spell circles that draw
## themselves in under ground spells, a descending sigil for an ultimate,
## and impacts with a shockwave, a column of light and sparks. View only:
## it listens to the same authority signals and changes nothing in the sim.
## Colours are the caster's accent; the ally/enemy telegraph stays on top
## as the thing to read. Kits with their own look (arrows, lightning, chains
## and the rest) are built by KitLooks.

const CIRCLE := preload("res://scripts/view/shaders/spell_circle.gdshader")
const PILLAR := preload("res://scripts/view/shaders/spell_pillar.gdshader")

var _wv: WorldView
var _bolts := {}     # SimProjectile -> {trail, glyph, big}
var _circles := {}   # SimArea -> {node, mat, sigil, sigil_mat, motes}
var _fading: Array[Dictionary] = []  # {node, mat, t, life, kind, grow}
var _grapples := {}  # Unit -> chain links held while it grapples
static var _streaks: NoiseTexture2D
static var _dot_mats := {}
## Glow budget for busy fights: 1 with a few effects alive, down to 0.5 as
## they pile up, so a crowded teamfight stays readable instead of turning
## into one white bloom. New additive materials and flash lights scale by it.
static var crowd := 1.0
## No single additive effect brighter than this (times its colour).
const ENERGY_CAP := 2.6
## At most this many flash lights alive at once; extra flashes skip the light.
const MAX_FLASH_LIGHTS := 6


func setup(a: CombatAuthority, wv: WorldView) -> void:
	_wv = wv
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Connected after WorldView, so its projectile node already exists.
	a.projectile_spawned.connect(_on_projectile_spawned)
	a.projectile_ended.connect(_on_projectile_ended)
	a.area_spawned.connect(_on_area_spawned)
	a.area_detonated.connect(_on_area_detonated)
	a.melee_swung.connect(_on_melee_swung)
	a.dash_started.connect(_on_dash_started)
	a.grapple_started.connect(_on_grapple_started)


static func _is_champion(u: Unit) -> bool:
	return u != null and is_instance_valid(u) and u.def.kind == ChampionDef.Kind.CHAMPION


# ------------------------------------------------------------------ bolts

func _on_projectile_spawned(p: CombatAuthority.SimProjectile) -> void:
	if not _is_champion(p.source):
		return
	var host: Node3D = _wv._projectiles.get(p)
	if host == null:
		return
	var col := p.source.def.accent_color
	var big := p.ability.pierce or p.ability.projectile_radius >= 0.2
	var look := KitLooks.bolt_look(p.ability)
	if look != "":
		var d := KitLooks.build_bolt(look, host, col, p.ability, self)
		d.host = host
		d.big = big
		d.look = look
		_bolts[p] = d
		return
	var trail := _trail(col, big)
	add_child(trail)
	var glyph := Node3D.new()
	host.add_child(glyph)
	for i in (3 if big else 2):
		var ring := MeshInstance3D.new()
		var t := TorusMesh.new()
		var r := (0.42 if big else 0.26) - i * 0.07
		t.inner_radius = r * 0.86
		t.outer_radius = r
		t.rings = 24
		t.ring_segments = 4
		ring.mesh = t
		ring.material_override = _add_mat(col, 2.4 - i * 0.5)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.rotation_degrees = Vector3(90, 0, 0)  # faces along the flight
		glyph.add_child(ring)
	if big:
		# The lance: a long bright core streaming behind the head.
		var core := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.0
		c.bottom_radius = 0.16
		c.height = 2.6
		c.radial_segments = 10
		core.mesh = c
		core.material_override = _add_mat(col.lightened(0.3), 2.6)
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		core.rotation_degrees = Vector3(-90, 0, 0)
		core.position = Vector3(0, 0, 1.3)
		host.add_child(core)
	_bolts[p] = {"trail": trail, "glyph": glyph, "big": big, "host": host}


func _on_projectile_ended(p: CombatAuthority.SimProjectile, at: Vector3) -> void:
	var b: Dictionary = _bolts.get(p, {})
	_bolts.erase(p)
	if b.is_empty():
		return
	for key in ["trail", "extra_trail"]:
		var trail: CPUParticles3D = b.get(key)
		if trail and is_instance_valid(trail):
			trail.emitting = false
			get_tree().create_timer(trail.lifetime + 0.1).timeout.connect(trail.queue_free)
	if b.has("links"):
		(b.links as Node3D).queue_free()
	var col := p.source.def.accent_color if is_instance_valid(p.source) else Color(0.6, 0.8, 0.8)
	var big: bool = b.big
	_shockwave(at, col, 1.4 if big else 0.8, 0.28, p.direction)
	_flash(at, col, 3.0 if big else 1.8, 0.2)
	_sparks(at, col, 16 if big else 9, 0.45, 5.0 if big else 3.5)


func _trail(col: Color, big: bool) -> CPUParticles3D:
	var t := CPUParticles3D.new()
	t.local_coords = false
	t.amount = 70 if big else 36
	t.lifetime = 0.45 if big else 0.32
	t.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	t.emission_sphere_radius = 0.12 if big else 0.06
	t.direction = Vector3.UP
	t.spread = 180.0
	t.initial_velocity_min = 0.2
	t.initial_velocity_max = 0.9
	t.gravity = Vector3(0, 0.6, 0)
	t.damping_min = 1.0
	t.damping_max = 2.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	t.scale_amount_curve = curve
	var g := Gradient.new()
	g.set_color(0, Color(col.lightened(0.2), 0.75))
	g.set_color(1, Color(col, 0.0))
	t.color_ramp = g
	var q := QuadMesh.new()
	var sz := 0.3 if big else 0.17
	q.size = Vector2(sz, sz)
	q.material = _dot_mat()
	t.mesh = q
	t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return t


# ------------------------------------------------------------------ circles

func _on_area_spawned(ar: CombatAuthority.SimArea) -> void:
	if not _is_champion(ar.source) or ar.ability.delivery == AbilityDef.Delivery.WARD:
		return
	var col := ar.source.def.accent_color
	var r := ar.ability.area_radius
	if KitLooks.area_look(ar.ability) == "severed":
		var ends := _line_ends(ar, 0.14)
		var lay := KitLooks.chain_links(self, col, 140, 1.15)
		KitLooks.lay_chain(lay, ends[0], ends[1], 0.0)
		_circles[ar] = {"lay": lay, "n": lay.multimesh.visible_instance_count}
		lay.multimesh.visible_instance_count = 0
		return
	var n := Node3D.new()
	add_child(n)
	n.global_position = ar.center + Vector3(0, Palette.DECAL_LIFT + 0.07, 0)
	var circle := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(r * 2.0, r * 2.0)
	circle.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = CIRCLE
	m.set_shader_parameter("col", col)
	m.set_shader_parameter("runes", Runes.strip())
	m.set_shader_parameter("progress", 0.0)
	m.set_shader_parameter("energy", 1.3)
	circle.material_override = m
	circle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(circle)
	var motes := CPUParticles3D.new()
	motes.amount = int(18 + r * 8)
	motes.lifetime = 0.9
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	motes.emission_ring_axis = Vector3.UP
	motes.emission_ring_radius = r * 0.9
	motes.emission_ring_inner_radius = r * 0.2
	motes.emission_ring_height = 0.05
	motes.direction = Vector3.UP
	motes.spread = 10.0
	motes.initial_velocity_min = 0.6
	motes.initial_velocity_max = 1.6
	motes.gravity = Vector3.ZERO
	var g := Gradient.new()
	g.set_color(0, Color(col.lightened(0.4), 0.9))
	g.set_color(1, Color(col, 0.0))
	motes.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(0.14, 0.14)
	q.material = _dot_mat()
	motes.mesh = q
	motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(motes)
	var entry := {"node": n, "mat": m, "spin": 0.0, "motes": motes}
	if ar.ability.is_ultimate:
		# The Word: a great sigil comes down out of the sky onto the circle.
		var sigil := MeshInstance3D.new()
		var sp := PlaneMesh.new()
		sp.size = Vector2(r * 1.6, r * 1.6)
		sigil.mesh = sp
		var sm := ShaderMaterial.new()
		sm.shader = CIRCLE
		sm.set_shader_parameter("col", col.lightened(0.2))
		sm.set_shader_parameter("runes", Runes.strip())
		sm.set_shader_parameter("energy", 2.0)
		sigil.material_override = sm
		sigil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(sigil)
		var light := OmniLight3D.new()
		light.light_color = col
		light.omni_range = r * 2.0
		light.light_energy = 0.0
		n.add_child(light)
		entry.sigil = sigil
		entry.sigil_mat = sm
		entry.light = light
	_circles[ar] = entry


func _on_area_detonated(ar: CombatAuthority.SimArea) -> void:
	var e: Dictionary = _circles.get(ar, {})
	_circles.erase(ar)
	if e.is_empty():
		return
	if e.has("lay"):
		_severed(ar, e)
		return
	var n: Node3D = e.node
	(e.motes as CPUParticles3D).emitting = false
	_fading.append({"node": n, "mat": e.mat, "t": 0.0, "life": 0.5, "kind": "circle", "grow": 0.15})
	var col := ar.source.def.accent_color if is_instance_valid(ar.source) else Color(0.6, 0.8, 0.8)
	var r := ar.ability.area_radius
	var big := ar.ability.is_ultimate
	match KitLooks.area_look(ar.ability):
		"lightning":
			var l := KitLooks.lightning(self, ar.center, col, big)
			_fading.append({"node": l.node, "mat": null, "t": 0.0, "life": 0.55 if big else 0.4, "kind": "tick", "tick": l.tick, "grow": 0.0})
		"thorns", "rocks":
			var h := KitLooks.spikes(self, ar.center, r, col, KitLooks.area_look(ar.ability) == "rocks")
			_fading.append({"node": h, "mat": null, "t": 0.0, "life": 1.1 if big else 0.9, "kind": "spikes", "grow": 0.0})
		"smoke":
			KitLooks.grave_smoke(self, ar.center, r, col)
			_pillar(ar.center, col.darkened(0.3), r * 0.35, 3.0, 0.35)
		_:
			_pillar(ar.center, col, r * (0.55 if big else 0.45), 7.0 if big else 4.0, 0.6 if big else 0.4)
	_shockwave(ar.center + Vector3(0, Palette.DECAL_LIFT + 0.1, 0), col, r * 1.35, 0.4 if big else 0.3, Vector3.UP)
	_flash(ar.center + Vector3(0, 1.0, 0), col, 6.0 if big else 3.5, 0.35)
	_sparks(ar.center + Vector3(0, 0.3, 0), col, 40 if big else 22, 0.8, 7.0 if big else 5.0, 35.0)


func _process(delta: float) -> void:
	crowd = clampf(sqrt(10.0 / maxf(10.0, float(_bolts.size() + _circles.size() + _fading.size()))), 0.5, 1.0)
	for p: CombatAuthority.SimProjectile in _bolts:
		var b: Dictionary = _bolts[p]
		var host: Node3D = b.host
		if not is_instance_valid(host):
			continue
		for key in ["trail", "extra_trail"]:
			var t: Node3D = b.get(key)
			if t:
				t.global_position = host.global_position
		if b.has("glyph"):
			(b.glyph as Node3D).rotate_object_local(Vector3.FORWARD, delta * 9.0)
		if b.get("spin"):
			(b.spin as Node3D).rotate_object_local(b.get("spin_axis", Vector3.FORWARD), delta * float(b.get("spin_rate", 9.0)))
		if b.get("tick"):
			(b.tick as Callable).call(delta)
		if b.has("links") and is_instance_valid(p.source):
			KitLooks.lay_chain(b.links, _hand(p.source), host.global_position)
	_update_grapples()
	for ar: CombatAuthority.SimArea in _circles:
		var e: Dictionary = _circles[ar]
		var k := 1.0 - clampf(ar.timer / maxf(ar.ability.area_delay, 0.01), 0.0, 1.0)
		if e.has("lay"):
			# The contract chain snakes out along the line before it bursts.
			var mm := (e.lay as MultiMeshInstance3D).multimesh
			mm.visible_instance_count = int(float(e.n) * minf(k * 2.5, 1.0))
			continue
		e.spin += delta * (0.6 + k * 2.0)
		var m: ShaderMaterial = e.mat
		m.set_shader_parameter("progress", clampf(k * 1.6, 0.0, 1.0))
		m.set_shader_parameter("spin", e.spin)
		m.set_shader_parameter("energy", 1.1 + k * 1.4)
		if e.has("sigil"):
			var s: MeshInstance3D = e.sigil
			s.position.y = lerpf(9.0, 0.25, k * k)
			s.rotation.y = -e.spin * 1.5
			(e.sigil_mat as ShaderMaterial).set_shader_parameter("spin", -e.spin)
			(e.light as OmniLight3D).light_energy = k * 3.0
			(e.light as OmniLight3D).position.y = s.position.y
	for f in _fading:
		f.t += delta
		var k: float = clampf(f.t / f.life, 0.0, 1.0)
		var n: Node3D = f.node
		if not is_instance_valid(n):
			continue
		match f.kind:
			"circle":
				(f.mat as ShaderMaterial).set_shader_parameter("alpha", 1.0 - k)
				n.scale = Vector3.ONE * (1.0 + k * f.grow)
			"pillar":
				(f.mat as ShaderMaterial).set_shader_parameter("alpha", (1.0 - k) * (1.0 - k))
				n.scale = Vector3(1.0 + k * 0.6, 0.6 + minf(k * 4.0, 1.0) * 0.4, 1.0 + k * 0.6)
			"wave":
				n.scale = Vector3.ONE * lerpf(0.15, f.grow, 1.0 - (1.0 - k) * (1.0 - k))
				(f.mat as StandardMaterial3D).albedo_color.a = 1.0 - k
			"light":
				(n as OmniLight3D).light_energy = f.grow * (1.0 - k) * (1.0 - k)
			"tick":
				(f.tick as Callable).call(k, delta)
			"spikes":
				# Burst up fast, hold, then sink back into the floor.
				var up := minf(k / 0.12, 1.0)
				var down := clampf((k - 0.65) / 0.35, 0.0, 1.0)
				n.scale = Vector3(1.0, maxf(0.01, (1.0 - (1.0 - up) * (1.0 - up)) * (1.0 - down)), 1.0)
			"swoosh":
				var a := (1.0 - k) * (1.0 - k)
				(f.mat as StandardMaterial3D).albedo_color = Color(2.2 * a, 2.2 * a, 2.2 * a, 1.0)
				n.rotation.y = f.grow + k * 0.35
			"follow":
				var u: Unit = f.unit
				if is_instance_valid(u):
					n.global_position = u.global_position + Vector3(0, u.def.height * 0.5, 0)
				if k > 0.6:
					(n as CPUParticles3D).emitting = false
		if k >= 1.0:
			n.queue_free()
	_fading = _fading.filter(func(f: Dictionary) -> bool: return f.t < f.life)


# ------------------------------------------------------------------ melee and dashes

func _on_melee_swung(caster: Unit, a: AbilityDef) -> void:
	if not _is_champion(caster):
		return
	var col := caster.def.accent_color.lightened(0.35)
	var mi := KitLooks.swoosh(a.range, a.arc_degrees, col, caster.def.height * 0.55)
	add_child(mi)
	mi.global_position = caster.global_position
	mi.rotation.y = caster.aim_yaw
	var life := 0.32 if a.is_ultimate else 0.22
	_fading.append({"node": mi, "mat": mi.material_override, "t": 0.0, "life": life, "kind": "swoosh", "grow": caster.aim_yaw})
	_sparks(caster.global_position + Vector3(0, caster.def.height * 0.5, 0) + Vector3(-sin(caster.aim_yaw), 0, -cos(caster.aim_yaw)) * a.range * 0.7,
			col, 8 if a.is_ultimate else 5, 0.35, 3.0)
	var base := caster.def.accent_color
	match KitLooks.melee_look(a):
		"lash":
			var d := KitLooks.lash(self, caster.global_position, caster.aim_yaw, a.range, a.arc_degrees, caster.def.height * 0.55, base)
			_fading.append({"node": d.node, "mat": null, "t": 0.0, "life": 0.32, "kind": "tick", "tick": d.tick, "grow": 0.0,
					"at": caster.global_position + Vector3(0, 1.0, 0)})
		"seal":
			var fwd := Vector3(-sin(caster.aim_yaw), 0, -cos(caster.aim_yaw))
			var at := caster.global_position + fwd * 1.1 + Vector3(0, caster.def.height * 0.55, 0)
			var d := KitLooks.seal(self, at, caster.aim_yaw, base)
			_fading.append({"node": d.node, "mat": null, "t": 0.0, "life": 0.6, "kind": "tick", "tick": d.tick, "grow": 0.0, "at": at})
			_flash(at, base, 2.4, 0.25)
			_sparks(at, base.lightened(0.3), 14, 0.5, 4.0)


func _on_dash_started(caster: Unit, a: AbilityDef) -> void:
	if not _is_champion(caster):
		return
	var t := KitLooks._particles(self, caster.def.accent_color, 60, 0.45, 0.12, 0.3, Vector3(0, 0.4, 0), 0.4)
	t.emission_sphere_radius = caster.def.radius * 0.8
	t.global_position = caster.global_position + Vector3(0, caster.def.height * 0.5, 0)
	var life := a.dash_duration + 0.5
	_fading.append({"node": t, "mat": null, "t": 0.0, "life": life, "kind": "follow", "unit": caster, "grow": 0.0})


## The point a champion's chains and bolts leave from.
func _hand(u: Unit) -> Vector3:
	for child in u.get_children():
		if child is UnitView:
			return (child as UnitView).launch_point()
	return u.global_position + Vector3(0, u.def.height * 0.6, 0)


## Both ends of a line area (from the caster's side), lifted by y.
static func _line_ends(ar: CombatAuthority.SimArea, y: float) -> Array[Vector3]:
	var half := ar.dir * (ar.ability.range * 0.5)
	return [ar.center - half + Vector3(0, y, 0), ar.center + half + Vector3(0, y, 0)]


## Chain Traverse: an iron chain from her to the wall it hooked, held while
## the pull lasts. WorldView draws the thin glow line it wraps.
func _on_grapple_started(caster: Unit, _a: AbilityDef) -> void:
	if not _is_champion(caster):
		return
	if _grapples.has(caster):
		(_grapples[caster] as Node).queue_free()
	_grapples[caster] = KitLooks.chain_links(self, caster.def.accent_color, 110)
	_sparks(caster.grapple_anchor, caster.def.accent_color.lightened(0.3), 10, 0.4, 3.5)
	_flash(caster.grapple_anchor, caster.def.accent_color, 1.6, 0.2)


func _update_grapples() -> void:
	for u in _grapples.keys():
		var links: MultiMeshInstance3D = _grapples[u]
		if is_instance_valid(u) and (u as Unit).alive and (u as Unit).is_grappling():
			var unit: Unit = u
			var from := unit.get_global_transform_interpolated().origin + Vector3(0, unit.def.height * 0.6, 0)
			KitLooks.lay_chain(links, from, unit.grapple_anchor, 0.04)
		else:
			links.queue_free()
			_grapples.erase(u)


func _severed(ar: CombatAuthority.SimArea, e: Dictionary) -> void:
	(e.lay as Node).queue_free()
	var col := ar.source.def.accent_color if is_instance_valid(ar.source) else Color(0.78, 0.68, 0.95)
	var ends := _line_ends(ar, 0.0)
	var h := KitLooks.chain_stalks(self, ends[0], ends[1], ar.ability.line_width, col)
	_fading.append({"node": h, "mat": null, "t": 0.0, "life": 1.2, "kind": "spikes", "grow": 0.0, "at": ar.center})
	_flash(ar.center + Vector3(0, 1.0, 0), col, 5.0, 0.35)
	for i in 3:
		_sparks(ends[0].lerp(ends[1], (float(i) + 0.5) / 3.0) + Vector3(0, 0.4, 0), col, 16, 0.7, 5.5, 35.0)
	_shockwave(ar.center + Vector3(0, Palette.DECAL_LIFT + 0.1, 0), col.darkened(0.2), ar.ability.line_width, 0.35, Vector3.UP)


# ------------------------------------------------------------------ pieces

func _shockwave(at: Vector3, col: Color, radius: float, life: float, facing: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.88
	t.outer_radius = 1.0
	t.rings = 40
	t.ring_segments = 4
	mi.mesh = t
	var m := _add_mat(col.lightened(0.3), 2.2).duplicate() as StandardMaterial3D
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at
	if absf(facing.normalized().dot(Vector3.UP)) < 0.9:
		mi.look_at(at + facing, Vector3.UP)
		mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	_fading.append({"node": mi, "mat": m, "t": 0.0, "life": life, "kind": "wave", "grow": radius})


func _pillar(at: Vector3, col: Color, radius: float, height: float, life: float) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius * 0.7
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = 24
	c.cap_top = false
	c.cap_bottom = false
	mi.mesh = c
	var m := ShaderMaterial.new()
	m.shader = PILLAR
	m.set_shader_parameter("col", col)
	m.set_shader_parameter("streaks", _streak_tex())
	m.set_shader_parameter("energy", 3.2)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var holder := Node3D.new()
	add_child(holder)
	holder.global_position = at
	holder.add_child(mi)
	mi.position.y = height * 0.5
	_fading.append({"node": holder, "mat": m, "t": 0.0, "life": life, "kind": "pillar", "grow": 0.0})


func _flash(at: Vector3, col: Color, energy: float, life: float) -> void:
	var lights := 0
	for f in _fading:
		if f.kind == "light":
			lights += 1
	if lights >= MAX_FLASH_LIGHTS:
		return
	energy *= crowd
	var l := OmniLight3D.new()
	l.light_color = col.lightened(0.2)
	l.omni_range = 5.0
	l.light_energy = energy
	add_child(l)
	l.global_position = at
	_fading.append({"node": l, "mat": null, "t": 0.0, "life": life, "kind": "light", "grow": energy})


func _sparks(at: Vector3, col: Color, amount: int, life: float, speed: float, spread := 180.0) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = life
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -7.0, 0)
	p.damping_min = 1.0
	p.damping_max = 2.5
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	var g := Gradient.new()
	g.set_color(0, Color(col.lightened(0.6), 1.0))
	g.set_color(1, Color(col, 0.0))
	p.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(0.1, 0.1)
	q.material = _dot_mat()
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)


static func _add_mat(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	energy = minf(energy, ENERGY_CAP) * crowd
	m.albedo_color = Color(col.r * energy, col.g * energy, col.b * energy, 1.0)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	return m


static func _dot_mat() -> StandardMaterial3D:
	if _dot_mats.has("dot"):
		return _dot_mats["dot"]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = Fire._soft_dot()
	m.albedo_color = Color(1.6, 1.6, 1.6)
	_dot_mats["dot"] = m
	return m


static func _streak_tex() -> NoiseTexture2D:
	if _streaks:
		return _streaks
	var n := FastNoiseLite.new()
	n.frequency = 0.03
	n.fractal_octaves = 2
	_streaks = NoiseTexture2D.new()
	_streaks.width = 128
	_streaks.height = 128
	_streaks.seamless = true
	_streaks.noise = n
	return _streaks
