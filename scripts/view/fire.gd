class_name Fire
extends Node3D
## A small open flame: soft additive particles and a warm light that
## flickers. View only. Used by braziers, lanterns and the camp fire.

var _light: OmniLight3D
var _base_energy := 1.0
var _t := 0.0
var _seed := 0.0


## Adds a fire at `pos` under `parent`. `size` 1.0 is a brazier.
static func add(parent: Node3D, pos: Vector3, size := 1.0, light_range := 7.0, energy := 1.6) -> Fire:
	var f := Fire.new()
	f.position = pos
	parent.add_child(f)
	f._make(size, light_range, energy)
	return f


func _make(size: float, light_range: float, energy: float) -> void:
	_seed = randf() * 100.0
	var p := CPUParticles3D.new()
	p.amount = int(18 * size) + 6
	p.lifetime = 0.7
	p.preprocess = 1.0
	p.local_coords = true
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.16 * size
	p.direction = Vector3.UP
	p.spread = 12.0
	p.gravity = Vector3(0, 1.6 * size, 0)
	p.initial_velocity_min = 0.3 * size
	p.initial_velocity_max = 0.7 * size
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.6))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.45, 1.0))
	ramp.add_point(0.45, Color(1.0, 0.45, 0.12, 0.9))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.5, 0.12, 0.04, 0.0))
	p.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.32, 0.42) * size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_dot()
	m.albedo_color = Color(2.2, 2.0, 1.8)
	quad.material = m
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.68, 0.38)
	_light.light_energy = energy
	_light.omni_range = light_range
	_light.omni_attenuation = 1.4
	_light.position = Vector3(0, 0.5 * size, 0)
	_base_energy = energy
	add_child(_light)


static var _dot: Texture2D


static func _soft_dot() -> Texture2D:
	if _dot:
		return _dot
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 64
	t.height = 64
	_dot = t
	return _dot


func _process(delta: float) -> void:
	_t += delta
	var k := sin(_t * 9.0 + _seed) * 0.5 + sin(_t * 23.0 + _seed * 2.0) * 0.3 + sin(_t * 4.0) * 0.2
	_light.light_energy = _base_energy * (1.0 + k * 0.12)
