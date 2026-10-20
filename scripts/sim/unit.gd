class_name Unit
extends CharacterBody3D
## Gameplay state for one combatant. Only CombatAuthority calls sim_step();
## visuals live in UnitView and read this state, never write it.

signal cast_started(slot: int, ability: AbilityDef, target: Vector3)
signal cast_released(slot: int, ability: AbilityDef, target: Vector3)
signal damaged(amount: float, source: Unit)
signal died(killer: Unit)
signal respawned
## A press that could not become a cast, with a short reason for the HUD.
signal cast_rejected(slot: int, reason: String)

enum CastPhase { NONE, WINDUP, RECOVERY }

const GRAVITY := 20.0
## A press that arrives while busy is remembered this long.
const INPUT_BUFFER := 0.25
const LAYER_WORLD := 1
const LAYER_UNITS := 2

@export var def: ChampionDef
@export var team: int = 0

var controller: UnitController
## Stable id shared by server and clients.
var net_id: int = 0
var health: float = 0.0
var alive: bool = true
var respawn_timer: float = 0.0
var spawn_transform: Transform3D
var aim_yaw: float = 0.0
var aim_point: Vector3 = Vector3.ZERO
## Match rule multiplier on this unit's damage to structures (rising tide).
var structure_bonus: float = 1.0
## Stunned: no movement, no casts, until the timer runs out.
var stun_timer: float = 0.0
## Dash in progress (DASH delivery): the sim moves the unit, not its input.
var dash_timer: float = 0.0
var dash_velocity: Vector3 = Vector3.ZERO
var dash_ability: AbilityDef
var dash_hit: Array[Unit] = []
## Last flat move direction from the command, in world space (dash aim).
var move_dir: Vector3 = Vector3.ZERO

## Progression (match rules feed xp; the unit applies levels and the pick).
const LEVEL_XP: Array[float] = [0.0, 300.0, 700.0, 1200.0, 1800.0]  # xp to reach levels 1..5
const HEALTH_PER_LEVEL := 0.07
const DAMAGE_PER_LEVEL := 0.06
const UPGRADE_LEVEL := 3
signal leveled(level: int)
signal upgraded(slot: int, a: AbilityDef)
var max_health: float = 0.0
var level: int = 1
var xp: float = 0.0
## Damage multiplier from level (champions only).
var damage_mult: float = 1.0
## Slot -> AbilityDef chosen as an upgrade (replaces the def's ability).
var slot_overrides := {}
## True while an upgrade offer waits for a pick.
var upgrade_pending: bool = false

var cast_phase: CastPhase = CastPhase.NONE
var cast_slot: int = -1
var cast_timer: float = 0.0
var cast_target: Vector3 = Vector3.ZERO
var cooldowns: PackedFloat32Array = PackedFloat32Array()
var buffered_slot: int = -1
var buffer_timer: float = 0.0

var slow_amount: float = 0.0
var slow_timer: float = 0.0

## Lock-on target for homing abilities, chosen at cast start.
var cast_target_unit: Unit
## While any of these is alive this unit cannot be damaged (a core behind its tower).
var protectors: Array[Unit] = []
## Seconds a dead unit that never respawns stays before removal (minions).
var corpse_timer: float = 1.0
## Last unit that damaged this one and when (authority time), for tower aggro.
var last_attacker: Unit
var last_attacked_at: float = -100.0


func _ready() -> void:
	collision_layer = LAYER_UNITS
	# Units do not body-block each other for now. Overlapping CharacterBody3D
	# capsules were pushed apart faster than run speed (29 m/s measured), and
	# a MOBA needs a deliberate rule for champion and minion blocking anyway.
	collision_mask = LAYER_WORLD
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = def.radius
	capsule.height = def.height
	shape.shape = capsule
	shape.position.y = def.height * 0.5
	add_child(shape)
	spawn_transform = global_transform
	aim_yaw = rotation.y
	cooldowns.resize(def.slot_count())
	max_health = def.max_health
	health = max_health


## The ability in a slot for this unit (an upgrade pick replaces the def's).
func get_slot(slot: int) -> AbilityDef:
	return slot_overrides.get(slot, def.get_slot(slot))


## The two upgrades offered for slot 1, if any.
func upgrade_options() -> Array[AbilityDef]:
	var out: Array[AbilityDef] = []
	var a := def.get_slot(1)
	if a:
		for u in a.upgrades:
			out.append(u as AbilityDef)
	return out


func add_xp(amount: float) -> void:
	if def.kind != ChampionDef.Kind.CHAMPION or amount <= 0.0:
		return
	xp += amount
	while level < LEVEL_XP.size() and xp >= LEVEL_XP[level]:
		level += 1
		var frac := health / max_health
		max_health = def.max_health * (1.0 + HEALTH_PER_LEVEL * (level - 1))
		damage_mult = 1.0 + DAMAGE_PER_LEVEL * (level - 1)
		if alive:
			health = max_health * frac
		if level == UPGRADE_LEVEL and upgrade_options().size() == 2:
			upgrade_pending = true
		leveled.emit(level)


func choose_upgrade(option: int) -> void:
	var opts := upgrade_options()
	if not upgrade_pending or option < 1 or option > opts.size():
		return
	upgrade_pending = false
	slot_overrides[1] = opts[option - 1]
	upgraded.emit(1, opts[option - 1])


func is_casting() -> bool:
	return cast_phase != CastPhase.NONE


func cast_ability() -> AbilityDef:
	return get_slot(cast_slot) if cast_slot >= 0 else null


func cooldown_fraction(slot: int) -> float:
	var a := get_slot(slot)
	if a == null or a.cooldown <= 0.0:
		return 0.0
	return clampf(cooldowns[slot] / a.cooldown, 0.0, 1.0)


func current_move_speed() -> float:
	var speed := def.move_speed * (1.0 - slow_amount)
	if is_casting():
		var a := cast_ability()
		speed *= a.move_mult_while_casting if a else 1.0
	return speed


func forward() -> Vector3:
	return Vector3(-sin(aim_yaw), 0.0, -cos(aim_yaw))


## Height projectiles fly at and the point aim checks are made from.
func muzzle_position() -> Vector3:
	return global_position + Vector3(0, def.height * 0.6, 0) + forward() * (def.radius + 0.1)


func sim_step(cmd: UnitCommand, dt: float, authority: CombatAuthority) -> void:
	if not alive:
		return
	for i in cooldowns.size():
		cooldowns[i] = maxf(0.0, cooldowns[i] - dt)
	if slow_timer > 0.0:
		slow_timer -= dt
		if slow_timer <= 0.0:
			slow_amount = 0.0

	if cmd.upgrade_choice > 0:
		choose_upgrade(cmd.upgrade_choice)
	if stun_timer > 0.0:
		# Stunned: the aim stays where it was, nothing is buffered, no movement.
		stun_timer -= dt
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * dt
		move_and_slide()
		return
	aim_yaw = cmd.aim_yaw
	aim_point = cmd.aim_point
	rotation.y = aim_yaw

	_update_buffer(cmd, dt)
	_advance_cast(dt, authority)
	if not is_casting() and buffered_slot >= 0:
		_try_start_cast(buffered_slot, cmd, authority)

	var dir := Vector3(cmd.move.x, 0.0, -cmd.move.y).limit_length(1.0).rotated(Vector3.UP, aim_yaw)
	move_dir = dir
	var speed := current_move_speed()
	var top_speed := def.move_speed
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if dash_timer > 0.0:
		dash_timer -= dt
		velocity.x = dash_velocity.x
		velocity.z = dash_velocity.z
		top_speed = dash_velocity.length()
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * dt
	var before := global_position
	move_and_slide()
	if dash_timer > 0.0 or dash_ability != null:
		authority.dash_contact(self, before)
		if dash_timer <= 0.0:
			dash_ability = null
	# Guard: the physics step may never carry a unit faster than its speed.
	var moved := Vector2(global_position.x - before.x, global_position.z - before.z)
	var limit := maxf(top_speed, 0.01) * dt * 1.02
	if moved.length() > limit:
		var fixed := moved.limit_length(limit)
		global_position = Vector3(before.x + fixed.x, global_position.y, before.z + fixed.y)


func _update_buffer(cmd: UnitCommand, dt: float) -> void:
	if buffer_timer > 0.0:
		buffer_timer -= dt
		if buffer_timer <= 0.0:
			buffered_slot = -1
	# Abilities win over the held basic attack. When several are pressed at
	# once, a ready one wins over one still on cooldown.
	var want := -1
	for slot in range(1, def.slot_count()):
		if cmd.pressed(UnitCommand.ability_button(slot)) and (want < 0 or (cooldowns[want] > 0.0 and cooldowns[slot] <= 0.0)):
			want = slot
	if want > 0:
		buffered_slot = want
		buffer_timer = INPUT_BUFFER
	elif cmd.pressed(UnitCommand.BTN_ATTACK) and buffered_slot < 0:
		buffered_slot = 0
		buffer_timer = INPUT_BUFFER


func _try_start_cast(slot: int, cmd: UnitCommand, authority: CombatAuthority) -> void:
	var a := get_slot(slot)
	if a == null or cooldowns[slot] > 0.0:
		# Keep an ability press only if it will come off cooldown within the
		# buffer window; otherwise drop it so the basic attack is not blocked.
		if a == null or slot == 0 or cooldowns[slot] > buffer_timer:
			if a != null and slot != 0:
				cast_rejected.emit(slot, "%s ready in %.1f s" % [a.display_name, cooldowns[slot]])
			buffered_slot = -1
		return
	buffered_slot = -1
	cast_target_unit = null
	if a.homing:
		var t := authority.find_unit(cmd.target_id)
		if t == null or not t.alive or not authority.are_enemies(self, t) \
				or _flat_distance(t) > a.range + t.def.radius:
			return  # no valid lock: nothing happens, no cooldown spent
		cast_target_unit = t
	cast_slot = slot
	cast_phase = CastPhase.WINDUP
	cast_timer = a.cast_time
	# Cooldown runs from the moment the cast commits, so "cooldown 0.85"
	# means one attack every 0.85 s when held.
	cooldowns[slot] = a.cooldown
	cast_target = clamp_target(a, aim_point)
	cast_started.emit(slot, a, cast_target)


func _flat_distance(other: Unit) -> float:
	return Vector2(other.global_position.x - global_position.x, other.global_position.z - global_position.z).length()


## Ground targets are clamped to range; projectiles keep only the direction.
func clamp_target(a: AbilityDef, point: Vector3) -> Vector3:
	var from := global_position
	var flat := Vector3(point.x - from.x, 0.0, point.z - from.z)
	if flat.length() < 0.5:
		flat = forward()
	if a.delivery == AbilityDef.Delivery.GROUND_AREA:
		flat = flat.limit_length(a.range)
	elif a.delivery == AbilityDef.Delivery.WARD:
		return Vector3(from.x, from.y, from.z)
	elif a.delivery == AbilityDef.Delivery.DASH:
		# Dashes go the way the unit is moving (WASD), forward when standing.
		var d := move_dir if move_dir.length() > 0.1 else forward()
		d.y = 0.0
		d = d.normalized() * a.dash_distance
		return Vector3(from.x + d.x, from.y, from.z + d.z)
	else:
		flat = flat.normalized() * a.range
	return Vector3(from.x + flat.x, from.y, from.z + flat.z)


func _advance_cast(dt: float, authority: CombatAuthority) -> void:
	if cast_phase == CastPhase.NONE:
		return
	var a := cast_ability()
	cast_timer -= dt
	if cast_phase == CastPhase.WINDUP:
		# Ground targets follow the aim during windup; projectiles too, so the
		# release goes where the player is looking at that moment.
		cast_target = clamp_target(a, aim_point)
		if a.homing and cast_target_unit:
			cast_target = cast_target_unit.global_position
		if cast_timer <= 0.0:
			if a.homing and (cast_target_unit == null or not is_instance_valid(cast_target_unit) or not cast_target_unit.alive):
				interrupt_cast()  # target gone during the windup
				return
			cast_released.emit(cast_slot, a, cast_target)
			authority.release_ability(self, a, cast_target, cast_target_unit)
			cast_phase = CastPhase.RECOVERY
			cast_timer += a.recovery
	if cast_phase == CastPhase.RECOVERY and cast_timer <= 0.0:
		cast_phase = CastPhase.NONE
		cast_slot = -1


func start_dash(a: AbilityDef, target: Vector3) -> void:
	var dir := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	if dir.length() < 0.1:
		dir = forward()
	dash_velocity = dir.normalized() * (a.dash_distance / maxf(a.dash_duration, 0.01))
	dash_timer = a.dash_duration
	dash_ability = a
	dash_hit.clear()


func interrupt_cast() -> void:
	dash_timer = 0.0
	dash_ability = null
	cast_phase = CastPhase.NONE
	cast_slot = -1
	buffered_slot = -1
	cast_target_unit = null


func is_protected() -> bool:
	for p in protectors:
		if is_instance_valid(p) and p.alive:
			return true
	return false


## Stun: interrupts any cast (and dash), longest stun wins.
func apply_stun(duration: float) -> void:
	if duration <= 0.0:
		return
	interrupt_cast()
	stun_timer = maxf(stun_timer, duration)


func is_stunned() -> bool:
	return stun_timer > 0.0


func apply_slow(amount: float, duration: float) -> void:
	# Strongest slow wins; durations do not stack.
	if amount >= slow_amount or slow_timer <= 0.0:
		slow_amount = amount
		slow_timer = maxf(slow_timer, duration)


## Called by the authority only.
func set_dead(killer: Unit) -> void:
	alive = false
	health = 0.0
	interrupt_cast()
	slow_amount = 0.0
	slow_timer = 0.0
	stun_timer = 0.0
	respawn_timer = def.respawn_time
	corpse_timer = 1.0
	velocity = Vector3.ZERO
	collision_layer = 0
	died.emit(killer)


## Called by the authority only.
func respawn() -> void:
	global_transform = spawn_transform
	aim_yaw = spawn_transform.basis.get_euler().y
	alive = true
	health = max_health
	for i in cooldowns.size():
		cooldowns[i] = 0.0
	collision_layer = LAYER_UNITS
	respawned.emit()
