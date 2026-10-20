extends Node3D
## Milestone 1 sandbox: one Ruinscribe against training dummies in the
## Proving Court. Wires the authority, controllers, views and HUD together.

const SCRIBE := preload("res://data/champions/ruinscribe.tres")
const DUMMY := preload("res://data/champions/training_dummy.tres")

var authority: CombatAuthority
var player: Unit
var rig: CameraRig
var bot: SparringBot
var hud: Hud


func _ready() -> void:
	add_child(ArenaBuilder.new())
	authority = CombatAuthority.new()
	authority.name = "CombatAuthority"
	add_child(authority)

	player = _spawn(SCRIBE, 0, Vector3(0, 0, 12), 0.0)
	bot = SparringBot.new(authority)
	bot.enabled = false
	for p: Vector3 in [Vector3(0, 0, -4), Vector3(-7, 0, -8), Vector3(7, 0, -11)]:
		var d := _spawn(DUMMY, 1, p, PI)
		d.controller = bot

	rig = CameraRig.new()
	rig.target = player
	add_child(rig)
	player.controller = HumanController.new(rig)

	var world_view := WorldView.new()
	add_child(world_view)
	world_view.setup(authority, player)

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	layer.add_child(hud)
	hud.setup(authority, player, rig, bot)

	_parse_args()
	if DisplayServer.get_name() != "headless" and not autoplay:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Command line, after "--":
##   --autoplay           the champion plays itself (DemoController)
##   --bot                dummies fight back from the start
##   --shot=PATH          save a screenshot after --shot-frames frames, then quit
##   --shot-frames=N      default 180
var autoplay := false
var _shot_path := ""
var _shot_frames := 180
var _frames := 0


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--autoplay":
			autoplay = true
			player.controller = DemoController.new(authority)
			rig.follow_unit_yaw = true
		elif arg == "--bot":
			bot.enabled = true
		elif arg.begins_with("--shot="):
			_shot_path = arg.substr(7)
		elif arg.begins_with("--shot-frames="):
			_shot_frames = int(arg.substr(14))


func _process(_delta: float) -> void:
	if _shot_path.is_empty():
		return
	_frames += 1
	if _frames == _shot_frames:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(_shot_path)
		print("saved screenshot ", _shot_path)
		get_tree().quit()


func _spawn(def: ChampionDef, team: int, pos: Vector3, yaw: float) -> Unit:
	var u := Unit.new()
	u.def = def
	u.team = team
	u.name = "%s_%d" % [def.id, authority.units.size()]
	u.position = pos
	u.rotation.y = yaw
	add_child(u)
	u.add_child(UnitView.new(u))
	authority.register_unit(u)
	return u


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_bot"):
		bot.enabled = not bot.enabled
	elif event.is_action_pressed("toggle_help"):
		hud.show_help = not hud.show_help
