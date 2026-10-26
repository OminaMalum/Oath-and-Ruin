class_name CombatAuthority
extends Node
## The single owner of combat rules: it steps every unit on the fixed physics
## tick, moves projectiles, resolves areas, applies damage with team rules,
## and handles death and respawn. Nothing else changes health.

signal projectile_spawned(p: SimProjectile)
signal projectile_ended(p: SimProjectile, hit_point: Vector3)
signal area_spawned(a: SimArea)
signal area_detonated(a: SimArea)
signal unit_damaged(target: Unit, amount: float, source: Unit)
## Health an ability restored (source set) or a shield an item gave (match stats).
signal unit_healed(target: Unit, amount: float, source: Unit)
signal unit_shielded(target: Unit, amount: float)
signal unit_died(target: Unit, killer: Unit)
signal unit_respawned(target: Unit)
signal unit_removed(target: Unit)
## Damage refused because the target is protected (a core behind its tower).
signal damage_blocked(target: Unit, source: Unit)
## A melee arc was released (for swing visuals; hits come as unit_damaged).
signal melee_swung(caster: Unit, a: AbilityDef)
## A dash started (for trail visuals; the unit's own position replicates).
signal dash_started(caster: Unit, a: AbilityDef)
## A grapple launched (the unit holds grapple_anchor while it travels).
signal grapple_started(caster: Unit, a: AbilityDef)
## A SELF ability went off (Still Water's brace).
signal self_cast(caster: Unit, a: AbilityDef)
## A summon was placed (a sentry, a banner).
signal summoned(u: Unit, caster: Unit)

## Tests turn this off and call step() themselves.
@export var auto_step: bool = true

var units: Array[Unit] = []
var projectiles: Array[SimProjectile] = []
var areas: Array[SimArea] = []
var _next_fx_id: int = 1
var tick: int = 0
## Seconds of simulated time since start.
var time: float = 0.0
var _next_unit_id: int = 1
## Makes a summoned unit: func(def, team, pos, yaw) -> Unit. The match sets
## it (names, views); without one the authority adds a bare Unit beside itself.
var spawner: Callable


class SimProjectile:
	extends RefCounted
	var id: int = 0
	var source: Unit
	var ability: AbilityDef
	var position: Vector3
	var direction: Vector3
	var target: Unit  # homing only
	var travelled: float = 0.0
	var alive: bool = true
	var hit: Array[Unit] = []  # piercing shots: already struck


class SimArea:
	extends RefCounted
	var id: int = 0
	var source: Unit
	var ability: AbilityDef
	var center: Vector3
	## Flat unit vector from the caster to the centre at release (walls lie across it).
	var dir: Vector3 = Vector3.FORWARD
	var timer: float
	var alive: bool = true
	## Damage multiplier for the burst (RESIDUAL charges spent on the cast).
	var power: float = 1.0


func register_unit(u: Unit, net_id: int = 0) -> void:
	u.net_id = net_id if net_id > 0 else _next_unit_id
	_next_unit_id = maxi(_next_unit_id, u.net_id + 1)
	units.append(u)


func find_unit(net_id: int) -> Unit:
	for u in units:
		if u.net_id == net_id:
			return u
	return null


## Removes a unit and anything it has in flight, so nothing refers to a
## freed node.
func remove_unit(u: Unit) -> void:
	units.erase(u)
	for p in projectiles:
		if p.source == u:
			_end_projectile(p, p.position)
	projectiles = projectiles.filter(func(x: SimProjectile) -> bool: return x.alive)
	for ar in areas:
		if ar.source == u:
			ar.alive = false
	areas = areas.filter(func(x: SimArea) -> bool: return x.alive)
	unit_removed.emit(u)
	u.queue_free()


func _physics_process(delta: float) -> void:
	if auto_step:
		step(delta)


func step(dt: float) -> void:
	tick += 1
	time += dt
	# Alternate the stepping order every tick so neither team always acts first
	# (a fixed order let Oath win 6 of 8 mirrored bot matches).
	var order := units.duplicate()
	if tick % 2 == 0:
		order.reverse()
	for u in order:
		if u.alive:
			var cmd: UnitCommand = u.controller.get_command(u) if u.controller else UnitCommand.new()
			u.sim_step(cmd, dt, self)
		elif u.def.respawn_time >= 0.0:
			if u.controller and u.controller.commands_while_dead():
				u.sim_step(u.controller.get_command(u), dt, self)  # only shopping applies
			u.respawn_timer -= dt
			if u.respawn_timer <= 0.0:
				u.respawn()
				unit_respawned.emit(u)
		elif u.def.kind == ChampionDef.Kind.MINION or u.def.kind == ChampionDef.Kind.SUMMON:
			u.corpse_timer -= dt
			if u.corpse_timer <= 0.0:
				remove_unit(u)
	_step_projectiles(dt)
	_step_areas(dt)
	_step_passives(dt)
	_step_summons(dt)
	_step_item_effects(dt)


func are_enemies(a: Unit, b: Unit) -> bool:
	return a.team != b.team


func release_ability(caster: Unit, a: AbilityDef, target: Vector3, target_unit: Unit = null) -> void:
	var q := a == caster.get_slot(1)
	if caster.def.passive == ChampionDef.Passive.MEASURED and a != caster.def.basic_attack:
		caster.passive_primed_until = time + PRIMED_TIME
	if caster.def.passive == ChampionDef.Passive.STAND_BEHIND and (q or a == caster.get_slot(2)):
		caster.passive_primed_until = time + PRIMED_TIME
	if caster.def.passive == ChampionDef.Passive.REFRAIN and (q or a == caster.get_slot(2)):
		var slot := 1 if q else 2
		if caster.refrain_slot == 3 - slot and time - caster.refrain_at <= REFRAIN_TIME:
			a = empowered(a)  # the second of the pair; the sequence starts over
			caster.refrain_slot = -1
		else:
			caster.refrain_slot = slot
			caster.refrain_at = time
	if q and caster.def.passive == ChampionDef.Passive.FLAME and caster.passive_stacks >= 1.0:
		for u in units:
			if u.alive and u.team == caster.team and u.def.kind == ChampionDef.Kind.CHAMPION \
					and _flat(u.global_position, target) <= a.area_radius + u.def.radius:
				give_shield(caster, u, caster.def.passive_value * floorf(caster.passive_stacks), PASSIVE_SHIELD_TIME)
		caster.passive_stacks = 0.0
	if q and caster.def.passive == ChampionDef.Passive.FURY and caster.passive_stacks >= FURY_MAX:
		caster.passive_stacks = 0.0
		heal(caster, caster.max_health * caster.def.passive_value, caster)  # once, however many it hits
	if a.self_quick > 0.0:
		caster.apply_quick(a.self_quick, a.self_quick_duration)
	if caster.def.passive == ChampionDef.Passive.CALIBRATE and q:
		caster.passive_marks["calib"] = floorf(caster.passive_stacks)  # this cast's bonus
		caster.passive_stacks = 0.0
	match a.delivery:
		AbilityDef.Delivery.PROJECTILE:
			var p := SimProjectile.new()
			p.id = _next_fx_id
			_next_fx_id += 1
			p.source = caster
			p.ability = a
			p.position = caster.muzzle_position()
			var flat := Vector3(target.x - caster.global_position.x, 0.0, target.z - caster.global_position.z)
			p.direction = flat.normalized() if flat.length() > 0.01 else caster.forward()
			p.target = target_unit if a.homing else null
			projectiles.append(p)
			projectile_spawned.emit(p)
		AbilityDef.Delivery.GROUND_AREA, AbilityDef.Delivery.WARD, AbilityDef.Delivery.WALL:
			var ar := SimArea.new()
			ar.id = _next_fx_id
			_next_fx_id += 1
			ar.source = caster
			ar.ability = a
			ar.center = Vector3(target.x, 0.0, target.z)
			var d := Vector3(target.x - caster.global_position.x, 0.0, target.z - caster.global_position.z)
			ar.dir = d.normalized() if d.length() > 0.1 else caster.forward()
			if a.line_width > 0.0:
				# A line from the caster along the aim: centre at its middle.
				var p := caster.global_position + ar.dir * (a.range * 0.5)
				ar.center = Vector3(p.x, 0.0, p.z)
			ar.timer = area_lifetime(a)
			if q and caster.def.passive == ChampionDef.Passive.RESIDUAL and a.delivery == AbilityDef.Delivery.GROUND_AREA:
				ar.power = 1.0 + caster.def.passive_value * floorf(caster.passive_stacks)
				caster.passive_stacks = 0.0
			areas.append(ar)
			area_spawned.emit(ar)
		AbilityDef.Delivery.MELEE_ARC:
			melee_swung.emit(caster, a)
			var fwd := caster.forward()
			var half := deg_to_rad(a.arc_degrees * 0.5)
			for u in units.duplicate():
				if not u.alive or u == caster or (a.hits_enemies_only and not are_enemies(caster, u)):
					continue
				var to := Vector3(u.global_position.x - caster.global_position.x, 0.0, u.global_position.z - caster.global_position.z)
				if to.length() > a.range + u.def.radius:
					continue
				if a.arc_degrees < 360.0 and to.length() > u.def.radius and absf(fwd.signed_angle_to(to, Vector3.UP)) > half:
					continue
				if apply_damage(caster, u, a.damage, a) and a.push_distance > 0.0:
					_push(u, caster.global_position, a.push_distance)
		AbilityDef.Delivery.SELF:
			if a.brace_duration > 0.0:
				caster.apply_brace(a.brace_reduction, a.brace_duration)
			_self_shields(caster, a)
			if a.transform_duration > 0.0:
				caster.start_transform(a)
			self_cast.emit(caster, a)
		AbilityDef.Delivery.SUMMON:
			_summon(caster, a, target)
			if caster.def.passive == ChampionDef.Passive.REMEMBRANCE and caster.passive_stacks >= 1.0:
				# Names Remembered: every own summon lasts longer, the new one too.
				var extra := caster.def.passive_value * floorf(caster.passive_stacks)
				caster.passive_stacks = 0.0
				for u in units:
					if u.alive and u.summoner == caster and u.life_timer > 0.0:
						u.life_timer += extra
		AbilityDef.Delivery.DASH:
			caster.start_dash(a, target)
			dash_started.emit(caster, a)
		AbilityDef.Delivery.GRAPPLE:
			if caster.start_grapple(a, target):
				grapple_started.emit(caster, a)
	# Stormthread Spindle: casting an ability primes the next basic hit.
	if a != caster.def.basic_attack and not caster.items.is_empty() and item_with(caster, ItemDef.Passive.STORMTHREAD):
		caster.item_counters["stormthread"] = time


## A grapple reached its wall. MOMENTUM: a long enough route primes the
## next basic hit on a champion.
func grapple_finished(u: Unit, a: AbilityDef) -> void:
	if u.def.passive == ChampionDef.Passive.MOMENTUM \
			and _flat(u.global_position, u.grapple_from) >= a.grapple_min_travel:
		u.passive_primed_until = time + MOMENTUM_TIME


## Is a circle at `pos` (radius r) inside the area? Lines are rectangles
## along ar.dir, `range` long and line_width wide; the rest are circles.
static func in_area(ar: SimArea, pos: Vector3, r: float) -> bool:
	var a := ar.ability
	if a.line_width > 0.0:
		var to := Vector3(pos.x - ar.center.x, 0.0, pos.z - ar.center.z)
		var along := absf(to.dot(ar.dir))
		var across := absf(to.dot(Vector3(-ar.dir.z, 0.0, ar.dir.x)))
		return along <= a.range * 0.5 + r and across <= a.line_width * 0.5 + r
	return Vector2(pos.x - ar.center.x, pos.z - ar.center.z).length() <= a.area_radius + r


## Ground areas burst after their delay; wards and walls stand for their duration.
static func area_lifetime(a: AbilityDef) -> float:
	return a.ward_duration if _stands(a) else a.area_delay


static func _stands(a: AbilityDef) -> bool:
	return a.delivery == AbilityDef.Delivery.WARD or a.delivery == AbilityDef.Delivery.WALL


## The two flat end points of a wall.
static func wall_ends(ar: SimArea) -> Array[Vector3]:
	var side := Vector3(-ar.dir.z, 0.0, ar.dir.x) * (ar.ability.wall_length * 0.5)
	return [ar.center - side, ar.center + side]


## Called by a dashing unit each tick with where it started the tick: every
## enemy it passes through takes the dash damage once.
func dash_contact(u: Unit, from: Vector3) -> void:
	var a := u.dash_ability
	if a == null or a.damage <= 0.0:
		return
	for e in units:
		if not e.alive or not are_enemies(u, e) or e in u.dash_hit:
			continue
		if _segment_circle_t(from, u.global_position, e.global_position, e.def.radius + u.def.radius) >= 0.0:
			u.dash_hit.append(e)
			apply_damage(u, e, a.damage, a)
			if a.stop_on_champion and e.def.kind == ChampionDef.Kind.CHAMPION:
				# Break Their Line: the charge ends on the first champion and drives it back.
				if a.push_distance > 0.0 and e.alive:
					e.displace(e.global_position + Vector3(u.dash_velocity.x, 0.0, u.dash_velocity.z).normalized() * a.push_distance)
				u.dash_timer = 0.0
				return


## Damage multiplier for a champion standing in an allied ward (strongest wins).
func ward_factor(target: Unit) -> float:
	if target.def.kind != ChampionDef.Kind.CHAMPION:
		return 1.0
	var best := 0.0
	for ar in areas:
		if ar.alive and ar.ability.delivery == AbilityDef.Delivery.WARD and is_instance_valid(ar.source) \
				and ar.source.team == target.team \
				and Vector2(target.global_position.x - ar.center.x, target.global_position.z - ar.center.z).length() <= ar.ability.area_radius + target.def.radius:
			best = maxf(best, ar.ability.ward_reduction)
	return 1.0 - best


## Which item power an ability uses: 0 weapon, 1 spell, -1 none.
static func power_kind(source: Unit, a: AbilityDef) -> int:
	if a == null or source == null:
		return -1
	match a.scaling:
		AbilityDef.Scaling.WEAPON:
			return 0
		AbilityDef.Scaling.SPELL:
			return 1
		AbilityDef.Scaling.NONE:
			return -1
	return 0 if source.def.power == ChampionDef.Power.WEAPON else 1


## Damage after armor (weapon) or magic resist (spell). Champions only.
static func mitigate(target: Unit, amount: float, kind: int) -> float:
	if kind < 0 or target.def.kind != ChampionDef.Kind.CHAMPION:
		return amount
	var defence := target.armor if kind == 0 else target.magic_resist
	return amount * 100.0 / (100.0 + maxf(defence, 0.0))


## `proc_kind` >= 0 marks damage from an item passive (a is null): it is
## reduced by the target's defence but never triggers another item passive.
func apply_damage(source: Unit, target: Unit, amount: float, a: AbilityDef, proc_kind: int = -1) -> bool:
	if not target.alive or amount <= 0.0:
		return false
	if a != null and a.hits_enemies_only and not are_enemies(source, target):
		return false
	if target.is_protected():
		damage_blocked.emit(target, source)
		return false
	if target.def.kind == ChampionDef.Kind.STRUCTURE:
		if a != null:
			amount *= a.structure_damage_mult
		amount *= source.structure_bonus
	amount *= ward_factor(target)
	var kind := proc_kind
	if source.def.kind == ChampionDef.Kind.CHAMPION and proc_kind < 0:
		amount *= source.damage_mult
		kind = power_kind(source, a)
		# Item power is for fights: it does not speed up sieges.
		if kind >= 0 and target.def.kind != ChampionDef.Kind.STRUCTURE:
			amount *= 1.0 + (source.weapon_power if kind == 0 else source.spell_power) / 100.0
	amount = mitigate(target, amount, kind)
	amount *= passive_damage_factor(source, target, a)
	if source.weaken_timer > 0.0:
		amount *= 1.0 - source.weaken_amount
	if target.mark_timer > 0.0:
		amount *= 1.0 + target.mark_amount
	if target.brace_timer > 0.0 and proc_kind < 0 and source.def.kind == ChampionDef.Kind.CHAMPION and _in_front(target, source):
		amount *= 1.0 - target.brace_amount  # Still Water: the one braced hit
		target.brace_timer = 0.0
		target.brace_amount = 0.0
		damage_blocked.emit(target, source)
	if target.def.passive == ChampionDef.Passive.FORMATION and target.passive_stacks > 0.0:
		amount *= 1.0 - target.def.passive_value * target.passive_stacks
	if target.shield > 0.0:
		var soaked := minf(target.shield, amount)
		target.shield -= soaked
		amount -= soaked
		if target.shield <= 0.0:
			target.shield_timer = 0.0
	target.health -= amount
	target.last_attacker = source
	target.last_attacked_at = time
	if source.def.kind == ChampionDef.Kind.CHAMPION:
		target.last_champion_hit_at = time
		if target.def.kind == ChampionDef.Kind.CHAMPION:
			source.champion_fight_at = time
			target.champion_fight_at = time
			if source.def.passive == ChampionDef.Passive.FURY:
				source.passive_stacks = minf(source.passive_stacks + FURY_DEALT, FURY_MAX)
			if target.def.passive == ChampionDef.Passive.FURY:
				target.passive_stacks = minf(target.passive_stacks + FURY_TAKEN, FURY_MAX)
	target.cancel_recall("Recall cancelled: you were hit")
	target.damaged.emit(amount, source)
	unit_damaged.emit(target, amount, source)
	if a != null and a.slow_amount > 0.0:
		target.apply_slow(a.slow_amount, a.slow_duration)
	if a != null and a.stun_duration > 0.0 and target.def.kind != ChampionDef.Kind.STRUCTURE:
		target.apply_stun(a.stun_duration)
	if a != null and a.root_duration > 0.0 and target.def.kind != ChampionDef.Kind.STRUCTURE:
		target.apply_root(a.root_duration)
	if a != null and a.mark_duration > 0.0 and target.def.kind != ChampionDef.Kind.STRUCTURE:
		target.apply_mark(a.mark_amount, a.mark_duration)
	if a != null and a.weaken_duration > 0.0 and _markable(target):
		target.apply_weaken(a.weaken_amount, a.weaken_duration)
	if a != null and a.interrupts and target.def.kind == ChampionDef.Kind.CHAMPION and target.is_casting():
		target.interrupt_cast()
	if a != null and (a.taunt_duration > 0.0 or a.charm_duration > 0.0) and _compellable(target):
		if a.taunt_duration > 0.0:
			target.apply_compel(Unit.Compel.TAUNT, source, a.taunt_duration)
		else:
			target.apply_compel(Unit.Compel.CHARM, source, a.charm_duration)
	if proc_kind < 0 and a != null and target.def.kind == ChampionDef.Kind.CHAMPION \
			and (a.stun_duration > 0.0 or a.root_duration > 0.0 or a.taunt_duration > 0.0 or a.charm_duration > 0.0):
		_harness(source)
	if proc_kind < 0 and a != null:
		_hit_passives(source, target, a)
		_item_passives(source, target, a)
	if target.alive and target.health <= 0.0:
		# A summon's kill belongs to whoever placed it.
		var credit := source.summoner if source.summoner and is_instance_valid(source.summoner) else source
		target.set_dead(credit)
		unit_died.emit(target, credit)
		_on_kill(credit, target)
	return true


## Taunts and charms move champions and minions, never structures or the
## neutral camp (it would walk off its post).
static func _compellable(u: Unit) -> bool:
	return u.def.kind == ChampionDef.Kind.CHAMPION or u.def.kind == ChampionDef.Kind.MINION


## Passive multipliers on one hit. INSCRIBE counts basic attack hits per
## target; RESOLVE softens hits while the target is below half health.
func passive_damage_factor(source: Unit, target: Unit, a: AbilityDef) -> float:
	var f := 1.0
	if source.def.passive == ChampionDef.Passive.INSCRIBE and a != null and a == source.def.basic_attack \
			and target.def.kind != ChampionDef.Kind.STRUCTURE:
		var n: int = source.hit_streak.get(target.net_id, 0) + 1
		if n >= 3:
			n = 0
			f *= 1.0 + source.def.passive_value
		source.hit_streak[target.net_id] = n
	if target.def.passive == ChampionDef.Passive.RESOLVE and target.health < target.max_health * 0.5:
		f *= 1.0 - target.def.passive_value
	if source.def.passive == ChampionDef.Passive.LONGSHOT and a != null and a == source.def.basic_attack \
			and target.def.kind != ChampionDef.Kind.STRUCTURE \
			and Vector2(target.global_position.x - source.global_position.x, target.global_position.z - source.global_position.z).length() > source.def.passive_range:
		f *= 1.0 + source.def.passive_value
	if source.def.passive == ChampionDef.Passive.QUARRY and a != null and _markable(target):
		var key := target.net_id
		var m: Vector2 = source.passive_marks.get(key, Vector2(0, -100))
		var n := int(m.x) if time - m.y <= MARK_TIME else 0
		if a == source.def.basic_attack:
			source.passive_marks[key] = Vector2(mini(n + 1, 3), time)
		elif a == source.get_slot(1) and n > 0:
			f *= 1.0 + source.def.passive_value * n
			source.passive_marks.erase(key)
	if source.def.passive == ChampionDef.Passive.MOMENTUM and a != null and a == source.def.basic_attack \
			and _markable(target) and time <= source.passive_primed_until:
		f *= 1.0 + source.def.passive_value
		source.passive_primed_until = -1.0  # one stored hit, no stacking
	if source.def.passive == ChampionDef.Passive.SEAM and a != null and _markable(target):
		var ready_key := "seam:%d" % target.net_id
		var prime_key := "seamprime:%d" % target.net_id
		var to_src := Vector3(source.global_position.x - target.global_position.x, 0.0, source.global_position.z - target.global_position.z)
		var behind := to_src.length() > 0.05 and target.forward().dot(to_src.normalized()) < -SEAM_BEHIND
		var primed := time - float(source.passive_marks.get(prime_key, -100.0)) <= SEAM_PRIME_TIME
		if time >= float(source.passive_marks.get(ready_key, -100.0)) and (behind or primed):
			f *= 1.0 + source.def.passive_value
			source.passive_marks[ready_key] = time + SEAM_COOLDOWN
			source.passive_marks.erase(prime_key)
	if source.def.passive == ChampionDef.Passive.CALIBRATE and a != null and a == source.get_slot(1):
		f *= 1.0 + source.def.passive_value * float(source.passive_marks.get("calib", 0.0))
	if source.def.passive == ChampionDef.Passive.TITHE and target.def.kind != ChampionDef.Kind.STRUCTURE and target.is_impaired():
		f *= 1.0 + source.def.passive_value
	return f


## LANTERN: allied champions near a living Lantern champion (itself too)
## regain health every tick. ENCORE: the same circle moves faster.
## BARROWBLOOD: the unit regains health while below half.
func _step_passives(dt: float) -> void:
	for src in units:
		if not src.alive:
			continue
		match src.def.passive:
			ChampionDef.Passive.LANTERN, ChampionDef.Passive.ENCORE:
				for u in units:
					if u.alive and u.team == src.team and u.def.kind == ChampionDef.Kind.CHAMPION \
							and _flat(u.global_position, src.global_position) <= src.def.passive_range:
						if src.def.passive == ChampionDef.Passive.LANTERN:
							heal(u, src.def.passive_value * dt)
						else:
							u.apply_quick(src.def.passive_value, 0.25)
			ChampionDef.Passive.BARROWBLOOD:
				if src.health < src.max_health * 0.5:
					heal(src, src.def.passive_value * dt)
			ChampionDef.Passive.REFRAIN:
				if src.refrain_slot >= 0 and time - src.refrain_at > REFRAIN_TIME:
					src.refrain_slot = -1  # the song lapsed
			ChampionDef.Passive.FORMATION:
				if src.passive_stacks > 0.0 and time > src.passive_primed_until:
					src.passive_stacks = 0.0  # the line broke up
			ChampionDef.Passive.ROOTS:
				if time >= src.passive_ready_at and _in_own_ward(src):
					src.passive_ready_at = time + ROOTS_EVERY
					give_shield(src, src, src.def.passive_value, ROOTS_SHIELD_TIME)
			ChampionDef.Passive.FURY:
				if time - src.champion_fight_at > FIGHT_TIME * 0.75:
					src.passive_stacks = maxf(src.passive_stacks - FURY_FADE * dt, 0.0)


## Burns tick twice a second (item damage: no on-hit effects); Cairnheart
## mends a champion that has not been hit by a champion for a while.
func _step_item_effects(dt: float) -> void:
	for u in units:
		if not u.alive:
			continue
		if u.burn_timer > 0.0:
			u.burn_timer -= dt
			var acc: float = u.item_counters.get("burn_acc", 0.0) + dt
			if acc >= BURN_TICK or u.burn_timer <= 0.0:
				if is_instance_valid(u.burn_source) and u.burn_source.alive:
					apply_damage(u.burn_source, u, u.burn_dps * acc, null, 1)
				acc = 0.0
			u.item_counters["burn_acc"] = acc
			if u.burn_timer <= 0.0:
				u.burn_source = null
		if u.def.kind == ChampionDef.Kind.CHAMPION and not u.items.is_empty() and u.health < u.max_health \
				and time - u.last_champion_hit_at >= CAIRN_QUIET:
			var cairn := item_with(u, ItemDef.Passive.CAIRNHEART)
			if cairn:
				heal(u, u.max_health * cairn.passive_value * dt)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## EMBER: a champion kill resets the killer's slot 1 and heals it.
func _on_kill(killer: Unit, victim: Unit) -> void:
	if killer == null or not is_instance_valid(killer) or not killer.alive:
		return
	if killer.def.passive == ChampionDef.Passive.EMBER and victim.def.kind == ChampionDef.Kind.CHAMPION:
		if killer.cooldowns.size() > 1:
			killer.cooldowns[1] = 0.0
		heal(killer, killer.max_health * killer.def.passive_value)


## Rule-driven removal (a timed-out siege beast), no killer credited.
func kill(target: Unit) -> void:
	if target.alive:
		target.set_dead(null)
		unit_died.emit(target, null)


## `source`: the champion whose ability heals (item passives read it).
## `cast_id`: the area doing the healing, so FLAME counts each cast once.
func heal(target: Unit, amount: float, source: Unit = null, cast_id: int = -1) -> void:
	if source and source != target and cast_id >= 0 and is_instance_valid(source) \
			and source.def.passive == ChampionDef.Passive.FLAME and target.def.kind == ChampionDef.Kind.CHAMPION \
			and minf(time - target.champion_fight_at, time - source.champion_fight_at) <= FIGHT_TIME \
			and not source.passive_marks.has("ember:%d" % cast_id):
		source.passive_marks["ember:%d" % cast_id] = true
		source.passive_stacks = minf(source.passive_stacks + 1.0, FLAME_MAX)
	if source and source != target and is_instance_valid(source) and target.health < target.max_health * 0.35:
		var lantern := item_with(source, ItemDef.Passive.LANTERN)
		if lantern:
			amount *= 1.0 + lantern.passive_value
	amount *= 1.0 - target.heal_cut
	if source and source != target and is_instance_valid(source) and target.def.kind == ChampionDef.Kind.CHAMPION:
		_cantor(source, target)
	if target.alive and amount > 0.0:
		var before := target.health
		target.health = minf(target.max_health, target.health + amount)
		if source:
			unit_healed.emit(target, target.health - before, source)


func _step_projectiles(dt: float) -> void:
	var space := get_viewport().world_3d.direct_space_state if is_inside_tree() else null
	for p in projectiles:
		var a := p.ability
		if a.homing:
			_step_homing(p, dt)
			continue
		var step_len := minf(a.projectile_speed * dt, a.range - p.travelled)
		var from := p.position
		var to := from + p.direction * step_len
		# Walls stop projectiles.
		var wall_t := 2.0
		if space:
			var q := PhysicsRayQueryParameters3D.create(from, to, Unit.LAYER_WORLD)
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				wall_t = from.distance_to(hit.position) / maxf(step_len, 0.0001)
		wall_t = minf(wall_t, _storm_wall_t(p.source, from, to))
		# Earliest unit along the segment, tested on the ground plane against
		# each unit's radius. Pure math, so it does not depend on physics timing.
		var best: Unit = null
		var best_t := wall_t
		for u in units:
			if not u.alive or (a.hits_enemies_only and not are_enemies(p.source, u)) or u == p.source:
				continue
			if from.y < u.global_position.y - 0.2 or from.y > u.global_position.y + u.def.height + 0.2:
				continue
			if a.pierce and u in p.hit:
				continue
			var t := _segment_circle_t(from, to, u.global_position, u.def.radius + a.projectile_radius)
			if t < 0.0 or t >= wall_t:
				continue
			if a.pierce:
				p.hit.append(u)  # passes through: everyone on the line this tick is struck
				apply_damage(p.source, u, a.damage * (1.0 if p.hit.size() == 1 else a.pierce_falloff), a)
			elif t < best_t:
				best_t = t
				best = u
		if best:
			apply_damage(p.source, best, a.damage, a)
			_end_projectile(p, from.lerp(to, best_t))
		elif wall_t <= 1.0:
			_end_projectile(p, from.lerp(to, wall_t))
		else:
			p.position = to
			p.travelled += step_len
			if p.travelled >= a.range - 0.001:
				_end_projectile(p, to)
	projectiles = projectiles.filter(func(x: SimProjectile) -> bool: return x.alive)


## First t in [0,1] where the flat segment crosses a standing wall raised by
## an enemy of `source`, or 2 for none. Homing tower shots are not checked.
func _storm_wall_t(source: Unit, from: Vector3, to: Vector3) -> float:
	var best := 2.0
	for ar in areas:
		if not ar.alive or ar.ability.delivery != AbilityDef.Delivery.WALL or not is_instance_valid(ar.source) \
				or not are_enemies(ar.source, source):
			continue
		var e := wall_ends(ar)
		var hit: Variant = Geometry2D.segment_intersects_segment(Vector2(from.x, from.z), Vector2(to.x, to.z),
				Vector2(e[0].x, e[0].z), Vector2(e[1].x, e[1].z))
		if hit != null:
			var d := Vector2(to.x - from.x, to.z - from.z).length()
			var t := (hit as Vector2).distance_to(Vector2(from.x, from.z)) / maxf(d, 0.0001)
			best = minf(best, t)
	return best


## Homing shots fly at the target's chest and can only hit that target.
func _step_homing(p: SimProjectile, dt: float) -> void:
	var t := p.target
	if t == null or not is_instance_valid(t) or not t.alive:
		_end_projectile(p, p.position)
		return
	var aim := t.global_position + Vector3(0, t.def.height * 0.5, 0)
	var to := aim - p.position
	var step_len := p.ability.projectile_speed * dt
	if to.length() <= step_len + t.def.radius:
		apply_damage(p.source, t, p.ability.damage, p.ability)
		_end_projectile(p, aim)
		return
	p.direction = to.normalized()
	p.position += p.direction * step_len
	p.travelled += step_len
	if p.travelled > p.ability.range * 3.0:
		_end_projectile(p, p.position)  # safety: never chase forever


func _end_projectile(p: SimProjectile, at: Vector3) -> void:
	p.alive = false
	p.position = at
	projectile_ended.emit(p, at)


## First t in [0,1] where the flat segment enters the circle, or -1.
static func _segment_circle_t(from: Vector3, to: Vector3, center: Vector3, r: float) -> float:
	var f := Vector2(from.x - center.x, from.z - center.z)
	var d := Vector2(to.x - from.x, to.z - from.z)
	if f.length() <= r:
		return 0.0
	var a := d.dot(d)
	if a < 0.000001:
		return -1.0
	var b := 2.0 * f.dot(d)
	var c := f.dot(f) - r * r
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return -1.0
	var t := (-b - sqrt(disc)) / (2.0 * a)
	return t if t >= 0.0 and t <= 1.0 else -1.0


func _step_areas(dt: float) -> void:
	for ar in areas:
		ar.timer -= dt
		if ar.ability.delivery == AbilityDef.Delivery.WARD and ar.ability.heal_per_second > 0.0 \
				and is_instance_valid(ar.source):
			for u in units:
				if u.alive and u.team == ar.source.team and u.def.kind == ChampionDef.Kind.CHAMPION \
						and Vector2(u.global_position.x - ar.center.x, u.global_position.z - ar.center.z).length() <= ar.ability.area_radius + u.def.radius:
					heal(u, ar.ability.heal_per_second * dt, ar.source, ar.id)
		if ar.ability.delivery == AbilityDef.Delivery.WARD and ar.ability.enemy_slow > 0.0 \
				and is_instance_valid(ar.source):
			for u in units:
				if u.alive and are_enemies(ar.source, u) and u.def.kind != ChampionDef.Kind.STRUCTURE \
						and _flat(u.global_position, ar.center) <= ar.ability.area_radius + u.def.radius:
					u.apply_slow(ar.ability.enemy_slow, 0.25)
		if ar.ability.delivery == AbilityDef.Delivery.WARD and (ar.ability.ally_haste > 0.0 or ar.ability.ally_quick > 0.0) \
				and is_instance_valid(ar.source):
			for u in units:
				if u.alive and u.team == ar.source.team and u.def.kind == ChampionDef.Kind.CHAMPION \
						and _flat(u.global_position, ar.center) <= ar.ability.area_radius + u.def.radius:
					if ar.ability.ally_haste > 0.0:
						u.apply_haste(ar.ability.ally_haste, 0.25)
					if ar.ability.ally_quick > 0.0:
						u.apply_quick(ar.ability.ally_quick, 0.25)
		if ar.timer <= 0.0 and _stands(ar.ability):
			ar.alive = false
			area_detonated.emit(ar)  # a ward or wall simply ends
		elif ar.timer <= 0.0:
			ar.alive = false
			_burst(ar)
			area_detonated.emit(ar)
	areas = areas.filter(func(x: SimArea) -> bool: return x.alive)
	areas.append_array(_new_areas)
	_new_areas.clear()


var _new_areas: Array[SimArea] = []


## A ground area bursts: damage (and its effects) on everyone inside, then
## the extras: pull enemies toward the centre, heal allied champions, and
## leave a second area behind.
func _burst(ar: SimArea) -> void:
	var a := ar.ability
	var src_ok := is_instance_valid(ar.source)
	for u: Unit in units.duplicate():
		if not u.alive:
			continue
		if not in_area(ar, u.global_position, u.def.radius):
			continue
		if src_ok and not are_enemies(ar.source, u):
			if a.ally_heal > 0.0 and u.def.kind == ChampionDef.Kind.CHAMPION:
				heal(u, a.ally_heal, ar.source, ar.id)
			continue
		var dmg := a.damage
		if src_ok and ar.source.def.passive == ChampionDef.Passive.STORMEYE \
				and _flat(u.global_position, ar.center) <= a.area_radius * 0.4 + u.def.radius:
			dmg *= 1.0 + ar.source.def.passive_value
		dmg *= ar.power
		var hurt := apply_damage(ar.source, u, dmg, a) if src_ok and dmg > 0.0 else true
		if a.push_distance > 0.0 and hurt:
			_push(u, ar.center, a.push_distance)
		if a.pull_distance > 0.0 and u.alive and hurt and u.def.kind != ChampionDef.Kind.STRUCTURE:
			var to := ar.center - u.global_position
			to.y = 0.0
			var dist := minf(a.pull_distance, maxf(to.length() - 0.6, 0.0))
			if dist > 0.05:
				u.displace(u.global_position + to.normalized() * dist)
	if a.leaves is AbilityDef and src_ok:
		var b := SimArea.new()
		b.id = _next_fx_id
		_next_fx_id += 1
		b.source = ar.source
		b.ability = a.leaves
		b.center = ar.center
		b.dir = ar.dir
		b.timer = area_lifetime(b.ability)
		_new_areas.append(b)
		area_spawned.emit(b)


## The first owned item with this passive, or null.
static func item_with(u: Unit, passive: ItemDef.Passive) -> ItemDef:
	for it in u.items:
		if it.passive == passive:
			return it
	return null


## Item passives on a landed hit between champions (see data/items/adventurer).
## Item damage passes proc_kind, so it never comes back here.
func _item_passives(source: Unit, target: Unit, a: AbilityDef) -> void:
	if source.def.kind != ChampionDef.Kind.CHAMPION or target.def.kind != ChampionDef.Kind.CHAMPION:
		return
	if not source.items.is_empty():
		var basic := a == source.def.basic_attack
		var duel := item_with(source, ItemDef.Passive.DUELIST)
		if duel and basic:
			# Every third basic hit on the same champion; stacks fade after the cooldown.
			var key := "duelist:%d" % target.net_id
			var last: Vector2 = source.item_counters.get(key, Vector2(0, -100))
			var n := 1 if time - last.y > duel.passive_cooldown else int(last.x) + 1
			if n >= 3:
				n = 0
				apply_damage(source, target, duel.passive_value, null, 0)
			source.item_counters[key] = Vector2(n, time)
		var kind := power_kind(source, a)
		var giant := item_with(source, ItemDef.Passive.GIANTFALL)
		if giant and basic and target.alive and target.health > 0.0:
			var key := "giant:%d" % target.net_id
			if source.item_ready_at.get(key, -100.0) <= time:
				source.item_ready_at[key] = time + giant.passive_cooldown
				apply_damage(source, target, minf(target.max_health * giant.passive_value, GIANTFALL_CAP), null, 0)
		var ranger := item_with(source, ItemDef.Passive.RANGER)
		if ranger and basic:
			source.apply_quick(ranger.passive_value, 1.5)
		var writ := item_with(source, ItemDef.Passive.WRIT)
		if writ:
			if not basic:
				source.item_counters["writ"] = time  # an ability hit primes the next basic
			elif time - float(source.item_counters.get("writ", -100.0)) <= PRIME_TIME \
					and source.item_ready_at.get("writ", -100.0) <= time and target.alive and target.health > 0.0:
				source.item_counters.erase("writ")
				source.item_ready_at["writ"] = time + writ.passive_cooldown
				apply_damage(source, target, writ.passive_value, null, 0)
		var thread := item_with(source, ItemDef.Passive.STORMTHREAD)
		if thread and basic and time - float(source.item_counters.get("stormthread", -100.0)) <= PRIME_TIME \
				and target.alive and target.health > 0.0:
			source.item_counters.erase("stormthread")
			apply_damage(source, target, thread.passive_value, null, 1)
		var ashen := item_with(source, ItemDef.Passive.ASHEN)
		if ashen and kind == 0:
			target.apply_heal_cut(ashen.passive_value, HEAL_CUT_TIME)
		var glass := item_with(source, ItemDef.Passive.WITCHGLASS)
		if glass and kind == 1 and not basic:
			target.apply_heal_cut(glass.passive_value, HEAL_CUT_TIME)
		var cinder := item_with(source, ItemDef.Passive.CINDER)
		if cinder and kind == 1 and not basic:
			target.burn_source = source
			target.burn_dps = cinder.passive_value / BURN_TIME
			target.burn_timer = BURN_TIME  # refreshes, never stacks
		var codex := item_with(source, ItemDef.Passive.CODEX)
		if codex and not basic and target.alive and target.health > 0.0:
			# Two different abilities on the same champion within 4 s.
			var key := "codex:%d" % target.net_id
			var prev: Array = source.item_counters.get(key, [&"", -100.0])
			if prev[0] != a.id and time - float(prev[1]) <= 4.0 and source.item_ready_at.get(key, -100.0) <= time:
				source.item_ready_at[key] = time + codex.passive_cooldown
				apply_damage(source, target, codex.passive_value, null, 1)
			source.item_counters[key] = [a.id, time]
	# Bastion Plate and Spellward Mantle share one low-health shield: owning
	# both never gives two.
	var bastion := item_with(target, ItemDef.Passive.BASTION)
	if bastion == null:
		bastion = item_with(target, ItemDef.Passive.SPELLWARD)
	if bastion and target.alive and target.health > 0.0 and target.health < target.max_health * 0.35 \
			and target.item_ready_at.get("bastion", -100.0) <= time:
		target.item_ready_at["bastion"] = time + bastion.passive_cooldown
		target.apply_shield(bastion.passive_value + target.max_health * 0.1, 4.0)
		unit_shielded.emit(target, target.shield)


const BURN_TIME := 3.0      # Cinder Reliquary: passive_value spread over this
const BURN_TICK := 0.5
const CAIRN_QUIET := 6.0    # Cairnheart: seconds without champion damage
const HEAL_CUT_TIME := 2.5
const PRIME_TIME := 4.0     # Headsman's Writ and Stormthread: primed this long
const GIANTFALL_CAP := 40.0


## A champion's shield on another unit (passives and items): applies it and
## runs the shield giver's items (Cantor's Thread, Pilgrim's Bulwark).
func give_shield(source: Unit, target: Unit, amount: float, duration: float) -> void:
	target.apply_shield(amount, duration)
	unit_shielded.emit(target, target.shield)
	if source == null or source == target or not is_instance_valid(source) or source.items.is_empty():
		return
	if target.def.kind == ChampionDef.Kind.CHAMPION:
		_cantor(source, target)
		var bulwark := item_with(source, ItemDef.Passive.BULWARK)
		if bulwark and source.item_ready_at.get("bulwark", -100.0) <= time:
			source.item_ready_at["bulwark"] = time + bulwark.passive_cooldown
			source.apply_shield(bulwark.passive_value, PASSIVE_SHIELD_TIME)
			unit_shielded.emit(source, source.shield)


## Cantor's Thread: an ally the owner heals or shields moves faster briefly.
func _cantor(source: Unit, target: Unit) -> void:
	if source.items.is_empty():
		return
	var cantor := item_with(source, ItemDef.Passive.CANTOR)
	if cantor:
		target.apply_quick(cantor.passive_value, 1.5)


## Oathkeeper's Harness: hard crowd control on an enemy champion shields the
## nearest allied champion within 8 m (the owner if nobody else).
func _harness(source: Unit) -> void:
	if source == null or source.items.is_empty():
		return
	var harness := item_with(source, ItemDef.Passive.HARNESS)
	if harness == null or source.item_ready_at.get("harness", -100.0) > time:
		return
	source.item_ready_at["harness"] = time + harness.passive_cooldown
	var best := source
	var best_d := INF
	for u in units:
		if u != source and u.alive and u.team == source.team and u.def.kind == ChampionDef.Kind.CHAMPION:
			var d := _flat(u.global_position, source.global_position)
			if d <= 8.0 and d < best_d:
				best = u
				best_d = d
	give_shield(source, best, harness.passive_value, PASSIVE_SHIELD_TIME)


const SEAM_COOLDOWN := 6.0  # SEAM: per target
const SEAM_BEHIND := 0.3    # how far behind counts (dot product)
const SEAM_PRIME_TIME := 3.0
const FIGHT_TIME := 4.0     # FLAME: "in a fight" = champion damage this recently
const FLAME_MAX := 3.0
const FURY_MAX := 100.0
const FURY_DEALT := 10.0
const FURY_TAKEN := 6.0
const FURY_FADE := 15.0     # per second, once out of the fight
const REFRAIN_TIME := 6.0
const RESIDUAL_MAX := 2.0
const RESIDUAL_WINDOW := 1.5  # longer than any one cast (Tempest strikes for 1.2 s)


## REFRAIN: the stronger version of a Q or E that ends a pair, made once per
## ability and kept. A song grows wider and quicker, a charm lasts longer and
## reaches further, anything else hits harder.
static var _empowered := {}
static func empowered(a: AbilityDef) -> AbilityDef:
	var key := a.get_instance_id()
	if _empowered.has(key):
		return _empowered[key]
	var b := a.duplicate() as AbilityDef
	if b.ally_haste > 0.0 or b.ally_quick > 0.0:
		b.ally_haste *= 1.4
		b.ally_quick *= 1.4
		b.area_radius += 1.0
	elif b.charm_duration > 0.0:
		b.charm_duration += 0.4
		b.range += 3.0
	else:
		b.damage *= 1.25
	_empowered[key] = b
	return b


const MARK_TIME := 4.0      # MARGINALIA and QUARRY marks last this long
const PASSIVE_SHIELD_TIME := 3.0
const PRIMED_TIME := 6.0    # STAND_BEHIND: a cast primes the next hit this long
const STAND_COOLDOWN := 8.0
const MEASURED_COOLDOWN := 6.0
const CALIBRATE_MAX := 4.0
const REMEMBRANCE_MAX := 3.0
const FORMATION_MAX := 3.0
const FORMATION_TIME := 4.0
const ROOTS_EVERY := 6.0
const ROOTS_SHIELD_TIME := 3.0
const MOMENTUM_TIME := 3.0   # MOMENTUM: the primed hit waits this long


## Champions and training dummies take marks; minions and structures do not.
static func _markable(u: Unit) -> bool:
	return u.def.kind == ChampionDef.Kind.CHAMPION or u.def.kind == ChampionDef.Kind.DUMMY


## Champion passives that react to a landed hit (MARGINALIA, STAND_BEHIND).
## QUARRY changes the damage itself, in passive_damage_factor.
func _hit_passives(source: Unit, target: Unit, a: AbilityDef) -> void:
	if not _markable(target) or not source.alive:
		return
	match source.def.passive:
		ChampionDef.Passive.SEAM:
			if a == source.get_slot(2):
				source.passive_marks["seamprime:%d" % target.net_id] = time  # the knife opens a seam
		ChampionDef.Passive.RESIDUAL:
			if (a == source.get_slot(4) or a.is_ultimate) and target.def.kind != ChampionDef.Kind.STRUCTURE:
				var key := "rc:ult" if a.is_ultimate else "rc:%s" % a.id  # Tempest's strikes are one cast
				if time - float(source.passive_marks.get(key, -100.0)) > RESIDUAL_WINDOW:
					source.passive_marks[key] = time  # once per cast
					source.passive_stacks = minf(source.passive_stacks + 1.0, RESIDUAL_MAX)
		ChampionDef.Passive.MARGINALIA:
			if a == source.get_slot(1):
				source.passive_marks[target.net_id] = Vector2(1, time)
			elif a == source.get_slot(2):
				var m: Vector2 = source.passive_marks.get(target.net_id, Vector2(0, -100))
				if m.x > 0 and time - m.y <= MARK_TIME:
					source.passive_marks.erase(target.net_id)
					source.apply_shield(source.def.passive_value, PASSIVE_SHIELD_TIME)
					unit_shielded.emit(source, source.shield)
		ChampionDef.Passive.REMEMBRANCE:
			if a != source.def.basic_attack and a != source.get_slot(0) and target.def.kind != ChampionDef.Kind.STRUCTURE:
				var key := "rem:ult" if a.is_ultimate else "rem:%s" % a.id
				if time - float(source.passive_marks.get(key, -100.0)) > RESIDUAL_WINDOW:
					source.passive_marks[key] = time  # once per cast, however many it hits
					source.passive_stacks = minf(source.passive_stacks + 1.0, REMEMBRANCE_MAX)
		ChampionDef.Passive.CALIBRATE:
			if a == source.get_slot(0):
				source.passive_stacks = minf(source.passive_stacks + 1.0, CALIBRATE_MAX)
		ChampionDef.Passive.FORMATION:
			if a == source.get_slot(0):
				for u in units:
					if u != source and u.alive and u.team == source.team and u.def.kind == ChampionDef.Kind.CHAMPION \
							and _flat(u.global_position, source.global_position) <= source.def.passive_range:
						source.passive_stacks = minf(source.passive_stacks + 1.0, FORMATION_MAX)
						source.passive_primed_until = time + FORMATION_TIME
						break
		ChampionDef.Passive.MEASURED:
			if a == source.def.basic_attack and time <= source.passive_primed_until and time >= source.passive_ready_at:
				source.passive_primed_until = -1.0
				source.passive_ready_at = time + MEASURED_COOLDOWN
				give_shield(source, source, source.def.passive_value, PASSIVE_SHIELD_TIME)
		ChampionDef.Passive.STAND_BEHIND:
			if a == source.def.basic_attack and time <= source.passive_primed_until and time >= source.passive_ready_at:
				var best: Unit = null
				for u in units:
					if u.alive and u.team == source.team and u.def.kind == ChampionDef.Kind.CHAMPION \
							and _flat(u.global_position, source.global_position) <= source.def.passive_range \
							and (best == null or _shield_need(u) > _shield_need(best)):
						best = u
				if best:
					source.passive_primed_until = -1.0
					source.passive_ready_at = time + STAND_COOLDOWN
					give_shield(source, best, source.def.passive_value, PASSIVE_SHIELD_TIME)


## Who needs a shield most: missing health share; the caster itself counts
## a little less, so a hurt ally beside it wins a tie.
static func _shield_need(u: Unit) -> float:
	return 1.0 - u.health / u.max_health - (0.05 if u.def.passive == ChampionDef.Passive.STAND_BEHIND else 0.0)


## Pushes `u` straight away from `from` (walls stop it). Structures stay put.
func _push(u: Unit, from: Vector3, dist: float) -> void:
	if not u.alive or u.def.kind == ChampionDef.Kind.STRUCTURE:
		return
	var d := Vector3(u.global_position.x - from.x, 0.0, u.global_position.z - from.z)
	d = d.normalized() if d.length() > 0.05 else u.forward() * -1.0
	u.displace(u.global_position + d * dist)


## Is `other` in front of `u` (within about 70 degrees of where it faces)?
static func _in_front(u: Unit, other: Unit) -> bool:
	var to := Vector3(other.global_position.x - u.global_position.x, 0.0, other.global_position.z - u.global_position.z)
	return to.length() < 0.05 or u.forward().dot(to.normalized()) >= 0.35


## Is the unit standing in one of its own wards (ROOTS: First Grove)?
func _in_own_ward(u: Unit) -> bool:
	for ar in areas:
		if ar.alive and ar.source == u and ar.ability.delivery == AbilityDef.Delivery.WARD \
				and in_area(ar, u.global_position, u.def.radius):
			return true
	return false


## SELF shields: the caster, an ally, or whichever of them needs it most.
func _self_shields(caster: Unit, a: AbilityDef) -> void:
	if a.shield_mode == AbilityDef.ShieldMode.NONE or a.shield_amount <= 0.0:
		return
	var ally: Unit = null
	for u in units:
		if u != caster and u.alive and u.team == caster.team and u.def.kind == ChampionDef.Kind.CHAMPION \
				and _flat(u.global_position, caster.global_position) <= a.area_radius + u.def.radius \
				and (ally == null or _shield_need(u) > _shield_need(ally)):
			ally = u
	match a.shield_mode:
		AbilityDef.ShieldMode.SELF:
			give_shield(caster, caster, a.shield_amount, a.shield_duration)
		AbilityDef.ShieldMode.SELF_AND_ALLY:
			give_shield(caster, caster, a.shield_amount, a.shield_duration)
			if ally:
				give_shield(caster, ally, a.shield_amount, a.shield_duration)
		AbilityDef.ShieldMode.MOST_HURT:
			var pick := ally if ally and _shield_need(ally) > _shield_need(caster) else caster
			give_shield(caster, pick, a.shield_amount, a.shield_duration)


## Places a summon. Past summon_max for its group, the oldest goes. In place:
## an existing one of the group is swapped where it stands.
func _summon(caster: Unit, a: AbilityDef, target: Vector3) -> void:
	var def := a.summon as ChampionDef
	if def == null:
		return
	var group := a.summon_group if a.summon_group != &"" else StringName(def.id)
	var mine: Array[Unit] = []
	for u in units:
		if u.alive and u.summoner == caster and u.summon_group == group:
			mine.append(u)
	var at := Vector3(target.x, 0.0, target.z)
	if a.summon_in_place and not mine.is_empty():
		var old: Unit = mine[mine.size() - 1]
		at = Vector3(old.global_position.x, 0.0, old.global_position.z)
		expire_summon(old)
		mine.erase(old)
	else:
		at = _clear_of_walls(caster, at, def.radius + 0.2)
	while mine.size() >= maxi(a.summon_max, 1):
		expire_summon(mine.pop_front())
	var yaw := caster.aim_yaw
	var u: Unit = spawner.call(def, caster.team, at, yaw) if spawner.is_valid() else _spawn_bare(def, caster.team, at, yaw)
	u.summoner = caster
	u.summon_group = group
	u.life_timer = a.summon_duration
	u.aim_yaw = yaw
	u.controller = SummonController.new(self)
	summoned.emit(u, caster)


func _spawn_bare(def: ChampionDef, team: int, pos: Vector3, yaw: float) -> Unit:
	var u := Unit.new()
	u.def = def
	u.team = team
	u.position = pos
	u.rotation.y = yaw
	get_parent().add_child(u)
	register_unit(u)
	return u


## A summon's time ran out (or a newer one replaced it): it falls, no credit.
func expire_summon(u: Unit) -> void:
	if u.alive:
		u.set_dead(null)
		unit_died.emit(u, null)


func _step_summons(dt: float) -> void:
	for u in units:
		if u.alive and u.life_timer >= 0.0:
			u.life_timer -= dt
			if u.life_timer <= 0.0 or u.summoner == null or not is_instance_valid(u.summoner):
				expire_summon(u)


## A summon set down behind a wall lands on the near side of it instead.
func _clear_of_walls(caster: Unit, at: Vector3, margin: float) -> Vector3:
	var from := caster.global_position + Vector3(0, 0.6, 0)
	var to := Vector3(at.x, from.y, at.z)
	var q := PhysicsRayQueryParameters3D.create(from, to, Unit.LAYER_WORLD)
	var hit := caster.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return at
	var back := (from - to).normalized() * margin
	return Vector3(hit.position.x + back.x, 0.0, hit.position.z + back.z)

