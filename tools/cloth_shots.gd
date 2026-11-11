extends SceneTree
## Cloth review: a champion runs forward, stops dead, then turns, shot from
## the side, with and without ClothSim, so the swing can be compared.
## xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 --fixed-fps 60 \
##   -s tools/cloth_shots.gd -- --model=oathwarden --out=/tmp/cloth [--off]

var _m: Node3D
var _anim: AnimationPlayer
var _cam: Camera3D
var _f := 0
var _out := "/tmp/cloth"
var _id := "oathwarden"
var _off := false
const SHOTS := {50: "run", 75: "stop_a", 88: "stop_b", 110: "turn_a", 122: "turn_b", 150: "settle"}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--model="):
			_id = a.get_slice("=", 1)
		elif a.begins_with("--out="):
			_out = a.get_slice("=", 1)
		elif a == "--off":
			_off = true
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
	_m = (load("res://assets/champions/%s.glb" % _id) as PackedScene).instantiate()
	w.add_child(_m)
	ChampionModel.dress(_m, 0, Color(0.9, 0.7, 0.3))
	_anim = _m.find_children("*", "AnimationPlayer", true, false)[0]
	_anim.play("run")
	if not _off:
		ClothSim.attach(_m, true)
	_cam = Camera3D.new()
	_cam.fov = 40
	w.add_child(_cam)
	_cam.make_current()


func _process(delta: float) -> bool:
	_f += 1
	var dt := 1.0 / 60.0
	if _f < 70:
		_m.position.z -= 7.0 * dt  # model faces -z
	elif _f == 70:
		_anim.play("idle", 0.1)
	elif _f >= 100 and _f < 112:
		_m.rotation.y += deg_to_rad(15.0)
	_cam.position = _m.position + Vector3(3.6, 1.3, -0.6)
	_cam.look_at(_m.position + Vector3(0, 1.0, 0))
	if SHOTS.has(_f):
		root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, SHOTS[_f]])
	return _f > 155
