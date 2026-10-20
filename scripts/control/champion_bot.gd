class_name ChampionBot
extends UnitController
## A lane bot for a champion. Simple, readable states:
##   RETREAT  below 35% health: walk to the fountain, stay until 90%
##   FIGHT    an enemy it can see is in range: attack it, glyph when it helps
##   PUSH     follow the front of its own wave, never walk under an enemy
##            tower without its own minions there to tank
## It only knows what is within its sight radius and what its own team
## knows (allied positions). Difficulty changes reaction time and aim error,
## never damage or knowledge.

enum State { PUSH, FIGHT, RETREAT, OBJECTIVE }

var authority: CombatAuthority
var match_info: MatchInfo
var state: State = State.PUSH
var sight: float = 18.0
var reaction: float = 0.3      # seconds before a newly seen enemy is engaged
var aim_error: float = 0.7     # metres of random aim offset
var _rng := RandomNumberGenerator.new()
var _t: float = 0.0
var _target: Unit
var _seen_for: float = 0.0
var _strafe_dir: float = 1.0
var _strafe_timer: float = 0.0
var _route_idx: int = 0
var _route_back: bool = false


func _init(a: CombatAuthority, info: MatchInfo, seed_value: int) -> void:
	authority = a
	match_info = info
	_rng.seed = seed_value


func get_command(unit: Unit) -> UnitCommand:
	var dt := 1.0 / Engine.physics_ticks_per_second
	_t += dt
	var c := UnitCommand.new()
	c.aim_yaw = unit.aim_yaw
	var pos := unit.global_position
	var hp := unit.health / unit.def.max_health
	var fountain := match_info.fountain(unit.team)

	# Retreat earlier when an enemy champion is around; minions alone are
	# not worth a trip home until health is really low.
	var threat := _enemy_champion_near(unit)
	if state == State.RETREAT:
		if hp >= 0.9:
			state = State.PUSH
	elif hp < (0.25 if threat else 0.15):
		state = State.RETREAT
	if _route_idx > 0 and flat_distance(pos, fountain) < 4.0:
		_route_idx = 0  # respawned at home: the old route no longer applies
	if state == State.RETREAT and _route_idx > 0:
		var back := _route_goal(unit, true)  # leave the ruins the way it came in
		c.aim_yaw = yaw_towards(pos, back)
		c.move = world_to_move((back - pos).normalized(), c.aim_yaw)
		return c
	if state == State.RETREAT:
		var dir := fountain - pos
		if flat_distance(pos, fountain) > 2.0:
			c.aim_yaw = yaw_towards(pos, fountain)
			c.move = world_to_move(dir.normalized(), c.aim_yaw)
		return c

	# Step out of any hostile circle on the ground (it is visible to everyone).
	for ar in authority.areas:
		if ar.source and is_instance_valid(ar.source) and authority.are_enemies(unit, ar.source) \
				and flat_distance(pos, ar.center) <= ar.ability.area_radius + unit.def.radius:
			var away := pos - ar.center
			away.y = 0.0
			if away.length() < 0.1:
				away = Vector3(1, 0, 0)
			c.aim_yaw = yaw_towards(pos, pos + away)
			c.move = world_to_move(away.normalized(), c.aim_yaw)
			return c

	# What can it see?
	var enemy_champ: Unit = null
	var weakest_minion: Unit = null
	var enemy_struct: Unit = null
	var d_champ := INF
	for u in authority.units:
		if not u.alive or not authority.are_enemies(unit, u) or u.def.kind == ChampionDef.Kind.DUMMY:
			continue
		var d := flat_distance(pos, u.global_position)
		if d > sight + u.def.radius:
			continue
		match u.def.kind:
			ChampionDef.Kind.CHAMPION:
				if d < d_champ:
					d_champ = d
					enemy_champ = u
			ChampionDef.Kind.MINION:
				if weakest_minion == null or u.health < weakest_minion.health:
					weakest_minion = u
			ChampionDef.Kind.STRUCTURE:
				if not u.is_protected():
					enemy_struct = u

	var basic := unit.def.basic_attack
	var pick: Unit = null
	var can_siege := enemy_struct != null and _wave_tanks(unit, enemy_struct) \
			and flat_distance(pos, enemy_struct.global_position) <= basic.range + enemy_struct.def.radius - 1.0
	var finishing := enemy_champ != null and enemy_champ.health / enemy_champ.def.max_health < 0.35 \
			and hp > 0.4 and _safe_from_tower(unit, enemy_champ.global_position)
	var edge := _numbers_edge(unit)
	if enemy_champ and (d_champ <= basic.range - 1.0 or finishing) and _safe_from_tower(unit, enemy_champ.global_position):
		pick = enemy_champ
	elif can_siege and (enemy_champ == null or edge):
		pick = enemy_struct  # outnumbered or absent defenders: hit the structure while the wave tanks
	elif weakest_minion and flat_distance(pos, weakest_minion.global_position) <= basic.range - 1.0:
		pick = weakest_minion
	elif can_siege:
		pick = enemy_struct
	var goal := _push_position(unit, edge)
	var objective := _wants_objective(unit, enemy_champ)
	if objective:
		goal = _route_goal(unit, false)
		if pick == null and match_info.match_ctl.beast_state == MatchController.Beast.AWAKE and _route_idx >= 3:
			var b := match_info.match_ctl.beast
			if b and is_instance_valid(b) and b.alive and flat_distance(pos, b.global_position) <= basic.range:
				pick = b
	if pick != _target:
		_target = pick
		_seen_for = 0.0
	else:
		_seen_for += dt
	if objective:
		if match_info.match_ctl.beast_state == MatchController.Beast.CAPTURE and _route_idx >= 3:
			goal = match_info.match_ctl.objective_position() + Vector3(1.5, 0, (match_info.slot_of(unit) - 1.5))
	elif _route_idx > 0:
		goal = _route_goal(unit, true)  # walk back out the way it came
	if _target and _seen_for >= reaction:
		state = State.FIGHT
		var aim := _target.global_position + Vector3(_rng.randf_range(-aim_error, aim_error), 0, _rng.randf_range(-aim_error, aim_error))
		c.aim_yaw = yaw_towards(pos, aim)
		c.aim_point = aim
		c.buttons = UnitCommand.BTN_ATTACK
		var glyph := unit.def.get_slot(1)
		if glyph and unit.cooldowns[1] <= 0.0 and flat_distance(pos, _target.global_position) <= glyph.range:
			if _target.def.kind == ChampionDef.Kind.CHAMPION or _clump(unit, _target.global_position, glyph.area_radius) >= 3:
				c.buttons |= UnitCommand.BTN_ABILITY_1
		# Sidestep while fighting champions, so skillshots can miss it too.
		_strafe_timer -= dt
		if _strafe_timer <= 0.0:
			_strafe_timer = _rng.randf_range(0.6, 1.4)
			_strafe_dir = -_strafe_dir
		var move := Vector2(_strafe_dir, 0.0) if _target.def.kind == ChampionDef.Kind.CHAMPION else Vector2.ZERO
		if flat_distance(pos, _target.global_position) > basic.range - 2.0:
			move = Vector2(_strafe_dir * 0.3, 1.0)  # close in on a fleeing target
		if objective and _target.def.kind == ChampionDef.Kind.NEUTRAL:
			move = Vector2.ZERO
		# Do not stand inside enemy tower range while fighting.
		if not _safe_from_tower(unit, pos):
			move = world_to_move((goal - pos).normalized(), c.aim_yaw)
		c.move = move
		return c

	state = State.OBJECTIVE if objective else State.PUSH
	if flat_distance(pos, goal) > 1.0:
		c.aim_yaw = yaw_towards(pos, goal)
		c.aim_point = goal
		c.move = world_to_move((goal - pos).normalized(), c.aim_yaw)
	return c


## Bots in slots 1 and 2 contest the objective when it is open, they are
## healthy and their team still has at least two champions up.
func _wants_objective(unit: Unit, enemy_champ: Unit) -> bool:
	if not match_info.objective_open() or match_info.slot_of(unit) == 0:
		return false
	if unit.health / unit.def.max_health < 0.5:
		return false
	var up := 0
	for u in authority.units:
		if u.alive and u.team == unit.team and u.def.kind == ChampionDef.Kind.CHAMPION:
			up += 1
	return up >= 2


## Next point on the walk to the camp (or back out of it).
func _route_goal(unit: Unit, back: bool) -> Vector3:
	var route := match_info.objective_route(unit.team)
	var pos := unit.global_position
	if back:
		var i := _route_idx - 1
		if flat_distance(pos, route[i]) < 1.5:
			_route_idx -= 1
			if _route_idx == 0:
				return _push_position(unit, false)
			i -= 1
		return route[maxi(i, 0)]
	if _route_idx < route.size() and flat_distance(pos, route[_route_idx]) < 1.5:
		_route_idx += 1
	return route[mini(_route_idx, route.size() - 1)]


func _enemy_champion_near(unit: Unit) -> bool:
	for u in authority.units:
		if u.alive and authority.are_enemies(unit, u) and u.def.kind == ChampionDef.Kind.CHAMPION \
				and flat_distance(unit.global_position, u.global_position) <= sight:
			return true
	return false


## True when more of its team's champions are up than the enemy's. Deaths
## are public (the kill feed and respawn timers), so this is not hidden info.
func _numbers_edge(unit: Unit) -> bool:
	var up := [0, 0]
	for u in authority.units:
		if u.alive and u.def.kind == ChampionDef.Kind.CHAMPION and u.team < 2:
			up[u.team] += 1
	return up[unit.team] > up[1 - unit.team]


## Behind the front-most allied minion, or at its own tower when the wave is
## gone. With a numbers edge it walks level with the wave to press the push.
func _push_position(unit: Unit, press: bool) -> Vector3:
	var lane := match_info.lane_dir(unit.team)  # unit vector toward the enemy base
	var front: Unit = null
	var best := -INF
	for u in authority.units:
		if u.alive and u.team == unit.team and u.def.kind == ChampionDef.Kind.MINION:
			var progress := u.global_position.dot(lane)
			if progress > best:
				best = progress
				front = u
	var slot := float(match_info.slot_of(unit))
	var side := Vector3(lane.z, 0, -lane.x) * (slot - 1.0) * 2.5  # spread bots across the lane
	if front:
		return front.global_position - lane * (1.0 if press else 5.0) + side
	return match_info.hold_point(unit.team) + side


func _wave_tanks(unit: Unit, structure: Unit) -> bool:
	for u in authority.units:
		if u.alive and u.team == unit.team and u.def.kind == ChampionDef.Kind.MINION \
				and flat_distance(u.global_position, structure.global_position) <= 15.0:
			return true
	return false


## True when an enemy tower would not shoot at this spot (or its wave tanks it).
func _safe_from_tower(unit: Unit, spot: Vector3) -> bool:
	for u in authority.units:
		if u.alive and authority.are_enemies(unit, u) and u.def.kind == ChampionDef.Kind.STRUCTURE \
				and u.def.basic_attack and flat_distance(spot, u.global_position) <= u.def.basic_attack.range + 1.5:
			return _wave_tanks(unit, u)
	return true


func _clump(unit: Unit, at: Vector3, radius: float) -> int:
	var n := 0
	for u in authority.units:
		if u.alive and authority.are_enemies(unit, u) and flat_distance(at, u.global_position) <= radius + u.def.radius:
			n += 1
	return n
