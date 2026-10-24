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
## Diagnosis log (OATH_CAMLOG=1): prints target switches and large facing
## changes for the followed bot (team 0 slot 0) so camera work can be checked.
var _camlog: bool = false
var _last_yaw_logged: float = 0.0
## Aim error is a slow drift, re-rolled a few times a second, not per tick
## noise (per tick noise made a melee target's facing jitter 30 degrees).
var _aim_off: Vector3 = Vector3.ZERO
var _aim_off_timer: float = 0.0
## Grapple routes cost a few physics queries: looked for at most this often.
const GRAPPLE_LOOK := 0.25
var _grapple_look_t: float = 0.0
## A bot turns no faster than this (degrees per second), like a hand on a mouse.
const MAX_TURN_DEG := 720.0
var _last_yaw: float = 0.0
var _has_yaw: bool = false
## A champion target at the edge of reach is kept this long before it is
## dropped, so the pick does not flicker between it and nothing.
const LOSE_GRACE := 0.5
var _lose_timer: float = 0.0
## Separation: a bot steps off any unit it is standing on (allies most of
## all), the way a player would not stack on a teammate. Units do not collide
## with each other physically, so this is the only thing keeping them apart.
const SEP_MARGIN := 0.6
const SEP_MARGIN_ALLY := 1.4   # allied champions keep about two metres apart
## A ranged bot backs away while an enemy champion is closer than this.
const KITE_DISTANCE := 6.0
var kite_enabled := OS.get_environment("OATH_NOKITE") != "1"
var sep_enabled := OS.get_environment("OATH_NOSEP") != "1"


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
	_camlog = OS.get_environment("OATH_CAMLOG") == "1" and team == 0 and slot == 0
	# The map is mirrored across the lane, so the sidestep direction must be
	# too: "right" for one team is the other team's "left". With the same
	# world side for both, one team drifted toward the jungle mouth while
	# kiting and the other toward the wall, which showed up as a side bias.
	_strafe_dir = 1.0 if team == 0 else -1.0
	var env_dir := OS.get_environment("OATH_STRAFE%d" % team)  # diagnosis only: force a side per team
	if env_dir != "":
		_strafe_dir = float(env_dir)


## Easy, Normal or Hard: slower or faster reactions and looser or tighter aim.
## Damage, health and what the bot can see never change.
func set_difficulty(level: int) -> void:
	match level:
		0:
			reaction = 0.6
			aim_error = 1.5
		2:
			reaction = 0.18
			aim_error = 0.35
		_:
			reaction = 0.3
			aim_error = 0.7


func get_command(unit: Unit) -> UnitCommand:
	if not unit.alive:
		# Dead: only shopping, as a player may; no bot state moves.
		var buy := UnitCommand.new()
		buy.buy_item = _next_buy(unit)
		return buy
	var c := _decide(unit)
	# The move was decided relative to the wanted facing; keep it in world
	# terms while the facing is rate limited, so the walk direction holds.
	var world_move := move_to_world(c.move, c.aim_yaw)
	if sep_enabled and unit.recall_timer <= 0.0 and not c.pressed(UnitCommand.BTN_RECALL):
		world_move = (world_move + _separation(unit)).limit_length(1.0)
	# Turn rate limit: the facing moves toward the wanted yaw, never snaps.
	if _has_yaw:
		var step := deg_to_rad(MAX_TURN_DEG) / Engine.physics_ticks_per_second
		var diff := wrapf(c.aim_yaw - _last_yaw, -PI, PI)
		c.aim_yaw = wrapf(_last_yaw + clampf(diff, -step, step), -PI, PI)
	c.move = world_to_move(world_move, c.aim_yaw)
	_last_yaw = c.aim_yaw
	_has_yaw = true
	if _camlog:
		var d := rad_to_deg(absf(wrapf(c.aim_yaw - _last_yaw_logged, -PI, PI)))
		if d > 20.0:
			print("CAMLOG %.2f yaw jump %.0f deg (%.0f -> %.0f) state=%s target=%s" % [authority.time, d, rad_to_deg(_last_yaw_logged), rad_to_deg(c.aim_yaw), State.keys()[state], _target.name if _target else "none"])
		_last_yaw_logged = c.aim_yaw
	return c


func _decide(unit: Unit) -> UnitCommand:
	var dt := 1.0 / Engine.physics_ticks_per_second
	_t += dt
	var c := UnitCommand.new()
	c.aim_yaw = unit.aim_yaw
	if unit.upgrade_pending:
		c.upgrade_choice = upgrade_pick  # the same path a player's 1 or 2 key takes
	c.buy_item = _next_buy(unit)
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
	if _wants_recall(unit, hp):
		# Stand still and recall (the same T press a player makes); walking
		# on would cancel it, so the bot only does this when nobody is near.
		c.move = Vector2.ZERO
		if unit.recall_timer <= 0.0:
			c.buttons |= UnitCommand.BTN_RECALL
		return c
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
			# A grapple too, when a wall lies on the way home.
			if _enemy_champion_within(unit, 7.0):
				for slot in range(1, unit.def.slot_count()):
					var d := unit.get_slot(slot)
					if d and d.delivery == AbilityDef.Delivery.DASH and not d.is_ultimate and unit.cooldowns[slot] <= 0.0:
						c.buttons |= UnitCommand.ability_button(slot)
						break
					if d and d.delivery == AbilityDef.Delivery.GRAPPLE and unit.ready_in(slot) <= 0.0 and not unit.is_grappling():
						var g := _grapple_toward(unit, d, fountain, 4.0, dt)
						if g.is_finite():
							c.aim_point = g
							c.buttons |= UnitCommand.ability_button(slot)
							break
		return c

	# Step out of any hostile circle or line on the ground (visible to everyone).
	for ar in authority.areas:
		if ar.source and is_instance_valid(ar.source) and authority.are_enemies(unit, ar.source) \
				and ar.ability.delivery == AbilityDef.Delivery.GROUND_AREA \
				and CombatAuthority.in_area(ar, pos, unit.def.radius):
			var away := pos - ar.center
			away.y = 0.0
			if ar.ability.line_width > 0.0:
				# Out of a line: sideways, the short way.
				var side := Vector3(-ar.dir.z, 0.0, ar.dir.x)
				away = side * (1.0 if away.dot(side) >= 0.0 else -1.0)
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
	# Hysteresis: keep hitting the same minion while it is alive and in reach,
	# instead of flipping between two of them every tick they trade places.
	if pick and _target and pick != _target and pick.def.kind == ChampionDef.Kind.MINION \
			and _target.def.kind == ChampionDef.Kind.MINION and _target.alive \
			and flat_distance(pos, _target.global_position) <= reach + _target.def.radius:
		pick = _target
	if pick == null and _target and _target.alive and _target.def.kind == ChampionDef.Kind.CHAMPION \
			and _lose_timer < LOSE_GRACE and flat_distance(pos, _target.global_position) <= sight:
		_lose_timer += dt
		pick = _target
	else:
		_lose_timer = 0.0
	if pick != _target:
		if _camlog:
			print("CAMLOG %.2f target %s -> %s state=%s" % [authority.time, _target.name if _target else "none", pick.name if pick else "none", State.keys()[state]])
		_target = pick
		_seen_for = 0.0
	else:
		_seen_for += dt
	if objective:
		if match_info.match_ctl.beast_state == MatchController.Beast.CAPTURE and _route_idx >= 3:
			goal = match_info.match_ctl.objective_position() + Vector3(1.5, 0, (match_info.slot_of(unit) - 1.5))
	elif _route_idx > 0:
		goal = _route_goal(unit, true)  # walk back out the way it came
	_aim_off_timer -= dt
	if _aim_off_timer <= 0.0:
		_aim_off_timer = _rng.randf_range(0.3, 0.6)
		_aim_off = Vector3(_rng.randf_range(-aim_error, aim_error), 0, _rng.randf_range(-aim_error, aim_error))
	if _target and _seen_for < reaction:
		# Reacting: face the new target already (a player looks before firing),
		# keep walking, do not fire yet. Before this the bot faced its walk goal
		# for the reaction window, which flipped its facing 180 degrees on every
		# target change.
		c.aim_yaw = yaw_towards(pos, _target.global_position)
		c.aim_point = _target.global_position
		if flat_distance(pos, goal) > 1.0:
			c.move = world_to_move((goal - pos).normalized(), c.aim_yaw)
		return c
	if _target:
		state = State.FIGHT
		var aim := _target.global_position + _aim_off
		c.aim_yaw = yaw_towards(pos, aim)
		c.aim_point = aim
		c.buttons = UnitCommand.BTN_ATTACK
		var dist := flat_distance(pos, _target.global_position)
		for slot in range(1, unit.def.slot_count()):
			var ab := unit.get_slot(slot)
			if ab == null or unit.ready_in(slot) > 0.0:
				continue
			if ab.delivery == AbilityDef.Delivery.GRAPPLE:
				# Chain in onto a champion out of reach, when the fight looks good
				# and the landing is not under the enemy tower. One charge stays
				# kept for the way out, unless the kill looks likely.
				var t_hp := _target.health / _target.max_health
				var spare := unit.charges[slot] >= ab.max_charges or t_hp < 0.35
				if _target.def.kind == ChampionDef.Kind.CHAMPION and not unit.is_grappling() and spare \
						and dist > basic.range + 2.0 and dist <= ab.range + 6.0 and (t_hp < 0.5 or hp > 0.6) \
						and _safe_from_tower(unit, _target.global_position):
					var g := _grapple_toward(unit, ab, _target.global_position, 4.0, dt)
					if g.is_finite():
						c.aim_point = g
						c.buttons |= UnitCommand.ability_button(slot)
						break
				continue
			if ab.ally_heal > 0.0:
				# A healing burst goes where the hurt ally stands, not on the enemy.
				var who := _hurt_ally_for(unit, ab)
				if who and (not ab.is_ultimate or unit.ultimate_ready_level()):
					c.aim_point = who.global_position
					c.buttons |= UnitCommand.ability_button(slot)
					break
				continue
			if _use_ability(unit, ab, _target, dist, hp):
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
		elif not melee and kite_enabled and _enemy_champion_within(unit, KITE_DISTANCE) \
				and _safe_from_tower(unit, pos - move_to_world(Vector2(0, 1), c.aim_yaw) * 2.0):
			move = Vector2(_strafe_dir * 0.4, -1.0)  # ranged: back away from a close champion
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


## An aim point whose grapple lands at least `gain` metres nearer `goal`,
## trying the straight line first and then a few angles either side; INF when
## no marked wall serves (or the last look was too recent).
func _grapple_toward(unit: Unit, a: AbilityDef, goal: Vector3, gain: float, dt: float) -> Vector3:
	_grapple_look_t -= dt
	if _grapple_look_t > 0.0:
		return Vector3.INF
	_grapple_look_t = GRAPPLE_LOOK
	var pos := unit.global_position
	var to := Vector3(goal.x - pos.x, 0.0, goal.z - pos.z)
	if to.length() < 0.5:
		return Vector3.INF
	var now := to.length()
	for deg: float in [0.0, 25.0, -25.0, 50.0, -50.0]:
		var dir := to.normalized().rotated(Vector3.UP, deg_to_rad(deg))
		var aim := pos + dir * a.range
		var end := unit.grapple_endpoint(a, aim)
		if end.is_finite() and flat_distance(end, goal) <= now - gain:
			return aim
	return Vector3.INF


## When to press the ability, by what it does. Same information a player has.
func _use_ability(unit: Unit, a: AbilityDef, target: Unit, dist: float, hp: float) -> bool:
	if a == null:
		return false
	var champ := target.def.kind == ChampionDef.Kind.CHAMPION
	if a.is_ultimate:
		return _use_ultimate(unit, a, target, dist, hp)
	if a.delivery == AbilityDef.Delivery.PROJECTILE and (a.root_duration > 0.0 or a.mark_duration > 0.0 or a.charm_duration > 0.0):
		# Chains, marks and lures are for champions in reach.
		return champ and dist <= a.range
	if a.taunt_duration > 0.0:
		# A roar around itself: only when a champion is close enough to catch.
		return champ and dist <= a.area_radius
	if a.delivery == AbilityDef.Delivery.WALL:
		# A storm wall against a ranged champion's shots, when it is losing the trade.
		return champ and target.def.basic_attack and target.def.basic_attack.range > 5.0 \
				and dist > 6.0 and dist <= target.def.basic_attack.range + 2.0 and hp < 0.7
	if a.delivery == AbilityDef.Delivery.WARD and a.ally_haste > 0.0:
		# A song: sing as soon as a champion fight starts close by.
		return champ and dist <= 12.0
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
		AbilityDef.Delivery.MELEE_ARC:
			# A close sweep (Break the Seal): on a champion in reach.
			return champ and dist <= a.range + target.def.radius
		AbilityDef.Delivery.GROUND_AREA:
			return dist <= a.range and (champ or _clump(unit, target.global_position, a.area_radius) >= 3)
		AbilityDef.Delivery.WARD:
			# Plant it in a champion fight: when hurt, or when an ally is in it and hurt.
			if not champ or dist > 6.0:
				return false
			return hp < 0.8 or _hurt_ally_within(unit, a.area_radius)
		AbilityDef.Delivery.DASH:
			if a.damage <= 0.0:
				# A plain step (no damage) is only an escape from a champion too close.
				return champ and hp < 0.45 and dist < 6.0
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
			if a.ally_haste > 0.0:
				return dist <= 10.0 and (pair or t_hp < 0.6 or hp < 0.6)
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
	# Spread bots across the lane. World x for both teams (not lane relative),
	# so the formation is a mirror image across the lane like the map is:
	# slot 0 stands on the camp side for both teams.
	var side := Vector3(1, 0, 0) * (slot - 1.0) * 2.5
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


## Push away from every unit this one overlaps (capsule plus a margin).
## Allied champions push hardest: two bots in one spot read as a clump.
func _separation(unit: Unit) -> Vector3:
	var out := Vector3.ZERO
	var pos := unit.global_position
	for u in authority.units:
		if u == unit or not u.alive or u.def.kind == ChampionDef.Kind.STRUCTURE or u.def.kind == ChampionDef.Kind.DUMMY:
			continue
		var ally_champ := u.team == unit.team and u.def.kind == ChampionDef.Kind.CHAMPION
		var r := unit.def.radius + u.def.radius + (SEP_MARGIN_ALLY if ally_champ else SEP_MARGIN)
		var away := pos - u.global_position
		away.y = 0.0
		var d := away.length()
		if d >= r:
			continue
		if d < 0.05:
			away = Vector3(cos(_t * 7.0 + match_info.slot_of(unit)), 0, sin(_t * 7.0 + match_info.slot_of(unit)))
			d = 0.05
		var w := 1.2 if ally_champ else 0.8
		out += away / d * (1.0 - d / r) * w
	return out


func _clump(unit: Unit, at: Vector3, radius: float) -> int:
	var n := 0
	for u in authority.units:
		if u.alive and authority.are_enemies(unit, u) and flat_distance(at, u.global_position) <= radius + u.def.radius:
			n += 1
	return n


## The next step in the champion's build order (ItemShop.next_step), as a
## shop number, once the bot stands in its fountain with the gold for it;
## 0 otherwise.
func _next_buy(unit: Unit) -> int:
	if not unit.can_shop():
		return 0
	var idx := ItemShop.next_step(unit)
	return idx if idx > 0 and unit.buy_problem(idx).is_empty() else 0


## Recall when heading home hurt, or when the next item is affordable and
## health is down, but only far from home, with no enemy champion within
## RECALL_SAFE and no hit taken for a moment.
const RECALL_SAFE := 14.0
const RECALL_MIN_DISTANCE := 20.0
func _wants_recall(unit: Unit, hp: float) -> bool:
	if not unit.shop_point.is_finite() or unit.is_casting():
		return false
	if flat_distance(unit.global_position, match_info.fountain(unit.team)) < RECALL_MIN_DISTANCE:
		return false
	if _enemy_champion_within(unit, RECALL_SAFE) or authority.time - unit.last_attacked_at < 2.0:
		return false
	if state == State.RETREAT:
		return true
	return hp < 0.6 and _next_item_cost(unit) <= unit.gold and state == State.PUSH


func _next_item_cost(unit: Unit) -> float:
	return ItemShop.next_step_price(unit)


func commands_while_dead() -> bool:
	return true


## The most hurt allied champion (itself included) under 45% health within
## reach of a healing burst, or null.
func _hurt_ally_for(unit: Unit, a: AbilityDef) -> Unit:
	var best: Unit = null
	var best_hp := 0.45
	for u in authority.units:
		if u.alive and u.team == unit.team and u.def.kind == ChampionDef.Kind.CHAMPION \
				and flat_distance(unit.global_position, u.global_position) <= a.range:
			var f := u.health / u.max_health
			if f < best_hp:
				best_hp = f
				best = u
	return best
