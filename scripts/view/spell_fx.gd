class_name SpellFx
extends Node3D
## Spell effects layered over WorldView's projectiles and telegraphs: trails
## and spinning glyphs on bolts, a streaming lance, spell circles that draw
## themselves in under ground spells, a descending sigil for an ultimate,
## and impacts with a shockwave, a column of light and sparks. View only:
## it listens to the same authority signals and changes nothing in the sim.
## Colours are the caster's accent; the ally/enemy telegraph stays on top
## as the thing to read.

const CIRCLE := preload("res://scripts/view/shaders/spell_circle.gdshader")
const PILLAR := preload("res://scripts/view/shaders/spell_pillar.gdshader")

var _wv: WorldView
var _bolts := {}     # SimProjectile -> {trail, glyph, big}
var _circles := {}   # SimArea -> {node, mat, sigil, sigil_mat, motes}
var _fading: Array[Dictionary] = []  # {node, mat, t, life, kind, grow}
static var _streaks: NoiseTexture2D
static var _dot_mats := {}


func setup(a: CombatAuthority, wv: WorldView) -> void:
	_wv = wv
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Connected after WorldView, so its projectile node already exists.
	a.projectile_spawned.connect(_on_projectile_spawned)
	a.projectile_ended.connect(_on_projectile_ended)
	a.area_spawned.connect(_on_area_spawned)
	a.area_detonated.connect(_on_area_detonated)


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
	var trail: CPUParticles3D = b.trail
	trail.emitting = false
	get_tree().create_timer(trail.lifetime + 0.1).timeout.connect(trail.queue_free)
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
	var n: Node3D = e.node
	(e.motes as CPUParticles3D).emitting = false
	_fading.append({"node": n, "mat": e.mat, "t": 0.0, "life": 0.5, "kind": "circle", "grow": 0.15})
	var col := ar.source.def.accent_color if is_instance_valid(ar.source) else Color(0.6, 0.8, 0.8)
	var r := ar.ability.area_radius
	var big := ar.ability.is_ultimate
	_pillar(ar.center, col, r * (0.55 if big else 0.45), 7.0 if big else 4.0, 0.6 if big else 0.4)
	_shockwave(ar.center + Vector3(0, Palette.DECAL_LIFT + 0.1, 0), col, r * 1.35, 0.4 if big else 0.3, Vector3.UP)
	_flash(ar.center + Vector3(0, 1.0, 0), col, 6.0 if big else 3.5, 0.35)
	_sparks(ar.center + Vector3(0, 0.3, 0), col, 40 if big else 22, 0.8, 7.0 if big else 5.0, 35.0)


func _process(delta: float) -> void:
	for p: CombatAuthority.SimProjectile in _bolts:
		var b: Dictionary = _bolts[p]
		var host: Node3D = b.host
		if is_instance_valid(host):
			(b.trail as Node3D).global_position = host.global_position
			(b.glyph as Node3D).rotate_object_local(Vector3.FORWARD, delta * 9.0)
	for ar: CombatAuthority.SimArea in _circles:
		var e: Dictionary = _circles[ar]
		var k := 1.0 - clampf(ar.timer / maxf(ar.ability.area_delay, 0.01), 0.0, 1.0)
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
		if k >= 1.0:
			n.queue_free()
	_fading = _fading.filter(func(f: Dictionary) -> bool: return f.t < f.life)


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
