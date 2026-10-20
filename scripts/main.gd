extends Node3D
## Entry point. Offline by default: one Ruinscribe against training dummies
## in the Proving Court. Network modes (Gate 1) are chosen on the command
## line after "--":
##   --mode=match|court                 skip the menu (match = 3v3 bot match)
##   --spectate                         match with all six champions as bots
##   --server [--port=N]                dedicated server (run with --headless)
##   --connect=HOST[:PORT] [--token=ID] client
##   --lag=MS --jitter=MS --loss=0..1   simulated network conditions (this process's sends)
##   --netlog                           print NETLOG lines (tests)
##   --autoplay                         the local champion plays itself
##   --netbot=MODE                      client test driver: attack | strafe | idle | cheat
##   --bot                              dummies fight back from the start
##   --quit-after-secs=S                exit after S seconds
##   --shot=PATH [--shot-frames=N]      save a screenshot and quit
##   --warp=S                           run the sim 32x fast until S seconds (captures)

const SCRIBE := preload("res://data/champions/ruinscribe.tres")
const DUMMY := preload("res://data/champions/training_dummy.tres")
const DUMMY_SPOTS := [Vector3(0, 0, -4), Vector3(-7, 0, -8), Vector3(7, 0, -11)]

var authority: CombatAuthority
var player: Unit
var rig: CameraRig
var bot: SparringBot
var hud: Hud
var net: NetSession
var world_view: WorldView
var match_ctl: MatchController

var autoplay := false
var args := {}
var _shot_path := ""
var _shot_frames := 180
var _warp_until := -1.0
var _frames := 0
var _quit_after := -1.0
var _elapsed := 0.0


func _ready() -> void:
	_parse_args()
	var mode: String = args.get("mode", Session.mode)
	if args.has("server") or args.has("connect"):
		mode = "court"
	if mode.is_empty():
		if DisplayServer.get_name() == "headless":
			mode = "court"
		else:
			var menu := MainMenu.new()
			var layer := CanvasLayer.new()
			add_child(layer)
			layer.add_child(menu)
			menu.chosen.connect(_on_menu)
			return
	add_child(LaneMapBuilder.new() if mode == "match" else ArenaBuilder.new())
	authority = CombatAuthority.new()
	authority.name = "CombatAuthority"
	add_child(authority)
	bot = SparringBot.new(authority)
	bot.enabled = args.has("bot")

	if args.has("server"):
		_start_server()
	elif args.has("connect"):
		_start_client()
	elif mode == "match":
		_start_match()
	else:
		_start_offline()


func _on_menu(mode: String) -> void:
	if mode == "quit":
		get_tree().quit()
		return
	Session.mode = mode
	get_tree().reload_current_scene()


func _start_match() -> void:
	match_ctl = MatchController.new()
	match_ctl.name = "Match"
	match_ctl.human_slot = not (args.has("spectate") or autoplay)
	match_ctl.bot_seed = int(args.get("seed", "1"))
	var headless := DisplayServer.get_name() == "headless"
	if not headless:
		match_ctl.make_view = func(u: Unit) -> void: u.add_child(UnitView.new(u))
	add_child(match_ctl)
	match_ctl.setup(authority, self)
	match_ctl.start()
	player = match_ctl.player()
	if headless:
		match_ctl.match_over.connect(func(_w: int) -> void: get_tree().quit())
		return
	_setup_presentation(player)
	if match_ctl.human_slot:
		player.controller = HumanController.new(rig)
	else:
		rig.follow_unit_yaw = true
	var layer := CanvasLayer.new()
	add_child(layer)
	var mh := MatchHud.new()
	layer.add_child(mh)
	mh.setup(match_ctl, rig)


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	autoplay = args.has("autoplay")
	_shot_path = args.get("shot", "")
	_shot_frames = int(args.get("shot-frames", "180"))
	_warp_until = float(args.get("warp", "-1"))
	if _warp_until > 0.0:
		Engine.max_physics_steps_per_frame = 32
		Engine.time_scale = 32.0
	_quit_after = float(args.get("quit-after-secs", "-1"))


func _spawn_dummies() -> void:
	for p: Vector3 in DUMMY_SPOTS:
		var d := Unit.new()
		d.def = DUMMY
		d.team = 1
		d.position = p
		d.rotation.y = PI
		d.name = "dummy_%d" % authority.units.size()
		add_child(d)
		authority.register_unit(d)
		d.controller = bot
		if DisplayServer.get_name() != "headless":
			d.add_child(UnitView.new(d))


func _start_offline() -> void:
	player = Unit.new()
	player.def = SCRIBE
	player.team = 0
	player.name = "ruinscribe"
	player.position = Vector3(0, 0, 12)
	add_child(player)
	player.add_child(UnitView.new(player))
	authority.register_unit(player)
	_spawn_dummies()
	_setup_presentation(player)
	player.controller = DemoController.new(authority) if autoplay else HumanController.new(rig)


func _make_net() -> NetSession:
	net = NetSession.new()
	net.name = "Net"  # same node path on server and clients, required for RPCs
	net.authority = authority
	net.world = self
	net.champion_def = SCRIBE
	net.lag_ms = float(args.get("lag", "0"))
	net.jitter_ms = float(args.get("jitter", "0"))
	net.loss = float(args.get("loss", "0"))
	net.log_enabled = args.has("netlog")
	return net


func _start_server() -> void:
	_make_net()
	# Two seats facing each other across the court; more joiners reuse them.
	net.spawn_points = [
		Transform3D(Basis(), Vector3(-3, 0, 10)),
		Transform3D(Basis(Vector3.UP, PI), Vector3(3, 0, -14)),
	]
	add_child(net)
	_spawn_dummies()
	var port := int(args.get("port", str(NetSession.DEFAULT_PORT)))
	var err := net.start_server(port)
	if err != OK:
		push_error("Server could not listen on %d: %s" % [port, error_string(err)])
		get_tree().quit(2)
		return
	print("Server listening on port %d" % port)


func _start_client() -> void:
	_make_net()
	net.token = args.get("token", "player%d" % (Time.get_ticks_usec() % 100000))
	authority.auto_step = false  # the server owns the simulation
	var headless := DisplayServer.get_name() == "headless"
	if not headless:
		net.make_view = func(u: Unit) -> void: u.add_child(UnitView.new(u))
	add_child(net)
	var mode: String = args.get("netbot", "")
	if mode.is_empty() and (autoplay or headless):
		mode = "attack"
	net.local_unit_ready.connect(_on_local_unit)
	if mode.is_empty():
		rig = CameraRig.new()
		add_child(rig)
		net.local_controller = HumanController.new(rig)
	else:
		net.local_controller = NetTestDriver.new(authority, mode)
	var target: String = args.get("connect")
	var parts := target.split(":")
	var port := int(parts[1]) if parts.size() > 1 else NetSession.DEFAULT_PORT
	net.start_client(parts[0] if not parts[0].is_empty() else "127.0.0.1", port)


func _on_local_unit(u: Unit) -> void:
	player = u
	if DisplayServer.get_name() == "headless" or hud != null:
		return
	_setup_presentation(u)
	net.status_changed.connect(func(t: String) -> void: hud.status = t)


func _setup_presentation(local_unit: Unit) -> void:
	if rig == null:
		rig = CameraRig.new()
		add_child(rig)
	rig.target = local_unit
	rig.snap_to_target()
	rig.follow_unit_yaw = autoplay or args.has("netbot")
	world_view = WorldView.new()
	add_child(world_view)
	world_view.setup(authority, local_unit)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	layer.add_child(hud)
	hud.setup(authority, local_unit, rig, bot if net == null and match_ctl == null else null)
	if DisplayServer.get_name() != "headless" and not rig.follow_unit_yaw:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if match_ctl and match_ctl.over:
		if event.is_action_pressed("restart"):
			get_tree().reload_current_scene()
		elif event.is_action_pressed("menu"):
			Session.mode = ""
			get_tree().reload_current_scene()
		return
	if event.is_action_pressed("toggle_bot") and net == null and match_ctl == null:
		bot.enabled = not bot.enabled
	elif event.is_action_pressed("toggle_help") and hud:
		hud.show_help = not hud.show_help


func _process(delta: float) -> void:
	_elapsed += delta
	if _quit_after > 0.0 and _elapsed >= _quit_after:
		_quit_after = -1.0
		if net:
			net.leave()
			await get_tree().create_timer(0.3).timeout  # let the disconnect go out
		get_tree().quit()
		return
	if _warp_until > 0.0 and (authority.time >= _warp_until or (match_ctl and match_ctl.over)):
		_warp_until = -1.0
		Engine.time_scale = 1.0
		_frames = 0  # count shot frames from the end of the warp
	if _shot_path.is_empty() or _warp_until > 0.0:
		return
	_frames += 1
	if _frames == _shot_frames:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_shot_path)
		print("saved screenshot ", _shot_path)
		get_tree().quit()
