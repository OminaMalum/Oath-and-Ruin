extends SceneTree
## Close-up review shots of a champion model in its clips, lit like the map.
## xvfb-run -a -s "-screen 0 1280x960x24" godot --rendering-driver opengl3 --path . -s tools/model_shots.gd -- \
##   --model=res://assets/champions/ruinscribe.glb --out=/tmp/model [--team=0]
## Each shot: [file, clip, time in s (-1 = release), camera yaw degrees, distance]
## --strip=CLIP[:N[:YAW]] instead shoots N frames spread over one clip (strip_00.png ...).

const SHOTS := [
	["front", "idle", 0.6, 25.0, 3.4],
	["back", "idle", 0.6, 160.0, 3.4],
	["side", "idle", 0.6, 90.0, 3.4],
	["run_a", "run", 0.05, 35.0, 3.8],
	["run_b", "run", 0.2, 35.0, 3.8],
	["attack", "attack", -1.0, 30.0, 3.6],
	["ability_1", "ability_1", -1.0, 30.0, 3.8],
	["ability_2", "ability_2", -1.0, 50.0, 3.8],
	["ability_3_up", "ability_3", 0.2, 30.0, 4.0],
	["ability_3", "ability_3", -1.0, 30.0, 4.0],
	["death", "death", 1.2, 60.0, 4.0],
	["face", "idle", 0.6, 15.0, 1.3],
	["game_back", "run", 0.1, 180.0, 7.5],
]

var _out := "/tmp/model"
var _model := "res://assets/champions/ruinscribe.glb"
var _team := 0
var _inst: Node3D
var _player: AnimationPlayer
var _cam: Camera3D
var _i := 0
var _wait := 0
var _timing := {}
var _shots: Array = SHOTS
var _size := 1.0  # the camera closes in on smaller units


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.get_slice("=", 1)
		elif a.begins_with("--model="):
			_model = a.get_slice("=", 1)
		elif a.begins_with("--team="):
			_team = int(a.get_slice("=", 1))
		elif a.begins_with("--strip="):
			var parts := a.get_slice("=", 1).split(":")
			var n := int(parts[1]) if parts.size() > 1 else 8
			var yaw := float(parts[2]) if parts.size() > 2 else 30.0
			_shots = []
			for i in n:
				_shots.append(["strip_%02d" % i, parts[0], -2.0 - float(i) / float(maxi(n - 1, 1)), yaw, 3.8])
	DirAccess.make_dir_recursive_absolute(_out)
	var world := Node3D.new()
	root.add_child(world)
	Art.environment(world)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	floor.mesh = pm
	floor.material_override = Art.ground()
	world.add_child(floor)
	_inst = (load(_model) as PackedScene).instantiate()
	world.add_child(_inst)
	var id := _model.get_file().get_basename()
	var dp := "res://data/champions/%s.tres" % id
	var def := load(dp if ResourceLoader.exists(dp) else "res://data/units/%s.tres" % id) as ChampionDef
	ChampionModel.dress(_inst, _team, def.accent_color, def.primary_color)
	_size = clampf(def.height / 1.9, 0.5, 1.2)
	_player = _inst.find_children("*", "AnimationPlayer", true, false)[0]
	var tj := _model.get_basename() + ".timing.json"
	if FileAccess.file_exists(tj):
		_timing = JSON.parse_string(FileAccess.get_file_as_string(tj)).get("release", {})
	_cam = Camera3D.new()
	_cam.fov = 40.0
	world.add_child(_cam)
	_cam.make_current()
	_setup()


func _setup() -> void:
	var s: Array = _shots[_i]
	var clip: String = s[1]
	var t: float = s[2]
	if t <= -2.0:
		t = (-2.0 - t) * _player.get_animation(clip).length
	elif t < 0.0:
		t = float(_timing.get(clip, 0.0))
	_player.play(clip)
	_player.seek(t, true)
	_player.pause()
	# The camera stays on the sun side and the model turns, so every view is lit.
	_inst.rotation.y = PI + deg_to_rad(float(s[3]))
	var d: float = s[4] * _size
	var look := Vector3(0, (1.1 if s[4] > 2.0 else 1.62) * _size, 0)
	_cam.look_at_from_position(look + Vector3(d * 0.35, d * 0.22, d), look)
	_wait = 6


func _process(_delta: float) -> bool:
	_wait -= 1
	if _wait > 0:
		return false
	var s: Array = _shots[_i]
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, s[0]])
	print("saved ", s[0])
	_i += 1
	if _i >= _shots.size():
		return true
	_setup()
	return false
