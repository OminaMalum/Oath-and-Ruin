class_name ChampionBot
extends UnitController
## A lane bot for a champion. Simple, readable states:
##   RETREAT  below 25% health with an enemy champion near (15% otherwise):
##            walk to the fountain, stay until 90%
##   FIGHT    an enemy it can see is in reach: attack it, use the ability when
##            its rule says so (glyph on champions or clumps, ward when hurt,
##            dash to close on a champion or to escape)
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
## Which upgrade this bot takes at level 3 (1 or 2).
var upgrade_pick: int = 1
var _committed: bool = false  # fighting at the objective camp


func _init(a: CombatAuthority, info: MatchInfo, seed_value: int) -> void:
	authority = a
	match_info = info
	_rng.seed = seed_value
	# Seeds are match_seed * 100 + team * 10 + slot. The same champion on the
	# two teams takes opposite options (A/B test), and each slot reads its own
	# bit of the match seed, so the three picks on a team vary between seeds
	# instead of always forming the same two trios.
	var match_seed := seed_value / 100
	var team := (seed_value / 10) % 10
	var slot := seed_value % 10
	upgrade_pick = 1 + (((match_seed >> slot) & 1) + team) % 2


func get_command(unit: Unit) -> UnitCommand:
	var dt := 1.0 / Engine.physics_ticks_per_second
	_t += dt
	var c := UnitCommand.new()
	c.aim_yaw = unit.aim_yaw
	if unit.upgrade_pending:
		c.upgrade_choice = upgrade_pick  # the same path a player's 1 or 2 key takes
	var pos := unit.global_position
	var hp := unit.health / unit.max_health
	var fountain := match_info.fountain(unit.team)

	# Retreat earlier when an enemy champion is around; minions alone are
	# not worth a trip home until health is really low.
	var threat := _enemy_champion_near(unit)
	if state == State.RETREAT:
		if hp >= 0.9:
			state = State.PUSH
	elif hp < (0.25 if threat else 0.15) and not (_allied_ward(unit) and hp >= 0.12):
		state = State.RETREAT  # inside a friendly ward it holds a little longer
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
			# A dash is also an escape: use it when an enemy champion is close.
			var q := unit.get_slot(1)
			if q and q.delivery == AbilityDef.Delivery.DASH and unit.cooldowns[1] <= 0.0 and _enemy_champion_within(unit, 7.0):
				c.buttons |= UnitCommand.BTN_ABILITY_1
		return c

	# Step out of any hostile circle on the ground (it is visible to everyone).
	for ar in authority.areas:
		if ar.source and is_instance_valid(ar.source) and authority.are_enemies(unit, ar.source) \
				and ar.ability.delivery == AbilityDef.Delivery.GROUND_AREA \
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
	# Melee champions walk in to reach; ranged ones wait until in range.
	var melee := basic.range < 5.0
	var reach := basic.range + 5.0 if melee else basic.range - 1.0
	var pick: Unit = null
	var can_siege := enemy_struct != null and _wave_tanks(unit, enemy_struct) \
			and flat_distance(pos, enemy_struct.global_position) <= (reach if melee else basic.range - 1.0) + enemy_struct.def.radius
	var finishing := enemy_champ != null and enemy_champ.health / enemy_champ.max_health < 0.35 \
			and hp > 0.4 and _safe_from_tower(unit, enemy_champ.global_position)
	var edge := _numbers_edge(unit)
	if enemy_champ and (d_champ <= reach or finishing) and _safe_from_tower(unit, enemy_champ.global_position):
		pick = enemy_champ
	elif can_siege and (enemy_champ == null or edge):
		pick = enemy_struct  # outnumbered or absent defenders: hit the structure while the wave tanks
	elif weakest_minion and flat_distance(pos, weakest_minion.global_position) <= reach:
		pick = weakest_minion
	elif can_siege:
		pick = enemy_struct
	var goal := _push_position(unit, edge)
	var objective := _wants_objective(unit, enemy_champ)
	if objective:
		goal = _route_goal(unit, false)
		if pick == null and match_info.match_ctl.beast_state == MatchController.Beast.AWAKE and _route_idx >= 3:
			var b := match_info.match_ctl.beast
			if b and is_instance_valid(b) and b.alive and flat_distance(pos, b.global_position) <= maxf(basic.range, 9.0):
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
		var dist := flat_distance(pos, _target.global_position)
		for slot in range(1, unit.def.slot_count()):
			if unit.cooldowns[slot] <= 0.0 and _use_ability(unit, unit.get_slot(slot), _target, dist, hp):
				c.buttons |= UnitCommand.ability_button(slot)
				break
		# Ranged champions sidestep while fighting champions, so skillshots can miss.
		_strafe_timer -= dt
		if _strafe_timer <= 0.0:
			_strafe_timer = _rng.randf_range(0.6, 1.4)
			_strafe_dir = -_strafe_dir
		var move := Vector2(_strafe_dir, 0.0) if _target.def.kind == ChampionDef.Kind.CHAMPION and not melee else Vector2.ZERO
		if dist > (basic.range * 0.7 if melee else basic.range - 2.0):
			move = Vector2(0.0 if melee else _strafe_dir * 0.3, 1.0)  # close in
		if objective and _target.def.kind == ChampionDef.Kind.NEUTRAL and not melee:
			move = Vector2.ZERO
		# Team play: a ranged ally fights from inside a friendly ward when one is near.
		var ward := _allied_ward(unit)
		if ward and not melee and _target.def.kind == ChampionDef.Kind.CHAMPION:
			var into := ward.center - pos
			into.y = 0.0
			if into.length() > ward.ability.area_radius * 0.6:
				move = world_to_move(into.normalized(), c.aim_yaw)
			else:
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


## When to press the ability, by what it does. Same information a player has.
func _use_ability(unit: Unit, a: AbilityDef, target: Unit, dist: float, hp: float) -> bool:
	if a == null:
		return false
	var champ := target.def.kind == ChampionDef.Kind.CHAMPION
	if a.is_ultimate:
		return _use_ultimate(unit, a, target, dist, hp)
	if a.stun_duration > 0.0:
		# A stun is for champions: when they are casting, fleeing, or about to die.
		return champ and dist <= a.range + target.def.radius and (target.is_casting() \
				or target.health / target.max_health < 0.4 or hp < 0.5)
	if a.delivery == AbilityDef.Delivery.PROJECTILE and a.pierce:
		# A piercing line: a champion, or two or more enemies lined up behind each other.
		return dist <= a.range and (champ or _on_line(unit, target, a) >= 2)
	if a.delivery == AbilityDef.Delivery.PROJECTILE and a.slow_amount > 0.0:
		# A slowing throw: stick it on a champion that is getting away.
		return champ and dist <= a.range and dist > unit.def.basic_attack.range
	match a.delivery:
		AbilityDef.Delivery.GROUND_AREA:
			return dist <= a.range and (champ or _clump(unit, target.global_position, a.area_radius) >= 3)
		AbilityDef.Delivery.WARD:
			# Plant it in a champion fight: when hurt, or when an ally is in it and hurt.
			if not champ or dist > 6.0:
				return false
			return hp < 0.8 or _hurt_ally_within(unit, a.area_radius)
		AbilityDef.Delivery.DASH:
			# Gap close onto a champion just out of reach, when the fight looks good.
			var t_hp := target.health / target.max_health
			return champ and dist > unit.def.basic_attack.range + 0.5 and dist <= a.dash_distance + 1.0 \
					and (t_hp < 0.5 or hp > 0.6) and _safe_from_tower(unit, target.global_position)
	return false


## Ultimates are saved for champion fights that matter: a hurt target, two
## enemy champions together, or its own team in trouble.
func _use_ultimate(unit: Unit, a: AbilityDef, target: Unit, dist: float, hp: float) -> bool:
	if not unit.ultimate_ready_level() or target.def.kind != ChampionDef.Kind.CHAMPION:
		return false
	var t_hp := target.health / target.max_health
	var pair := _enemy_champions_within(unit, target.global_position, 5.0) >= 2
	match a.delivery:
		AbilityDef.Delivery.GROUND_AREA:
			return dist <= a.range and (pair or t_hp < 0.6)
		AbilityDef.Delivery.WARD:
			return dist <= 8.0 and (hp < 0.6 or _hurt_ally_within(unit, a.area_radius + 2.0))
		AbilityDef.Delivery.DASH:
			return dist > unit.def.basic_attack.range + 0.5 and dist <= a.dash_distance + 1.0 \
					and (pair or t_hp < 0.6) and _safe_from_tower(unit, target.global_position)
	return dist <= a.range and (pair or t_hp < 0.6)


func _enemy_champions_within(unit: Unit, at: Vector3, r: float) -> int:
	var n := 0
	for u in authority.units:
		if u.alive and authority.are_enemies(unit, u) and u.def.kind == ChampionDef.Kind.CHAMPION \
				and flat_distance(at, u.global_position) <= r:
			n += 1
	return n


## A friendly ward close enough to step into (within 6 m of its edge).
func _allied_ward(unit: Unit) -> CombatAuthority.SimArea:
	for ar in authority.areas:
		if ar.alive and ar.ability.delivery == AbilityDef.Delivery.WARD and is_instance_valid(ar.source) \
				and ar.source.team == unit.team and flat_distance(unit.global_position, ar.center) <= ar.ability.area_radius + 6.0:
			return ar
	return null


## Enemies within the line from the unit through `target` out to the range.
func _on_line(unit: Unit, target: Unit, a: AbilityDef) -> int:
	var from := unit.global_position
	var dir := Vector3(target.global_position.x - from.x, 0, target.global_position.z - from.z)
	if dir.length() < 0.1:
		return 0
	var to := from + dir.normalized() * a.range
	var n := 0
	for u in authority.units:
		if u.alive and authority.are_enemies(unit, u) and u.def.kind != ChampionDef.Kind.STRUCTURE \
				and CombatAuthority._segment_circle_t(from, to, u.global_position, u.def.radius + a.projectile_radius) >= 0.0:
			n += 1
	return n


func _hurt_ally_within(unit: Unit, r: float) -> bool:
	for u in authority.units:
		if u != unit and u.alive and u.team == unit.team and u.def.kind == ChampionDef.Kind.CHAMPION \
				and u.health / u.max_health < 0.7 and flat_distance(unit.global_position, u.global_position) <= r:
			return true
	return false


func _enemy_champion_within(unit: Unit, r: float) -> bool:
	for u in authority.units:
		if u.alive and authority.are_enemies(unit, u) and u.def.kind == ChampionDef.Kind.CHAMPION \
				and flat_distance(unit.global_position, u.global_position) <= r:
			return true
	return false


## Bots in slots 1 and 2 contest the objective when it is open, they are
## healthy and their team still has at least two champions up.
func _wants_objective(unit: Unit, enemy_champ: Unit) -> bool:
	if not match_info.objective_open() or match_info.slot_of(unit) == 0:
		_committed = false
		return false
	var hp := unit.health / unit.max_health
	# Once at the camp it stays until badly hurt; to set out it needs its
	# partner (the other objective slot) alive and healthy too, so they go as a pair.
	if _committed:
		_committed = hp >= 0.3
		return _committed
	if hp < 0.6:
		return false
	for u in authority.units:
		if u != unit and u.alive and u.team == unit.team and u.def.kind == ChampionDef.Kind.CHAMPION \
				and match_info.slot_of(u) > 0 and u.health / u.max_health >= 0.6:
			if _route_idx >= 3:
				_committed = true
			return true
	return false


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
