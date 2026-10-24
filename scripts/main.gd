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
##   --no-predict                       client: turn off own-champion prediction
##   --netbot=MODE                      client test driver: attack | strafe | idle | cheat
##   --bot                              dummies fight back from the start
##   --quit-after-secs=S                exit after S seconds
##   --champion=ID                      any id in data/champions (match and court)
##   --seed=N                           match: bot seed (lineup and bot choices); random when left out
##   --difficulty=0|1|2                 match: enemy bots Easy, Normal or Hard (default: the saved setting)
##   --items=adventurer|classic         shop catalog (default: the saved setting; network play: classic)
##   --pause                            open the pause menu (screenshots)
##   --settings                         menu: open the settings panel (screenshots)
##   --lineup=A,B,C                     match: these three champions on both teams
##   --map=three                        match: the rough three lane test map
##   --shot=PATH [--shot-frames=N]      save a screenshot and quit
##   --shop[=finished]                  open the shop panel (screenshots), on its second page
##   --scoreboard                       show the scoreboard (screenshots)
##   --warp=S                           run without drawing until S seconds (needs --fixed-fps 60)
##   --follow=N                         spectate: follow champion N (0-2 Oath, 3-5 Ruin)
##   --camaudit                         spectate: measure camera obstruction and pops, print CAMAUDIT at the end
##   --overview-at=S                    recordings: switch to the high spectator view at S seconds

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
var pause_menu: PauseMenu

var autoplay := false
var args := {}
var _shot_path := ""
var _shot_frames := 180
var _warp_until := -1.0
var _frames := 0
var _quit_after := -1.0
var _elapsed := 0.0
var _overview_at := -1.0


func _ready() -> void:
	Settings.load_once()
	Settings.apply()
	_parse_args()
	# One catalog for the whole match. Network peers default to classic so a
	# server and its clients always agree.
	var net_play := args.has("server") or args.has("connect")
	var items_arg: String = args.get("items", "classic" if net_play else ("adventurer" if Settings.adventurer_items else "classic"))
	ItemShop.use_adventurer(items_arg == "adventurer")
	if args.has("champion"):
		Session.champion = StringName(args.champion)
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
	if mode == "match" and args.get("map", "") == "three":
		mode = "match3"
	var map: Node3D = LaneMapBuilder.new() if mode == "match" else (ThreeLaneBuilder.new() if mode == "match3" else ArenaBuilder.new())
	add_child(map)
	GrappleAnchors.mark(map, LaneMapBuilder.BASE_Z + 1.0 if mode == "match" else (ThreeLaneBuilder.BASE_Z + 1.0 if mode == "match3" else INF))
	authority = CombatAuthority.new()
	authority.name = "CombatAuthority"
	add_child(authority)
	bot = SparringBot.new(authority)
	bot.enabled = args.has("bot")

	if args.has("server"):
		_start_server()
	elif args.has("connect"):
		_start_client()
	elif mode == "match" or mode == "match3":
		_start_match(mode == "match3")
	else:
		_start_offline()


func _on_menu(mode: String) -> void:
	if mode == "quit":
		get_tree().quit()
		return
	Session.mode = mode
	get_tree().reload_current_scene()


func _start_match(three_lane := false) -> void:
	match_ctl = MatchController.new()
	match_ctl.name = "Match"
	match_ctl.three_lane = three_lane
	match_ctl.human_slot = not (args.has("spectate") or autoplay)
	match_ctl.human_pick = Session.champion
	# From the menu every match draws a new seed: a new lineup and new teammates.
	match_ctl.bot_seed = int(args.seed) if args.has("seed") else randi_range(1, 99999)
	match_ctl.difficulty = clampi(int(args.get("difficulty", str(Settings.difficulty))), 0, 2)
	if args.has("lineup"):
		for id in (args.lineup as String).split(","):
			match_ctl.lineup_ids.append(StringName(id))
	var headless := DisplayServer.get_name() == "headless"
	if not headless:
		match_ctl.make_view = func(u: Unit) -> void: u.add_child(UnitView.new(u))
	add_child(match_ctl)
	match_ctl.setup(authority, self)
	match_ctl.start()
	player = match_ctl.player()
	if args.has("spectate") and args.has("follow"):
		# Recordings: follow champion N (0-2 Oath, 3-5 Ruin) instead of the first.
		player = match_ctl.champions[clampi(int(args.follow), 0, match_ctl.champions.size() - 1)]
	if headless:
		match_ctl.match_over.connect(func(_w: int) -> void: get_tree().quit())
		return
	_setup_presentation(player)
	if match_ctl.human_slot:
		player.controller = HumanController.new(rig)
	else:
		rig.follow_unit_yaw = true
	rig.audit = args.has("camaudit")
	HumanController.shop_open = false
	if args.has("shop"):
		HumanController.set_shop(true)
	MatchHud.force_scoreboard = args.has("scoreboard")
	var layer := CanvasLayer.new()
	add_child(layer)
	var mh := MatchHud.new()
	layer.add_child(mh)
	mh.setup(match_ctl, rig)
	if match_ctl.human_slot and not args.has("seed"):
		match_ctl.match_over.connect(func(w: int) -> void: Settings.record(w == 0))


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	autoplay = args.has("autoplay")
	_shot_path = args.get("shot", "")
	_shot_frames = int(args.get("shot-frames", "180"))
	_warp_until = float(args.get("warp", "-1"))
	if _warp_until > 0.0:
		# Skip drawing instead of scaling time: Engine.time_scale stretches every
		# physics step (32x made each tick 0.53 s) and changed match outcomes.
		RenderingServer.render_loop_enabled = false
	_quit_after = float(args.get("quit-after-secs", "-1"))
	_overview_at = float(args.get("overview-at", "-1"))


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
	player.def = Session.champion_def()
	player.team = 0
	player.name = String(player.def.id)
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
	net.prediction_enabled = not args.has("no-predict")
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
	# Respawn moves the champion across the map: cut to it instead of the
	# camera flying 90 m over the walls (seen in the camera audit).
	local_unit.respawned.connect(func() -> void: rig.snap_to_target())
	local_unit.recalled.connect(func() -> void: rig.snap_to_target())
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
	if args.get("shop", "") == "finished":
		hud.shop_tab = 1  # screenshots of the second shop page
	if DisplayServer.get_name() != "headless" and not rig.follow_unit_yaw:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var top := CanvasLayer.new()
	top.layer = 10
	add_child(top)
	pause_menu = PauseMenu.new()
	pause_menu.setup(match_ctl, net == null)
	top.add_child(pause_menu)


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
	if rig and rig.audit and match_ctl and match_ctl.over and _quit_after != 0.0:
		print("CAMAUDIT ", JSON.stringify(rig.audit_stats))
		_quit_after = 0.0
		get_tree().quit()
		return
	if _quit_after > 0.0 and _elapsed >= _quit_after:
		_quit_after = -1.0
		if net:
			net.leave()
			await get_tree().create_timer(0.3).timeout  # let the disconnect go out
		get_tree().quit()
		return
	if _overview_at > 0.0 and rig and authority.time >= _overview_at:
		_overview_at = -1.0
		rig.overview = true
	if _warp_until > 0.0 and (authority.time >= _warp_until or (match_ctl and match_ctl.over)):
		_warp_until = -1.0
		RenderingServer.render_loop_enabled = true
		_frames = 0  # count shot frames from the end of the warp
	if _shot_path.is_empty() or _warp_until > 0.0:
		return
	_frames += 1
	if _frames == _shot_frames:
		if args.has("pause") and pause_menu:
			pause_menu.open()
			await get_tree().create_timer(0.3, true).timeout  # runs while paused
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_shot_path)
		print("saved screenshot ", _shot_path)
		get_tree().quit()
