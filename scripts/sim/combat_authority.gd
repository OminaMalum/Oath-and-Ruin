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
		AbilityDef.Delivery.GROUND_AREA, AbilityDef.Delivery.WARD:
			var ar := SimArea.new()
			ar.id = _next_fx_id
			_next_fx_id += 1
			ar.source = caster
			ar.ability = a
			ar.center = Vector3(target.x, 0.0, target.z)
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
				if to.length() > u.def.radius and absf(fwd.signed_angle_to(to, Vector3.UP)) > half:
					continue
				apply_damage(caster, u, a.damage, a)
		AbilityDef.Delivery.DASH:
			caster.start_dash(a, target)
			dash_started.emit(caster, a)


## Ground areas burst after their delay; wards stand for their duration.
static func area_lifetime(a: AbilityDef) -> float:
	return a.ward_duration if a.delivery == AbilityDef.Delivery.WARD else a.area_delay


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


func apply_damage(source: Unit, target: Unit, amount: float, a: AbilityDef) -> bool:
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
	if source.def.kind == ChampionDef.Kind.CHAMPION:
		amount *= source.damage_mult
	amount *= passive_damage_factor(source, target, a)
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
	if target.health <= 0.0:
		target.set_dead(source)
		unit_died.emit(target, source)
		_on_kill(source, target)
	return true


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
	return f


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


func heal(target: Unit, amount: float) -> void:
	if target.alive and amount > 0.0:
		target.health = minf(target.max_health, target.health + amount)


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
					heal(u, ar.ability.heal_per_second * dt)
		if ar.timer <= 0.0 and ar.ability.delivery == AbilityDef.Delivery.WARD:
			ar.alive = false
			area_detonated.emit(ar)  # a ward simply ends
		elif ar.timer <= 0.0:
			ar.alive = false
			for u in units:
				if not u.alive:
					continue
				var d := Vector2(u.global_position.x - ar.center.x, u.global_position.z - ar.center.z).length()
				if d <= ar.ability.area_radius + u.def.radius:
					apply_damage(ar.source, u, ar.ability.damage, ar.ability)
			area_detonated.emit(ar)
	areas = areas.filter(func(x: SimArea) -> bool: return x.alive)
