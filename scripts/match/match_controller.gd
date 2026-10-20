class_name MatchController
extends Node
## Runs a 3v3 lane match on the LaneMapBuilder map: spawns structures,
## champions and minion waves, heals in fountains, scales respawn timers,
## decides victory and records match statistics. Rules live here and in the
## CombatAuthority; nothing visual.

signal match_over(winner: int)
## A short line every player should see (objective warnings, captures).
signal announce(text: String, team: int)

const SCRIBE := preload("res://data/champions/ruinscribe.tres")
const WARDEN := preload("res://data/champions/oathwarden.tres")
const RUNNER := preload("res://data/champions/ashrunner.tres")
## Each team fields one of each role. Slot 0 holds the lane; slots 1 and 2
## may go for the objective.
const ROSTER: Array[ChampionDef] = [SCRIBE, WARDEN, RUNNER]
const TOWER := preload("res://data/units/tower.tres")
const CORE := preload("res://data/units/core.tres")
const MELEE := preload("res://data/units/minion_melee.tres")
const CASTER := preload("res://data/units/minion_caster.tres")
const BREAKER := preload("res://data/units/minion_breaker.tres")
const BEAST_WILD := preload("res://data/units/shrinebearer_wild.tres")
const BEAST_TAME := preload("res://data/units/shrinebearer.tres")

## Neutral objective timings (seconds).
const BEAST_FIRST := 180.0
const BEAST_EVERY := 150.0     # after a capture or a failed capture
const BEAST_WARNING := 30.0
const CAPTURE_TIME := 3.0
const CAPTURE_WINDOW := 20.0
const CAPTURE_RADIUS := 4.0
const SIEGE_LIFETIME := 75.0
const BEAST_REGEN := 60.0      # per second once nobody has fought it for BEAST_REGEN_DELAY
const BEAST_REGEN_DELAY := 8.0

const FIRST_WAVE := 3.0
const WAVE_EVERY := 25.0
const FOUNTAIN_RADIUS := 6.0
const TIME_LIMIT := 25.0 * 60.0
## Experience: shared by a team's champions within XP_RADIUS of the event.
const XP_RADIUS := 12.0
const XP_MINION := 30.0       # split among nearby enemy champions
const XP_BREAKER := 60.0
const XP_KILL := 150.0        # to the killer
const XP_ASSIST := 50.0       # to each other nearby champion of the killer's team
const XP_STRUCTURE := 120.0   # to every champion of the team
const XP_BEAST := 100.0
const XP_PER_SECOND := 1.0    # trickle so nobody falls too far behind
## Rising tide: from TIDE_START every new minion hits structures harder,
## and from TIDE_EXTRA_MELEE each wave brings one more Shieldbearer.
## It keeps a stalemate from lasting: matches should end in 10 to 15 minutes.
const TIDE_START := 5.0 * 60.0
const TIDE_PER_MINUTE := 0.35
const TIDE_MAX := 4.0
const TIDE_EXTRA_MELEE := 8.0 * 60.0

var authority: CombatAuthority
var world: Node3D
var info := MatchInfo.new()
var make_view: Callable
var human_slot: bool = true          # team 0 slot 0 is the player
var human_pick: StringName = &"ruinscribe"  # champion the player chose
var bot_seed: int = 1

var champions: Array[Unit] = []
var structures: Array[Unit] = []
var cores: Array[Unit] = [null, null]
var towers: Array[Unit] = [null, null]
var over: bool = false
var winner: int = -1

var _wave_timer: float = FIRST_WAVE

## Objective state, readable by HUD and bots.
enum Beast { SLEEPING, AWAKE, CAPTURE, OUT }
var beast_state: Beast = Beast.SLEEPING
var beast_timer: float = BEAST_FIRST
var beast: Unit
var capture_team: int = -1
var capture_progress: float = 0.0
var siege: Unit
var _siege_left: float = 0.0
var _warned: bool = false
var _wave_count: int = 0
var _tide_announced: bool = false
var stats := {}


func setup(a: CombatAuthority, parent: Node3D) -> void:
	authority = a
	world = parent
	info.match_ctl = self
	for team in 2:
		var s := 1.0 if team == 0 else -1.0
		info.fountains.append(Vector3(0, 0, s * LaneMapBuilder.FOUNTAIN_Z))
		info.hold_points.append(Vector3(0, 0, s * (LaneMapBuilder.TOWER_Z + 6.0)))
		info.lane_dirs.append(Vector3(0, 0, -s))
	_reset_stats()
	a.unit_damaged.connect(_on_damaged)
	a.unit_died.connect(_on_died)


func start() -> void:
	for team in 2:
		var s := 1.0 if team == 0 else -1.0
		var face := 0.0 if team == 0 else PI
		var tower := _spawn(TOWER, team, Vector3(0, 0, s * LaneMapBuilder.TOWER_Z), face)
		tower.controller = TowerController.new(authority)
		var core := _spawn(CORE, team, Vector3(0, 0, s * LaneMapBuilder.CORE_Z), face)
		core.protectors = [tower]
		towers[team] = tower
		cores[team] = core
		structures.append_array([tower, core])
		var roster := team_roster(team)
		for slot in 3:
			var p := info.fountain(team) + Vector3((slot - 1) * 3.0, 0, -s * 2.0)
			var u := _spawn(roster[slot], team, p, face)
			u.name = "%s_%s_%d" % [Palette.TEAM_NAMES[team], roster[slot].id, slot]
			info.slots[u] = slot
			champions.append(u)
			if not (team == 0 and slot == 0 and human_slot):
				u.controller = ChampionBot.new(authority, info, bot_seed * 100 + team * 10 + slot)
			stats.champions[u.name] = {"team": team, "champion": String(roster[slot].id), "kills": 0, "deaths": 0, "damage_to_champions": 0.0, "damage_to_structures": 0.0, "minion_kills": 0, "level": 1, "upgrade": "", "upgrade_at": -1.0}
			u.upgraded.connect(func(_slot: int, a: AbilityDef) -> void:
				stats.champions[u.name].upgrade = String(a.id)
				stats.champions[u.name].upgrade_at = snappedf(authority.time, 0.1)
				stats.events.append({"t": snappedf(authority.time, 0.1), "event": "upgrade", "unit": u.name, "pick": String(a.id)}))
			u.leveled.connect(func(lv: int) -> void: stats.champions[u.name].level = lv)


## The player's pick goes first on their team (slot 0), the others follow.
func team_roster(team: int) -> Array[ChampionDef]:
	var r: Array[ChampionDef] = ROSTER.duplicate()
	if team == 0 and human_slot:
		for i in r.size():
			if r[i].id == human_pick:
				var d: ChampionDef = r[i]
				r.remove_at(i)
				r.push_front(d)
				break
	return r


func player() -> Unit:
	return champions[0]


func _spawn(def: ChampionDef, team: int, pos: Vector3, yaw: float) -> Unit:
	var u := Unit.new()
	u.def = def
	u.team = team
	u.position = pos
	u.rotation.y = yaw
	u.name = "%s_%s_%d" % [Palette.TEAM_NAMES[team], def.id, authority.units.size()]
	world.add_child(u)
	authority.register_unit(u)
	if make_view.is_valid():
		make_view.call(u)
	return u


func _physics_process(dt: float) -> void:
	if over:
		return
	stats.duration = authority.time
	_wave_timer -= dt
	if _wave_timer <= 0.0:
		_wave_timer += WAVE_EVERY
		_spawn_wave()
	for u in champions:
		u.add_xp(XP_PER_SECOND * dt)
	for u in champions:
		if u.alive and UnitController.flat_distance(u.global_position, info.fountain(u.team)) <= FOUNTAIN_RADIUS:
			authority.heal(u, u.def.fountain_heal * dt)
	_objective(dt)
	if authority.time >= TIME_LIMIT:
		_finish(-1, "time limit")


func objective_position() -> Vector3:
	return LaneMapBuilder.CAMP


## Sleeping -> warning -> awake (fight it) -> capture circle -> reward.
## Anyone may ignore it: the reward pushes one lane, it never wins alone.
func _objective(dt: float) -> void:
	match beast_state:
		Beast.SLEEPING:
			beast_timer -= dt
			if not _warned and beast_timer <= BEAST_WARNING:
				_warned = true
				announce.emit("The Shrinebearer wakes in %d seconds" % roundi(BEAST_WARNING), -1)
			if beast_timer <= 0.0:
				beast = _spawn(BEAST_WILD, 2, objective_position() + Vector3(0, 1.2, 0), PI * 0.5)
				beast.controller = NeutralController.new(authority)
				beast_state = Beast.AWAKE
				announce.emit("The Shrinebearer is awake in the west ruins", -1)
				stats.events.append({"t": snappedf(authority.time, 0.1), "event": "objective_awake"})
		Beast.AWAKE:
			if is_instance_valid(beast) and beast.alive and authority.time - beast.last_attacked_at > BEAST_REGEN_DELAY:
				authority.heal(beast, BEAST_REGEN * dt)
		Beast.CAPTURE:
			beast_timer -= dt
			var present := [0, 0]
			for u in champions:
				if u.alive and UnitController.flat_distance(u.global_position, objective_position()) <= CAPTURE_RADIUS:
					present[u.team] += 1
			var alone := -1
			if present[0] > 0 and present[1] == 0:
				alone = 0
			elif present[1] > 0 and present[0] == 0:
				alone = 1
			if alone >= 0:
				if alone != capture_team:
					capture_team = alone
					capture_progress = 0.0
				capture_progress += dt
				if capture_progress >= CAPTURE_TIME:
					_captured(alone)
			if beast_state == Beast.CAPTURE and beast_timer <= 0.0:
				announce.emit("Nobody claimed the Shrinebearer", -1)
				_sleep()
		Beast.OUT:
			_siege_left -= dt
			if siege == null or not is_instance_valid(siege) or not siege.alive:
				_sleep()
			elif _siege_left <= 0.0:
				authority.kill(siege)  # crumbles
				_sleep()


func _on_beast_died() -> void:
	beast_state = Beast.CAPTURE
	beast_timer = CAPTURE_WINDOW
	capture_team = -1
	capture_progress = 0.0
	announce.emit("The Shrinebearer is down. Stand in its circle to claim it", -1)


func _captured(team: int) -> void:
	beast_state = Beast.OUT
	stats.objective_captures[team] += 1
	stats.events.append({"t": snappedf(authority.time, 0.1), "event": "objective_captured", "team": Palette.TEAM_NAMES[team]})
	announce.emit("%s claimed the Shrinebearer. It marches on the lane" % Palette.TEAM_NAMES[team], team)
	var s := 1.0 if team == 0 else -1.0
	var start := Vector3(-3.0, 0, s * 6.0)
	var path := PackedVector3Array([start, Vector3(0, 0, 0), Vector3(0, 0, -s * LaneMapBuilder.CORE_Z)])
	siege = _spawn(BEAST_TAME, team, start, 0.0 if team == 0 else PI)
	var sc := MinionController.new(authority, path)
	sc.structures_only = true
	siege.controller = sc
	_siege_left = SIEGE_LIFETIME


func _sleep() -> void:
	beast_state = Beast.SLEEPING
	beast_timer = BEAST_EVERY
	_warned = false
	capture_team = -1
	capture_progress = 0.0


## Structure damage multiplier for minions spawned now.
func tide_bonus() -> float:
	if authority.time < TIDE_START:
		return 1.0
	return minf(1.0 + floorf((authority.time - TIDE_START) / 60.0 + 1.0) * TIDE_PER_MINUTE, TIDE_MAX)


func _spawn_wave() -> void:
	_wave_count += 1
	if authority.time >= TIDE_START and not _tide_announced:
		_tide_announced = true
		announce.emit("The tide rises: minions now hit structures harder each minute", -1)
		stats.events.append({"t": snappedf(authority.time, 0.1), "event": "tide_rises"})
	for team in 2:
		if not cores[team].alive:
			continue
		var s := 1.0 if team == 0 else -1.0
		var path := PackedVector3Array([Vector3(0, 0, s * 46.0), Vector3(0, 0, 0), Vector3(0, 0, -s * LaneMapBuilder.CORE_Z)])
		var defs := [MELEE, MELEE, MELEE, CASTER, CASTER]
		if authority.time >= TIDE_EXTRA_MELEE:
			defs.push_front(MELEE)
		# Breach: once the enemy tower is down, every wave brings a Breaker.
		var breach: bool = towers[1 - team] != null and not towers[1 - team].alive
		for i in defs.size():
			var melee: int = defs.size() - 2
			var row := 0 if i < melee else 1
			var col := (i - (melee - 1) * 0.5) if row == 0 else (i - melee) * 2.0 - 1.0
			var p := Vector3(col * 1.4, 0, s * (49.0 + row * 2.0))
			var m := _spawn(defs[i], team, p, 0.0 if team == 0 else PI)
			m.controller = MinionController.new(authority, path)
			m.structure_bonus = tide_bonus()
		if breach:
			var b := _spawn(BREAKER, team, Vector3(0, 0, s * 47.0), 0.0 if team == 0 else PI)
			var bc := MinionController.new(authority, path)
			bc.structures_only = true
			b.controller = bc
			b.structure_bonus = tide_bonus()


func _on_damaged(target: Unit, amount: float, source: Unit) -> void:
	if over or source == null or not is_instance_valid(source):
		return
	var key: String = ChampionDef.Kind.keys()[source.def.kind].to_lower() + "_to_" + ChampionDef.Kind.keys()[target.def.kind].to_lower()
	stats.damage[key] = stats.damage.get(key, 0.0) + amount
	if stats.first_champion_fight < 0.0 and source.def.kind == ChampionDef.Kind.CHAMPION and target.def.kind == ChampionDef.Kind.CHAMPION:
		stats.first_champion_fight = authority.time
	if target.def.kind == ChampionDef.Kind.STRUCTURE:
		var gap: float = authority.time - stats._last_structure_hit
		stats.longest_gap_without_structure_damage = maxf(stats.longest_gap_without_structure_damage, gap)
		stats._last_structure_hit = authority.time
	if stats.champions.has(source.name):
		var c: Dictionary = stats.champions[source.name]
		if target.def.kind == ChampionDef.Kind.CHAMPION:
			c.damage_to_champions += amount
		elif target.def.kind == ChampionDef.Kind.STRUCTURE:
			c.damage_to_structures += amount


## Gives `amount` to `team`'s living champions within XP_RADIUS of `at`
## (split between them when `split`).
func _grant_xp(team: int, at: Vector3, amount: float, split: bool, skip: Unit = null) -> void:
	var near: Array[Unit] = []
	for u in champions:
		if u.alive and u.team == team and u != skip and UnitController.flat_distance(u.global_position, at) <= XP_RADIUS:
			near.append(u)
	for u in near:
		u.add_xp(amount / near.size() if split else amount)


func _on_died(target: Unit, killer: Unit) -> void:
	if over:
		return
	var kname: String = killer.name if killer and is_instance_valid(killer) else ""
	var at := target.global_position
	match target.def.kind:
		ChampionDef.Kind.CHAMPION:
			if killer and is_instance_valid(killer) and killer.def.kind == ChampionDef.Kind.CHAMPION:
				killer.add_xp(XP_KILL)
			_grant_xp(1 - target.team, at, XP_ASSIST, false, killer)
		ChampionDef.Kind.MINION:
			if target.team < 2:
				_grant_xp(1 - target.team, at, XP_BREAKER if target.def.look == ChampionDef.Look.BREAKER else XP_MINION, true)
		ChampionDef.Kind.NEUTRAL:
			if killer and is_instance_valid(killer) and killer.team < 2:
				_grant_xp(killer.team, at, XP_BEAST, false)
		ChampionDef.Kind.STRUCTURE:
			for u in champions:
				if u.team == 1 - target.team:
					u.add_xp(XP_STRUCTURE)
	match target.def.kind:
		ChampionDef.Kind.CHAMPION:
			# Respawns grow with match time: 6 s, plus 2 s per minute, at most 20 s.
			target.respawn_timer = minf(6.0 + floorf(authority.time / 60.0) * 2.0, 20.0)
			stats.champions[target.name].deaths += 1
			stats.kills[1 - target.team] += 1
			if stats.champions.has(kname):
				stats.champions[kname].kills += 1
			stats.events.append({"t": snappedf(authority.time, 0.1), "event": "champion_death", "unit": target.name, "killer": kname})
		ChampionDef.Kind.MINION:
			if kname.is_empty():
				return
			stats.minions_killed[1 - target.team] += 1
			if stats.champions.has(kname):
				stats.champions[kname].minion_kills += 1
		ChampionDef.Kind.NEUTRAL:
			if target == beast:
				_on_beast_died()
		ChampionDef.Kind.STRUCTURE:
			stats.events.append({"t": snappedf(authority.time, 0.1), "event": "structure_destroyed", "unit": target.name, "killer": kname})
			if target == cores[0] or target == cores[1]:
				_finish(1 - target.team, "core destroyed")


func _finish(win: int, reason: String) -> void:
	over = true
	winner = win
	stats.winner = Palette.TEAM_NAMES[win] if win >= 0 else "none"
	stats.reason = reason
	stats.duration = authority.time
	stats.waves = _wave_count
	for team in 2:
		stats.structures_left[team] = structures.filter(func(u: Unit) -> bool: return u.team == team and u.alive).size()
	authority.auto_step = false  # freeze the field on the result
	var line := JSON.stringify(_public_stats())
	print("MATCHLOG " + line)
	_save_telemetry(line)
	match_over.emit(win)


func _public_stats() -> Dictionary:
	var out := {}
	for k: String in stats:
		if not k.begins_with("_"):
			out[k] = stats[k]
	return out


func _save_telemetry(line: String) -> void:
	DirAccess.make_dir_recursive_absolute("user://telemetry")
	var path := "user://telemetry/match_%s.json" % Time.get_datetime_string_from_system().replace(":", "-")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(line)
		stats._file = ProjectSettings.globalize_path(path)


func _reset_stats() -> void:
	stats = {
		"duration": 0.0, "winner": "", "reason": "", "waves": 0,
		"kills": [0, 0], "minions_killed": [0, 0], "structures_left": [2, 2],
		"first_champion_fight": -1.0, "objective_captures": [0, 0], "longest_gap_without_structure_damage": 0.0,
		"damage": {}, "champions": {}, "events": [],
		"_last_structure_hit": 0.0, "_file": "",
	}
