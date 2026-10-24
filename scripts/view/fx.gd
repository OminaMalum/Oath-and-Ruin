class_name Fx
## One-shot particle effects for hits and deaths. View only; each emitter
## frees itself when done. Kept small and short so fights stay readable.

static var _quad_mats := {}


static func _mat(col: Color, additive: bool) -> StandardMaterial3D:
	var key := "%s:%s" % [col.to_html(), additive]
	if _quad_mats.has(key):
		return _quad_mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = Fire._soft_dot()
	m.albedo_color = col
	_quad_mats[key] = m
	return m


static func _burst(parent: Node, at: Vector3, amount: int, life: float, size: float, speed: Vector2, gravity: Vector3,
		ramp: Gradient, additive: bool, spread := 180.0, dir := Vector3.UP) -> CPUParticles3D:
	if parent == null or not parent.is_inside_tree():
		return null
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = amount
	p.lifetime = life
	p.direction = dir
	p.spread = spread
	p.gravity = gravity
	p.initial_velocity_min = speed.x
	p.initial_velocity_max = speed.y
	p.damping_min = 1.0
	p.damping_max = 3.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(0.25, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	p.color_ramp = ramp
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = _mat(Color(1.5, 1.5, 1.5) if additive else Color.WHITE, additive)
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var host: Node = parent.get_tree().current_scene
	if host == null:
		host = parent.get_tree().root
	host.add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


static func _ramp(a: Color, b: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, a)
	g.set_color(1, b)
	return g


## A few warm sparks where a hit lands.
static func hit(parent: Node, at: Vector3, big := false) -> void:
	_burst(parent, at, 10 if big else 5, 0.35, 0.07, Vector2(2.0, 4.5), Vector3(0, -6, 0),
		_ramp(Color(1.0, 0.85, 0.5, 1.0), Color(1.0, 0.4, 0.1, 0.0)), true)


## A fallen unit: a low puff of dust and a wisp of its team colour rising.
static func death(parent: Node, at: Vector3, col: Color, scale := 1.0) -> void:
	_burst(parent, at + Vector3(0, 0.2, 0), int(14 * scale), 1.1, 0.7 * scale, Vector2(0.6, 1.6), Vector3(0, 0.3, 0),
		_ramp(Color(0.55, 0.48, 0.38, 0.55), Color(0.55, 0.48, 0.38, 0.0)), false, 80.0)
	_burst(parent, at + Vector3(0, 0.8, 0), int(12 * scale), 1.4, 0.18, Vector2(0.4, 1.0), Vector3(0, 1.4, 0),
		_ramp(Color(col.r, col.g, col.b, 1.0), Color(col.r, col.g, col.b, 0.0)), true, 25.0)


## A structure falls: a big dust cloud, stone chips, and its crystal
## shattering into team coloured shards.
static func collapse(parent: Node, at: Vector3, col: Color, crystal_y: float) -> void:
	_burst(parent, at + Vector3(0, 1.0, 0), 40, 2.4, 2.6, Vector2(1.0, 3.0), Vector3(0, 0.25, 0),
		_ramp(Color(0.6, 0.53, 0.43, 0.7), Color(0.6, 0.53, 0.43, 0.0)), false, 90.0)
	_burst(parent, at + Vector3(0, crystal_y, 0), 36, 1.6, 0.22, Vector2(3.0, 7.0), Vector3(0, -9, 0),
		_ramp(Color(col.r * 1.5, col.g * 1.5, col.b * 1.5, 1.0), Color(col.r, col.g, col.b, 0.0)), true)
	_burst(parent, at + Vector3(0, crystal_y * 0.5, 0), 24, 1.3, 0.16, Vector2(2.0, 5.0), Vector3(0, -12, 0),
		_ramp(Color(0.45, 0.42, 0.38, 1.0), Color(0.35, 0.33, 0.3, 0.0)), false)
