class_name Sounds
extends Node
## Every sound that is not a footstep goes through here. The clips are short
## original synthesised WAVs (tools/mksounds.py and tools/mksounds2.py).
##
## Two halves. The static half loads clips by name and plays interface
## sounds (menu, shop, callouts) that have no place in the world. The node
## half (one per match or court, made in main.gd) listens to the sim and
## turns its events into sound: casts by kind, heals, shields, stuns, a
## structure coming down, the player's own level, gold and recall, and a
## wind bed. Reads state only; headless runs make no players at all.

const DIR := "res://assets/sounds/%s.wav"

static var _cache := {}
static var _last_ui := {}  # name -> msec, so one event cannot machine-gun


## The clip called `name`, or null. Loaded once.
static func stream(name: String) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	var path := DIR % name
	var s: AudioStream = load(path) if ResourceLoader.exists(path) else null
	_cache[name] = s
	return s


static func silent() -> bool:
	return DisplayServer.get_name() == "headless"


## Interface sound, heard the same wherever the camera is. `gap` is the
## shortest time before the same clip may play again.
static func ui(name: String, volume_db := 0.0, gap := 0.04) -> AudioStreamPlayer:
	if silent():
		return null
	var s := stream(name)
	var tree := Engine.get_main_loop() as SceneTree
	if s == null or tree == null:
		return null
	var now := Time.get_ticks_msec()
	if now - int(_last_ui.get(name, -100000)) < int(gap * 1000.0):
		return null
	_last_ui[name] = now
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = volume_db
	p.process_mode = Node.PROCESS_MODE_ALWAYS  # menus work while the match is paused
	p.autoplay = true  # starts as it enters the tree, which may be a frame later
	p.finished.connect(p.queue_free)
	tree.root.add_child.call_deferred(p)
	return p


## Click and hover sounds for a button (menus, results, pause).
static func wire(b: BaseButton, back := false) -> void:
	b.pressed.connect(func() -> void: Sounds.ui("ui_back" if back else "ui_click", -4.0))
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			Sounds.ui("ui_hover", -6.0))
	b.focus_entered.connect(func() -> void: Sounds.ui("ui_hover", -6.0))


## Which clip a released projectile makes.
static func cast_clip(p: CombatAuthority.SimProjectile) -> String:
	if p.source.def.kind == ChampionDef.Kind.STRUCTURE:
		return "tower_shot"
	var a := p.ability
	if a.is_ultimate or a.damage >= 110.0 or a.projectile_radius >= 0.6:
		return "cast_heavy"
	var weapon := a.scaling == AbilityDef.Scaling.WEAPON \
			or (a.scaling == AbilityDef.Scaling.CHAMPION and p.source.def.power == ChampionDef.Power.WEAPON)
	return "cast_arrow" if weapon and p.source.def.kind == ChampionDef.Kind.CHAMPION else "cast_bolt"


## Which clip a melee swing makes: heavy for slams, stuns and big bodies.
static func swing_clip(caster: Unit, a: AbilityDef) -> String:
	var heavy := a.stun_duration > 0.0 or a.push_distance > 0.0 or a.cast_time >= 0.35 or a.is_ultimate \
			or caster.def.kind == ChampionDef.Kind.NEUTRAL or caster.def.look == ChampionDef.Look.BREAKER
	return "swing_heavy" if heavy else "swing"


# ------------------------------------------------------------------ node

var authority: CombatAuthority
var viewer: Unit
var world_view: WorldView
var match_ctl: MatchController

var _recall: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _stunned := {}       # Unit -> true while its stun has been sounded
var _last_at := {}       # "clip:unit id" -> authority.time of the last play
var _was_shop := false


func setup(a: CombatAuthority, local_unit: Unit, wv: WorldView, m: MatchController = null) -> void:
	authority = a
	viewer = local_unit
	world_view = wv
	match_ctl = m
	if silent():
		set_process(false)
		return
	a.melee_swung.connect(func(c: Unit, ab: AbilityDef) -> void:
		_at(swing_clip(c, ab), c, c.global_position + Vector3(0, 1.0, 0), 0.0 if _champion(c) else -9.0, 0.05))
	a.dash_started.connect(func(c: Unit, _ab: AbilityDef) -> void: _at("dash", c, c.global_position + Vector3(0, 1.0, 0), 0.0))
	a.grapple_started.connect(func(c: Unit, _ab: AbilityDef) -> void: _at("grapple", c, c.global_position + Vector3(0, 1.0, 0), 0.0))
	a.self_cast.connect(func(c: Unit, ab: AbilityDef) -> void:
		if ab.shield_mode == AbilityDef.ShieldMode.NONE:  # shields make their own sound
			_at("buff", c, c.global_position + Vector3(0, 1.0, 0), -2.0))
	a.summoned.connect(func(u: Unit, _c: Unit) -> void: _at("summon", u, u.global_position + Vector3(0, 0.5, 0), 0.0))
	# Fountains and auras heal a little every tick: only a real heal sounds.
	a.unit_healed.connect(func(t: Unit, amount: float, _src: Unit) -> void:
		if amount >= 20.0 and _champion(t):
			_at("heal", t, t.global_position + Vector3(0, 1.2, 0), -2.0, 0.6))
	a.unit_shielded.connect(func(t: Unit, amount: float) -> void:
		if amount >= 15.0:
			_at("shield", t, t.global_position + Vector3(0, 1.2, 0), -3.0, 0.6))
	a.unit_died.connect(_on_died)
	a.unit_removed.connect(func(u: Unit) -> void: _stunned.erase(u))
	_hook_viewer()
	_wind = AudioStreamPlayer.new()
	var w := stream("amb_wind") as AudioStreamWAV
	if w:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
		_wind.stream = w
		_wind.volume_db = -15.0
		add_child(_wind)
		_wind.play()


## The player's own progress: these are heard, not placed in the world.
func _hook_viewer() -> void:
	var p := viewer
	if p == null or p.def.kind != ChampionDef.Kind.CHAMPION:
		return
	p.leveled.connect(func(lv: int) -> void:
		ui("upgrade" if lv == Unit.ULT_LEVEL else "level_up", -3.0))
	p.upgraded.connect(func(_slot: int, _a: AbilityDef) -> void: ui("upgrade", -3.0))
	p.item_bought.connect(func(_it: ItemDef) -> void: ui("buy", -2.0))
	p.item_sold.connect(func(_it: ItemDef, _g: float) -> void: ui("sell", -2.0))
	# Gold with a place is a last hit or a kill; the trickle has none.
	p.gold_earned.connect(func(_g: float, at: Vector3) -> void:
		if at.is_finite():
			ui("gold", -5.0, 0.07))
	p.cast_rejected.connect(func(_slot: int, _reason: String) -> void: ui("deny", -6.0, 0.35))
	p.recall_started.connect(func() -> void:
		_stop_recall()
		_recall = ui("recall", -6.0, 0.0))
	p.recall_cancelled.connect(func(_reason: String) -> void: _stop_recall())
	p.recalled.connect(func() -> void:
		_stop_recall()
		ui("recall_done", -3.0))
	p.respawned.connect(func() -> void: ui("respawn", -3.0))


func _stop_recall() -> void:
	if _recall and is_instance_valid(_recall):
		_recall.queue_free()
	_recall = null


func _champion(u: Unit) -> bool:
	return u.def.kind == ChampionDef.Kind.CHAMPION


## A world sound at `at`, at most once per `gap` seconds for this unit.
func _at(clip: String, u: Unit, at: Vector3, volume_db: float, gap := 0.1) -> void:
	var key := "%s:%d" % [clip, u.get_instance_id()]
	if authority.time - float(_last_at.get(key, -100.0)) < gap:
		return
	_last_at[key] = authority.time
	world_view.sfx(clip, at, volume_db)


func _on_died(target: Unit, _killer: Unit) -> void:
	if target.def.kind != ChampionDef.Kind.STRUCTURE:
		return
	var core := target.def.look == ChampionDef.Look.CORE
	# Heard across the whole map, louder up close.
	world_view.sfx("core_fall" if core else "tower_fall", target.global_position + Vector3(0, 2.0, 0), 4.0, 400.0)


func _process(_delta: float) -> void:
	if authority == null:
		return
	for u in authority.units:
		var st := u.alive and u.is_stunned()
		if st and not _stunned.has(u):
			_stunned[u] = true
			if _champion(u):
				_at("stun", u, u.global_position + Vector3(0, u.def.height, 0), -1.0, 0.3)
		elif not st:
			_stunned.erase(u)
	var shop := HumanController.shop_open
	if shop != _was_shop:
		_was_shop = shop
		ui("shop_open" if shop else "ui_back", -4.0)
	if _last_at.size() > 400:
		_last_at.clear()
