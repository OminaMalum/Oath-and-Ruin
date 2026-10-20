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

## Tests turn this off and call step() themselves.
@export var auto_step: bool = true

var units: Array[Unit] = []
var projectiles: Array[SimProjectile] = []
var areas: Array[SimArea] = []
var _next_fx_id: int = 1
var tick: int = 0
var _next_unit_id: int = 1


class SimProjectile:
	extends RefCounted
	var id: int = 0
	var source: Unit
	var ability: AbilityDef
	var position: Vector3
	var direction: Vector3
	var travelled: float = 0.0
	var alive: bool = true


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
	u.queue_free()


func _physics_process(delta: float) -> void:
	if auto_step:
		step(delta)


func step(dt: float) -> void:
	tick += 1
	for u in units:
		if u.alive:
			var cmd := u.controller.get_command(u) if u.controller else UnitCommand.new()
			u.sim_step(cmd, dt, self)
		else:
			u.respawn_timer -= dt
			if u.respawn_timer <= 0.0:
				u.respawn()
				unit_respawned.emit(u)
	_step_projectiles(dt)
	_step_areas(dt)


func are_enemies(a: Unit, b: Unit) -> bool:
	return a.team != b.team


func release_ability(caster: Unit, a: AbilityDef, target: Vector3) -> void:
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
			projectiles.append(p)
			projectile_spawned.emit(p)
		AbilityDef.Delivery.GROUND_AREA:
			var ar := SimArea.new()
			ar.id = _next_fx_id
			_next_fx_id += 1
			ar.source = caster
			ar.ability = a
			ar.center = Vector3(target.x, 0.0, target.z)
			ar.timer = a.area_delay
			areas.append(ar)
			area_spawned.emit(ar)


func apply_damage(source: Unit, target: Unit, amount: float, a: AbilityDef) -> bool:
	if not target.alive or amount <= 0.0:
		return false
	if a != null and a.hits_enemies_only and not are_enemies(source, target):
		return false
	target.health -= amount
	target.damaged.emit(amount, source)
	unit_damaged.emit(target, amount, source)
	if a != null and a.slow_amount > 0.0:
		target.apply_slow(a.slow_amount, a.slow_duration)
	if target.health <= 0.0:
		target.set_dead(source)
		unit_died.emit(target, source)
	return true


func _step_projectiles(dt: float) -> void:
	var space := get_viewport().world_3d.direct_space_state if is_inside_tree() else null
	for p in projectiles:
		var a := p.ability
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
			var t := _segment_circle_t(from, to, u.global_position, u.def.radius + a.projectile_radius)
			if t >= 0.0 and t < best_t:
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
		if ar.timer <= 0.0:
			ar.alive = false
			for u in units:
				if not u.alive:
					continue
				var d := Vector2(u.global_position.x - ar.center.x, u.global_position.z - ar.center.z).length()
				if d <= ar.ability.area_radius + u.def.radius:
					apply_damage(ar.source, u, ar.ability.damage, ar.ability)
			area_detonated.emit(ar)
	areas = areas.filter(func(x: SimArea) -> bool: return x.alive)
