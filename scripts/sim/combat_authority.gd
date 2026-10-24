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
		elif u.def.kind == ChampionDef.Kind.MINION:
			u.corpse_timer -= dt
			if u.corpse_timer <= 0.0:
				remove_unit(u)
	_step_projectiles(dt)
	_step_areas(dt)
	_step_passives(dt)


func are_enemies(a: Unit, b: Unit) -> bool:
	return a.team != b.team


func release_ability(caster: Unit, a: AbilityDef, target: Vector3, target_unit: Unit = null) -> void:
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
			ar.timer = area_lifetime(a)
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
				apply_damage(caster, u, a.damage, a)
		AbilityDef.Delivery.DASH:
			caster.start_dash(a, target)
			dash_started.emit(caster, a)


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
	if target.mark_timer > 0.0:
		amount *= 1.0 + target.mark_amount
	if target.shield > 0.0:
		var soaked := minf(target.shield, amount)
		target.shield -= soaked
		amount -= soaked
		if target.shield <= 0.0:
			target.shield_timer = 0.0
	target.health -= amount
	target.last_attacker = source
	target.last_attacked_at = time
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
	if a != null and (a.taunt_duration > 0.0 or a.charm_duration > 0.0) and _compellable(target):
		if a.taunt_duration > 0.0:
			target.apply_compel(Unit.Compel.TAUNT, source, a.taunt_duration)
		else:
			target.apply_compel(Unit.Compel.CHARM, source, a.charm_duration)
	if proc_kind < 0 and a != null:
		_item_passives(source, target, a)
	if target.alive and target.health <= 0.0:
		target.set_dead(source)
		unit_died.emit(target, source)
		_on_kill(source, target)
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
func heal(target: Unit, amount: float, source: Unit = null) -> void:
	if source and source != target and is_instance_valid(source) and target.health < target.max_health * 0.35:
		var lantern := item_with(source, ItemDef.Passive.LANTERN)
		if lantern:
			amount *= 1.0 + lantern.passive_value
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
				apply_damage(p.source, u, a.damage, a)
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
					heal(u, ar.ability.heal_per_second * dt, ar.source)
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
		if _flat(u.global_position, ar.center) > a.area_radius + u.def.radius:
			continue
		if src_ok and not are_enemies(ar.source, u):
			if a.ally_heal > 0.0 and u.def.kind == ChampionDef.Kind.CHAMPION:
				heal(u, a.ally_heal, ar.source)
			continue
		var dmg := a.damage
		if src_ok and ar.source.def.passive == ChampionDef.Passive.STORMEYE \
				and _flat(u.global_position, ar.center) <= a.area_radius * 0.4 + u.def.radius:
			dmg *= 1.0 + ar.source.def.passive_value
		var hurt := apply_damage(ar.source, u, dmg, a) if src_ok and dmg > 0.0 else true
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
		var codex := item_with(source, ItemDef.Passive.CODEX)
		if codex and not basic and target.alive and target.health > 0.0:
			# Two different abilities on the same champion within 4 s.
			var key := "codex:%d" % target.net_id
			var prev: Array = source.item_counters.get(key, [&"", -100.0])
			if prev[0] != a.id and time - float(prev[1]) <= 4.0 and source.item_ready_at.get(key, -100.0) <= time:
				source.item_ready_at[key] = time + codex.passive_cooldown
				apply_damage(source, target, codex.passive_value, null, 1)
			source.item_counters[key] = [a.id, time]
	var bastion := item_with(target, ItemDef.Passive.BASTION)
	if bastion and target.alive and target.health > 0.0 and target.health < target.max_health * 0.35 \
			and target.item_ready_at.get("bastion", -100.0) <= time:
		target.item_ready_at["bastion"] = time + bastion.passive_cooldown
		target.apply_shield(bastion.passive_value + target.max_health * 0.1, 4.0)
		unit_shielded.emit(target, target.shield)
