class_name SummonModel
extends Node3D
## Built models for summons (Look SENTRY, BANNER and SPIRIT), added by the
## world view when a summon appears. A summon with a modelled body in
## assets/units/<id>.glb is handed to UnitView instead (clips, cloth,
## ragdoll); the shapes here are for the fixed summons, dressed in the same
## textured looks as the champion models. View only.

var unit: Unit
var _head: Node3D        # sentry: the gun carriage that tracks the aim
var _barrel: Node3D      # sentry: kicks back on a shot
var _kick := 0.0
var _cloth: MeshInstance3D
var _aura: MeshInstance3D
var _t := 0.0
var _dead := false


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
	_t = fmod(float(unit.net_id) * 0.37, TAU)
	match unit.def.look:
		ChampionDef.Look.SENTRY:
			_sentry()
		ChampionDef.Look.BANNER:
			_banner()
		ChampionDef.Look.SPIRIT:
			_spirit()
	unit.cast_released.connect(func(_s: int, _a: AbilityDef, _t2: Vector3) -> void: _kick = 1.0)
	unit.died.connect(_on_died)


func _process(dt: float) -> void:
	if is_queued_for_deletion():
		return
	_t += dt
	if unit.def.look == ChampionDef.Look.SPIRIT:
		position.y = 0.15 + sin(_t * 4.0) * 0.08  # it floats
		return
	if _dead:
		return
	if _head:
		_head.rotation.y = lerp_angle(_head.rotation.y, unit.aim_yaw, 1.0 - exp(-10.0 * dt))
		_kick = maxf(_kick - dt * 6.0, 0.0)
		_barrel.position.z = 0.1 * _kick * _kick
	if _aura:
		var s := 1.0 + 0.03 * sin(_t * 2.2)
		_aura.scale = Vector3(s, 1.0, s)
		(_aura.material_override as StandardMaterial3D).albedo_color.a = 0.14 + 0.06 * sin(_t * 2.2)
	if _cloth:
		(_cloth.material_override as ShaderMaterial).set_shader_parameter("t", _t)


func _on_died(_killer: Unit) -> void:
	_dead = true
	Fx.death(unit, global_position + Vector3(0, unit.def.height * 0.5, 0), unit.def.accent_color, 0.7)
	# Knocked over: the sentry tips off its tripod, the standard falls.
	var tw := create_tween()
	var away := Vector3(0, 0, 1).rotated(Vector3.UP, unit.aim_yaw) * 0.3
	tw.set_parallel(true)
	tw.tween_property(self, "rotation_degrees", Vector3(70.0, 0, 18.0), 0.45).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(self, "position", position + away + Vector3(0, -0.1, 0), 0.45).set_ease(Tween.EASE_IN)


func _part(mesh: Mesh, m: Material, pos: Vector3, rot_deg := Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = rot_deg
	(parent if parent else self).add_child(mi)
	return mi


func _look(nm: String, tint := Color.WHITE) -> StandardMaterial3D:
	return ChampionModel._make(ChampionModel.LOOKS[nm], tint)


func _team() -> Color:
	return Palette.team_color(unit.team).darkened(0.2)


## Brasswright's field sentry: a brass repeater on an iron tripod. The gun
## carriage turns toward the aim, the barrel kicks back on each bolt and a
## team lamp on the breech shows which side it guards.
func _sentry() -> void:
	var iron := _look("Iron")
	var brass := _look("Brass")
	var wood := _look("Wood")
	var team := Palette.mat(_team(), 0.8)
	# Tripod with iron shoes and a brace ring.
	for i in 3:
		var ang := TAU * i / 3.0
		var leg := _part(UnitView._cyl(0.035, 0.05, 1.0), wood, Vector3(sin(ang) * 0.3, 0.46, cos(ang) * 0.3))
		leg.rotation = Vector3(cos(ang) * 0.38, 0.0, -sin(ang) * 0.38)
		_part(UnitView._cyl(0.06, 0.07, 0.08), iron, Vector3(sin(ang) * 0.47, 0.04, cos(ang) * 0.47))
		_part(UnitView._cyl(0.05, 0.05, 0.04), brass, Vector3(sin(ang) * 0.14, 0.9, cos(ang) * 0.14))
	_part(UnitView._cyl(0.16, 0.16, 0.06), iron, Vector3(0, 0.86, 0))
	# A brass gear ring the carriage turns on.
	_part(UnitView._cyl(0.22, 0.2, 0.08), brass, Vector3(0, 0.92, 0))
	for i in 12:
		var a := TAU * i / 12.0
		_part(UnitView._box(Vector3(0.05, 0.06, 0.04)), brass, Vector3(sin(a) * 0.23, 0.92, cos(a) * 0.23)).rotation.y = a
	# The carriage: breech block, drum magazine, barrel with bands, a sight.
	_head = Node3D.new()
	_head.position = Vector3(0, 0.96, 0)
	add_child(_head)
	_part(UnitView._box(Vector3(0.44, 0.3, 0.5)), brass, Vector3(0, 0.17, 0.05), Vector3.ZERO, _head)
	_part(UnitView._box(Vector3(0.48, 0.05, 0.54)), iron, Vector3(0, 0.0, 0.05), Vector3.ZERO, _head)
	_part(UnitView._cyl(0.17, 0.17, 0.22), iron, Vector3(0, 0.18, 0.28), Vector3(90, 0, 0), _head)
	_part(UnitView._cyl(0.08, 0.08, 0.04), brass, Vector3(0, 0.18, 0.41), Vector3(90, 0, 0), _head)
	_part(UnitView._box(Vector3(0.5, 0.06, 0.1)), team, Vector3(0, 0.34, 0.02), Vector3.ZERO, _head)
	_part(UnitView._box(Vector3(0.03, 0.08, 0.03)), iron, Vector3(0, 0.37, -0.15), Vector3.ZERO, _head)
	_barrel = Node3D.new()
	_head.add_child(_barrel)
	_part(UnitView._cyl(0.06, 0.07, 0.9), iron, Vector3(0, 0.17, -0.65), Vector3(90, 0, 0), _barrel)
	_part(UnitView._cyl(0.085, 0.085, 0.08), brass, Vector3(0, 0.17, -0.4), Vector3(90, 0, 0), _barrel)
	_part(UnitView._cyl(0.08, 0.085, 0.07), brass, Vector3(0, 0.17, -1.05), Vector3(90, 0, 0), _barrel)
	_part(UnitView._cyl(0.03, 0.03, 0.9), brass, Vector3(0.1, 0.1, -0.5), Vector3(90, 0, 0), _barrel)
	_part(UnitView._cyl(0.03, 0.03, 0.9), brass, Vector3(-0.1, 0.1, -0.5), Vector3(90, 0, 0), _barrel)
	# Breech lamp: the summon's accent, and the team lamp on the drum.
	_part(UnitView._sphere(0.06), Palette.glow(unit.def.accent_color, 1.6), Vector3(0, 0.3, 0.2), Vector3.ZERO, _head)
	_part(UnitView._sphere(0.035), Palette.glow(_team().lightened(0.3), 1.4), Vector3(0, 0.18, 0.45), Vector3.ZERO, _head)
	_head.rotation.y = unit.aim_yaw


## Banneret's rally standard: an oak pole on an iron spike, a crossbar with
## a team cloth that waves, gold fringe, a brass sun finial and a faint
## pulsing ring on the ground at the rally's reach.
func _banner() -> void:
	var wood := _look("Wood")
	var brass := _look("Brass")
	var iron := _look("Iron")
	var trim := _look("Trim")
	_part(UnitView._cyl(0.04, 0.05, 2.85), wood, Vector3(0, 1.42, 0))
	_part(UnitView._cyl(0.06, 0.06, 0.1), brass, Vector3(0, 0.95, 0))
	_part(UnitView._cyl(0.065, 0.065, 0.08), brass, Vector3(0, 2.4, 0))
	_part(UnitView._cyl(0.03, 0.03, 1.0), wood, Vector3(0, 2.62, 0), Vector3(0, 0, 90))
	for sx in [-1.0, 1.0]:
		_part(UnitView._sphere(0.045), brass, Vector3(sx * 0.5, 2.62, 0))
	# Finial: a brass sun disc with rays.
	_part(UnitView._cyl(0.12, 0.12, 0.03), trim, Vector3(0, 3.0, 0), Vector3(90, 0, 0))
	for i in 8:
		var a := TAU * i / 8.0
		_part(UnitView._box(Vector3(0.03, 0.14, 0.02)), trim, Vector3(sin(a) * 0.17, 3.0 + cos(a) * 0.17, 0)).rotation.z = -a
	_part(UnitView._sphere(0.05), Palette.glow(unit.def.accent_color, 1.8), Vector3(0, 3.0, 0))
	# Ground spike and a ring of earth it is driven into.
	_part(UnitView._cyl(0.02, 0.05, 0.3), iron, Vector3(0, 0.15, 0))
	_part(UnitView._cyl(0.28, 0.34, 0.08), Art.stone("plaza", Color(0.7, 0.65, 0.58)), Vector3(0, 0.04, 0))
	# The cloth: a grid that waves in a shader, hung from the crossbar.
	_cloth = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(0.95, 1.25)
	pm.subdivide_width = 10
	pm.subdivide_depth = 14
	pm.orientation = PlaneMesh.FACE_Z
	_cloth.mesh = pm
	var sm := ShaderMaterial.new()
	sm.shader = _cloth_shader()
	sm.set_shader_parameter("col", _team())
	sm.set_shader_parameter("trim", Color(0.9, 0.72, 0.35))
	sm.set_shader_parameter("accent", unit.def.accent_color)
	sm.set_shader_parameter("tex", ChampionModel._make(ChampionModel.LOOKS["Team"], Color.WHITE).albedo_texture)
	_cloth.material_override = sm
	_cloth.position = Vector3(0, 1.98, 0.01)
	_cloth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_cloth)
	# Rally reach on the ground, team coloured, breathing.
	var am := Palette.glow(_team().lightened(0.2), 1.2)
	am.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	am.albedo_color.a = 0.18
	am.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var t := TorusMesh.new()
	t.inner_radius = maxf(unit.def.passive_range - 0.18, 0.5)
	t.outer_radius = maxf(unit.def.passive_range, 0.6)
	t.rings = 64
	t.ring_segments = 4
	_aura = MeshInstance3D.new()
	_aura.mesh = t
	_aura.material_override = am
	_aura.scale = Vector3(1, 0.04, 1)
	_aura.position = Vector3(0, Palette.DECAL_LIFT * 0.6, 0)
	_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_aura)


static var _cloth_sh: Shader


static func _cloth_shader() -> Shader:
	if _cloth_sh:
		return _cloth_sh
	_cloth_sh = Shader.new()
	_cloth_sh.code = """
shader_type spatial;
render_mode cull_disabled;
uniform float t = 0.0;
uniform vec4 col : source_color = vec4(0.5, 0.2, 0.2, 1.0);
uniform vec4 trim : source_color = vec4(0.9, 0.7, 0.35, 1.0);
uniform vec4 accent : source_color = vec4(0.95, 0.8, 0.45, 1.0);
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
varying vec2 uvv;
void vertex() {
	// Hung from the top edge: the lower it is the more it swings.
	float hang = clamp(0.5 - VERTEX.y / 1.25, 0.0, 1.0);
	float w = sin(t * 2.6 + VERTEX.y * 3.0 + VERTEX.x * 2.0) * 0.1 + sin(t * 4.1 + VERTEX.x * 6.0) * 0.035;
	VERTEX.z += w * hang * hang;
	VERTEX.x += sin(t * 1.7 + VERTEX.y * 2.0) * 0.02 * hang;
	uvv = UV;
}
void fragment() {
	vec3 base = col.rgb * texture(tex, uvv * 3.0).rgb * 1.4;
	// Gold fringe along the bottom and sides, a sun badge in the middle.
	float edge = step(uvv.y, 0.08) + step(abs(uvv.x - 0.5), 0.5) * step(0.47, abs(uvv.x - 0.5));
	float d = length((uvv - vec2(0.5, 0.58)) * vec2(1.0, 1.3));
	float badge = smoothstep(0.17, 0.15, d) * step(0.09, d) + smoothstep(0.06, 0.04, d);
	vec3 c = mix(base, trim.rgb, clamp(edge, 0.0, 1.0));
	c = mix(c, accent.rgb, badge);
	ALBEDO = c;
	ROUGHNESS = 0.9;
	EMISSION = accent.rgb * badge * 0.25;
}
"""
	return _cloth_sh


## A willing dead without a model: a shrouded figure in funeral cords, hem
## dissolving into violet light. (The modelled one lives in assets/units.)
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
