extends SceneTree
## Art review screenshots from fixed cameras on the match map, after the
## match has run a little (so towers, minions and champions are on the map).
## xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 --fixed-fps 60 \
##   -s tools/art_shots.gd -- --mode=match --spectate --warp=20 --artshots=/tmp/shots [--only=NAME,NAME]

## name: [camera position, look-at point]
const VIEWS := {
	"tower_oath": [Vector3(9.5, 7.5, 44.0), Vector3(0, 3.0, 32.0)],
	"lane_mid": [Vector3(0, 11.0, 18.0), Vector3(0, 0.0, -2.0)],
	"tower_ruin_close": [Vector3(-4.5, 3.2, -24.0), Vector3(0, 4.0, -32.0)],
	"flank_east": [Vector3(15.0, 4.0, 30.0), Vector3(15.0, 1.0, 10.0)],
	"base_oath": [Vector3(0, 14.0, 40.0), Vector3(0, 1.0, 60.0)],
	"camp": [Vector3(-16.0, 9.0, 8.0), Vector3(-28.0, 0.5, 0.0)],
	"overview": [Vector3(32.0, 48.0, 50.0), Vector3(0, 0, 8.0)],
}

var _main: Node
var _cam: Camera3D
var _dir := ""
var _queue: Array = []
var _wait := 0
var _started := false


func _initialize() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--artshots="):
			_dir = a.get_slice("=", 1)
		elif a.begins_with("--only="):
			only = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_dir)
	for k: String in VIEWS:
		if only.is_empty() or k in only.split(","):
			_queue.append(k)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		var warp: float = _main.get("_warp_until")
		if warp > 0.0:
			return false
		_started = true
		for c in root.find_children("*", "CanvasLayer", true, false):
			(c as CanvasLayer).visible = false
		_cam = Camera3D.new()
		_cam.fov = 60.0
		_cam.far = 400.0
		root.add_child(_cam)
		_next()
		return false
	_wait -= 1
	if _wait > 0:
		return false
	if _wait == 0:
		var k: String = _queue.pop_front()
		var path := "%s/%s.png" % [_dir, k]
		root.get_viewport().get_texture().get_image().save_png(path)
		print("saved art shot ", path)
		if _queue.is_empty():
			return true
		_next()
	return false


func _next() -> void:
	var v: Array = VIEWS[_queue[0]]
	_cam.global_position = v[0]
	_cam.look_at(v[1])
	_cam.make_current()
	_wait = 12
