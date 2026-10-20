extends SceneTree
## Headless gameplay tests. Each test builds a tiny world (floor, optional
## wall, authority, units driven by ScriptedController) and runs real
## physics ticks.
##   godot --headless --path . --fixed-fps 60 -s tests/run_tests.gd
## Exit code is the number of failures.

const SCRIBE := preload("res://data/champions/ruinscribe.tres")
const DUMMY := preload("res://data/champions/training_dummy.tres")
const DT := 1.0 / 60.0

var failures: int = 0
var checks: int = 0
var world: Node3D
var authority: CombatAuthority


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var tests := [
		"test_basic_attack_damage", "test_basic_attack_cadence", "test_ability_cooldown",
		"test_range_limit", "test_team_rule", "test_wall_blocks_projectile",
		"test_death_and_respawn", "test_area_can_be_dodged", "test_area_hits_and_slows",
		"test_bot_obeys_range_and_cooldown", "test_casting_slows_movement",
		"test_dead_units_ignore_commands", "test_command_roundtrip",
	]
	for t: String in tests:
		_make_world()
		var before := failures
		await call(t)
		print(("PASS " if failures == before else "FAIL ") + t)
		world.queue_free()
		await process_frame
	print("%d checks, %d failures" % [checks, failures])
	quit(failures)


func check(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		push_error("  check failed: " + what)
		print("  check failed: " + what)


func _make_world(with_wall := false) -> void:
	world = Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = Unit.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.5, 0)
	world.add_child(floor_body)
	authority = CombatAuthority.new()
	world.add_child(authority)


func add_wall(pos: Vector3, size: Vector3) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = Unit.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	b.add_child(shape)
	b.position = pos
	world.add_child(b)


func spawn(def: ChampionDef, team: int, pos: Vector3) -> Unit:
	var u := Unit.new()
	u.def = def
	u.team = team
	u.position = pos
	world.add_child(u)
	u.controller = ScriptedController.new()
	authority.register_unit(u)
	return u


func cmd(u: Unit) -> UnitCommand:
	return (u.controller as ScriptedController).command


## Face and aim at a point (the same thing a player's camera produces).
func aim(u: Unit, point: Vector3) -> void:
	var to := point - u.global_position
	cmd(u).aim_yaw = atan2(-to.x, -to.z)
	cmd(u).aim_point = point


func ticks(n: int) -> void:
	for i in n:
		await physics_frame


func secs(s: float) -> void:
	await ticks(roundi(s / DT))


# --- tests -----------------------------------------------------------------

func test_basic_attack_damage() -> void:
	var me := spawn(SCRIBE, 0, Vector3.ZERO)
	var target := spawn(DUMMY, 1, Vector3(0, 0, -8))
	await ticks(2)
	aim(me, target.global_position)
	var hits: Array[float] = []
	authority.unit_damaged.connect(func(t: Unit, amt: float, _s: Unit) -> void:
		if t == target: hits.append(amt))
	cmd(me).buttons = UnitCommand.BTN_ATTACK
	await ticks(1)
	cmd(me).buttons = 0
	# Not yet: windup is 0.15 s and travel to 8 m is about 0.23 s.
	await ticks(8)
	check(hits.is_empty(), "no damage before windup and travel finish")
	await secs(1.0)
	check(hits.size() == 1, "exactly one hit (got %d)" % hits.size())
	check(is_equal_approx(target.health, DUMMY.max_health - SCRIBE.basic_attack.damage),
		"dummy lost exactly basic damage (health %.1f)" % target.health)


func test_basic_attack_cadence() -> void:
	var me := spawn(SCRIBE, 0, Vector3.ZERO)
	var target := spawn(DUMMY, 1, Vector3(0, 0, -5))
	await ticks(2)
	aim(me, target.global_position)
	var n := {"releases": 0}  # lambdas capture locals by value; mutate a dict
	me.cast_released.connect(func(slot: int, _a: AbilityDef, _t: Vector3) -> void:
		if slot == 0: n.releases += 1)
	cmd(me).buttons = UnitCommand.BTN_ATTACK  # held
	await secs(3.0)
	cmd(me).buttons = 0
	# Casts start every 0.85 s (cooldown runs from cast start): releases at 0.15, 1.00, 1.85, 2.70 s.
	check(n.releases == 4, "held attack releases 4 times in 3 s (got %d)" % n.releases)


func test_ability_cooldown() -> void:
	var me := spawn(SCRIBE, 0, Vector3.ZERO)
	await ticks(2)
	aim(me, Vector3(0, 0, -8))
	var n := {"spawned": 0}
	authority.area_spawned.connect(func(_a: CombatAuthority.SimArea) -> void: n.spawned += 1)
	for i in 3:  # press, then spam during the cooldown
		cmd(me).buttons = UnitCommand.BTN_ABILITY_1
		await ticks(1)
		cmd(me).buttons = 0
		await secs(1.0)
	check(n.spawned == 1, "spamming Q during cooldown casts once (got %d)" % n.spawned)
	check(me.cooldowns[1] > 0.0, "ability is on cooldown")
	await secs(SCRIBE.get_slot(1).cooldown)
	cmd(me).buttons = UnitCommand.BTN_ABILITY_1
	await ticks(1)
	cmd(me).buttons = 0
	await secs(0.5)
	check(n.spawned == 2, "casts again after the cooldown (got %d)" % n.spawned)


func test_range_limit() -> void:
	var me := spawn(SCRIBE, 0, Vector3.ZERO)
	var far := spawn(DUMMY, 1, Vector3(0, 0, -(SCRIBE.basic_attack.range + 4.0)))
	await ticks(2)
	aim(me, far.global_position)
	var n := {"ended": 0}
	authority.projectile_ended.connect(func(_p: CombatAuthority.SimProjectile, _at: Vector3) -> void: n.ended += 1)
	cmd(me).buttons = UnitCommand.BTN_ATTACK
	await ticks(1)
	cmd(me).buttons = 0
	await secs(1.5)
	check(n.ended == 1, "projectile expired")
	check(far.health == DUMMY.max_health, "target beyond range untouched")
	check(authority.projectiles.is_empty(), "no projectiles left in flight")


func test_team_rule() -> void:
	var me := spawn(SCRIBE, 0, Vector3.ZERO)
	var ally := spawn(DUMMY, 0, Vector3(0, 0, -4))
	var enemy := spawn(DUMMY, 1, Vector3(0, 0, -9))
	await ticks(2)
	aim(me, enemy.global_position)
	cmd(me).buttons = UnitCommand.BTN_ATTACK
	await ticks(1)
	cmd(me).buttons = 0
	await secs(1.0)
	check(ally.health == DUMMY.max_health, "bolt passes through an ally without damage")
	check(enemy.health < DUMMY.max_health, "bolt hits the enemy behind the ally")


func test_wall_blocks_projectile() -> void:
	var me := spawn(SCRIBE, 0, Vector3.ZERO)
	var enemy := spawn(DUMMY, 1, Vector3(0, 0, -10))
	add_wall(Vector3(0, 1.5, -5), Vector3(4, 3, 0.6))
	await ticks(2)
	aim(me, enemy.global_position)
	cmd(me).buttons = UnitCommand.BTN_ATTACK
	await ticks(1)
	cmd(me).buttons = 0
	await secs(1.0)
	check(enemy.health == DUMMY.max_health, "wall stops the bolt")


func test_death_and_respawn() -> void:
	var fragile: ChampionDef = DUMMY.duplicate()
	fragile.max_health = 80.0
	fragile.respawn_time = 2.0
	var me := spawn(SCRIBE, 0, Vector3.ZERO)
	var enemy := spawn(fragile, 1, Vector3(0, 0, -6))
	await ticks(2)
	var spawn_pos := enemy.global_position
	aim(me, enemy.global_position)
	var n := {"deaths": 0, "killer": null}
	authority.unit_died.connect(func(_t: Unit, k: Unit) -> void:
		n.deaths += 1
		n.killer = k)
	cmd(me).buttons = UnitCommand.BTN_ATTACK
	await secs(1.5)  # two releases (0.15, 1.0) plus travel
	cmd(me).buttons = 0
	check(n.deaths == 1 and not enemy.alive, "two bolts (84) kill an 80 hp target")
	check(n.killer == me, "kill credited to the caster")
	check(enemy.collision_layer == 0, "dead unit has no collision")
	# Shots at a corpse do nothing.
	cmd(me).buttons = UnitCommand.BTN_ATTACK
	await secs(0.5)
	cmd(me).buttons = 0
	check(n.deaths == 1, "no second death while dead")
	await secs(2.0)
	check(enemy.alive, "respawned after respawn_time")
	check(enemy.health == fragile.max_health, "full health after respawn")
	check(enemy.global_position.distance_to(spawn_pos) < 0.05, "back at spawn point")
	check(enemy.collision_layer == Unit.LAYER_UNITS, "collision restored")


func test_area_can_be_dodged() -> void:
	var me := spawn(SCRIBE, 0, Vector3.ZERO)
	var runner := spawn(SCRIBE, 1, Vector3(0, 0, -8))
	await ticks(2)
	aim(me, runner.global_position)
	cmd(runner).aim_yaw = 0.0
	cmd(me).buttons = UnitCommand.BTN_ABILITY_1
	await ticks(1)
	cmd(me).buttons = 0
	await secs(0.35)  # windup (0.3 s) ends, glyph placed
	check(authority.areas.size() == 1, "glyph placed")
	cmd(runner).move = Vector2(1, 0)  # strafe right as soon as it appears
	await secs(1.0)
	check(runner.health == SCRIBE.max_health, "walking out during the telegraph avoids it (health %.0f)" % runner.health)


func test_area_hits_and_slows() -> void:
	var me := spawn(SCRIBE, 0, Vector3.ZERO)
	var target := spawn(SCRIBE, 1, Vector3(0, 0, -8))
	await ticks(2)
	aim(me, target.global_position)
	cmd(me).buttons = UnitCommand.BTN_ABILITY_1
	await ticks(1)
	cmd(me).buttons = 0
	await secs(1.2)
	var glyph := SCRIBE.get_slot(1)
	check(is_equal_approx(target.health, SCRIBE.max_health - glyph.damage), "standing in the glyph takes its damage")
	check(target.slow_amount == glyph.slow_amount and target.slow_timer > 0.0, "and is slowed")
	check(is_equal_approx(target.current_move_speed(), SCRIBE.move_speed * (1.0 - glyph.slow_amount)), "slow applies to move speed")
	check(me.health == SCRIBE.max_health, "caster is never hit by own glyph")
	await secs(glyph.slow_duration)
	check(target.slow_amount == 0.0, "slow wears off")


func test_bot_obeys_range_and_cooldown() -> void:
	var dummy := spawn(DUMMY, 1, Vector3.ZERO)
	var me := spawn(SCRIBE, 0, Vector3(0, 0, -30))
	var bot := SparringBot.new(authority)
	bot.sight_range = 40.0
	dummy.controller = bot
	var n := {"releases": 0}
	dummy.cast_released.connect(func(_s: int, _a: AbilityDef, _t: Vector3) -> void: n.releases += 1)
	await secs(2.0)
	check(n.releases == 0, "bot does not fire at a target out of range")
	me.global_position = Vector3(0, 0, -10)
	await secs(5.0)
	# Casts start at 0, 2.2, 4.4 s; windup 0.7: releases at 0.7, 2.9 (5.1 is outside).
	check(n.releases == 2, "bot fire rate obeys windup and cooldown (got %d)" % n.releases)
	check(me.health == SCRIBE.max_health - 2 * DUMMY.basic_attack.damage, "both bot shots hit a still target")


func test_casting_slows_movement() -> void:
	var me := spawn(SCRIBE, 0, Vector3.ZERO)
	await ticks(2)
	aim(me, Vector3(0, 0, -10))
	cmd(me).move = Vector2(0, 1)
	await ticks(10)
	var free_speed := Vector2(me.velocity.x, me.velocity.z).length()
	cmd(me).buttons = UnitCommand.BTN_ABILITY_1
	await ticks(3)
	var cast_speed := Vector2(me.velocity.x, me.velocity.z).length()
	check(is_equal_approx(free_speed, SCRIBE.move_speed), "full speed when free (%.2f)" % free_speed)
	check(is_equal_approx(cast_speed, SCRIBE.move_speed * SCRIBE.get_slot(1).move_mult_while_casting),
		"slowed while casting (%.2f)" % cast_speed)


func test_dead_units_ignore_commands() -> void:
	var me := spawn(SCRIBE, 0, Vector3.ZERO)
	var other := spawn(SCRIBE, 1, Vector3(0, 0, -6))
	await ticks(2)
	authority.apply_damage(other, me, 10000.0, SCRIBE.basic_attack)
	check(not me.alive, "killed")
	aim(me, other.global_position)
	cmd(me).buttons = UnitCommand.BTN_ATTACK | UnitCommand.BTN_ABILITY_1
	cmd(me).move = Vector2(0, 1)
	await secs(1.0)
	check(authority.projectiles.is_empty() and authority.areas.is_empty(), "a dead unit cannot cast")
	check(me.global_position.distance_to(Vector3.ZERO) < 0.05, "a dead unit cannot move")


func test_command_roundtrip() -> void:
	var c := UnitCommand.new()
	c.move = Vector2(3, 4)  # over length 1 must be clamped on receipt
	c.aim_yaw = 1.25
	c.aim_point = Vector3(1, 2, 3)
	c.buttons = UnitCommand.BTN_ATTACK
	var d := UnitCommand.from_dict(c.to_dict())
	check(d.move.length() <= 1.0001, "received move vector clamped")
	check(d.aim_yaw == c.aim_yaw and d.aim_point == c.aim_point and d.buttons == c.buttons, "fields survive")
	await ticks(1)
