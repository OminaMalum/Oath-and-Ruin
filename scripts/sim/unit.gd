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
## Structures also sit on this layer so the camera arm can avoid them.
const LAYER_STRUCTURE := 4
## World geometry a grapple chain may hook onto (set beside LAYER_WORLD on
## approved walls only; see GrappleAnchors).
const LAYER_ANCHOR := 8
## After a grapple press with no valid anchor, the next try waits this long.
const GRAPPLE_RETRY := 0.3

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

## Gold and items. The match pays gold in; buy_item() is the only way out.
## Two catalogs: CLASSIC (four flat items, the baseline) and ADVENTURER
## (components, recipes, boots, selling). One for the whole match, chosen
## before it starts with use_economy(); every peer must use the same one.
const CLASSIC_ECONOMY := preload("res://data/economy.tres")
const ADVENTURER_ECONOMY := preload("res://data/economy_adventurer.tres")
static var ECONOMY: EconomyDef = CLASSIC_ECONOMY
signal item_sold(item: ItemDef, gold: float)
## Gold that came with a place to show it (last hit, kill): the HUD pops it up.
signal gold_earned(amount: float, at: Vector3)
signal item_bought(item: ItemDef)
var gold: float = 0.0
var items: Array[ItemDef] = []
## Own fountain; buying works within ECONOMY.shop_radius of it, or while dead.
## INF: this unit has no shop (training, minions).
var shop_point: Vector3 = Vector3.INF
## From items: multiplies ability cooldowns (Q, E, R) and walking speed.
var cooldown_mult: float = 1.0
var speed_mult: float = 1.0
## From adventurer items (see ItemDef for what each point does).
var weapon_power: float = 0.0
var spell_power: float = 0.0
var armor: float = 0.0
var magic_resist: float = 0.0
var attack_speed: float = 0.0
var ability_haste: float = 0.0
## Shield: soaks damage before health, gone when the timer ends.
var shield: float = 0.0
var shield_timer: float = 0.0
## Item passive state, kept by the authority. Keys are item and target ids;
## values are authority times. Selling an item never clears these, so a
## sell and rebuy cannot reset a passive.
var item_ready_at := {}
var item_counters := {}
## Recall home: counts down while the champion stands still; 0 when not recalling.
signal recall_started
signal recall_cancelled(reason: String)
signal recalled
var recall_timer: float = 0.0

## Progression (match rules feed xp; the unit applies levels and the pick).
const LEVEL_XP: Array[float] = [0.0, 220.0, 500.0, 850.0, 1300.0]  # xp to reach levels 1..5
const HEALTH_PER_LEVEL := 0.07
const DAMAGE_PER_LEVEL := 0.06
const UPGRADE_LEVEL := 3
## Ultimates (AbilityDef.is_ultimate) can be cast from this level.
const ULT_LEVEL := 4
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
## INSCRIBE passive: basic attack hits landed per target (net_id -> count).
var hit_streak := {}
## MARGINALIA and QUARRY marks this unit has put on others:
## net_id -> Vector2(count, authority time placed).
var passive_marks := {}
## STAND_BEHIND: primed until this authority time; ready again at the other.
var passive_primed_until: float = -1.0
var passive_ready_at: float = -1.0
## FLAME embers, FURY fury (0 to 100), RESIDUAL charges.
var passive_stacks: float = 0.0
## Authority time this champion last dealt or took champion damage.
var champion_fight_at: float = -100.0
## REFRAIN: the last of slot 1 or 2 cast, and when (authority time).
var refrain_slot: int = -1
var refrain_at: float = -100.0

var cast_phase: CastPhase = CastPhase.NONE
var cast_slot: int = -1
var cast_timer: float = 0.0
var cast_target: Vector3 = Vector3.ZERO
var cooldowns: PackedFloat32Array = PackedFloat32Array()
## Abilities with max_charges > 1: uses left, and time until the next comes
## back (one at a time). cooldowns[slot] is then only the short charge_lock.
var charges: PackedInt32Array = PackedInt32Array()
var recharge: PackedFloat32Array = PackedFloat32Array()
var buffered_slot: int = -1
var buffer_timer: float = 0.0

var slow_amount: float = 0.0
var slow_timer: float = 0.0
## Rooted: no walking or dashing; attacks and casts still work.
var root_timer: float = 0.0
## Marked: takes mark_amount more damage from every source.
var mark_amount: float = 0.0
var mark_timer: float = 0.0
## Taunt or charm: the unit's own command is replaced while the timer runs
## (see _compelled). compel_point is the caster's position, kept fresh by the
## server each tick and sent in snapshots, so a client predicts the same walk.
enum Compel { NONE, TAUNT, CHARM }
var compel: Compel = Compel.NONE
var compel_timer: float = 0.0
var compel_point: Vector3 = Vector3.ZERO
var compel_source: Unit
## Haste: basic attacks come this much sooner. Quick: moves this much faster.
var haste_amount: float = 0.0
var haste_timer: float = 0.0
var quick_amount: float = 0.0
var quick_timer: float = 0.0
## Healing cut: heals on this unit are cut by heal_cut (strongest wins).
var heal_cut: float = 0.0
var heal_cut_timer: float = 0.0
## Burn (Cinder Reliquary): damage per second from burn_source, one at a time;
## a new burn refreshes it rather than stacking.
var burn_source: Unit
var burn_dps: float = 0.0
var burn_timer: float = 0.0
## Authority time of the last damage taken from a champion (Cairnheart).
var last_champion_hit_at: float = -100.0
## Weakened: this unit's damage is cut by weaken_amount (strongest wins).
var weaken_amount: float = 0.0
var weaken_timer: float = 0.0
## Grapple in flight: the wall point the chain holds, and where travel began
## (kept across a redirect, so MOMENTUM measures the whole route).
var grapple_anchor: Vector3 = Vector3.ZERO
var grapple_from: Vector3 = Vector3.ZERO
## Why the last grapple_endpoint call found no anchor (player feedback).
var grapple_problem: String = ""

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
	collision_layer = LAYER_UNITS | (LAYER_STRUCTURE if def.kind == ChampionDef.Kind.STRUCTURE else 0)
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
	charges.resize(def.slot_count())
	recharge.resize(def.slot_count())
	_fill_charges()
	max_health = def.max_health
	health = max_health


func _fill_charges() -> void:
	for i in charges.size():
		var a := get_slot(i)
		charges[i] = a.max_charges if a else 0
		recharge[i] = 0.0


func is_charged(slot: int) -> bool:
	var a := get_slot(slot)
	return a != null and a.max_charges > 1


## Charges come back one at a time, each taking the ability's cooldown.
func _step_charges(dt: float) -> void:
	for i in recharge.size():
		if recharge[i] <= 0.0:
			continue
		recharge[i] -= dt
		if recharge[i] <= 0.0:
			var a := get_slot(i)
			charges[i] = mini(charges[i] + 1, a.max_charges if a else 1)
			recharge[i] = cooldown_for(i, a) + recharge[i] if a and charges[i] < a.max_charges else 0.0


## Seconds until a press of `slot` can start a cast (0 = now).
func ready_in(slot: int) -> float:
	if is_charged(slot) and charges[slot] <= 0:
		return maxf(cooldowns[slot], recharge[slot])
	return cooldowns[slot]


## A committed cast spends its cooldown, or one charge and the short lock.
func _commit_cooldown(slot: int, a: AbilityDef) -> void:
	if a.max_charges > 1:
		charges[slot] = maxi(charges[slot] - 1, 0)
		cooldowns[slot] = a.charge_lock
		if recharge[slot] <= 0.0:
			recharge[slot] = cooldown_for(slot, a)
	else:
		cooldowns[slot] = cooldown_for(slot, a)


## A charge given back (a launch that could not happen).
func _refund_charge(slot: int) -> void:
	var a := get_slot(slot)
	if a == null or a.max_charges <= 1:
		return
	charges[slot] = mini(charges[slot] + 1, a.max_charges)
	if charges[slot] >= a.max_charges:
		recharge[slot] = 0.0


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
		recompute_stats()
		if level == UPGRADE_LEVEL and upgrade_options().size() == 2:
			upgrade_pending = true
		leveled.emit(level)


## Level and item bonuses to max health, damage, cooldowns and speed. Health
## keeps its fraction, so a level or an item never heals or hurts.
func recompute_stats(set_max_health: bool = true) -> void:
	var hp := 0.0
	var dmg := 0.0
	var cdr := 0.0
	var spd := 0.0
	weapon_power = 0.0
	spell_power = 0.0
	armor = 0.0
	magic_resist = 0.0
	attack_speed = 0.0
	ability_haste = 0.0
	for it in items:
		hp += it.health
		dmg += it.damage
		cdr += it.cooldown
		spd += it.move_speed
		weapon_power += it.weapon_power
		spell_power += it.spell_power
		armor += it.armor
		magic_resist += it.magic_resist
		attack_speed += it.attack_speed
		ability_haste += it.haste
	ability_haste = minf(ability_haste, ECONOMY.haste_cap)
	damage_mult = (1.0 + DAMAGE_PER_LEVEL * (level - 1)) * (1.0 + dmg)
	cooldown_mult = clampf(1.0 - cdr, 0.4, 1.0) * 100.0 / (100.0 + ability_haste)
	speed_mult = 1.0 + spd
	if set_max_health:
		var frac := health / max_health if max_health > 0.0 else 1.0
		max_health = def.max_health * (1.0 + HEALTH_PER_LEVEL * (level - 1)) + hp
		if alive:
			health = max_health * frac


func add_gold(amount: float, at: Vector3 = Vector3.INF) -> void:
	if def.kind != ChampionDef.Kind.CHAMPION or amount <= 0.0:
		return
	gold += amount
	if at.is_finite():
		gold_earned.emit(amount, at)


func can_shop() -> bool:
	if not shop_point.is_finite():
		return false
	return not alive or _flat_distance_to(shop_point) <= ECONOMY.shop_radius


## How buying item `index` (1-based, ECONOMY.items) would go now:
## {item, price, consume (owned item positions the recipe uses), problem}.
## problem is "" when it can be bought.
func purchase_plan(index: int) -> Dictionary:
	var plan := {"item": null, "price": 0, "consume": [], "problem": ""}
	if index < 1 or index > ECONOMY.items.size():
		plan.problem = "No such item"
		return plan
	var it: ItemDef = ECONOMY.items[index - 1]
	plan.item = it
	var consume: Array[int] = []
	var price := it.cost
	for part: ItemDef in it.recipe:
		for n in items.size():
			if items[n] == part and n not in consume:
				consume.append(n)
				price -= part.cost
				break
	plan.consume = consume
	plan.price = price
	if it.kind != ItemDef.Kind.COMPONENT and items.has(it):
		plan.problem = "You already own %s" % it.display_name
	elif it.kind == ItemDef.Kind.STARTER and _owns_kind(ItemDef.Kind.STARTER):
		plan.problem = "You can carry one starter item"
	elif it.kind == ItemDef.Kind.BOOTS and _owns_kind(ItemDef.Kind.BOOTS):
		plan.problem = "You can wear one pair of boots"
	elif items.size() - consume.size() >= ECONOMY.slots:
		plan.problem = "Your item slots are full"
	elif not can_shop():
		plan.problem = "The shop opens at your fountain or while you wait to respawn"
	elif gold < price:
		plan.problem = "%s needs %d more gold" % [it.display_name, ceili(price - gold)]
	return plan


func _owns_kind(kind: ItemDef.Kind) -> bool:
	for it in items:
		if it.kind == kind:
			return true
	return false


func has_item(id: StringName) -> bool:
	for it in items:
		if it.id == id:
			return true
	return false


## Why item `index` (1-based, ECONOMY.items) cannot be bought now; "" if it can.
func buy_problem(index: int) -> String:
	return purchase_plan(index).problem


## Buys in one step: gold and recipe components go out, the item comes in.
## A failed buy changes nothing.
func buy_item(index: int) -> bool:
	var plan := purchase_plan(index)
	if not plan.problem.is_empty():
		cast_rejected.emit(-1, plan.problem)
		return false
	var it: ItemDef = plan.item
	var consume: Array = plan.consume
	consume.sort()
	consume.reverse()
	for n: int in consume:
		items.remove_at(n)
	gold -= plan.price
	items.append(it)
	recompute_stats()
	item_bought.emit(it)
	return true


## Gold back for the item in inventory position `slot` (1-based); 0 if none.
func sell_value(slot: int) -> float:
	if slot < 1 or slot > items.size():
		return 0.0
	return floorf(items[slot - 1].cost * ECONOMY.sell_fraction)


func sell_problem(slot: int) -> String:
	if ECONOMY.sell_fraction <= 0.0:
		return "Items cannot be sold"
	if slot < 1 or slot > items.size():
		return "No item there"
	if not can_shop():
		return "Sell at your fountain or while you wait to respawn"
	return ""


func sell_item(slot: int) -> bool:
	var problem := sell_problem(slot)
	if not problem.is_empty():
		cast_rejected.emit(-1, problem)
		return false
	var it: ItemDef = items[slot - 1]
	var value := sell_value(slot)
	items.remove_at(slot - 1)
	gold += value
	recompute_stats()
	item_sold.emit(it, value)
	return true


## Network: the inventory as ECONOMY.items indices, in order.
func item_indices() -> PackedByteArray:
	var out := PackedByteArray()
	for it in items:
		out.append(maxi(ECONOMY.items.find(it), 0))
	return out


func set_item_indices(list: PackedByteArray) -> void:
	items.clear()
	for i in list:
		if i < ECONOMY.items.size():
			items.append(ECONOMY.items[i])
	recompute_stats(false)


func _flat_distance_to(p: Vector3) -> float:
	return Vector2(global_position.x - p.x, global_position.z - p.z).length()


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
	if a.max_charges > 1:
		if charges[slot] > 0:
			return clampf(cooldowns[slot] / maxf(a.charge_lock, 0.01), 0.0, 1.0)
		return clampf(ready_in(slot) / cooldown_for(slot, a), 0.0, 1.0)
	return clampf(cooldowns[slot] / cooldown_for(slot, a), 0.0, 1.0)


## The cooldown a cast from `slot` starts: items shorten abilities, not basics.
func cooldown_for(slot: int, a: AbilityDef) -> float:
	return a.cooldown * cooldown_mult if slot > 0 else a.cooldown / (1.0 + haste_amount + attack_speed)


func current_move_speed() -> float:
	var speed := def.move_speed * speed_mult * (1.0 + quick_amount) * (1.0 - slow_amount)
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
	if cmd.buy_item > 0:
		buy_item(cmd.buy_item)  # dead champions can shop too
	if cmd.sell_item > 0:
		sell_item(cmd.sell_item)
	if not alive:
		return
	for i in cooldowns.size():
		cooldowns[i] = maxf(0.0, cooldowns[i] - dt)
	_step_charges(dt)
	if slow_timer > 0.0:
		slow_timer -= dt
		if slow_timer <= 0.0:
			slow_amount = 0.0
	_step_status(dt)
	if _step_recall(cmd, dt):
		return

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
	cmd = _compelled(cmd)
	aim_yaw = cmd.aim_yaw
	aim_point = cmd.aim_point
	rotation.y = aim_yaw

	_update_buffer(cmd, dt)
	_advance_cast(dt, authority)
	if not is_casting() and buffered_slot >= 0:
		_try_start_cast(buffered_slot, cmd, authority)
	step_motion(cmd, dt, authority)


## Movement for one tick: walk (or dash), gravity, collide, speed guard.
## The server runs it inside sim_step; a networked client runs the same code
## to predict its own champion (authority null: no dash hits).
func step_motion(cmd: UnitCommand, dt: float, authority: CombatAuthority) -> void:
	var dir := Vector3(cmd.move.x, 0.0, -cmd.move.y).limit_length(1.0).rotated(Vector3.UP, aim_yaw)
	move_dir = dir
	var speed := current_move_speed()
	var top_speed := def.move_speed * speed_mult * (1.0 + quick_amount)
	if root_timer > 0.0:
		speed = 0.0
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if dash_timer > 0.0:
		var part := 1.0
		if dash_ability and dash_ability.delivery == AbilityDef.Delivery.GRAPPLE and dash_timer < dt:
			part = dash_timer / dt  # land on the checked point, not a tick past it
		dash_timer -= dt
		velocity.x = dash_velocity.x * part
		velocity.z = dash_velocity.z * part
		top_speed = dash_velocity.length()
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * dt
	var before := global_position
	move_and_slide()
	if authority and (dash_timer > 0.0 or dash_ability != null):
		authority.dash_contact(self, before)
		if dash_timer <= 0.0:
			if dash_ability and dash_ability.delivery == AbilityDef.Delivery.GRAPPLE:
				authority.grapple_finished(self, dash_ability)
			dash_ability = null
	# Guard: the physics step may never carry a unit faster than its speed.
	var moved := Vector2(global_position.x - before.x, global_position.z - before.z)
	var limit := maxf(top_speed, 0.01) * dt * 1.02
	if moved.length() > limit:
		var fixed := moved.limit_length(limit)
		global_position = Vector3(before.x + fixed.x, global_position.y, before.z + fixed.y)


## Client-side prediction of one tick for the local champion. Mirrors the
## parts of sim_step that decide where the unit ends up (timers, stun, cast
## start and its move slow, dash, walking) and nothing that decides results:
## releases, hits, damage and real cooldowns stay with the server, and the
## next snapshot overwrites everything predicted here.
func predict_step(cmd: UnitCommand, dt: float) -> void:
	if not alive:
		return
	for i in cooldowns.size():
		cooldowns[i] = maxf(0.0, cooldowns[i] - dt)
	_step_charges(dt)
	if slow_timer > 0.0:
		slow_timer -= dt
		if slow_timer <= 0.0:
			slow_amount = 0.0
	_step_status(dt)
	if stun_timer > 0.0:
		stun_timer -= dt
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * dt
		move_and_slide()
		return
	cmd = _compelled(cmd)
	aim_yaw = cmd.aim_yaw
	aim_point = cmd.aim_point
	rotation.y = aim_yaw
	_update_buffer(cmd, dt)
	if cast_phase != CastPhase.NONE:
		var a := cast_ability()
		cast_timer -= dt
		if cast_phase == CastPhase.WINDUP and cast_timer <= 0.0:
			if a and a.delivery == AbilityDef.Delivery.DASH:
				start_dash(a, clamp_target(a, aim_point))
			elif a and a.delivery == AbilityDef.Delivery.GRAPPLE:
				start_grapple(a, cast_target)
			cast_phase = CastPhase.RECOVERY
			cast_timer += a.recovery if a else 0.0
		if cast_phase == CastPhase.RECOVERY and cast_timer <= 0.0:
			cast_phase = CastPhase.NONE
			cast_slot = -1
	if cast_phase == CastPhase.NONE and buffered_slot >= 0:
		var a := get_slot(buffered_slot)
		var grapple_at := clamp_target(a, aim_point) if a and a.delivery == AbilityDef.Delivery.GRAPPLE else Vector3.ZERO
		if a != null and ready_in(buffered_slot) <= 0.0 and not a.homing and grapple_at.is_finite() \
				and not (a.is_ultimate and not ultimate_ready_level()):
			cast_slot = buffered_slot
			cast_phase = CastPhase.WINDUP
			cast_timer = a.cast_time
			if a.delivery == AbilityDef.Delivery.GRAPPLE:
				cast_target = grapple_at
			_commit_cooldown(buffered_slot, a)
			buffered_slot = -1
		elif a == null or ready_in(buffered_slot) > buffer_timer or not grapple_at.is_finite():
			buffered_slot = -1
	step_motion(cmd, dt, null)


## Status timers both the server and a predicting client count down.
func _step_status(dt: float) -> void:
	root_timer = maxf(0.0, root_timer - dt)
	if shield_timer > 0.0:
		shield_timer -= dt
		if shield_timer <= 0.0:
			shield = 0.0
	if mark_timer > 0.0:
		mark_timer -= dt
		if mark_timer <= 0.0:
			mark_amount = 0.0
	if haste_timer > 0.0:
		haste_timer -= dt
		if haste_timer <= 0.0:
			haste_amount = 0.0
	if quick_timer > 0.0:
		quick_timer -= dt
		if quick_timer <= 0.0:
			quick_amount = 0.0
	if weaken_timer > 0.0:
		weaken_timer -= dt
		if weaken_timer <= 0.0:
			weaken_amount = 0.0
	if heal_cut_timer > 0.0:
		heal_cut_timer -= dt
		if heal_cut_timer <= 0.0:
			heal_cut = 0.0
	if compel_timer > 0.0:
		compel_timer -= dt
		if compel_source != null and (not is_instance_valid(compel_source) or not compel_source.alive):
			compel_timer = 0.0  # the caster died: free at once
		elif compel_source != null:
			compel_point = compel_source.global_position
		if compel_timer <= 0.0:
			_end_compel()


func _end_compel() -> void:
	compel = Compel.NONE
	compel_timer = 0.0
	compel_source = null


## While taunted or charmed the unit's own command is ignored. Taunted: face
## the caster, walk until in basic attack reach, hold the basic attack.
## Charmed: walk straight away from the caster, no attacks or abilities.
func _compelled(cmd: UnitCommand) -> UnitCommand:
	if compel_timer <= 0.0 or compel == Compel.NONE:
		return cmd
	var c := UnitCommand.new()
	c.buy_item = cmd.buy_item
	c.sell_item = cmd.sell_item
	var to := Vector3(compel_point.x - global_position.x, 0.0, compel_point.z - global_position.z)
	if to.length() < 0.05:
		to = forward()
	var d := to.normalized() if compel == Compel.TAUNT else -to.normalized()
	c.aim_yaw = atan2(-d.x, -d.z)
	if compel == Compel.TAUNT:
		c.aim_point = compel_point
		c.buttons = UnitCommand.BTN_ATTACK
		var reach := def.basic_attack.range * 0.8 if def.basic_attack else 2.0
		if to.length() > reach:
			c.move = Vector2(0.0, 1.0)
	else:
		c.aim_point = global_position + d * 5.0
		c.move = Vector2(0.0, 1.0)
	return c


func _update_buffer(cmd: UnitCommand, dt: float) -> void:
	if buffer_timer > 0.0:
		buffer_timer -= dt
		if buffer_timer <= 0.0:
			buffered_slot = -1
	# Abilities win over the held basic attack. When several are pressed at
	# once, a ready one wins over one still on cooldown.
	var want := -1
	for slot in range(1, def.slot_count()):
		if cmd.pressed(UnitCommand.ability_button(slot)) and (want < 0 or (ready_in(want) > 0.0 and ready_in(slot) <= 0.0)):
			want = slot
	if want > 0:
		buffered_slot = want
		buffer_timer = INPUT_BUFFER
	elif cmd.pressed(UnitCommand.BTN_ATTACK) and buffered_slot < 0:
		buffered_slot = 0
		buffer_timer = INPUT_BUFFER


func ultimate_ready_level() -> bool:
	return level >= ULT_LEVEL


func _try_start_cast(slot: int, cmd: UnitCommand, authority: CombatAuthority) -> void:
	var a := get_slot(slot)
	if a != null and a.is_ultimate and not ultimate_ready_level():
		cast_rejected.emit(slot, "%s unlocks at level %d" % [a.display_name, ULT_LEVEL])
		buffered_slot = -1
		return
	if a == null or ready_in(slot) > 0.0:
		# Keep an ability press only if it will come off cooldown within the
		# buffer window; otherwise drop it so the basic attack is not blocked.
		if a == null or slot == 0 or ready_in(slot) > buffer_timer:
			if a != null and slot != 0:
				cast_rejected.emit(slot, "%s ready in %.1f s" % [a.display_name, ready_in(slot)])
			buffered_slot = -1
		return
	buffered_slot = -1
	cast_target_unit = null
	if a.delivery == AbilityDef.Delivery.GRAPPLE:
		# The anchor is checked before anything is spent: no anchor, no charge,
		# a short wait and a message saying why.
		var at := clamp_target(a, aim_point)
		if not at.is_finite():
			cooldowns[slot] = maxf(cooldowns[slot], GRAPPLE_RETRY)
			cast_rejected.emit(slot, grapple_problem)
			return
		if root_timer > 0.0:
			cast_rejected.emit(slot, "Rooted: you cannot grapple")
			return
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
	_commit_cooldown(slot, a)
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
	if a.delivery == AbilityDef.Delivery.GROUND_AREA and a.line_width <= 0.0:
		flat = flat.limit_length(a.range)
	elif a.delivery == AbilityDef.Delivery.WARD:
		return Vector3(from.x, from.y, from.z)
	elif a.delivery == AbilityDef.Delivery.WALL:
		flat = flat.limit_length(a.range)
	elif a.delivery == AbilityDef.Delivery.GRAPPLE:
		return grapple_endpoint(a, point)
	elif a.delivery == AbilityDef.Delivery.GROUND_AREA and a.line_width > 0.0:
		flat = flat.normalized() * a.range  # a line: only the direction counts
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
		# release goes where the player is looking at that moment. A grapple
		# keeps the anchor checked when the cast began.
		if a.delivery != AbilityDef.Delivery.GRAPPLE:
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
	if root_timer > 0.0:
		cast_rejected.emit(-1, "Rooted: you cannot dash")
		return  # the cast is spent, the dash does not happen
	var dir := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	if dir.length() < 0.1:
		dir = forward()
	dash_velocity = dir.normalized() * (a.dash_distance / maxf(a.dash_duration, 0.01))
	dash_timer = a.dash_duration
	dash_ability = a
	dash_hit.clear()


## Where a grapple aimed at `point` would land, or Vector3.INF with the reason
## in grapple_problem. The chain flies flat from chest height along the aim;
## the first world surface it meets must be a marked anchor (LAYER_ANCHOR)
## and a wall (not a floor or a ledge top). The landing point stands off the
## wall by the unit's radius, must have ground under it, and the unit's own
## capsule must fit along the whole route (no passing through walls).
func grapple_endpoint(a: AbilityDef, point: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		grapple_problem = "No anchor"
		return Vector3.INF
	var dir := Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)
	if dir.length() < 0.5:
		dir = forward()
	dir = dir.normalized()
	var chest := global_position + Vector3(0.0, def.height * 0.6, 0.0)
	var ray := PhysicsRayQueryParameters3D.create(chest, chest + dir * a.range, LAYER_WORLD)
	var hit := space.intersect_ray(ray)
	if hit.is_empty():
		grapple_problem = "No wall in reach: aim at a wall within %d m" % roundi(a.range)
		return Vector3.INF
	var body := hit.collider as CollisionObject3D
	var normal: Vector3 = hit.normal
	if body == null or body.collision_layer & LAYER_ANCHOR == 0 or absf(normal.y) > 0.3:
		grapple_problem = "The chain cannot hold there"
		return Vector3.INF
	var flat_n := Vector3(normal.x, 0.0, normal.z).normalized()
	var hit_pos: Vector3 = hit.position
	var end := Vector3(hit_pos.x, global_position.y, hit_pos.z) + flat_n * (def.radius + 0.15)
	var travel := Vector3(end.x - global_position.x, 0.0, end.z - global_position.z)
	if travel.length() < 2.0:
		grapple_problem = "Too close to the wall"
		return Vector3.INF
	# Ground under the landing point.
	var down := PhysicsRayQueryParameters3D.create(end + Vector3(0, 1.0, 0), end - Vector3(0, 1.5, 0), LAYER_WORLD)
	var ground := space.intersect_ray(down)
	if ground.is_empty() or (ground.normal as Vector3).y < 0.7:
		grapple_problem = "No safe ground there"
		return Vector3.INF
	end.y = (ground.position as Vector3).y
	if not _route_clear(end):
		grapple_problem = "The way to that wall is blocked"
		return Vector3.INF
	grapple_problem = ""
	return end


## The unit's capsule can travel straight to `end` without touching a wall
## (checked a little off the floor so the floor itself does not count).
func _route_clear(end: Vector3) -> bool:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return false
	var shape := CapsuleShape3D.new()
	shape.radius = def.radius
	shape.height = def.height
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = LAYER_WORLD
	q.transform = Transform3D(Basis(), global_position + Vector3(0, def.height * 0.5 + 0.25, 0))
	q.motion = Vector3(end.x - global_position.x, end.y - global_position.y, end.z - global_position.z)
	var free := space.cast_motion(q)
	return not free.is_empty() and free[0] >= 0.999


## Launch along a checked grapple route. Roots keep the unit on the ground
## (the charge comes back); a launch that starts stays spent even if a stun
## or root cuts it short. A second grapple during travel redirects from here.
func start_grapple(a: AbilityDef, target: Vector3) -> bool:
	if not target.is_finite():
		return false
	var slot := cast_slot
	if root_timer > 0.0:
		cast_rejected.emit(slot, "Rooted: you cannot grapple")
		_refund_charge(slot)
		return false
	var d := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	if d.length() < 0.3:
		return false
	if not _route_clear(target):
		# Checked again at release: the unit may have moved since the press.
		cast_rejected.emit(slot, "The way to that wall is blocked")
		_refund_charge(slot)
		return false
	if dash_timer <= 0.0 or dash_ability == null or dash_ability.delivery != AbilityDef.Delivery.GRAPPLE:
		grapple_from = global_position
	dash_velocity = d.normalized() * a.grapple_speed
	dash_timer = d.length() / a.grapple_speed
	dash_ability = a
	dash_hit.clear()
	grapple_anchor = target + d.normalized() * (def.radius + 0.15) + Vector3(0, def.height * 0.6, 0)
	return true


func is_grappling() -> bool:
	return dash_timer > 0.0 and dash_ability != null and dash_ability.delivery == AbilityDef.Delivery.GRAPPLE


## Recall: a press starts it when the champion is free (not casting, not
## stunned, has a shop). While it runs the unit holds still; a move or any
## ability press cancels it. Returns true while recalling (the tick is used up).
func _step_recall(cmd: UnitCommand, dt: float) -> bool:
	if recall_timer <= 0.0:
		if cmd.pressed(UnitCommand.BTN_RECALL) and shop_point.is_finite() and not is_casting() \
				and stun_timer <= 0.0 and dash_timer <= 0.0:
			if can_shop():
				cast_rejected.emit(-1, "You are already home")
				return false
			recall_timer = ECONOMY.recall_time
			buffered_slot = -1
			recall_started.emit()
		else:
			return false
	if cmd.move.length() > 0.1:
		cancel_recall("Recall cancelled: you moved")
		return false
	if cmd.buttons & ~UnitCommand.BTN_RECALL != 0:
		cancel_recall("Recall cancelled")
		return false
	aim_yaw = cmd.aim_yaw
	rotation.y = aim_yaw
	velocity = Vector3(0.0, 0.0 if is_on_floor() else velocity.y - GRAVITY * dt, 0.0)
	move_and_slide()
	recall_timer -= dt
	if recall_timer <= 0.0:
		recall_timer = 0.0
		global_transform = spawn_transform
		aim_yaw = spawn_transform.basis.get_euler().y
		velocity = Vector3.ZERO
		reset_physics_interpolation()
		recalled.emit()
	return true


func cancel_recall(reason: String) -> void:
	if recall_timer <= 0.0:
		return
	recall_timer = 0.0
	recall_cancelled.emit(reason)


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
	cancel_recall("Recall cancelled: stunned")
	stun_timer = maxf(stun_timer, duration)


func is_stunned() -> bool:
	return stun_timer > 0.0


func apply_root(duration: float) -> void:
	if duration > 0.0:
		root_timer = maxf(root_timer, duration)
		if is_grappling():
			dash_timer = 0.0  # a root pulls a grappling unit down where it is
			dash_ability = null


func apply_heal_cut(amount: float, duration: float) -> void:
	if duration > 0.0 and (amount >= heal_cut or heal_cut_timer <= 0.0):
		heal_cut = amount
		heal_cut_timer = maxf(heal_cut_timer, duration)


func apply_weaken(amount: float, duration: float) -> void:
	if duration > 0.0 and (amount >= weaken_amount or weaken_timer <= 0.0):
		weaken_amount = amount
		weaken_timer = maxf(weaken_timer, duration)


func apply_mark(amount: float, duration: float) -> void:
	if duration > 0.0 and (amount >= mark_amount or mark_timer <= 0.0):
		mark_amount = amount
		mark_timer = maxf(mark_timer, duration)


## Taunt or charm from `source`: interrupts the current cast, longest wins.
func apply_compel(kind: Compel, source: Unit, duration: float) -> void:
	if duration <= 0.0 or duration < compel_timer:
		return
	interrupt_cast()
	cancel_recall("Recall cancelled: taunted" if kind == Compel.TAUNT else "Recall cancelled: charmed")
	compel = kind
	compel_timer = duration
	compel_source = source
	compel_point = source.global_position


func apply_haste(amount: float, duration: float) -> void:
	if amount >= haste_amount or haste_timer <= 0.0:
		haste_amount = amount
		haste_timer = maxf(haste_timer, duration)


func apply_quick(amount: float, duration: float) -> void:
	if amount >= quick_amount or quick_timer <= 0.0:
		quick_amount = amount
		quick_timer = maxf(quick_timer, duration)


## Drag the unit to `to` over `time` seconds (a pull). Uses the dash motion
## with no dash ability, so it hits nothing and walls still stop it.
func displace(to: Vector3, time: float = 0.25) -> void:
	var d := Vector3(to.x - global_position.x, 0.0, to.z - global_position.z)
	if d.length() < 0.05:
		return
	dash_velocity = d / time
	dash_timer = time
	dash_ability = null


## Rooted, slowed, stunned, taunted or charmed: what a TITHE passive punishes.
func is_impaired() -> bool:
	return root_timer > 0.0 or slow_timer > 0.0 or stun_timer > 0.0 or compel_timer > 0.0


## Shields never stack: the bigger one stays and the timer is refreshed.
func apply_shield(amount: float, duration: float) -> void:
	if not alive or amount <= 0.0:
		return
	shield = maxf(shield, amount)
	shield_timer = maxf(shield_timer, duration)


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
	recall_timer = 0.0
	slow_amount = 0.0
	slow_timer = 0.0
	root_timer = 0.0
	mark_amount = 0.0
	mark_timer = 0.0
	haste_amount = 0.0
	haste_timer = 0.0
	quick_amount = 0.0
	quick_timer = 0.0
	weaken_amount = 0.0
	weaken_timer = 0.0
	heal_cut = 0.0
	heal_cut_timer = 0.0
	burn_source = null
	burn_dps = 0.0
	burn_timer = 0.0
	shield = 0.0
	shield_timer = 0.0
	_end_compel()
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
	_fill_charges()
	hit_streak.clear()
	passive_marks.clear()
	passive_primed_until = -1.0
	passive_stacks = 0.0
	refrain_slot = -1
	collision_layer = LAYER_UNITS
	reset_physics_interpolation()  # drawn position jumps to the spawn, no slide across the map
	respawned.emit()
