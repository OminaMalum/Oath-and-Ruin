extends SceneTree
## Catches spell effects in a running bot match and saves close shots of them.
## xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 --fixed-fps 60 \
##   -s tools/fx_shots.gd -- --mode=match --spectate --warp=30 --fxshots=/tmp/fx [--count=8]

var _main: Node
var _cam: Camera3D
var _fx: SpellFx
var _dir := "/tmp/fx"
var _count := 8
var _taken := 0
var _cool := 0
var _pending := 0
var _label := ""
var _frames := 0
var _seen := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fxshots="):
			_dir = a.get_slice("=", 1)
		elif a.begins_with("--count="):
			_count = int(a.get_slice("=", 1))
	DirAccess.make_dir_recursive_absolute(_dir)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	var warp: float = _main.get("_warp_until")
	if warp > 0.0:
		return false
	_frames += 1
	if _frames > 60 * 120:
		return true
	if _cam == null:
		for c in root.find_children("*", "CanvasLayer", true, false):
			(c as CanvasLayer).visible = false
		_cam = Camera3D.new()
		_cam.fov = 55.0
		root.add_child(_cam)
		_cam.make_current()
		var found := root.find_children("*", "SpellFx", true, false)
		if found.is_empty():
			push_error("no SpellFx in the scene")
			return true
		_fx = found[0]
	if _pending > 0:
		_pending -= 1
		if _pending == 0:
			var path := "%s/%02d_%s.png" % [_dir, _taken, _label]
			root.get_viewport().get_texture().get_image().save_png(path)
			print("saved ", path)
			_taken += 1
			_cool = 20
			if _taken >= _count:
				return true
		return false
	_cool -= 1
	if _cool > 0:
		return false
	for f: Dictionary in _fx._fading:
		if f.kind == "pillar" and f.t > 0.06 and not _seen.has(f.node):
			_seen[f.node] = true
			_aim((f.node as Node3D).global_position, 9.0)
			_label = "detonation"
			_pending = 1
			return false
	# Prefer circles (they last), then bolts; one shot per spell.
	for ar: CombatAuthority.SimArea in _fx._circles:
		if _seen.has(ar):
			continue
		var k := 1.0 - clampf(ar.timer / maxf(ar.ability.area_delay, 0.01), 0.0, 1.0)
		if k < 0.6:
			continue
		_seen[ar] = true
		_aim(ar.center, 7.5)
		_label = String(ar.ability.id)
		_pending = 2
		return false
	for p: CombatAuthority.SimProjectile in _fx._bolts:
		if _seen.has(p) or p.travelled < 4.0:
			continue
		_seen[p] = true
		_aim(p.position, 5.0)
		_label = String(p.ability.id)
		_pending = 1
		return false
	return false


func _aim(at: Vector3, d: float) -> void:
	_cam.global_position = at + Vector3(d * 0.4, d * 0.75, d * 0.6)
	_cam.look_at(at + Vector3(0, 0.6, 0))
