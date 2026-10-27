extends SceneTree
## Summon model review: a sentry and a banner side by side under the map's
## light, the sentry tracking an aim that sweeps, firing at frame 60, both
## knocked over at frame 150. Shots at a few frames.
## xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 --fixed-fps 60 \
##   -s tools/summon_shots.gd -- --out=/tmp/sm

var _f := 0
var _out := "/tmp/sm"
var _units: Array[Unit] = []
var _cam: Camera3D
var _a: CombatAuthority


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_out)
	var w := Node3D.new()
	root.add_child(w)
	Art.environment(w)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	floor.mesh = pm
	floor.material_override = Art.ground()
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
	_a = CombatAuthority.new()
	w.add_child(_a)
	for spec: Array in [["field_sentry", Vector3(-1.4, 0, 0), 0], ["rally_banner", Vector3(1.4, 0, 0), 1]]:
		var u := Unit.new()
		u.def = load("res://data/units/%s.tres" % spec[0])
		u.team = spec[2]
		u.position = spec[1]
		w.add_child(u)
		_a.register_unit(u)
		u.add_child(SummonModel.new(u))
		_units.append(u)
	_cam = Camera3D.new()
	_cam.fov = 38
	w.add_child(_cam)
	_cam.make_current()


func _process(_delta: float) -> bool:
	_f += 1
	var s := _units[0]
	s.aim_yaw = sin(_f * 0.03) * 1.2
	if _f == 60:
		s.cast_released.emit(0, s.def.basic_attack, Vector3.ZERO)
	if _f == 150:
		for u in _units:
			u.died.emit(null)
	_cam.position = Vector3(2.6, 2.0, 3.6)
	_cam.look_at(Vector3(0, 1.3, 0))
	if _f in [20, 62, 66, 100, 158, 175]:
		root.get_viewport().get_texture().get_image().save_png("%s/s_%03d.png" % [_out, _f])
	return _f > 180
