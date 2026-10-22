class_name Magic
extends Node3D
## The fantasy layer: floating crystal clusters that bob and turn with their
## own light, and drifting motes of light over the map. View only.

var _t := 0.0
var _speed := 1.0
var _home := Vector3.ZERO
var _spin_rate := 0.3
var _bob := 0.12


## A cluster of 3 to 5 floating shards over `pos`.
static func crystals(parent: Node3D, pos: Vector3, col: Color, size := 1.0, rng: RandomNumberGenerator = null) -> Magic:
	var r := rng if rng else RandomNumberGenerator.new()
	var m := Magic.new()
	m.position = pos
	m._home = pos
	m._t = r.randf() * 10.0
	m._speed = r.randf_range(0.7, 1.2)
	m._spin_rate = r.randf_range(0.2, 0.45) * (1.0 if r.randf() < 0.5 else -1.0)
	parent.add_child(m)
	var mat := Palette.glow(col, 0.9)
	mat.albedo_color = col
	mat.roughness = 0.1
	mat.metallic = 0.3
	mat.rim_enabled = true
	mat.rim = 0.5
	var n := 3 + r.randi() % 3
	for i in n:
		var mi := MeshInstance3D.new()
		var big := i == 0
		var w := (0.28 if big else r.randf_range(0.1, 0.18)) * size
		mi.mesh = UnitView._octahedron(w, w * r.randf_range(2.2, 3.0), w * r.randf_range(1.4, 2.0))
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if not big:
			var a := TAU * i / n + r.randf_range(-0.3, 0.3)
			mi.position = Vector3(cos(a), r.randf_range(-0.4, 0.3), sin(a)) * 0.55 * size
			mi.rotation = Vector3(r.randf_range(-0.4, 0.4), r.randf() * TAU, r.randf_range(-0.4, 0.4))
		m.add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 1.2 * size
	light.omni_range = 5.0 * size
	m.add_child(light)
	return m


## Crystal growth: shards breaking out of the ground or a wall, fixed in
## place, leaning outward, with a soft light.
static func growth(parent: Node3D, pos: Vector3, col: Color, size := 1.0, rng: RandomNumberGenerator = null) -> Magic:
	var r := rng if rng else RandomNumberGenerator.new()
	var m := Magic.new()
	m.position = pos
	m._home = pos
	m._bob = 0.0
	m._spin_rate = 0.0
	parent.add_child(m)
	var mat := Palette.glow(col, 0.8)
	mat.albedo_color = col.darkened(0.1)
	mat.roughness = 0.12
	mat.metallic = 0.3
	mat.rim_enabled = true
	mat.rim = 0.5
	for i in 3 + r.randi() % 4:
		var mi := MeshInstance3D.new()
		var w := r.randf_range(0.07, 0.16) * size * (1.6 if i == 0 else 1.0)
		mi.mesh = UnitView._octahedron(w, w * r.randf_range(3.0, 5.0), w * 0.5)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(r.randf_range(-0.25, 0.25), 0, r.randf_range(-0.25, 0.25)) * size
		mi.rotation = Vector3(r.randf_range(-0.6, 0.6), r.randf() * TAU, r.randf_range(-0.6, 0.6))
		m.add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 0.9 * size
	light.omni_range = 3.5 * size
	light.position = Vector3(0, 0.5, 0)
	m.add_child(light)
	return m


## A floating island of rock far out over the valley, with a crystal on top.
static func island(parent: Node3D, pos: Vector3, scale: float, col: Color, rng: RandomNumberGenerator) -> Magic:
	var m := Magic.new()
	m.position = pos
	m._home = pos
	m._t = rng.randf() * 10.0
	m._speed = rng.randf_range(0.25, 0.4)
	m._bob = 0.6
	m._spin_rate = rng.randf_range(0.01, 0.03)
	parent.add_child(m)
	var rocks := ["rock_moss_set_01_rock01", "rock_moss_set_01_rock02", "rock_moss_set_01_rock03", "rock_moss_set_01_rock05"]
	var top := EnvDressing.prop(m, "rock_moss_set_01", rocks[rng.randi() % rocks.size()], Vector3.ZERO, rng.randf() * 360.0, scale, false)
	var under := EnvDressing.prop(m, "rock_moss_set_01", rocks[rng.randi() % rocks.size()], Vector3(0, -0.2 * scale, 0), rng.randf() * 360.0, scale * 0.8, false)
	if under:
		under.rotation_degrees.x = 180.0
	if top:
		growth(m, Vector3(0, 1.2 * scale, 0), col, scale * 0.9, rng)
	return m


func _process(delta: float) -> void:
	_t += delta * _speed
	if _bob > 0.0:
		position = _home + Vector3(0, sin(_t * 1.3) * _bob, 0)
	rotation.y += delta * _spin_rate


## Slow motes of light drifting in a box (centre, size), like dust in sun
## or spirits over old stones. Soft and few, so they never read as an effect.
static func motes(parent: Node3D, center: Vector3, extents: Vector3, col: Color, amount := 60) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.position = center
	p.amount = amount
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3(0, 0.03, 0)
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.25
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.2, 1.0))
	curve.add_point(Vector2(0.8, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = Fire._soft_dot()
	m.albedo_color = Color(col.r * 2.0, col.g * 2.0, col.b * 2.0, 0.8)
	quad.material = m
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	return p
