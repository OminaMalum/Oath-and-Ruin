extends SceneTree
## Plays one champion's spell looks on cue, in a running match, and saves
## close shots of each, so a kit can be reviewed without waiting for bots to
## cast it. View only: it calls SpellFx directly and changes no sim state.
## xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 --fixed-fps 60 \
##   -s tools/fx_stage.gd -- --mode=match --spectate --warp=5 --champ=chainbound --fxshots=/tmp/fx

var _main: Node
var _fx: SpellFx
var _cam: Camera3D
var _dir := "/tmp/fx"
var _champ := "chainbound"
var _u: Unit
var _step := 0
var _wait := 0
var _shots: Array = []  # [frames from cue, label]
var _cued := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fxshots="):
			_dir = a.get_slice("=", 1)
		elif a.begins_with("--champ="):
			_champ = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_dir)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if float(_main.get("_warp_until")) > 0.0:
		return false
	if _fx == null:
		for c in root.find_children("*", "CanvasLayer", true, false):
			(c as CanvasLayer).visible = false
		_fx = root.find_children("*", "SpellFx", true, false)[0]
		for u: Unit in _fx._wv.authority.units:
			if String(u.def.id) == _champ and u.alive:
				_u = u
				break
		if _u == null:
			push_error("no %s in the match" % _champ)
			return true
		_cam = Camera3D.new()
		_cam.fov = 50.0
		root.add_child(_cam)
		_cam.make_current()
	# Hold the champion still and the camera on it while each look plays.
	var at := _u.global_position
	_cam.global_position = at + Vector3(3.2, 4.2, 4.6)
	_cam.look_at(at + Vector3(0, 0.8, -1.2))
	if _wait > 0:
		_wait -= 1
		_cued += 1
		for s: Array in _shots:
			if int(s[0]) == _cued:
				var path := "%s/%s.png" % [_dir, s[1]]
				root.get_viewport().get_texture().get_image().save_png(path)
				print("saved ", path)
		return false
	var abil := _u.def.abilities
	_cued = 0
	match _step:
		0:
			_fx._on_melee_swung(_u, _u.def.basic_attack)
			_cue(40, [[6, "lash_a"], [12, "lash_b"]])
		1:
			_fx._on_melee_swung(_u, abil[3])
			_cue(50, [[6, "seal_a"], [18, "seal_b"]])
		2:
			# A chain bolt flying out: lay a chain from the hand to a point ahead.
			var links := KitLooks.chain_links(_fx, _u.def.accent_color, 120)
			KitLooks.lay_chain(links, _fx._hand(_u), _u.global_position + _u.forward() * 6.0 + Vector3(0, 1.0, 0))
			_cue(4, [[2, "chain_bolt"]])
			get_root_timer(0.2, links)
		3:
			var links := KitLooks.chain_links(_fx, _u.def.accent_color, 110)
			KitLooks.lay_chain(links, _u.global_position + Vector3(0, _u.def.height * 0.6, 0), _u.global_position + Vector3(-5, 2.2, -4), 0.04)
			_cue(4, [[2, "grapple"]])
			get_root_timer(0.2, links)
		4:
			var ar := CombatAuthority.SimArea.new()
			ar.source = _u
			ar.ability = abil[2]
			ar.dir = _u.forward()
			var p := _u.global_position + ar.dir * (ar.ability.range * 0.5)
			ar.center = Vector3(p.x, 0, p.z)
			ar.timer = ar.ability.area_delay * 0.4
			_fx._on_area_spawned(ar)
			_fx.set_meta("stage_area", ar)
			_cue(30, [[20, "severed_lay"]])
		5:
			var ar: CombatAuthority.SimArea = _fx.get_meta("stage_area")
			ar.timer = 0.0
			_fx._on_area_detonated(ar)
			_cue(50, [[8, "severed_a"], [24, "severed_b"]])
		_:
			return true
	_step += 1
	return false


func _cue(frames: int, shots: Array) -> void:
	_wait = frames
	_shots = shots


func get_root_timer(s: float, n: Node) -> void:
	create_timer(s).timeout.connect(n.queue_free)
