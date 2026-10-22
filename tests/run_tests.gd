extends SceneTree
## Headless gameplay tests. Each test builds a tiny world (floor, optional
## wall, authority, units driven by ScriptedController) and runs real
## physics ticks.
##   godot --headless --path . --fixed-fps 60 -s tests/run_tests.gd
## Exit code is the number of failures.

const SCRIBE := preload("res://data/champions/ruinscribe.tres")
const DUMMY := preload("res://data/champions/training_dummy.tres")
const TOWER := preload("res://data/units/tower.tres")
const CORE := preload("res://data/units/core.tres")
const MELEE := preload("res://data/units/minion_melee.tres")
const WARDEN := preload("res://data/champions/oathwarden.tres")
const RUNNER := preload("res://data/champions/ashrunner.tres")
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
		"test_unit_data_uses_ability_files", "test_tower_targeting", "test_core_protected_by_tower",
		"test_structure_damage_rules", "test_homing_shot_follows", "test_siege_units_ignore_minions",
		"test_match_victory", "test_objective_capture",
		"test_melee_arc", "test_dash", "test_dash_stopped_by_wall", "test_ward", "test_levels",
		"test_upgrade_choice", "test_roster",
		"test_second_slot_and_pierce", "test_stun", "test_knife_slow",
		"test_ultimate_unlock", "test_unmaking_word", "test_unbroken_oath", "test_ashfall",
		"test_passive_inscribe", "test_passive_resolve", "test_passive_ember", "test_last_hit_xp",
		"test_gold_and_shop", "test_items_change_stats", "test_bots_buy_items", "test_recall",
		"test_prediction_matches_authority", "test_snapshot_codec_roundtrip", "test_snapshot_fits_packet",
		"test_net_command_queue", "test_asset_contract",
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


# --- Gate 2 match rules ------------------------------------------------------

## Unit files must point at the ability files, not carry stale copies of them
## (a stale copy hid the minions' structure damage bonus for a whole tuning pass).
func test_unit_data_uses_ability_files() -> void:
	for dir in ["res://data/units", "res://data/champions"]:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".tres"):
				continue
			var d: ChampionDef = load(dir + "/" + f)
			var all: Array = [d.basic_attack]
			all.append_array(d.abilities)
			for a in all:
				if a != null:
					check((a as AbilityDef).resource_path.begins_with("res://data/abilities/"),
						"%s uses an ability file (got '%s')" % [f, (a as AbilityDef).resource_path])
	await ticks(1)


func test_tower_targeting() -> void:
	var tower := spawn(TOWER, 1, Vector3.ZERO)
	tower.controller = TowerController.new(authority)
	var minion := spawn(MELEE, 0, Vector3(0, 0, 10))
	var champ := spawn(SCRIBE, 0, Vector3(3, 0, 8))
	var ally := spawn(SCRIBE, 1, Vector3(3, 0, 4))
	await ticks(2)
	var tc: TowerController = tower.controller
	check(tc.current == minion, "tower shoots the minion before the champion")
	authority.apply_damage(champ, ally, 10.0, SCRIBE.basic_attack)
	await ticks(2)
	check(tc.current == champ, "tower switches to a champion who hits an allied champion near it")
	champ.global_position = Vector3(0, 0, 40)  # walks out of range
	await secs(2.5)
	check(tc.current == minion, "tower returns to the minion once the champion is out of range")


func test_core_protected_by_tower() -> void:
	var tower := spawn(TOWER, 1, Vector3(0, 0, -10))
	var core := spawn(CORE, 1, Vector3(0, 0, -20))
	core.protectors = [tower]
	var me := spawn(SCRIBE, 0, Vector3.ZERO)
	await ticks(2)
	var blocked := [0]
	authority.damage_blocked.connect(func(_t: Unit, _s: Unit) -> void: blocked[0] += 1)
	authority.apply_damage(me, core, 100.0, SCRIBE.basic_attack)
	check(core.health == CORE.max_health and blocked[0] == 1, "core takes no damage while its tower stands")
	authority.kill(tower)
	authority.apply_damage(me, core, 100.0, SCRIBE.basic_attack)
	check(is_equal_approx(core.health, CORE.max_health - 100.0), "core takes damage once its tower falls")


func test_structure_damage_rules() -> void:
	var tower := spawn(TOWER, 1, Vector3(0, 0, -10))
	var minion := spawn(MELEE, 0, Vector3.ZERO)
	var me := spawn(SCRIBE, 0, Vector3(4, 0, 0))
	var other := spawn(MELEE, 1, Vector3(-4, 0, 0))
	await ticks(2)
	var strike := MELEE.basic_attack
	authority.apply_damage(minion, tower, strike.damage, strike)
	var once := TOWER.max_health - tower.health
	check(is_equal_approx(once, strike.damage * strike.structure_damage_mult) and strike.structure_damage_mult > 1.0,
		"minion strike gets its structure bonus (%.1f)" % once)
	minion.structure_bonus = 2.0
	var before := tower.health
	authority.apply_damage(minion, tower, strike.damage, strike)
	check(is_equal_approx(before - tower.health, once * 2.0), "rising tide bonus multiplies structure damage")
	authority.apply_damage(minion, other, strike.damage, strike)
	check(is_equal_approx(other.health, MELEE.max_health - strike.damage), "bonuses do not apply to minions")
	authority.apply_damage(me, tower, 42.0, SCRIBE.basic_attack)
	check(is_equal_approx(before - tower.health, once * 2.0 + 42.0), "champion bolts hit structures for plain damage")


func test_homing_shot_follows() -> void:
	var tower := spawn(TOWER, 1, Vector3.ZERO)
	tower.controller = TowerController.new(authority)
	var champ := spawn(SCRIBE, 0, Vector3(0, 0, 12))
	await ticks(2)
	var hit := [false]
	authority.unit_damaged.connect(func(t: Unit, _a: float, s: Unit) -> void:
		if t == champ and s == tower: hit[0] = true)
	# Make the tower target the champion, then sidestep during the shot.
	var ally := spawn(SCRIBE, 1, Vector3(2, 0, 4))
	authority.apply_damage(champ, ally, 1.0, SCRIBE.basic_attack)
	cmd(champ).move = Vector2(1, 0)
	await secs(1.5)
	check(hit[0], "tower shot follows a target that moves sideways")


func test_siege_units_ignore_minions() -> void:
	var tower := spawn(TOWER, 1, Vector3(0, 0, -30))
	var breaker := spawn(load("res://data/units/minion_breaker.tres"), 0, Vector3.ZERO)
	var mc := MinionController.new(authority, PackedVector3Array([Vector3(0, 0, -30)]))
	mc.structures_only = true
	breaker.controller = mc
	var blocker := spawn(MELEE, 1, Vector3(1.5, 0, -3))
	await secs(1.0)
	check(blocker.health == MELEE.max_health, "breaker does not stop to fight a minion")
	check(breaker.global_position.z < -2.0, "breaker keeps walking to the structure (z %.1f)" % breaker.global_position.z)
	await secs(8.0)
	check(tower.health < TOWER.max_health, "breaker hits the tower")


func _match() -> MatchController:
	var mc := MatchController.new()
	mc.human_slot = false
	world.add_child(mc)
	mc.setup(authority, world)
	mc.start()
	for c in mc.champions:
		c.controller = ScriptedController.new()  # stand still: the test drives the rules
	return mc


func test_match_victory() -> void:
	var mc := _match()
	await ticks(2)
	var won := [-2]
	mc.match_over.connect(func(w: int) -> void: won[0] = w)
	var hitter: Unit = mc.champions[0]
	authority.apply_damage(hitter, mc.cores[1], 99999.0, SCRIBE.basic_attack)
	check(mc.cores[1].alive and not mc.over, "core cannot fall while its tower stands")
	authority.apply_damage(hitter, mc.towers[1], 99999.0, SCRIBE.basic_attack)
	authority.apply_damage(hitter, mc.cores[1], 99999.0, SCRIBE.basic_attack)
	await ticks(1)
	check(mc.over and won[0] == 0 and mc.stats.winner == "Oath" and mc.stats.reason == "core destroyed",
		"destroying the enemy core wins (winner %s)" % mc.stats.winner)
	check(not authority.auto_step, "the field freezes on the result")
	authority.auto_step = true


func test_objective_capture() -> void:
	var mc := _match()
	mc.beast_timer = 0.05
	await ticks(6)
	check(mc.beast_state == MatchController.Beast.AWAKE and mc.beast != null, "beast wakes on its timer")
	authority.kill(mc.beast)
	await ticks(1)
	check(mc.beast_state == MatchController.Beast.CAPTURE, "beast down opens the capture circle")
	var a: Unit = mc.champions[0]
	var b: Unit = mc.champions[3]
	a.global_position = mc.objective_position() + Vector3(1, 0, 0)
	b.global_position = mc.objective_position() + Vector3(-1, 0, 0)
	await secs(4.0)
	check(mc.beast_state == MatchController.Beast.CAPTURE, "a contested circle is not claimed")
	b.global_position = Vector3(0, 0, -60)
	await secs(3.3)
	check(mc.beast_state == MatchController.Beast.OUT and mc.stats.objective_captures == [1, 0],
		"standing alone in the circle for 3 s claims it (%s)" % [mc.stats.objective_captures])
	check(mc.siege != null and mc.siege.team == 0 and (mc.siege.controller as MinionController).structures_only,
		"the claimed beast marches for the claiming team and goes for structures")


# --- Gate 3 champions and progression ----------------------------------------

func test_melee_arc() -> void:
	var me := spawn(WARDEN, 0, Vector3.ZERO)
	var front := spawn(DUMMY, 1, Vector3(0.8, 0, -2.5))
	var behind := spawn(DUMMY, 1, Vector3(0, 0, 2.5))
	var far := spawn(DUMMY, 1, Vector3(0, 0, -6))
	var ally := spawn(SCRIBE, 0, Vector3(-0.8, 0, -2.0))
	await ticks(2)
	aim(me, Vector3(0, 0, -10))
	cmd(me).buttons = UnitCommand.BTN_ATTACK
	await ticks(1)
	cmd(me).buttons = 0
	await secs(0.5)
	var dmg := WARDEN.basic_attack.damage
	check(is_equal_approx(front.health, DUMMY.max_health - dmg), "cleave hits an enemy in the arc (%.0f)" % front.health)
	check(behind.health == DUMMY.max_health, "cleave misses an enemy behind")
	check(far.health == DUMMY.max_health, "cleave misses an enemy out of reach")
	check(ally.health == SCRIBE.max_health, "cleave does not hurt allies")


func test_dash() -> void:
	var me := spawn(RUNNER, 0, Vector3.ZERO)
	var crossed := spawn(DUMMY, 1, Vector3(0, 0, -4))
	await ticks(2)
	aim(me, Vector3(0, 0, -10))
	me.apply_slow(0.5, 5.0)
	cmd(me).move = Vector2(0, 1)
	await ticks(2)
	cmd(me).buttons = UnitCommand.BTN_ABILITY_1
	await ticks(1)
	cmd(me).buttons = 0
	cmd(me).move = Vector2.ZERO
	var start := me.global_position
	await secs(0.5)
	var vault := RUNNER.get_slot(1)
	var moved := Vector2(me.global_position.x - start.x, me.global_position.z - start.z).length()
	check(absf(moved - vault.dash_distance) < 0.6, "vault carries the full distance even while slowed (%.2f m)" % moved)
	check(is_equal_approx(crossed.health, DUMMY.max_health - vault.damage), "vault cuts an enemy it passes through once")
	check(me.cooldowns[1] > 0.0, "vault goes on cooldown")


func test_dash_stopped_by_wall() -> void:
	add_wall(Vector3(0, 1, -4), Vector3(6, 2, 0.5))
	var me := spawn(RUNNER, 0, Vector3.ZERO)
	await ticks(2)
	aim(me, Vector3(0, 0, -10))
	cmd(me).buttons = UnitCommand.BTN_ABILITY_1
	await ticks(1)
	cmd(me).buttons = 0
	await secs(0.5)
	check(me.global_position.z > -4.0, "a wall stops the vault (z %.2f)" % me.global_position.z)


func test_ward() -> void:
	var warden := spawn(WARDEN, 0, Vector3.ZERO)
	var caster := spawn(SCRIBE, 0, Vector3(2, 0, 0))
	var outside := spawn(SCRIBE, 0, Vector3(9, 0, 0))
	var enemy := spawn(SCRIBE, 1, Vector3(0, 0, -12))
	var minion := spawn(MELEE, 0, Vector3(-1, 0, 1))
	await ticks(2)
	cmd(warden).buttons = UnitCommand.BTN_ABILITY_1
	await ticks(1)
	cmd(warden).buttons = 0
	await secs(0.5)
	var ward := warden.get_slot(1)
	check(authority.areas.size() == 1, "warding stand plants a ward")
	authority.apply_damage(enemy, caster, 100.0, null)
	authority.apply_damage(enemy, outside, 100.0, null)
	authority.apply_damage(enemy, minion, 100.0, null)
	check(is_equal_approx(SCRIBE.max_health - caster.health, 100.0 * (1.0 - ward.ward_reduction)), "an allied champion inside takes less damage (%.0f)" % (SCRIBE.max_health - caster.health))
	check(is_equal_approx(SCRIBE.max_health - outside.health, 100.0), "a champion outside takes full damage")
	check(is_equal_approx(MELEE.max_health - minion.health, 100.0), "minions are not warded")
	await secs(ward.ward_duration)
	check(authority.areas.is_empty(), "the ward ends after its duration")


func test_levels() -> void:
	var me := spawn(SCRIBE, 0, Vector3.ZERO)
	var target := spawn(DUMMY, 1, Vector3(0, 0, -5))
	await ticks(2)
	var leveled := [0]
	me.leveled.connect(func(_l: int) -> void: leveled[0] += 1)
	me.health = me.max_health * 0.5
	me.add_xp(Unit.LEVEL_XP[1])
	check(me.level == 2 and leveled[0] == 1, "enough xp reaches level 2")
	check(is_equal_approx(me.max_health, SCRIBE.max_health * (1.0 + Unit.HEALTH_PER_LEVEL)), "level raises max health")
	check(is_equal_approx(me.health / me.max_health, 0.5), "level keeps the health fraction")
	authority.apply_damage(me, target, 100.0, SCRIBE.basic_attack)
	check(is_equal_approx(DUMMY.max_health - target.health, 100.0 * (1.0 + Unit.DAMAGE_PER_LEVEL)), "level raises damage")
	me.add_xp(99999.0)
	check(me.level == Unit.LEVEL_XP.size(), "level caps at %d" % Unit.LEVEL_XP.size())
	var minion := spawn(MELEE, 0, Vector3(3, 0, 0))
	await ticks(1)
	minion.add_xp(99999.0)
	check(minion.level == 1, "only champions gain levels")


func test_upgrade_choice() -> void:
	var me := spawn(SCRIBE, 0, Vector3.ZERO)
	await ticks(2)
	cmd(me).upgrade_choice = 2
	await ticks(2)
	check(me.get_slot(1) == SCRIBE.get_slot(1), "no upgrade before the offer")
	me.add_xp(Unit.LEVEL_XP[Unit.UPGRADE_LEVEL - 1])
	check(me.upgrade_pending, "level %d offers an upgrade" % Unit.UPGRADE_LEVEL)
	var opts := me.upgrade_options()
	check(opts.size() == 2 and opts[0] != opts[1], "two different options")
	await ticks(2)
	check(not me.upgrade_pending and me.get_slot(1) == opts[1], "command picks option 2 (%s)" % me.get_slot(1).id)
	cmd(me).upgrade_choice = 1
	await ticks(2)
	check(me.get_slot(1) == opts[1], "the pick cannot be changed later")
	check(SCRIBE.get_slot(1) != opts[1], "the shared champion data is not changed")
	var d := UnitCommand.from_dict({"u": 7})
	check(d.upgrade_choice == 0, "an invalid upgrade choice from the network is dropped")
	for def: ChampionDef in [SCRIBE, WARDEN, RUNNER]:
		check(def.get_slot(1).upgrades.size() == 2, "%s has two upgrade options" % def.id)


func test_roster() -> void:
	var mc := MatchController.new()
	mc.human_slot = true
	mc.human_pick = &"ashrunner"
	world.add_child(mc)
	mc.setup(authority, world)
	var r0 := mc.team_roster(0)
	var r1 := mc.team_roster(1)
	check(r0[0].id == &"ashrunner" and r0.size() == 3, "the player's pick takes slot 0")
	check(r1[0].id == &"ruinscribe", "the bot team keeps the default order")
	var ids := {}
	for d in r0:
		ids[d.id] = true
	check(ids.size() == 3, "one of each role per team")
	await ticks(1)


# --- Gate 3, second abilities --------------------------------------------------

func test_second_slot_and_pierce() -> void:
	var me := spawn(SCRIBE, 0, Vector3.ZERO)
	var first := spawn(DUMMY, 1, Vector3(0, 0, -5))
	var second := spawn(DUMMY, 1, Vector3(0.3, 0, -9))
	var off := spawn(DUMMY, 1, Vector3(3, 0, -7))
	await ticks(2)
	aim(me, Vector3(0, 0, -20))
	cmd(me).buttons = UnitCommand.BTN_ABILITY_2
	await ticks(1)
	cmd(me).buttons = 0
	await secs(1.2)
	var lance := SCRIBE.get_slot(2)
	check(lance != null and lance.pierce, "the scribe has a piercing second ability")
	check(is_equal_approx(first.health, DUMMY.max_health - lance.damage), "the lance hits the first enemy on the line")
	check(is_equal_approx(second.health, DUMMY.max_health - lance.damage), "and passes through to the second")
	check(off.health == DUMMY.max_health, "an enemy off the line is missed")
	check(me.cooldowns[2] > 0.0, "slot 2 has its own cooldown")
	var d := UnitCommand.from_dict({"b": UnitCommand.BTN_ABILITY_2})
	check(d.buttons == UnitCommand.BTN_ABILITY_2, "the second ability button survives the network path")


func test_stun() -> void:
	var warden := spawn(WARDEN, 0, Vector3.ZERO)
	var victim := spawn(SCRIBE, 1, Vector3(0, 0, -2))
	await ticks(2)
	# The victim starts a long cast and tries to walk away.
	aim(victim, Vector3(0, 0, 10))
	cmd(victim).buttons = UnitCommand.BTN_ABILITY_2
	cmd(victim).move = Vector2(0, 1)
	await ticks(3)
	check(victim.is_casting(), "victim is mid cast")
	aim(warden, victim.global_position)
	cmd(warden).buttons = UnitCommand.BTN_ABILITY_2
	await ticks(1)
	cmd(warden).buttons = 0
	await secs(0.5)
	var slam := WARDEN.get_slot(2)
	check(victim.is_stunned(), "shield slam stuns")
	check(not victim.is_casting(), "the stun interrupts the cast")
	var at := victim.global_position
	await secs(0.4)
	check(victim.global_position.distance_to(at) < 0.05, "a stunned unit cannot move")
	await secs(0.6)
	check(not victim.is_stunned(), "the stun ends after %.1f s" % slam.stun_duration)
	await secs(0.5)
	check(victim.global_position.distance_to(at) > 1.0, "movement returns after the stun")
	var tower := spawn(TOWER, 1, Vector3(0, 0, -2))
	await ticks(1)
	authority.apply_damage(warden, tower, 10.0, slam)
	check(not tower.is_stunned(), "structures cannot be stunned")


func test_knife_slow() -> void:
	var me := spawn(RUNNER, 0, Vector3.ZERO)
	var target := spawn(SCRIBE, 1, Vector3(0, 0, -6))
	await ticks(2)
	aim(me, target.global_position)
	cmd(me).buttons = UnitCommand.BTN_ABILITY_2
	await ticks(1)
	cmd(me).buttons = 0
	await secs(0.8)
	var knife := RUNNER.get_slot(2)
	check(is_equal_approx(target.health, SCRIBE.max_health - knife.damage), "ember knife hits for its damage")
	check(is_equal_approx(target.slow_amount, knife.slow_amount), "and slows the target")
	check(is_equal_approx(target.current_move_speed(), SCRIBE.move_speed * (1.0 - knife.slow_amount)), "slowed speed is applied")


# --- Gate 3, ultimates and passives --------------------------------------------

func _level_up(u: Unit, level: int) -> void:
	u.add_xp(Unit.LEVEL_XP[level - 1])
	if u.upgrade_pending:
		u.choose_upgrade(1)


func test_ultimate_unlock() -> void:
	var me := spawn(SCRIBE, 0, Vector3.ZERO)
	var target := spawn(DUMMY, 1, Vector3(0, 0, -8))
	await ticks(2)
	for def: ChampionDef in [SCRIBE, WARDEN, RUNNER]:
		var r := def.get_slot(3)
		check(r != null and r.is_ultimate and r.cooldown >= 45.0, "%s has an ultimate in slot 3 with a long cooldown" % def.id)
		check(not def.passive_name.is_empty() and def.passive != ChampionDef.Passive.NONE, "%s has a passive" % def.id)
	var rejected := [""]
	me.cast_rejected.connect(func(_slot: int, reason: String) -> void: rejected[0] = reason)
	aim(me, target.global_position)
	cmd(me).buttons = UnitCommand.BTN_ABILITY_3
	await ticks(2)
	cmd(me).buttons = 0
	check(not me.is_casting() and me.cooldowns[3] == 0.0, "the ultimate does not cast before level %d" % Unit.ULT_LEVEL)
	check(rejected[0].contains("level"), "the press is refused with a reason (%s)" % rejected[0])
	_level_up(me, Unit.ULT_LEVEL)
	cmd(me).buttons = UnitCommand.BTN_ABILITY_3
	await ticks(2)
	cmd(me).buttons = 0
	check(me.is_casting() and me.cast_slot == 3, "at level %d the ultimate casts" % Unit.ULT_LEVEL)
	var d := UnitCommand.from_dict({"b": UnitCommand.BTN_ABILITY_3})
	check(d.buttons == UnitCommand.BTN_ABILITY_3 and UnitCommand.ability_button(3) == UnitCommand.BTN_ABILITY_3, "the ultimate button survives the network path")


func test_unmaking_word() -> void:
	var me := spawn(SCRIBE, 0, Vector3.ZERO)
	var inside := spawn(DUMMY, 1, Vector3(1.5, 0, -10))
	var outside := spawn(DUMMY, 1, Vector3(7, 0, -10))
	await ticks(2)
	_level_up(me, Unit.ULT_LEVEL)
	aim(me, Vector3(0, 0, -10))
	cmd(me).buttons = UnitCommand.BTN_ABILITY_3
	await ticks(1)
	cmd(me).buttons = 0
	var word := SCRIBE.get_slot(3)
	await secs(word.cast_time + 0.2)
	check(authority.areas.size() == 1 and is_equal_approx(authority.areas[0].ability.area_radius, word.area_radius), "the word draws its circle")
	check(inside.health == DUMMY.max_health, "nothing happens before the delay")
	await secs(word.area_delay + 0.1)
	var expect := word.damage * me.damage_mult
	check(is_equal_approx(DUMMY.max_health - inside.health, expect), "inside takes the burst (%.0f)" % (DUMMY.max_health - inside.health))
	check(outside.health == DUMMY.max_health, "outside the circle is untouched")
	check(is_equal_approx(inside.slow_amount, word.slow_amount), "the burst slows")
	check(me.cooldowns[3] > 50.0, "the ultimate is on its long cooldown")


func test_unbroken_oath() -> void:
	var warden := spawn(WARDEN, 0, Vector3.ZERO)
	var ally := spawn(SCRIBE, 0, Vector3(2, 0, 0))
	var far := spawn(SCRIBE, 0, Vector3(12, 0, 0))
	var enemy := spawn(SCRIBE, 1, Vector3(0, 0, -14))
	await ticks(2)
	_level_up(warden, Unit.ULT_LEVEL)
	ally.health = 100.0
	far.health = 100.0
	cmd(warden).buttons = UnitCommand.BTN_ABILITY_3
	await ticks(1)
	cmd(warden).buttons = 0
	var oath := WARDEN.get_slot(3)
	await secs(0.5)
	check(authority.areas.size() == 1 and authority.areas[0].ability == oath, "the oath stands as a ward")
	authority.apply_damage(enemy, ally, 100.0, null)
	check(is_equal_approx(100.0 - ally.health + oath.heal_per_second * 0.0, 100.0 * (1.0 - oath.ward_reduction)) or ally.health > 100.0 * oath.ward_reduction, "an ally inside takes less")
	var before := ally.health
	await secs(1.0)
	check(ally.health - before > oath.heal_per_second * 0.8 and ally.health - before < oath.heal_per_second * 1.2, "an ally inside heals about %.0f a second (%.0f)" % [oath.heal_per_second, ally.health - before])
	check(far.health == 100.0, "an ally outside does not heal")
	await secs(oath.ward_duration)
	check(authority.areas.is_empty(), "the oath ends after %.0f s" % oath.ward_duration)


func test_ashfall() -> void:
	var me := spawn(RUNNER, 0, Vector3.ZERO)
	var crossed := spawn(SCRIBE, 1, Vector3(0, 0, -5))
	var missed := spawn(SCRIBE, 1, Vector3(4, 0, -5))
	await ticks(2)
	_level_up(me, Unit.ULT_LEVEL)
	aim(me, Vector3(0, 0, -20))
	cmd(me).move = Vector2(0, 1)
	cmd(me).buttons = UnitCommand.BTN_ABILITY_3
	await ticks(1)
	cmd(me).buttons = 0
	var fall := RUNNER.get_slot(3)
	await secs(fall.cast_time + fall.dash_duration + 0.1)
	cmd(me).move = Vector2.ZERO
	check(me.global_position.z < -fall.dash_distance + 1.0, "the leap carries %.0f m (%.1f)" % [fall.dash_distance, -me.global_position.z])
	check(is_equal_approx(SCRIBE.max_health - crossed.health, fall.damage * me.damage_mult), "an enemy crossed takes the damage")
	check(crossed.is_stunned(), "and is stunned")
	check(missed.health == SCRIBE.max_health and not missed.is_stunned(), "an enemy off the line is untouched")


func test_passive_inscribe() -> void:
	var me := spawn(SCRIBE, 0, Vector3.ZERO)
	var target := spawn(DUMMY, 1, Vector3(0, 0, -6))
	var other := spawn(DUMMY, 1, Vector3(3, 0, -6))
	await ticks(2)
	var bolt := SCRIBE.basic_attack
	var hits: Array[float] = []
	target.damaged.connect(func(amount: float, _src: Unit) -> void: hits.append(amount))
	for i in 3:
		authority.apply_damage(me, target, bolt.damage, bolt)
	check(hits.size() == 3 and is_equal_approx(hits[0], bolt.damage) and is_equal_approx(hits[1], bolt.damage), "the first two bolts hit normally")
	check(is_equal_approx(hits[2], bolt.damage * (1.0 + SCRIBE.passive_value)), "the third bolt on the same target hits for +%.0f%%" % (SCRIBE.passive_value * 100.0))
	authority.apply_damage(me, other, bolt.damage, bolt)
	check(is_equal_approx(DUMMY.max_health - other.health, bolt.damage), "the count is per target")
	authority.apply_damage(me, target, 10.0, SCRIBE.get_slot(1))
	check(is_equal_approx(DUMMY.max_health - target.health, bolt.damage * (3.0 + SCRIBE.passive_value) + 10.0), "abilities do not count or get the bonus")


func test_passive_resolve() -> void:
	var warden := spawn(WARDEN, 0, Vector3.ZERO)
	var enemy := spawn(SCRIBE, 1, Vector3(0, 0, -6))
	await ticks(2)
	authority.apply_damage(enemy, warden, 100.0, null)
	check(is_equal_approx(WARDEN.max_health - warden.health, 100.0), "above half health a hit lands in full")
	warden.health = warden.max_health * 0.4
	var before := warden.health
	authority.apply_damage(enemy, warden, 100.0, null)
	check(is_equal_approx(before - warden.health, 100.0 * (1.0 - WARDEN.passive_value)), "below half health hits are softened by %.0f%%" % (WARDEN.passive_value * 100.0))


func test_passive_ember() -> void:
	var me := spawn(RUNNER, 0, Vector3.ZERO)
	var victim := spawn(SCRIBE, 1, Vector3(0, 0, -3))
	var minion := spawn(MELEE, 1, Vector3(2, 0, -3))
	await ticks(2)
	me.health = 200.0
	me.cooldowns[1] = 5.0
	minion.health = 1.0
	authority.apply_damage(me, minion, 10.0, RUNNER.basic_attack)
	check(me.cooldowns[1] == 5.0 and me.health == 200.0, "a minion kill does nothing")
	victim.health = 1.0
	authority.apply_damage(me, victim, 10.0, RUNNER.basic_attack)
	check(me.cooldowns[1] == 0.0, "a champion kill resets Vault")
	check(is_equal_approx(me.health, 200.0 + me.max_health * RUNNER.passive_value), "and heals %.0f%% of max health" % (RUNNER.passive_value * 100.0))


func test_last_hit_xp() -> void:
	var mc := _match()
	await ticks(2)
	var killer: Unit = mc.champions[0]
	var ally: Unit = mc.champions[1]
	var minion := spawn(MELEE, 1, killer.global_position + Vector3(0, 0, -2))
	await ticks(1)
	var k0 := killer.xp
	var a0 := ally.xp
	authority.apply_damage(killer, minion, 99999.0, killer.def.basic_attack)
	var share := MatchController.XP_MINION / 3.0  # three champions stand at the fountain
	check(is_equal_approx(ally.xp - a0, share), "a nearby ally gets its share of the minion (%.1f)" % (ally.xp - a0))
	check(is_equal_approx(killer.xp - k0, share + MatchController.XP_LAST_HIT), "the last hit pays %.0f on top (%.1f)" % [MatchController.XP_LAST_HIT, killer.xp - k0])
	authority.auto_step = true


func test_gold_and_shop() -> void:
	var eco := Unit.ECONOMY
	var mc := _match()
	await ticks(2)
	var killer: Unit = mc.champions[0]
	var ally: Unit = mc.champions[1]
	check(absf(killer.gold - eco.start_gold) < 1.0, "champions start with %d gold" % eco.start_gold)
	var minion := spawn(MELEE, 1, killer.global_position + Vector3(0, 0, -2))
	await ticks(1)
	var k0 := killer.gold
	var a0 := ally.gold
	var popups := []
	killer.gold_earned.connect(func(g: float, _at: Vector3) -> void: popups.append(g))
	authority.apply_damage(killer, minion, 99999.0, killer.def.basic_attack)
	var share := eco.minion_share / 3.0
	check(is_equal_approx(ally.gold - a0, share), "a nearby ally gets its gold share of the minion (%.1f)" % (ally.gold - a0))
	check(is_equal_approx(killer.gold - k0, share + eco.last_hit), "the last hit pays %.0f gold on top (%.1f)" % [eco.last_hit, killer.gold - k0])
	check(popups == [eco.last_hit], "the last hit gold is shown to the player")
	check(eco.last_hit >= 2.0 * eco.minion_share, "last hits pay much more than standing near")
	await secs(1.0)
	check(ally.gold - a0 > share + eco.per_second * 0.9, "gold trickles in over time")

	# Buying: at the fountain, with enough gold, through the command.
	var plate: ItemDef = eco.items[0]
	killer.gold = plate.cost - 1.0
	var notes := []
	killer.cast_rejected.connect(func(_s: int, r: String) -> void: notes.append(r))
	(killer.controller as ScriptedController).command.buy_item = 1
	await ticks(1)
	check(killer.items.is_empty() and notes.size() > 0 and "more gold" in notes[-1], "not enough gold: nothing bought, with a reason")
	killer.gold = plate.cost + 50.0
	await ticks(1)
	check(killer.items == [plate] and absf(killer.gold - 50.0) < 1.0, "bought %s for %d gold" % [plate.display_name, plate.cost])
	await ticks(1)
	check(killer.items.size() == 1, "the same item cannot be bought twice")
	(killer.controller as ScriptedController).command.buy_item = 0
	killer.gold = 5000.0
	killer.global_position = Vector3(0, 0, 0)
	(killer.controller as ScriptedController).command.buy_item = 2
	await ticks(1)
	check(killer.items.size() == 1, "no buying away from the fountain")
	authority.apply_damage(ally, killer, 99999.0, SCRIBE.basic_attack)  # a friendly hit does nothing
	authority.apply_damage(mc.champions[3], killer, 99999.0, SCRIBE.basic_attack)
	await ticks(1)
	check(not killer.alive and killer.items.size() == 2, "a dead champion can shop while waiting")
	(killer.controller as ScriptedController).command.buy_item = 0
	check(mc.stats.champions[killer.name].items.size() == 2, "purchases go into the match stats")
	check(mc.champions[3].gold > 0.0 and mc.stats.champions[mc.champions[3].name].gold_earned >= eco.kill, "a champion kill pays %d" % eco.kill)
	var d := UnitCommand.from_dict({"i": 99})
	check(d.buy_item == 0, "a bad item number from the network is dropped")
	check(UnitCommand.from_dict({"i": 3}).buy_item == 3, "a good one survives")


func test_items_change_stats() -> void:
	var me := spawn(SCRIBE, 0, Vector3.ZERO)
	await ticks(2)
	var eco := Unit.ECONOMY
	var hp0 := me.max_health
	var by_id := {}
	for it: ItemDef in eco.items:
		by_id[it.id] = it
	check(by_id.size() == 4, "four items in the shop")
	me.items.append(by_id[&"oathbound_plate"])
	me.items.append(by_id[&"ember_edge"])
	me.items.append(by_id[&"ash_hourglass"])
	me.items.append(by_id[&"wayfarer_greaves"])
	me.recompute_stats()
	check(is_equal_approx(me.max_health, hp0 + 150.0), "plate adds 150 health")
	check(is_equal_approx(me.damage_mult, 1.12), "edge adds 12% damage")
	check(is_equal_approx(me.current_move_speed(), SCRIBE.move_speed * 1.08), "greaves add 8% speed")
	check(is_equal_approx(me.cooldown_for(1, me.get_slot(1)), me.get_slot(1).cooldown * 0.85), "hourglass: Q 15% shorter")
	check(is_equal_approx(me.cooldown_for(0, me.get_slot(0)), me.get_slot(0).cooldown), "basic attacks unchanged")
	var start := me.global_position
	cmd(me).move = Vector2(0, 1)
	await secs(1.0)
	var walked := UnitController.flat_distance(start, me.global_position)
	check(walked > SCRIBE.move_speed * 1.03, "walks faster with greaves (%.2f m in 1 s)" % walked)
	# Network: gold and items survive a snapshot and set the client's stats.
	me.gold = 1234.0
	var s: Array = SnapshotCodec.decode(SnapshotCodec.encode(1, 0, 1, SnapshotCodec.encode_units([me]))).units[me.net_id]
	var twin := Unit.new()
	twin.def = SCRIBE
	world.add_child(twin)
	twin.collision_layer = 0
	SnapshotCodec.apply(twin, s)
	check(twin.items.size() == 4 and is_equal_approx(twin.gold, 1234.0), "items and gold reach the client")
	check(is_equal_approx(twin.speed_mult, 1.08) and is_equal_approx(twin.max_health, me.max_health), "client stats match the server")
	twin.queue_free()


func test_bots_buy_items() -> void:
	var mc := MatchController.new()
	mc.human_slot = false
	world.add_child(mc)
	mc.setup(authority, world)
	mc.start()
	await ticks(2)
	for c in mc.champions:
		c.gold = 5000.0
	await secs(0.5)
	for c in mc.champions:
		check(c.items.size() >= 1 and c.items[0].id == c.def.item_build[0], "%s bot buys its first item (%s)" % [c.name, c.items[0].id if c.items.size() > 0 else "none"])


func test_recall() -> void:
	var mc := _match()
	await ticks(2)
	var me: Unit = mc.champions[0]
	var sc := me.controller as ScriptedController
	var home := me.spawn_transform.origin
	var away := Vector3(2, 0, 0)
	me.global_position = away
	await ticks(1)
	sc.command.buttons = UnitCommand.BTN_RECALL
	await ticks(1)
	sc.command.buttons = 0
	check(me.recall_timer > 0.0, "T starts a recall")
	await secs(Unit.ECONOMY.recall_time - 0.5)
	check(UnitController.flat_distance(me.global_position, away) < 0.1, "still waiting before the time is up")
	await secs(0.6)
	check(me.recall_timer == 0.0 and UnitController.flat_distance(me.global_position, home) < 0.1, "home after %.0f s" % Unit.ECONOMY.recall_time)
	# Moving cancels.
	var reasons := []
	me.recall_cancelled.connect(func(r: String) -> void: reasons.append(r))
	me.global_position = away
	await ticks(1)
	sc.command.buttons = UnitCommand.BTN_RECALL
	await ticks(1)
	sc.command.buttons = 0
	sc.command.move = Vector2(0, 1)
	await ticks(2)
	sc.command.move = Vector2.ZERO
	check(me.recall_timer == 0.0 and reasons.size() == 1, "moving cancels the recall")
	# A hit cancels.
	sc.command.buttons = UnitCommand.BTN_RECALL
	await ticks(1)
	sc.command.buttons = 0
	authority.apply_damage(mc.champions[3], me, 10.0, SCRIBE.basic_attack)
	check(me.recall_timer == 0.0 and reasons.size() == 2, "a hit cancels the recall")
	# Pressing an ability cancels.
	sc.command.buttons = UnitCommand.BTN_RECALL
	await ticks(1)
	sc.command.buttons = UnitCommand.BTN_ATTACK
	await ticks(1)
	sc.command.buttons = 0
	check(me.recall_timer == 0.0 and reasons.size() == 3, "an attack cancels the recall")
	# The timer reaches network clients.
	sc.command.buttons = UnitCommand.BTN_RECALL
	await ticks(1)
	sc.command.buttons = 0
	var s: Array = SnapshotCodec.decode(SnapshotCodec.encode(1, 0, 1, SnapshotCodec.encode_units([me]))).units[me.net_id]
	check(absf(s[SnapshotCodec.RECALL] - me.recall_timer) < 0.01, "recall timer survives a snapshot")
	check(UnitCommand.from_dict({"b": UnitCommand.BTN_RECALL}).pressed(UnitCommand.BTN_RECALL), "recall survives the command path")


# --- Networking: prediction, snapshots, command queue ------------------------

## The client's prediction (Unit.predict_step) must land exactly where the
## server's sim_step does for the same commands: walking, a held attack, a
## ground ability, a dash and a stun. Any drift here would show online as
## constant small corrections.
func test_prediction_matches_authority() -> void:
	authority.auto_step = false
	for def: ChampionDef in [SCRIBE, RUNNER]:
		var srv := spawn(def, 0, Vector3(0, 0, 0))
		var twin := Unit.new()
		twin.def = def
		twin.position = Vector3(0, 0, 0)
		world.add_child(twin)
		twin.collision_layer = 0
		var worst := 0.0
		for t in 240:
			await physics_frame
			var c := cmd(srv)
			c.move = Vector2(1.0 if (t / 40) % 2 == 0 else -1.0, 1.0)
			c.aim_yaw = 0.3 + t * 0.004
			c.aim_point = srv.global_position + Vector3(0, 0, -9)
			c.buttons = UnitCommand.BTN_ATTACK if t > 20 else 0
			if t == 90:
				c.buttons |= UnitCommand.BTN_ABILITY_1
			if t == 150:
				srv.apply_stun(0.3)
				twin.apply_stun(0.3)  # online this arrives in the snapshot
			authority.step(DT)
			twin.predict_step(c, DT)
			worst = maxf(worst, srv.global_position.distance_to(twin.global_position))
		check(worst < 0.001, "%s: prediction matches the server tick for tick (worst %.4f m)" % [def.id, worst])
		check(srv.global_position.distance_to(Vector3.ZERO) > 5.0, "%s: the test actually moved (%.1f m)" % [def.id, srv.global_position.length()])
		authority.remove_unit(srv)
		twin.queue_free()
	authority.auto_step = true


func test_snapshot_codec_roundtrip() -> void:
	var u := spawn(RUNNER, 1, Vector3(12.345, 0.0, -61.237))
	await ticks(2)
	u.aim_yaw = -2.5
	u.health = 431.6
	u.cast_phase = Unit.CastPhase.WINDUP
	u.cast_slot = 1
	u.cast_timer = 0.0833
	u.cast_target = Vector3(3.0, 0.0, -50.0)
	u.cooldowns[1] = 69.99
	u.apply_slow(0.3, 1.25)
	u.stun_timer = 0.4
	u.dash_timer = 0.2
	u.dash_velocity = Vector3(-21.0, 0.0, 7.5)
	_level_up(u, 4)
	var bytes := SnapshotCodec.encode(777, 1234, 1, SnapshotCodec.encode_units([u]))
	var snap := SnapshotCodec.decode(bytes)
	check(snap.tick == 777 and snap.ack == 1234 and snap.units.has(u.net_id), "header survives (tick, ack, id)")
	var s: Array = snap.units[u.net_id]
	check((s[SnapshotCodec.POS] as Vector3).distance_to(u.global_position) < 0.01, "position within 1 cm")
	check(absf(angle_difference(s[SnapshotCodec.YAW], u.aim_yaw)) < 0.001, "yaw within 0.001 rad")
	check(absf(s[SnapshotCodec.HEALTH] - u.health) <= 0.5 and s[SnapshotCodec.ALIVE], "health within 0.5")
	check(s[SnapshotCodec.PHASE] == Unit.CastPhase.WINDUP and s[SnapshotCodec.SLOT] == 1, "cast phase and slot")
	var ct: float = s[SnapshotCodec.CAST_TIMER]
	check(ct >= u.cast_timer and ct - u.cast_timer < 1.0 / 600.0 + 0.0001, "cast timer rounds up by under 1/600 s (%.4f)" % ct)
	check(absf((s[SnapshotCodec.COOLDOWNS] as PackedFloat32Array)[1] - 69.99) < 0.002, "a 70 s cooldown fits")
	check(absf(s[SnapshotCodec.SLOW] - 0.3) < 0.005 and absf(s[SnapshotCodec.SLOW_TIMER] - 1.25) < 0.002, "slow amount and timer")
	check(absf(s[SnapshotCodec.STUN] - 0.4) < 0.002 and absf(s[SnapshotCodec.DASH_TIMER] - 0.2) < 0.002, "stun and dash timers")
	check((s[SnapshotCodec.DASH_VEL] as Vector3).distance_to(u.dash_velocity) < 0.01, "dash velocity")
	check(s[SnapshotCodec.LEVEL] == 4 and absf(s[SnapshotCodec.MAX_HEALTH] - u.max_health) <= 0.5, "level and max health")
	u.health = 0.3
	s = SnapshotCodec.decode(SnapshotCodec.encode(1, 0, 1, SnapshotCodec.encode_units([u]))).units[u.net_id]
	check(s[SnapshotCodec.HEALTH] >= 1.0, "a living unit never reads as 0 health")
	check(SnapshotCodec.decode(PackedByteArray([9, 9, 9])).is_empty(), "garbage is rejected, not half read")
	for n in [11, 20, bytes.size() - 6, bytes.size() - 1]:
		check(SnapshotCodec.decode(bytes.slice(0, n)).is_empty(), "a packet cut to %d bytes is rejected" % n)


## Worst case for a full 3v3 match: more units than the bot match peak (26),
## all of them casting, slowed and stunned at once, must still fit one packet.
func test_snapshot_fits_packet() -> void:
	var units: Array[Unit] = []
	for i in 6:
		units.append(spawn([SCRIBE, WARDEN, RUNNER][i % 3], i % 2, Vector3(i * 3.0 - 60.0, 0, 40.0)))
	for i in 4:
		units.append(spawn(TOWER if i < 2 else CORE, i % 2, Vector3(i * 5.0, 0, -50.0)))
	for i in 22:
		units.append(spawn(MELEE, i % 2, Vector3(i * 1.5 - 20.0, 0, 0)))
	await ticks(2)
	for u in units:
		u.cast_phase = Unit.CastPhase.WINDUP
		u.cast_slot = 0
		u.cast_timer = 0.2
		u.apply_slow(0.4, 2.0)
		u.stun_timer = 0.5
		u.dash_timer = 0.1
	var bytes := SnapshotCodec.encode(1, 1, units.size(), SnapshotCodec.encode_units(units))
	var old := {}
	for u in units:
		old[u.net_id] = [u.global_position, u.aim_yaw, u.health, u.alive, u.cast_phase, u.cast_slot,
			u.cast_timer, u.cast_target, u.cooldowns, u.slow_amount, u.slow_timer, u.respawn_timer, u.stun_timer]
	var old_size := var_to_bytes(old).size()
	print("  snapshot for %d units, everything active: %d bytes (old format %d, packet limit %d)" % [units.size(), bytes.size(), old_size, SnapshotCodec.MTU])
	check(bytes.size() <= SnapshotCodec.MTU, "32 busy units fit one %d byte packet (%d bytes)" % [SnapshotCodec.MTU, bytes.size()])
	check(old_size > SnapshotCodec.MTU, "the old format would not have (%d bytes)" % old_size)
	check(SnapshotCodec.decode(bytes).units.size() == units.size(), "every unit decodes")


func test_net_command_queue() -> void:
	var ctl := NetInputController.new()
	var u := spawn(SCRIBE, 0, Vector3.ZERO)
	var mk := func(x: float, b: int) -> UnitCommand:
		var c := UnitCommand.new()
		c.move = Vector2(x, 0)
		c.buttons = b
		return c
	# Packet for tick 3 arrives first, carrying 1..3; then a late repeat.
	ctl.receive(1, mk.call(0.1, 0))
	ctl.receive(3, mk.call(0.3, UnitCommand.BTN_ABILITY_1))
	ctl.receive(2, mk.call(0.2, 0))
	ctl.receive(2, mk.call(9.0, 0))
	var got: Array[float] = []
	for i in 3:
		got.append(snappedf(ctl.get_command(u).move.x, 0.01))
	check(got == [0.1, 0.2, 0.3] and ctl.applied_tick == 3, "commands apply one per tick in client order (%s)" % [got])
	ctl.receive(2, mk.call(0.2, 0))
	var again := ctl.get_command(u)
	check(is_equal_approx(again.move.x, 0.3) and not again.pressed(UnitCommand.BTN_ABILITY_1) and ctl.starved_ticks == 1,
		"a starved tick repeats movement but never an ability press")
	for i in 40:
		ctl.get_command(u)
	check(ctl.get_command(u).move == Vector2.ZERO, "silence for over 0.5 s stops the champion")
	for t in range(10, 30):
		ctl.receive(t, mk.call(1.0, 0))
	ctl.get_command(u)
	check(ctl.applied_tick >= 30 - NetInputController.MAX_QUEUE, "a burst is trimmed so the player does not stay behind (applied %d)" % ctl.applied_tick)


# --- Asset contract ------------------------------------------------------------

## Fixtures are Blender 5.2 exports of the template rig (tools/blender/
## make_fixtures.sh): one that follows the contract and four with the usual
## mistakes. Each mistake must be caught with a message that says what to fix.
func test_asset_contract() -> void:
	var dir := ProjectSettings.globalize_path("res://tests/fixtures/assets/")
	var cases := {
		"ok": [],
		"big": ["height 4.05", "Muzzle at"],
		"back": ["faces +Z"],
		"slide": ["feet would slide"],
		"late": ["'attack' releases", "'ability_2' releases"],
	}
	for k: String in cases:
		var path := dir + "ruinscribe_v%s.glb" % k
		var scene := AssetContract.load_gltf(path)
		check(scene != null, "%s: fixture loads through GLTFDocument" % k)
		if scene == null:
			continue
		world.add_child(scene)
		await ticks(1)
		var timing: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path.get_basename() + ".timing.json")).release
		var r := AssetContract.check(scene, SCRIBE, timing)
		var want: Array = cases[k]
		if want.is_empty():
			check(r.errors.is_empty(), "the template rig passes (%s)" % [r.errors])
			check(absf(r.measured.run_natural_speed_mps - SCRIBE.move_speed) < 0.2, "run stride measured at %.2f m/s" % r.measured.run_natural_speed_mps)
		for w: String in want:
			var found := false
			for e: String in r.errors:
				found = found or e.contains(w)
			check(found, "%s: an error mentions '%s' (%s)" % [k, w, r.errors])
		scene.queue_free()
	var bare := Node3D.new()
	var r2 := AssetContract.check(bare, SCRIBE)
	check(r2.errors.size() >= 3, "an empty scene fails (no mesh, sockets, AnimationPlayer)")
	bare.free()
	check(is_equal_approx(AssetContract.windup_speed(0.3, 0.3), 1.0) and AssetContract.windup_speed(0.6, 0.3) > AssetContract.MAX_SPEED,
		"windup speed is clip release over sim cast time")

