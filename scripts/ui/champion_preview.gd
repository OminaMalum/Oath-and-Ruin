class_name ChampionPreview
extends SubViewportContainer
## The picked champion's model on the menu, standing on a stone disc and
## turning slowly, in its own small world so the menu needs no map loaded.
## Lit warm from the front and cool from behind, like the golden hour map.

const VIEW := Vector2i(400, 440)

var _viewport: SubViewport
var _pivot: Node3D
var _model: Node3D
var _id: StringName = &""
## Screenshots: hold the turn at this angle (degrees); NAN turns freely.
var fixed_yaw: float = NAN


func _ready() -> void:
	stretch = true
	custom_minimum_size = Vector2(VIEW)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.size = VIEW
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	# The map's sky lights the model (ambient and reflections) but is not drawn.
	var sky := Sky.new()
	var sm := PanoramaSkyMaterial.new()
	sm.panorama = load(Art.SKY)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.1
	env.tonemap_white = 8.0
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.86, 0.66)
	key.light_energy = 1.9
	key.shadow_enabled = true
	key.rotation_degrees = Vector3(-32, 38, 0)
	_viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.55, 0.85, 0.9)
	rim.light_energy = 1.1
	rim.rotation_degrees = Vector3(-18, -150, 0)
	_viewport.add_child(rim)
	var cam := Camera3D.new()
	cam.fov = 30.0
	_viewport.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.45, 5.7), Vector3(0, 1.08, 0))
	cam.make_current()
	# A worn stone disc to stand on, with a brass ring.
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.95
	cyl.bottom_radius = 1.02
	cyl.height = 0.16
	cyl.radial_segments = 48
	disc.mesh = cyl
	disc.position = Vector3(0, -0.08, 0)
	disc.material_override = Palette.mat(Color(0.20, 0.185, 0.165), 0.92)
	_viewport.add_child(disc)
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.84
	tor.outer_radius = 0.89
	tor.rings = 64
	ring.mesh = tor
	ring.scale = Vector3(1, 0.3, 1)
	ring.position = Vector3(0, 0.005, 0)
	ring.material_override = Palette.mat(Palette.BRASS, 0.45, 0.8)
	_viewport.add_child(ring)
	_pivot = Node3D.new()
	_viewport.add_child(_pivot)


## Swap the model for champion `id` (a ChampionDef id with a glb).
func show_champion(id: StringName) -> void:
	if id == _id:
		return
	_id = id
	if _model:
		_model.queue_free()
		_model = null
	var path := ChampionModel.path_for(id)
	var def := load("res://data/champions/%s.tres" % id) as ChampionDef
	if path.is_empty() or def == null:
		return
	_model = (load(path) as PackedScene).instantiate()
	_pivot.add_child(_model)
	ChampionModel.dress(_model, 0, def.accent_color, def.primary_color)
	# Tall and short champions both fill the frame.
	var s := clampf(1.9 / maxf(def.height, 1.0), 0.9, 1.25)
	_model.scale = Vector3.ONE * s
	var players := _model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		var ap := players[0] as AnimationPlayer
		if ap.has_animation("idle"):
			ap.play("idle")
	# Models face -z; start turned a little toward the camera's left.
	_pivot.rotation.y = PI + deg_to_rad(24.0)


func _process(delta: float) -> void:
	if _pivot == null:
		return
	if is_nan(fixed_yaw):
		_pivot.rotation.y += delta * 0.35
	else:
		_pivot.rotation.y = PI + deg_to_rad(fixed_yaw)
