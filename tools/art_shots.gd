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
	"lane_low": [Vector3(4.0, 2.4, 7.0), Vector3(0, 0.8, -1.0)],
	"camp_close": [Vector3(-21.5, 3.2, 5.0), Vector3(-28.0, 1.2, 0.0)],
	"overview": [Vector3(32.0, 48.0, 50.0), Vector3(0, 0, 8.0)],
	"champ_1": [], "champ_2": [], "champ_3": [], "champ_4": [], "champ_5": [], "champ_6": [],
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


var _shown := {}


func _next() -> void:
	var k: String = _queue[0]
	if k.begins_with("champ"):
		# Behind and above a living champion with a model (a different one each
		# view when it can), the way a player sees it.
		var best: Unit = null
		for u: Unit in root.find_children("*", "Unit", true, false):
			if u.def.kind != ChampionDef.Kind.CHAMPION or not u.alive or ChampionModel.path_for(u.def.id).is_empty():
				continue
			var fresh := not _shown.has(u.def.id)
			var best_fresh := best != null and not _shown.has(best.def.id)
			if best == null or (fresh and not best_fresh) or (fresh == best_fresh and absf(u.global_position.x) < absf(best.global_position.x)):
				best = u
		if best:
			_shown[best.def.id] = true
		if best:
			var f := best.forward()
			var at := best.global_position + Vector3(0, 1.0, 0)
			_cam.global_position = at - f * 4.0 + Vector3(0, 4.5, 0)
			_cam.look_at(at + f * 1.0)
			print("champ view on ", best.name, " at ", best.global_position)
		_cam.make_current()
		_wait = 4
		return
	var v: Array = VIEWS[k]
	_cam.global_position = v[0]
	_cam.look_at(v[1])
	_cam.make_current()
	_wait = 12
