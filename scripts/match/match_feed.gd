class_name MatchFeed
extends RefCounted
## What just happened, in words: the kill feed and the big callouts (first
## blood, double and triple kills, a team wiped out, a tower down, a tower
## under attack). Derived from the sim's own signals; changes nothing in the
## match and is left out of telemetry. The match HUD draws it and the sound
## side picks a horn for each callout.

## A big line for everyone. `team` is who it is good news for (-1: nobody).
## `kind` picks the sound: first_blood, multi, wipe, tower, alarm.
signal callout(text: String, team: int, kind: String)
## A row for the kill feed.
signal entry_added(entry: Dictionary)

const MULTI_WINDOW := 10.0   # seconds between kills that still chain
const ALARM_EVERY := 25.0    # per structure
const FEED_LIFE := 8.0
const FEED_MAX := 5
const MULTI_NAMES := ["", "", "Double kill", "Triple kill"]

var match_ctl: MatchController
var authority: CombatAuthority
## Newest last: {t, killer, killer_team, victim, victim_team, victim_unit,
## kind}. `kind` is the callout that came with the kill ("" for a plain one).
var entries: Array[Dictionary] = []
var first_blood_done: bool = false
## Where the structure of the last alarm callout stands.
var alarm_at := Vector3.ZERO
var _streak := {}        # killer Unit -> {n, t}
var _alarm_at := {}      # structure Unit -> time of its last alarm


func _init(m: MatchController) -> void:
	match_ctl = m
	authority = m.authority
	authority.unit_died.connect(_on_died)
	authority.unit_damaged.connect(_on_damaged)


## Rows still young enough to show.
func visible_entries() -> Array[Dictionary]:
	var now := authority.time
	return entries.filter(func(e: Dictionary) -> bool: return now - float(e.t) <= FEED_LIFE)


## What to call a killer that is not a champion.
static func killer_label(killer: Unit) -> String:
	if killer == null or not is_instance_valid(killer):
		return "The field"
	match killer.def.kind:
		ChampionDef.Kind.CHAMPION:
			return killer.def.display_name
		ChampionDef.Kind.STRUCTURE:
			return "%s tower" % Palette.TEAM_NAMES[clampi(killer.team, 0, 2)]
		ChampionDef.Kind.MINION:
			return "%s minions" % Palette.TEAM_NAMES[clampi(killer.team, 0, 2)]
		ChampionDef.Kind.NEUTRAL:
			return "The Shrinebearer"
	return killer.def.display_name


func _on_died(target: Unit, killer: Unit) -> void:
	if match_ctl.over:
		return
	var now := authority.time
	if target.def.kind == ChampionDef.Kind.STRUCTURE:
		if target.def.look == ChampionDef.Look.TOWER:
			callout.emit("%s tower has fallen" % Palette.TEAM_NAMES[target.team], 1 - target.team, "tower")
		return
	if target.def.kind != ChampionDef.Kind.CHAMPION:
		return
	var by_champion := killer != null and is_instance_valid(killer) and killer.def.kind == ChampionDef.Kind.CHAMPION
	var e := {"t": now, "killer": killer_label(killer), "killer_team": killer.team if killer and is_instance_valid(killer) else -1,
		"victim": target.def.display_name, "victim_team": target.team, "victim_unit": target, "kind": ""}
	var good_for := 1 - target.team
	var down := 0
	for c in match_ctl.champions:
		if c.team == target.team and not c.alive:
			down += 1
	var n := 0
	if by_champion:
		var s: Dictionary = _streak.get(killer, {"n": 0, "t": -100.0})
		n = (int(s.n) + 1) if now - float(s.t) <= MULTI_WINDOW else 1
		_streak[killer] = {"n": n, "t": now}
	# One line per death, the biggest thing that is true.
	var text := ""
	if down >= 3:
		e.kind = "wipe"
		text = "%s is wiped out" % Palette.TEAM_NAMES[target.team]
	elif n >= 2:
		e.kind = "multi"
		text = "%s: %s" % [MULTI_NAMES[mini(n, 3)], killer.def.display_name]
	elif by_champion and not first_blood_done:
		e.kind = "first_blood"
		text = "First blood: %s" % killer.def.display_name
	if by_champion:
		first_blood_done = true
	entries.append(e)
	while entries.size() > FEED_MAX:
		entries.pop_front()
	entry_added.emit(e)
	if not text.is_empty():
		callout.emit(text, good_for, e.kind)


## A champion or a siege unit on a structure: its team hears about it, at
## most once per ALARM_EVERY for that structure.
func _on_damaged(target: Unit, _amount: float, source: Unit) -> void:
	if match_ctl.over or target.def.kind != ChampionDef.Kind.STRUCTURE or source == null or not is_instance_valid(source):
		return
	var now := authority.time
	if now - float(_alarm_at.get(target, -100.0)) < ALARM_EVERY:
		return
	_alarm_at[target] = now
	var what := "core" if target.def.look == ChampionDef.Look.CORE else "tower"
	alarm_at = target.global_position
	callout.emit("%s %s is under attack" % [Palette.TEAM_NAMES[target.team], what], 1 - target.team, "alarm")
