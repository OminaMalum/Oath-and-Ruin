extends SceneTree
## Layered animation review: a champion runs and throws its basic attack on
## the move (upper body attacks, legs keep running), then stops and attacks
## standing. Shots from the side through ModelAnimator, as in a match.
## xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 --fixed-fps 60 \
##   -s tools/move_cast_shots.gd -- --model=oathwarden --clip=attack --out=/tmp/mc [--die]
## --die: runs, then is killed by a blow from the front at frame 40 (ragdoll).

var _m: Node3D
var _lay: ModelAnimator
var _react: BodyReact
var _cam: Camera3D
var _f := 0
var _out := "/tmp/mc"
var _id := "oathwarden"
var _clip := "attack"
var _shots: Array[int] = []
var _die := false
var _rag: Ragdoll


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--model="):
			_id = a.get_slice("=", 1)
		elif a.begins_with("--out="):
			_out = a.get_slice("=", 1)
		elif a == "--die":
			_die = true
		elif a.begins_with("--clip="):
			_clip = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_out)
	var w := Node3D.new()
	root.add_child(w)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.32, 0.34, 0.38)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	w.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	w.add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.45, 0.42, 0.36)
	floor.material_override = fm
	w.add_child(floor)
	var ground := StaticBody3D.new()
	ground.collision_layer = Unit.LAYER_WORLD
	var gs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	gs.shape = box
	gs.position = Vector3(0, -0.5, 0)
	ground.add_child(gs)
	w.add_child(ground)
	var path := "res://assets/champions/%s.glb" % _id
	if not ResourceLoader.exists(path):
		path = "res://assets/units/%s.glb" % _id
	_m = (load(path) as PackedScene).instantiate()
	w.add_child(_m)
	ChampionModel.dress(_m, 0, Color(0.9, 0.7, 0.3))
	_lay = ModelAnimator.new(_m.find_children("*", "AnimationPlayer", true, false)[0])
	_react = BodyReact.attach(_m)
	ClothSim.attach(_m, true)
	_cam = Camera3D.new()
	_cam.fov = 40
	w.add_child(_cam)
	_cam.make_current()
	if _die:
		for i in 16:
			_shots.append(38 + i * 6)
		return
	for i in 8:
		_shots.append(32 + i * 4)
	for i in 8:
		_shots.append(100 + i * 4 if i < 4 else 140 + (i - 4) * 4)


func _process(_delta: float) -> bool:
	_f += 1
	var dt := 1.0 / 60.0
	var moving := 1.0 if _f < (40 if _die else 100) else 0.0
	if _die and _f == 40:
		_lay.die()
		_rag = Ragdoll.fall(_m, Vector3(0, 0, 1) * 2.6 + Vector3.UP * 1.4)
	_m.position.z -= 6.5 * dt * moving
	if not _die and (_f == 30 or _f == 120):
		_lay.cast(_clip, 1.0)
	_lay.update(dt, moving, 1.0, false)
	_react.drive(Vector2(0, 6.5 / 7.0 * moving), 0.0)
	if _f == 140:
		_react.hit(Vector2(0.3, 1.0))
	_cam.position = _m.position + (Vector3(4.2, 2.0, 0.6) if _die else Vector3(3.8, 1.4, -0.2))
	_cam.look_at(_m.position + (Vector3(0, 0.5, 0.6) if _die else Vector3(0, 0.95, 0)))
	if _f in _shots:
		root.get_viewport().get_texture().get_image().save_png("%s/s_%03d.png" % [_out, _f])
	return _f > 160
