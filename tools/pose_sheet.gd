extends SceneTree
## Renders every champion side by side in each presentation pose and
## saves one PNG per pose, for checking poses without playing a match.
## xvfb-run godot --rendering-driver opengl3 --path . --script tools/pose_sheet.gd -- --out=/tmp/poses
## View only: units are not in a sim, their public state is set by hand.

const DEFS := ["res://data/champions/ruinscribe.tres", "res://data/champions/oathwarden.tres", "res://data/champions/ashrunner.tres",
	"res://data/champions/lanternkeeper.tres", "res://data/champions/thornwright.tres", "res://data/champions/gravebinder.tres"]
var out_dir := "/tmp/poses"
var units: Array[Unit] = []


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.6, 0.66)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	world.add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 10)
	floor.mesh = pm
	floor.material_override = Palette.mat(Palette.STONE_WARM)
	world.add_child(floor)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.position = Vector3(0, 2.4, 6.0 + DEFS.size() * 1.2)  # in front, far enough for all of them
	cam.look_at(Vector3(0, 1.1, 0))
	cam.fov = 45
	for i in DEFS.size():
		var u := Unit.new()
		u.def = load(DEFS[i])
		u.team = 0
		u.position = Vector3((i - (DEFS.size() - 1) * 0.5) * 2.4, 0, 0)
		u.rotation.y = deg_to_rad(-70.0)  # near profile, facing right, so swings read
		world.add_child(u)
		u.aim_yaw = u.rotation.y
		u.add_child(UnitView.new(u))
		units.append(u)
	var poses := ["idle", "walk", "windup_half", "windup_full", "release", "follow_through", "death"]
	for p in poses:
		await _pose(p)
	quit()


func _set_all(phase: Unit.CastPhase, timer_frac: float, moving: bool) -> void:
	for u in units:
		u.cast_slot = 0 if phase != Unit.CastPhase.NONE else -1
		u.cast_phase = phase
		var a := u.def.basic_attack
		if phase == Unit.CastPhase.WINDUP:
			u.cast_timer = a.cast_time * timer_frac
		elif phase == Unit.CastPhase.RECOVERY:
			u.cast_timer = a.recovery * timer_frac
		u.velocity = u.forward() * u.def.move_speed if moving else Vector3.ZERO


func _pose(p: String) -> void:
	match p:
		"idle": _set_all(Unit.CastPhase.NONE, 0, false)
		"walk": _set_all(Unit.CastPhase.NONE, 0, true)
		"windup_half": _set_all(Unit.CastPhase.WINDUP, 0.5, false)
		"windup_full": _set_all(Unit.CastPhase.WINDUP, 0.02, false)
		"release":
			_set_all(Unit.CastPhase.RECOVERY, 0.95, false)
			for u in units:
				u.cast_released.emit(0, u.def.basic_attack, Vector3.ZERO)
		"follow_through": _set_all(Unit.CastPhase.RECOVERY, 0.4, false)
		"death":
			_set_all(Unit.CastPhase.NONE, 0, false)
			for u in units:
				u.died.emit(null)
	var frames := 4 if p == "release" else (25 if p == "death" else 30)
	for i in frames:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, p])
	print("pose ", p)
