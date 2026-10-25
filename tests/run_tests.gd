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
const LANTERN := preload("res://data/champions/lanternkeeper.tres")
const THORN := preload("res://data/champions/thornwright.tres")
const GRAVE := preload("res://data/champions/gravebinder.tres")
const BARROW := preload("res://data/champions/barrowking.tres")
const VEIL := preload("res://data/champions/veilsinger.tres")
const STORM := preload("res://data/champions/stormscald.tres")
const CHAIN := preload("res://data/champions/chainbound.tres")
const STILL := preload("res://data/champions/stillhand.tres")
const BRASS := preload("res://data/champions/brasswright.tres")
const BANNER := preload("res://data/champions/banneret.tres")
const ROOT := preload("res://data/champions/rootwarden.tres")
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
		"test_marginalia", "test_stand_behind", "test_exposed_seam", "test_last_hit_xp",
		"test_gold_and_shop", "test_items_change_stats", "test_bots_buy_items", "test_recall",
		"test_batch_b_data", "test_root", "test_pull", "test_bramble_field", "test_mark",
		"test_lantern_heals", "test_dawnlight", "test_quarry", "test_tithe",
		"test_batch_c_data", "test_taunt", "test_charm", "test_war_song", "test_refrain", "test_storm_wall",
		"test_tempest", "test_ancestral_fury", "test_passive_snapshot", "test_keep_the_flame", "test_residual_charge", "test_kings_wrath",
		"test_fourth_ability_data", "test_fold_step", "test_searing_light", "test_smoke_veil",
		"test_adventurer_shop", "test_adventurer_stats", "test_item_passives", "test_adventurer_snapshot",
		"test_adventurer_build_path", "test_adventurer_bot_match",
		"test_chainbound_data", "test_grapple_to_wall", "test_grapple_rejects", "test_grapple_interrupt",
		"test_grapple_redirect", "test_grapple_charges", "test_momentum", "test_weaken", "test_covenant_line",
		"test_anchor_marking", "test_chainbound_snapshot", "test_chainbound_bot_match",
		"test_items_weapon", "test_items_spell", "test_items_defence", "test_items_support", "test_item_catalog",
		"test_stillhand_data", "test_bellbreaker", "test_still_water", "test_courtyard_push", "test_measured_breath",
		"test_brace_snapshot", "test_stillhand_bot_match",
		"test_phase6_data", "test_field_sentry", "test_sentry_replaced", "test_masterwork_in_place", "test_sentry_kill_credit",
		"test_breach_falloff", "test_calibration", "test_emergency_vent", "test_rally_standard", "test_ordered_retreat",
		"test_break_their_line", "test_hold_formation", "test_grasping_root", "test_elder_shape", "test_deep_roots",
		"test_barkskin", "test_phase6_bot_match", "test_three_lane_match",
		"test_surrender", "test_difficulty", "test_settings_saved",
		"test_prediction_matches_authority", "test_snapshot_codec_roundtrip", "test_snapshot_fits_packet",
		"test_net_command_queue", "test_asset_contract", "test_item_cards",
	]
	for t: String in tests:
		_make_world()
		var before := failures
		await call(t)
		print(("PASS " if failures == before else "FAIL ") + t)
		ItemShop.use_adventurer(false)
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


func add_wall(pos: Vector3, size: Vector3, anchor := false) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = Unit.LAYER_WORLD | (Unit.LAYER_ANCHOR if anchor else 0)
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
	aim(crossed, Vector3(0, 0, 10))  # face the runner: no Exposed Seam
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
	check(r0 == r1, "both teams field the same three champions")
	var ids := {}
	for d in r0:
		ids[d.id] = true
	check(ids.size() == 3, "three different champions")
	var seen := {}
	for s in range(1, 40):
		var m := MatchController.new()
		m.human_slot = false
		m.bot_seed = s
		for d in m.team_roster(0):
			seen[d.id] = true
		m.free()
	check(seen.size() == MatchController.ROSTER.size(), "over many seeds every champion gets drafted (%d of %d)" % [seen.size(), MatchController.ROSTER.size()])
	var fixed := MatchController.new()
	fixed.lineup_ids = [&"gravebinder", &"lanternkeeper", &"thornwright"]
	check(fixed.team_roster(0)[1].id == &"lanternkeeper", "a fixed lineup is kept in order")
	fixed.free()
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
	aim(target, Vector3(0, 0, 10))  # face the runner: no Exposed Seam
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
	aim(crossed, Vector3(0, 0, 10))  # face the runner: no Exposed Seam
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


func test_exposed_seam() -> void:
	var me := spawn(RUNNER, 0, Vector3.ZERO)
	var foe := spawn(SCRIBE, 1, Vector3(0, 0, -3))
	var other := spawn(SCRIBE, 1, Vector3(3, 0, -3))
	aim(foe, Vector3(0, 0, 5))
	aim(other, Vector3(3, 0, 5))
	await ticks(4)
	var cut := RUNNER.basic_attack
	var h := foe.health
	authority.apply_damage(me, foe, 100.0, cut)
	var plain := h - foe.health
	aim(foe, Vector3(0, 0, -20))  # turn away
	await ticks(4)
	h = foe.health
	authority.apply_damage(me, foe, 100.0, cut)
	check(is_equal_approx(h - foe.health, plain * (1.0 + RUNNER.passive_value)), "Exposed Seam: a hit from behind deals +%d%%" % roundi(RUNNER.passive_value * 100.0))
	h = foe.health
	authority.apply_damage(me, foe, 100.0, cut)
	check(is_equal_approx(h - foe.health, plain), "then not again on that target for a while")
	h = other.health
	authority.apply_damage(me, other, 100.0, RUNNER.get_slot(2))
	check(is_equal_approx(h - other.health, plain), "Ember Knife from the front: a plain hit")
	h = other.health
	authority.apply_damage(me, other, 100.0, cut)
	check(is_equal_approx(h - other.health, plain * (1.0 + RUNNER.passive_value)), "but it opens a seam for the next hit")


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


# --- Batch B: Lanternkeeper, Thornwright, Gravebinder ------------------------

func _cast(u: Unit, slot: int, at: Vector3, wait: float) -> void:
	aim(u, at)
	cmd(u).buttons = UnitCommand.ability_button(slot) if slot > 0 else UnitCommand.BTN_ATTACK
	await ticks(1)
	cmd(u).buttons = 0
	await secs(wait)


func test_batch_b_data() -> void:
	_kit_data([LANTERN, THORN, GRAVE])


func _kit_data(defs: Array) -> void:
	for def: ChampionDef in defs:
		check(def.abilities.size() == 4 and def.get_slot(3).is_ultimate, "%s has Q, E, F and an ultimate R" % def.id)
		check(def.get_slot(1).upgrades.size() == 2, "%s Q offers two upgrades" % def.id)
		check(def.passive != ChampionDef.Passive.NONE and not def.passive_name.is_empty(), "%s has a passive" % def.id)
		check(def.item_build.size() == 4, "%s has a bot item order" % def.id)
		for slot in def.slot_count():
			check(not def.get_slot(slot).description.is_empty(), "%s slot %d is described" % [def.id, slot])
	await ticks(1)


func test_fourth_ability_data() -> void:
	check(UnitCommand.ability_button(4) == UnitCommand.BTN_ABILITY_4, "slot 4 has its own button (F)")
	for def: ChampionDef in [SCRIBE, WARDEN, RUNNER, LANTERN, THORN, GRAVE, BARROW, VEIL, STORM]:
		var f := def.get_slot(4)
		check(f != null and not f.is_ultimate and not f.description.is_empty(), "%s has a described F ability" % def.id)
		check(def.slot_count() == 5, "%s has five slots" % def.id)
	await ticks(1)


func test_fold_step() -> void:
	var me := spawn(SCRIBE, 0, Vector3.ZERO)
	await ticks(2)
	aim(me, Vector3(0, 0, -10))
	cmd(me).move = Vector2(0, 1)
	await ticks(2)
	cmd(me).buttons = UnitCommand.BTN_ABILITY_4
	await ticks(1)
	cmd(me).buttons = 0
	cmd(me).move = Vector2.ZERO
	var start := me.global_position
	await secs(0.4)
	var step := SCRIBE.get_slot(4)
	var moved := Vector2(me.global_position.x - start.x, me.global_position.z - start.z).length()
	check(absf(moved - step.dash_distance) < 0.6, "F: Fold Step carries %.1f m (%.2f m)" % [step.dash_distance, moved])
	check(me.cooldowns[4] > 0.0 and me.cooldowns[1] <= 0.0, "only the F slot goes on cooldown")


func test_searing_light() -> void:
	var me := spawn(LANTERN, 0, Vector3.ZERO)
	var foe := spawn(DUMMY, 1, Vector3(0, 0, -8))
	await ticks(2)
	await _cast(me, 4, foe.global_position, 0.7)
	var light := LANTERN.get_slot(4)
	check(is_equal_approx(foe.health, DUMMY.max_health - light.damage), "Searing Light hits for %d" % roundi(light.damage))
	check(foe.is_stunned(), "and stuns")


func test_smoke_veil() -> void:
	var me := spawn(RUNNER, 0, Vector3.ZERO)
	var ally := spawn(SCRIBE, 0, Vector3(2, 0, 0))
	await ticks(2)
	await _cast(me, 4, me.global_position, 0.4)
	var veil := RUNNER.get_slot(4)
	check(is_equal_approx(ally.quick_amount, veil.ally_quick), "Smoke Veil: an ally inside moves %d%% faster" % roundi(veil.ally_quick * 100.0))
	await secs(veil.ward_duration)
	check(ally.quick_amount == 0.0, "the speed ends with the smoke")


func _shop_champion(def: ChampionDef, gold: float) -> Unit:
	ItemShop.use_adventurer(true)
	var u := spawn(def, 0, Vector3.ZERO)
	u.shop_point = Vector3.ZERO
	u.gold = gold
	return u


func _idx(id: StringName) -> int:
	var i := ItemShop.index_of(id)
	check(i > 0, "%s is in the adventurer catalog" % id)
	return i


func test_adventurer_shop() -> void:
	var u := _shop_champion(THORN, 3000.0)
	await ticks(2)
	var edge := _idx(&"tempered_edge")
	var duel := _idx(&"duelists_measure")
	var duel_def: ItemDef = Unit.ECONOMY.items[duel - 1]
	check(Unit.ECONOMY.slots == 6 and Unit.ECONOMY.items.size() == 30, "six slots, thirty items")
	check(u.buy_item(edge) and is_equal_approx(u.gold, 3000.0 - 160.0), "a component costs its price")
	check(u.buy_item(edge), "components can be doubled")
	var g0 := u.gold
	check(u.buy_item(duel) and is_equal_approx(g0 - u.gold, duel_def.cost - 160.0), "a recipe pays only what the owned part does not cover (%d)" % roundi(g0 - u.gold))
	check(u.items.size() == 2 and u.items.count(duel_def) == 1, "and uses up one Edge, keeping the other")
	check(not u.buy_item(duel), "a finished item cannot be bought twice")
	check(u.buy_item(_idx(&"trailwardens_token")) and not u.buy_item(_idx(&"apprentices_focus")), "one starter only")
	check(u.buy_item(_idx(&"travelers_soles")), "soles")
	g0 = u.gold
	check(u.buy_item(_idx(&"wayfarers_boots")) and is_equal_approx(g0 - u.gold, 360.0 - 120.0), "boots use the soles")
	check(not u.buy_item(_idx(&"ironstride_boots")), "one pair of boots only")
	# Fill the bag, then a recipe still fits because its parts leave.
	u.buy_item(_idx(&"etched_focus"))
	u.buy_item(_idx(&"hourglass_chip"))
	check(u.items.size() == 6, "six items carried (%d)" % u.items.size())
	var before := u.items.duplicate()
	g0 = u.gold
	check(not u.buy_item(_idx(&"vital_cord")), "a full bag refuses a new component")
	check(u.items == before and u.gold == g0, "a failed buy changes neither items nor gold")
	check(u.buy_item(_idx(&"runecasters_codex")) and u.items.size() == 5, "a recipe in a full bag frees its parts' slots")
	# Selling, health kept as a fraction, never refilled.
	u.health = u.max_health * 0.5
	var hp_frac := u.health / u.max_health
	g0 = u.gold
	var first: ItemDef = u.items[0]
	check(u.sell_item(1) and is_equal_approx(u.gold - g0, floorf(first.cost * 0.7)), "selling pays 70%")
	check(is_equal_approx(u.health / u.max_health, hp_frac), "selling or buying never heals")
	u.global_position = Vector3(40, 0, 0)
	await ticks(1)
	check(not u.sell_item(1) and not u.buy_item(edge), "no selling or buying away from the fountain")
	# The command path: buy and sell go through UnitCommand like any input.
	u.global_position = Vector3.ZERO
	var n := u.items.size()
	cmd(u).sell_item = 1
	await ticks(1)
	cmd(u).sell_item = 0
	check(u.items.size() == n - 1, "selling works through the command")
	var c := UnitCommand.from_dict({"s": 3, "i": 2})
	check(c.sell_item == 3 and c.buy_item == 2, "sell and buy survive the wire")
	check(UnitCommand.from_dict({"s": 99}).sell_item == 0, "a bad sell slot is dropped")


func test_adventurer_stats() -> void:
	var u := _shop_champion(WARDEN, 9000.0)
	var foe := spawn(SCRIBE, 1, Vector3(0, 0, -3))
	await ticks(2)
	var cleave := WARDEN.basic_attack
	check(CombatAuthority.power_kind(u, cleave) == 0 and CombatAuthority.power_kind(foe, SCRIBE.basic_attack) == 1, "Oathwarden hits with weapon power, Ruinscribe with spell power")
	var h0 := foe.health
	authority.apply_damage(u, foe, 100.0, cleave)
	var base := h0 - foe.health
	foe.health = foe.max_health
	u.buy_item(_idx(&"tempered_edge"))
	authority.apply_damage(u, foe, 100.0, cleave)
	check(absf((foe.max_health - foe.health) - base * 1.07) < 0.01, "+7 weapon power: 7% more weapon damage")
	var tower := spawn(TOWER, 1, Vector3(0, 0, -8))
	await ticks(1)
	var th := tower.health
	authority.apply_damage(u, tower, 100.0, cleave)
	check(absf((th - tower.health) - 100.0 * u.damage_mult * cleave.structure_damage_mult * u.structure_bonus) < 0.01, "item power does not speed up sieges")
	foe.health = foe.max_health
	foe.items.append(Unit.ECONOMY.items[_idx(&"iron_links") - 1])
	foe.recompute_stats()
	authority.apply_damage(u, foe, 100.0, cleave)
	check(absf((foe.max_health - foe.health) - base * 1.07 * 100.0 / 112.0) < 0.01, "12 armor: weapon damage x 100/112")
	foe.health = foe.max_health
	authority.apply_damage(foe, u, 100.0, SCRIBE.basic_attack)
	var spell := u.max_health - u.health
	check(absf(spell - 100.0) < 0.01, "armor does nothing against spells")
	# Haste: 100 / (100 + haste), item haste capped at 40.
	var w := spawn(SCRIBE, 0, Vector3(5, 0, 0))
	for id in [&"runecasters_codex", &"lantern_of_returning", &"hourglass_chip", &"spellwalkers_boots"]:
		w.items.append(Unit.ECONOMY.items[_idx(id) - 1])
	w.recompute_stats()
	check(is_equal_approx(w.ability_haste, 40.0) and is_equal_approx(w.cooldown_mult, 100.0 / 140.0), "haste caps at 40 (cooldowns x %.3f)" % w.cooldown_mult)
	var a := spawn(THORN, 0, Vector3(-5, 0, 0))
	a.items.append(Unit.ECONOMY.items[_idx(&"quickstring") - 1])
	a.recompute_stats()
	check(is_equal_approx(a.cooldown_for(0, THORN.basic_attack), THORN.basic_attack.cooldown / 1.08), "attack speed shortens the basic attack only")
	# Shields soak damage first and never stack.
	foe.apply_shield(50.0, 2.0)
	foe.apply_shield(30.0, 2.0)
	check(is_equal_approx(foe.shield, 50.0), "the bigger shield stays")
	var hp := foe.health
	authority.apply_damage(foe, u, 0.0, null)
	authority.apply_damage(u, foe, 40.0, AbilityDef.new())
	check(foe.health == hp and foe.shield < 50.0, "a hit smaller than the shield leaves health alone")
	await secs(2.1)
	check(foe.shield == 0.0, "the shield ends with its timer")


func test_item_passives() -> void:
	var u := _shop_champion(THORN, 0.0)
	var foe := spawn(WARDEN, 1, Vector3(0, 0, -3))
	await ticks(2)
	var duel_def: ItemDef = Unit.ECONOMY.items[_idx(&"duelists_measure") - 1]
	u.items.append(duel_def)
	u.recompute_stats()
	var bow := THORN.basic_attack
	var hits: Array[float] = []
	for i in 3:
		var h := foe.health
		authority.apply_damage(u, foe, 50.0, bow)
		hits.append(h - foe.health)
	check(is_equal_approx(hits[0], hits[1]) and absf(hits[2] - hits[0] - duel_def.passive_value) < 0.01, "Duelist's Measure: the third hit adds %d (%.1f)" % [roundi(duel_def.passive_value), hits[2] - hits[0]])
	# Codex: two different abilities on one champion.
	var s := spawn(SCRIBE, 0, Vector3(3, 0, 0))
	var codex: ItemDef = Unit.ECONOMY.items[_idx(&"runecasters_codex") - 1]
	s.items.append(codex)
	s.recompute_stats()
	foe.health = foe.max_health
	var h0 := foe.health
	authority.apply_damage(s, foe, 50.0, SCRIBE.get_slot(1))
	var one := h0 - foe.health
	h0 = foe.health
	authority.apply_damage(s, foe, 50.0, SCRIBE.get_slot(2))
	check(absf((h0 - foe.health) - one - codex.passive_value) < 0.01, "Runecaster's Codex: a second, different ability adds %d" % roundi(codex.passive_value))
	h0 = foe.health
	authority.apply_damage(s, foe, 50.0, SCRIBE.get_slot(1))
	check(absf((h0 - foe.health) - one) < 0.01, "and then waits for its cooldown")
	# Bastion: a shield when a champion hit drops the owner low, on a long cooldown.
	var b := spawn(BARROW, 1, Vector3(-3, 0, 0))
	var bastion: ItemDef = Unit.ECONOMY.items[_idx(&"bastion_plate") - 1]
	b.items.append(bastion)
	b.recompute_stats()
	b.shop_point = b.global_position
	authority.apply_damage(u, b, b.max_health * 0.7, bow)
	check(b.shield > 0.0, "Bastion Plate shields below 35%% health (%d)" % roundi(b.shield))
	b.shield = 0.0
	b.gold = 5000.0
	b.sell_item(1)
	b.buy_item(_idx(&"bastion_plate"))
	authority.apply_damage(u, b, 10.0, bow)
	check(b.shield == 0.0, "selling and buying again does not reset its cooldown")
	# Lantern: heals on a badly hurt ally are stronger; others unchanged.
	var l := spawn(LANTERN, 0, Vector3(6, 0, 0))
	l.items.append(Unit.ECONOMY.items[_idx(&"lantern_of_returning") - 1])
	var ally := spawn(SCRIBE, 0, Vector3(7, 0, 0))
	ally.health = ally.max_health * 0.2
	h0 = ally.health
	authority.heal(ally, 100.0, l)
	check(is_equal_approx(ally.health - h0, 130.0), "Lantern of Returning: +30%% on an ally under 35%% (%.0f)" % (ally.health - h0))
	ally.health = ally.max_health * 0.6
	h0 = ally.health
	authority.heal(ally, 100.0, l)
	check(is_equal_approx(ally.health - h0, 100.0), "no bonus on a healthier ally")
	# No proc from a proc: item damage never triggers item passives.
	u.item_counters.clear()
	var dueling := u.item_counters.size()
	authority.apply_damage(u, foe, 10.0, null, 0)
	check(u.item_counters.size() == dueling, "item damage does not count as a hit for items")


func test_adventurer_snapshot() -> void:
	var u := _shop_champion(RUNNER, 0.0)
	await ticks(2)
	for id in [&"trailwardens_token", &"tempered_edge", &"tempered_edge", &"bastion_plate", &"wayfarers_boots", &"quickstring"]:
		u.items.append(Unit.ECONOMY.items[_idx(id) - 1])
	u.recompute_stats()
	u.apply_shield(123.0, 2.5)
	var snap := SnapshotCodec.decode(SnapshotCodec.encode(1, 0, 1, SnapshotCodec.encode_units([u])))
	var s: Array = snap.units[u.net_id]
	var c := spawn(RUNNER, 1, Vector3(5, 0, 0))
	await ticks(1)
	SnapshotCodec.apply(c, s)
	check(c.items == u.items, "six items, doubles included, survive the snapshot")
	check(is_equal_approx(c.weapon_power, u.weapon_power) and is_equal_approx(c.armor, u.armor), "and give the same stats on the client")
	check(absf(c.shield - 123.0) <= 1.0 and absf(c.shield_timer - 2.5) < 0.01, "shield and its timer")


func test_adventurer_build_path() -> void:
	var u := _shop_champion(SCRIBE, 160.0)
	await ticks(2)
	check(ItemShop.next_step(u) == _idx(&"apprentices_focus"), "the build starts with its starter")
	u.buy_item(ItemShop.next_step(u))
	u.gold = 200.0
	var codex := _idx(&"runecasters_codex")
	var step := ItemShop.next_step(u)
	check(step != codex and Unit.ECONOMY.items[step - 1].kind == ItemDef.Kind.COMPONENT, "short of gold, the next step is a Codex part")
	u.buy_item(step)
	u.gold = 5000.0
	check(ItemShop.next_step(u) == codex, "with the gold, the Codex itself (using the part)")
	check(is_equal_approx(ItemShop.next_step_price(u), 1000.0 - 160.0), "and its price counts the part")


## Bots with adventurer items buy along their builds, finished items included.
func test_adventurer_bot_match() -> void:
	ItemShop.use_adventurer(true)
	var mc := MatchController.new()
	mc.human_slot = false
	world.add_child(mc)
	mc.setup(authority, world)
	mc.start()
	await ticks(2)
	for u: Unit in mc.champions:
		u.gold = 3000.0
	await secs(1.0)
	var finished := 0
	for u: Unit in mc.champions:
		for it in u.items:
			if it.kind == ItemDef.Kind.FINISHED:
				finished += 1
	check(finished >= 6, "bots at the fountain with gold buy finished items (%d)" % finished)


func test_marginalia() -> void:
	var me := spawn(SCRIBE, 0, Vector3.ZERO)
	var foe := spawn(DUMMY, 1, Vector3(0, 0, -6))
	await ticks(2)
	authority.apply_damage(me, foe, 10.0, SCRIBE.get_slot(2))
	check(me.shield == 0.0, "Marginalia: the lance alone gives no shield")
	authority.apply_damage(me, foe, 10.0, SCRIBE.get_slot(1))
	authority.apply_damage(me, foe, 10.0, SCRIBE.get_slot(2))
	check(is_equal_approx(me.shield, SCRIBE.passive_value), "glyph then lance on the same target: a %d shield" % roundi(SCRIBE.passive_value))
	me.shield = 0.0
	authority.apply_damage(me, foe, 10.0, SCRIBE.get_slot(2))
	check(me.shield == 0.0, "the mark is spent")
	authority.apply_damage(me, foe, 10.0, SCRIBE.get_slot(1))
	await secs(CombatAuthority.MARK_TIME + 0.2)
	authority.apply_damage(me, foe, 10.0, SCRIBE.get_slot(2))
	check(me.shield == 0.0, "a mark older than %d s does nothing" % roundi(CombatAuthority.MARK_TIME))
	var minion := spawn(MELEE, 1, Vector3(3, 0, -6))
	await ticks(1)
	authority.apply_damage(me, minion, 1.0, SCRIBE.get_slot(1))
	authority.apply_damage(me, minion, 1.0, SCRIBE.get_slot(2))
	check(me.shield == 0.0, "minions cannot be inscribed")


func test_stand_behind() -> void:
	var warden := spawn(WARDEN, 0, Vector3.ZERO)
	var ally := spawn(SCRIBE, 0, Vector3(3, 0, 0))
	var far := spawn(SCRIBE, 0, Vector3(30, 0, 0))
	var foe := spawn(SCRIBE, 1, Vector3(0, 0, -2))
	await ticks(2)
	ally.health = ally.max_health * 0.5
	far.health = far.max_health * 0.2
	authority.apply_damage(warden, foe, 10.0, WARDEN.basic_attack)
	check(ally.shield == 0.0, "Stand Behind Me: an unprimed hit shields nobody")
	await _cast(warden, 1, warden.global_position, 0.6)
	authority.apply_damage(warden, foe, 10.0, WARDEN.basic_attack)
	check(is_equal_approx(ally.shield, WARDEN.passive_value) and far.shield == 0.0, "after a cast, the next hit shields the most hurt ally in reach")
	ally.shield = 0.0
	await _cast(warden, 2, foe.global_position, 0.6)
	authority.apply_damage(warden, foe, 10.0, WARDEN.basic_attack)
	check(ally.shield == 0.0, "then it waits %d s" % roundi(CombatAuthority.STAND_COOLDOWN))
	authority.apply_damage(warden, foe, 10.0, WARDEN.basic_attack)
	ally.health = ally.max_health
	warden.health = warden.max_health * 0.5
	await secs(CombatAuthority.STAND_COOLDOWN)
	warden.cooldowns.fill(0.0)
	await _cast(warden, 2, foe.global_position, 0.6)
	authority.apply_damage(warden, foe, 10.0, WARDEN.basic_attack)
	check(warden.shield > 0.0, "with no hurt ally it shields the Oathwarden")


func test_quarry() -> void:
	var me := spawn(THORN, 0, Vector3.ZERO)
	var foe := spawn(DUMMY, 1, Vector3(0, 0, -8))
	await ticks(2)
	var shot := THORN.get_slot(1)
	var h := foe.health
	authority.apply_damage(me, foe, 100.0, shot)
	check(is_equal_approx(h - foe.health, 100.0), "Patient Quarry: an unmarked target takes plain damage")
	for i in 5:
		authority.apply_damage(me, foe, 1.0, THORN.basic_attack)
	h = foe.health
	authority.apply_damage(me, foe, 100.0, shot)
	check(is_equal_approx(h - foe.health, 100.0 * (1.0 + 3.0 * THORN.passive_value)), "three marks at most: +%d%%" % roundi(300.0 * THORN.passive_value))
	h = foe.health
	authority.apply_damage(me, foe, 100.0, shot)
	check(is_equal_approx(h - foe.health, 100.0), "the marks are spent")
	authority.apply_damage(me, foe, 1.0, THORN.basic_attack)
	await secs(CombatAuthority.MARK_TIME + 0.2)
	h = foe.health
	authority.apply_damage(me, foe, 100.0, shot)
	check(is_equal_approx(h - foe.health, 100.0), "marks fade after %d s" % roundi(CombatAuthority.MARK_TIME))


func test_root() -> void:
	var me := spawn(GRAVE, 0, Vector3.ZERO)
	var foe := spawn(WARDEN, 1, Vector3(0, 0, -8))
	await ticks(2)
	await _cast(me, 1, foe.global_position, 0.9)
	var chains := GRAVE.get_slot(1)
	check(foe.root_timer > 0.0, "chains root the enemy hit")
	check(is_equal_approx(foe.health, WARDEN.max_health - chains.damage), "chains deal %.0f" % chains.damage)
	var at := foe.global_position
	cmd(foe).move = Vector2(1, 0)
	await secs(0.3)
	check(UnitController.flat_distance(at, foe.global_position) < 0.05, "a rooted champion cannot walk")
	await secs(1.2)
	check(UnitController.flat_distance(at, foe.global_position) > 1.0, "it walks again once the root ends")
	# A rooted dash does not happen.
	var runner := spawn(RUNNER, 1, Vector3(10, 0, 0))
	await ticks(2)
	runner.apply_root(2.0)
	var r0 := runner.global_position
	await _cast(runner, 1, Vector3(10, 0, -10), 0.5)
	check(UnitController.flat_distance(r0, runner.global_position) < 0.05, "a rooted champion cannot dash")
	var s: Array = SnapshotCodec.decode(SnapshotCodec.encode(1, 0, 1, SnapshotCodec.encode_units([runner]))).units[runner.net_id]
	check(absf(s[SnapshotCodec.ROOT] - runner.root_timer) < 0.01, "root timer survives a snapshot")


func test_pull() -> void:
	var me := spawn(GRAVE, 0, Vector3.ZERO)
	var foe := spawn(DUMMY, 1, Vector3(2.4, 0, -8))
	await ticks(2)
	var center := Vector3(0, 0, -8)
	await _cast(me, 2, center, 1.4)
	var d := UnitController.flat_distance(foe.global_position, center)
	check(d < 1.0, "grasping earth drags the enemy toward the middle (%.2f m from it)" % d)
	check(foe.health < DUMMY.max_health, "and hurts it")


func test_bramble_field() -> void:
	var me := spawn(THORN, 0, Vector3.ZERO)
	var foe := spawn(WARDEN, 1, Vector3(0, 0, -8))
	await ticks(2)
	await _cast(me, 2, foe.global_position, 1.0)
	var field := authority.areas.filter(func(a: CombatAuthority.SimArea) -> bool: return a.ability.enemy_slow > 0.0)
	check(field.size() == 1, "bramble leaves a thorn field behind")
	await secs(2.0)
	check(foe.slow_amount >= 0.35 - 0.001, "an enemy standing in the thorns stays slowed")
	foe.global_position = Vector3(8, 0, -8)
	await secs(0.5)
	check(foe.slow_timer <= 0.0, "the slow ends soon after leaving")
	await secs(2.0)
	check(authority.areas.filter(func(a: CombatAuthority.SimArea) -> bool: return a.ability.enemy_slow > 0.0).is_empty(), "the thorns wither")


func test_mark() -> void:
	var me := spawn(LANTERN, 0, Vector3.ZERO)
	var foe := spawn(DUMMY, 1, Vector3(0, 0, -8))
	await ticks(2)
	await _cast(me, 2, foe.global_position, 0.9)
	var raven := LANTERN.get_slot(2)
	check(foe.mark_timer > 0.0, "the raven marks the enemy")
	var h := foe.health
	authority.apply_damage(me, foe, 100.0, null)
	check(is_equal_approx(h - foe.health, 100.0 * (1.0 + raven.mark_amount)), "a marked enemy takes %d%% more" % roundi(raven.mark_amount * 100.0))


func test_lantern_heals() -> void:
	var me := spawn(LANTERN, 0, Vector3.ZERO)
	var ally := spawn(SCRIBE, 0, Vector3(3, 0, 0))
	await ticks(2)
	ally.health = 200.0
	await _cast(me, 1, me.global_position, 1.3)
	var gain := ally.health - 200.0
	check(gain > LANTERN.get_slot(1).heal_per_second * 0.8, "lantern light heals an ally standing in it (%.0f in 1 s)" % gain)



func test_keep_the_flame() -> void:
	var me := spawn(LANTERN, 0, Vector3.ZERO)
	var ally := spawn(SCRIBE, 0, Vector3(2, 0, 0))
	var foe := spawn(SCRIBE, 1, Vector3(0, 0, -12))
	await ticks(2)
	var light := LANTERN.get_slot(1)
	ally.health = 200.0
	await _cast(me, 1, ally.global_position, 1.3)
	check(me.passive_stacks == 0.0, "Keep the Flame: healing out of a fight stores nothing")
	authority.apply_damage(foe, ally, 10.0, SCRIBE.basic_attack)
	me.cooldowns[1] = 0.0
	await _cast(me, 1, ally.global_position, 1.3)
	check(is_equal_approx(me.passive_stacks, 1.0), "healing an ally in a fight stores one ember per cast")
	authority.apply_damage(foe, ally, 10.0, SCRIBE.basic_attack)
	me.cooldowns[1] = 0.0
	await _cast(me, 1, ally.global_position, light.cast_time + 0.05)
	check(is_equal_approx(ally.shield, LANTERN.passive_value) and is_equal_approx(me.shield, LANTERN.passive_value), "the next light shields everyone in it for %d per ember" % roundi(LANTERN.passive_value))
	check(me.passive_stacks <= 1.0, "and spends the embers")


func test_residual_charge() -> void:
	var me := spawn(STORM, 0, Vector3.ZERO)
	var foe := spawn(DUMMY, 1, Vector3(0, 0, -8))
	await ticks(2)
	var bolt := STORM.get_slot(4)
	var strike := STORM.get_slot(1)
	var h := foe.health
	await _cast(me, 1, foe.global_position, strike.cast_time + strike.area_delay + 0.2)
	var plain := h - foe.health
	check(plain > 0.0, "a plain Called Lightning (%.0f)" % plain)
	authority.apply_damage(me, foe, 1.0, bolt)
	authority.apply_damage(me, foe, 1.0, bolt)
	check(is_equal_approx(me.passive_stacks, 1.0), "Residual Charge: one cast stores one charge, however often it hits")
	await secs(CombatAuthority.RESIDUAL_WINDOW + 0.1)
	authority.apply_damage(me, foe, 1.0, bolt)
	await secs(CombatAuthority.RESIDUAL_WINDOW + 0.1)
	authority.apply_damage(me, foe, 1.0, bolt)
	check(is_equal_approx(me.passive_stacks, CombatAuthority.RESIDUAL_MAX), "up to two")
	me.cooldowns[1] = 0.0
	h = foe.health
	await _cast(me, 1, foe.global_position, strike.cast_time + strike.area_delay + 0.2)
	check(absf(h - foe.health - plain * (1.0 + 2.0 * STORM.passive_value)) < 1.0, "the next Called Lightning spends them: +%d%% (%.0f)" % [roundi(200.0 * STORM.passive_value), h - foe.health])
	check(me.passive_stacks == 0.0, "and they are gone")


func test_dawnlight() -> void:
	var me := spawn(LANTERN, 0, Vector3.ZERO)
	var ally := spawn(SCRIBE, 0, Vector3(0, 0, -8))
	var foe := spawn(DUMMY, 1, Vector3(1, 0, -8))
	await ticks(2)
	_level_up(me, Unit.ULT_LEVEL)
	ally.health = 100.0
	await _cast(me, 3, ally.global_position, 1.2)
	var dawn := LANTERN.get_slot(3)
	check(ally.health >= 100.0 + dawn.ally_heal, "dawnlight heals the ally in it (%.0f)" % ally.health)
	check(foe.health < DUMMY.max_health, "and burns the enemy")


func test_tithe() -> void:
	var me := spawn(GRAVE, 0, Vector3.ZERO)
	var foe := spawn(DUMMY, 1, Vector3(0, 0, -8))
	await ticks(2)
	var bolt := GRAVE.basic_attack
	await _cast(me, 0, foe.global_position, 0.8)
	check(is_equal_approx(DUMMY.max_health - foe.health, bolt.damage), "a free target takes plain damage")
	foe.apply_slow(0.3, 5.0)
	var h := foe.health
	await secs(0.5)
	await _cast(me, 0, foe.global_position, 0.8)
	check(is_equal_approx(h - foe.health, bolt.damage * (1.0 + GRAVE.passive_value)), "Soul Tithe: a slowed target takes %d%% more" % roundi(GRAVE.passive_value * 100.0))


# --- Batch C: Barrowking, Veilsinger, Stormscald -------------------------------

func test_batch_c_data() -> void:
	_kit_data([BARROW, VEIL, STORM])


func test_taunt() -> void:
	var me := spawn(BARROW, 0, Vector3.ZERO)
	var foe := spawn(SCRIBE, 1, Vector3(0, 0, -4))
	await ticks(2)
	await _cast(me, 1, me.global_position, 0.6)
	aim(foe, Vector3(0, 0, -20))
	cmd(foe).move = Vector2(0, 1)  # trying to walk away
	var roar := BARROW.get_slot(1)
	check(foe.compel == Unit.Compel.TAUNT and foe.compel_timer > 0.0, "the roar taunts an enemy in reach")
	check(is_equal_approx(foe.health, SCRIBE.max_health - roar.damage), "and deals %.0f" % roar.damage)
	check(absf(wrapf(foe.aim_yaw - atan2(-(me.global_position.x - foe.global_position.x), -(me.global_position.z - foe.global_position.z)), -PI, PI)) < 0.1, "a taunted champion faces the Barrowking")
	await secs(0.6)
	check(me.health < BARROW.max_health, "and attacks it instead of walking away (%.0f)" % me.health)
	await secs(1.0)
	check(foe.compel_timer <= 0.0 and foe.compel == Unit.Compel.NONE, "the taunt ends")
	var d0 := UnitController.flat_distance(foe.global_position, me.global_position)
	await secs(0.4)
	check(UnitController.flat_distance(foe.global_position, me.global_position) > d0 + 1.0, "then it walks away again")
	var s: Array = SnapshotCodec.decode(SnapshotCodec.encode(1, 0, 1, SnapshotCodec.encode_units([foe]))).units[foe.net_id]
	foe.apply_compel(Unit.Compel.TAUNT, me, 1.0)
	s = SnapshotCodec.decode(SnapshotCodec.encode(1, 0, 1, SnapshotCodec.encode_units([foe]))).units[foe.net_id]
	check(s[SnapshotCodec.COMPEL] == Unit.Compel.TAUNT and absf(s[SnapshotCodec.COMPEL_TIMER] - foe.compel_timer) < 0.01 \
			and UnitController.flat_distance(s[SnapshotCodec.COMPEL_POINT], me.global_position) < 0.02, "a taunt survives a snapshot")


func test_charm() -> void:
	var me := spawn(VEIL, 0, Vector3.ZERO)
	var foe := spawn(WARDEN, 1, Vector3(0, 0, -8))
	await ticks(2)
	aim(foe, me.global_position)
	cmd(foe).move = Vector2(0, 1)  # walking in to fight
	cmd(foe).buttons = UnitCommand.BTN_ATTACK
	aim(me, foe.global_position)
	cmd(me).buttons = UnitCommand.ability_button(2)
	await ticks(1)
	cmd(me).buttons = 0
	var lure := VEIL.get_slot(2)
	for i in 60:
		await ticks(1)
		if foe.compel_timer > 0.0:
			break
	check(foe.compel == Unit.Compel.CHARM, "the lure charms the first enemy hit")
	var d0 := UnitController.flat_distance(foe.global_position, me.global_position)
	await secs(0.5)
	check(UnitController.flat_distance(foe.global_position, me.global_position) > d0 + 1.5, "a charmed champion walks away")
	check(not foe.is_casting(), "and cannot attack")
	await secs(lure.charm_duration)
	check(foe.compel == Unit.Compel.NONE, "the charm ends")


func test_war_song() -> void:
	var me := spawn(VEIL, 0, Vector3.ZERO)
	var ally := spawn(SCRIBE, 0, Vector3(2, 0, 0))
	var far := spawn(SCRIBE, 0, Vector3(15, 0, 0))
	await ticks(2)
	await _cast(me, 1, me.global_position, 0.6)
	var song := VEIL.get_slot(1)
	check(is_equal_approx(ally.haste_amount, song.ally_haste), "War Song: an ally inside attacks %d%% faster" % roundi(song.ally_haste * 100.0))
	check(is_equal_approx(ally.cooldown_for(0, SCRIBE.basic_attack), SCRIBE.basic_attack.cooldown / (1.0 + song.ally_haste)), "its basic attack interval is shorter")
	check(is_equal_approx(ally.cooldown_for(1, SCRIBE.get_slot(1)), SCRIBE.get_slot(1).cooldown), "abilities are not sped up")
	check(far.haste_amount == 0.0, "an ally outside is not")
	await secs(song.ward_duration)
	check(ally.haste_amount == 0.0, "the haste ends with the song")


func test_refrain() -> void:
	var me := spawn(VEIL, 0, Vector3.ZERO)
	var foe := spawn(SCRIBE, 1, Vector3(0, 0, -6))
	await ticks(2)
	var song := VEIL.get_slot(1)
	var lure := VEIL.get_slot(2)
	await _cast(me, 1, me.global_position, song.cast_time + 0.1)
	check(is_equal_approx(me.haste_amount, song.ally_haste), "a first War Song is plain")
	await _cast(me, 2, foe.global_position, 1.2)
	check(foe.compel_timer > 0.0, "Lure after War Song lands")
	var strong := CombatAuthority.empowered(lure)
	check(is_equal_approx(strong.charm_duration, lure.charm_duration + 0.4) and is_equal_approx(strong.range, lure.range + 3.0), "Refrain: the second of the pair is the stronger Lure")
	var loud := CombatAuthority.empowered(song)
	check(is_equal_approx(loud.ally_haste, song.ally_haste * 1.4) and is_equal_approx(loud.area_radius, song.area_radius + 1.0), "and a closing War Song is wider and quicker")
	check(me.refrain_slot == -1, "the pair starts over")
	check(song.ally_haste == VEIL.get_slot(1).ally_haste, "the data itself is unchanged")


func test_storm_wall() -> void:
	var me := spawn(STORM, 0, Vector3.ZERO)
	var foe := spawn(SCRIBE, 1, Vector3(0, 0, -14))
	await ticks(2)
	await _cast(me, 2, foe.global_position, 0.5)
	check(authority.areas.any(func(a: CombatAuthority.SimArea) -> bool: return a.ability.delivery == AbilityDef.Delivery.WALL), "the storm wall stands")
	await _cast(foe, 0, me.global_position, 0.8)
	check(me.health == STORM.max_health, "an enemy shot stops at the wall")
	await _cast(me, 0, foe.global_position, 0.8)
	check(foe.health < SCRIBE.max_health, "the caster's own shots pass through")
	await secs(STORM.get_slot(2).ward_duration)
	await _cast(foe, 0, me.global_position, 0.9)
	check(me.health < STORM.max_health, "once it falls, shots hit again")


func test_tempest() -> void:
	var me := spawn(STORM, 0, Vector3.ZERO)
	var foe := spawn(DUMMY, 1, Vector3(0, 0, -10))
	var edge := spawn(DUMMY, 1, Vector3(3.2, 0, -10))
	await ticks(2)
	_level_up(me, Unit.ULT_LEVEL)
	var t := STORM.get_slot(3)
	await _cast(me, 3, foe.global_position, t.cast_time + t.area_delay + 0.6 * 2 + 0.2)
	var dmg := t.damage * me.damage_mult
	check(absf(DUMMY.max_health - foe.health - 3.0 * dmg) < 1.0, "Tempest strikes three times (%.0f)" % (DUMMY.max_health - foe.health))
	check(absf(DUMMY.max_health - edge.health - 3.0 * dmg) < 1.0, "the same at the edge (%.0f)" % (DUMMY.max_health - edge.health))
	check(is_equal_approx(me.passive_stacks, 1.0), "Residual Charge: one cast stores one charge (%.1f)" % me.passive_stacks)


func test_ancestral_fury() -> void:
	var me := spawn(BARROW, 0, Vector3.ZERO)
	var foe := spawn(SCRIBE, 1, Vector3(0, 0, -2))
	await ticks(2)
	for i in 6:
		authority.apply_damage(me, foe, 1.0, BARROW.basic_attack)
	check(is_equal_approx(me.passive_stacks, 60.0), "Ancestral Fury: hits dealt fill 10 each (%.0f)" % me.passive_stacks)
	for i in 7:
		authority.apply_damage(foe, me, 1.0, SCRIBE.basic_attack)
	check(is_equal_approx(me.passive_stacks, 100.0), "hits taken fill 6 each, up to 100")
	me.health = 300.0
	await _cast(me, 1, foe.global_position, BARROW.get_slot(1).cast_time + 0.05)
	check(absf(me.health - 300.0 - BARROW.max_health * BARROW.passive_value) < 1.0, "at full, Grave Roar heals %d%% of max health (%.0f)" % [roundi(BARROW.passive_value * 100.0), me.health - 300.0])
	check(me.passive_stacks < 20.0, "and spends the fury")
	await secs(2.0)  # the taunted foe swings back for a moment
	me.passive_stacks = 50.0
	await secs(CombatAuthority.FIGHT_TIME)
	check(me.passive_stacks < 50.0, "out of the fight it fades (%.0f)" % me.passive_stacks)


func test_kings_wrath() -> void:
	var me := spawn(BARROW, 0, Vector3.ZERO)
	var behind := spawn(SCRIBE, 1, Vector3(0, 0, 3))
	var far := spawn(SCRIBE, 1, Vector3(0, 0, -9))
	await ticks(2)
	_level_up(me, Unit.ULT_LEVEL)
	await _cast(me, 3, Vector3(0, 0, -5), BARROW.get_slot(3).cast_time + 0.05)
	check(behind.health < SCRIBE.max_health and behind.is_stunned(), "King's Wrath hits and stuns all around, even behind")
	check(far.health == SCRIBE.max_health, "but not beyond its reach")


# --- Match loop: surrender, difficulty, saved settings ------------------------

func test_surrender() -> void:
	var mc := _match()
	var result := [-2]
	mc.match_over.connect(func(w: int) -> void: result[0] = w)
	await ticks(2)
	mc.surrender(0)
	check(mc.over and mc.winner == 1 and result[0] == 1, "surrendering hands the match to the other team")
	check(mc.stats.reason == "surrendered", "the result says why")
	mc.surrender(1)
	check(mc.winner == 1, "a second surrender after the end changes nothing")


func test_difficulty() -> void:
	for level in 3:
		var mc := MatchController.new()
		mc.human_slot = true
		mc.difficulty = level
		mc.bot_seed = 3
		world.add_child(mc)
		mc.setup(authority, world)
		mc.start()
		var enemy := mc.champions.filter(func(u: Unit) -> bool: return u.team == 1)[0] as Unit
		var ally := mc.champions.filter(func(u: Unit) -> bool: return u.team == 0 and u.controller is ChampionBot)[0] as Unit
		var eb := enemy.controller as ChampionBot
		var ab := ally.controller as ChampionBot
		check(is_equal_approx(ab.reaction, 0.3) and is_equal_approx(ab.aim_error, 0.7), "%s: allied bots stay Normal" % Settings.DIFFICULTY_NAMES[level])
		if level == 0:
			check(eb.reaction > 0.3 and eb.aim_error > 0.7, "Easy: enemy bots react slower and aim looser")
		elif level == 2:
			check(eb.reaction < 0.3 and eb.aim_error < 0.7, "Hard: enemy bots react faster and aim tighter")
		else:
			check(is_equal_approx(eb.reaction, 0.3), "Normal: enemy bots unchanged")
		check(is_equal_approx(enemy.max_health, enemy.def.max_health), "difficulty never changes health")
		mc.queue_free()
		for u in mc.champions + mc.structures:
			authority.remove_unit(u)
		await ticks(1)


func test_settings_saved() -> void:
	var keep := [Settings.volume, Settings.mouse_sensitivity, Settings.difficulty, Settings.wins.duplicate(), Settings.losses.duplicate()]
	Settings.volume = 0.35
	Settings.mouse_sensitivity = 1.6
	Settings.difficulty = 2
	Settings.wins = [0, 0, 4]
	Settings.losses = [0, 0, 1]
	Settings.save()
	Settings.volume = 1.0
	Settings.mouse_sensitivity = 1.0
	Settings.difficulty = 0
	Settings._loaded = false
	Settings.load_once()
	check(is_equal_approx(Settings.volume, 0.35) and is_equal_approx(Settings.mouse_sensitivity, 1.6) and Settings.difficulty == 2, "settings come back after a restart")
	check(Settings.record_text() == "Your record on Hard: 4 wins, 1 loss", "the record reads plainly (%s)" % Settings.record_text())
	Settings.record(true)
	check(Settings.wins[2] == 5, "a win is counted for the chosen difficulty")
	Settings.volume = keep[0]
	Settings.mouse_sensitivity = keep[1]
	Settings.difficulty = keep[2]
	Settings.wins.assign(keep[3])
	Settings.losses.assign(keep[4])
	Settings.save()
	await ticks(1)


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
## Item cards (hover and Alt): every adventurer item shows its stats, and
## an item with a passive shows the passive part of its text, not the stats.
func test_item_cards() -> void:
	var eco: EconomyDef = load("res://data/economy_adventurer.tres")
	var bare := 0
	for it: ItemDef in eco.items:
		var stats := Hud.item_stat_lines(it)
		var extra := Hud.item_passive_text(it)
		if stats.is_empty() and extra.is_empty():
			bare += 1
		if it.passive != ItemDef.Passive.NONE:
			check(not extra.is_empty() and not extra.begins_with("+"), "%s card shows its passive" % it.id)
	check(bare == 0, "every item card has stats or a passive (%d bare)" % bare)
	var duel: ItemDef = load("res://data/items/adventurer/duelists_measure.tres")
	check(Hud.item_stat_lines(duel) == PackedStringArray(["+18 weapon power", "+15% attack speed"]), "Duelist's Measure lists its two stats")
	check(InputMap.has_action("item_details"), "Alt is bound to item details")


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



# --- Phase 4: Chainbound -------------------------------------------------

func test_chainbound_data() -> void:
	check(CHAIN.slot_count() == 5 and CHAIN.get_slot(3).is_ultimate, "Chainbound has Q, E, F and an ultimate R")
	var e := CHAIN.get_slot(2)
	check(e.delivery == AbilityDef.Delivery.GRAPPLE and e.max_charges == 2, "E is a two charge grapple")
	check(CHAIN.get_slot(3).line_width > 0.0, "R is a line on the ground")
	check(CHAIN.get_slot(4).weaken_amount > 0.0 and CHAIN.get_slot(4).stun_duration == 0.0, "F weakens and does not stun")
	check(CHAIN.passive == ChampionDef.Passive.MOMENTUM and not CHAIN.passive_name.is_empty(), "Borrowed Momentum passive")
	check(CHAIN.hero_name == "Veyra Sable", "lore name")
	for slot in CHAIN.slot_count():
		check(not CHAIN.get_slot(slot).description.is_empty(), "slot %d is described" % slot)
	check(not MatchController.ROSTER.has(CHAIN) and MatchController.PROTOTYPES.has(CHAIN), "a prototype: pickable, never drawn at random")
	var mc := MatchController.new()
	mc.human_slot = true
	mc.human_pick = &"chainbound"
	world.add_child(mc)
	mc.setup(authority, world)
	check(mc.team_roster(0)[0] == CHAIN, "the player can pick Chainbound")
	await ticks(1)


## Press E aimed at `at`.
func _grapple(u: Unit, at: Vector3) -> void:
	aim(u, at)
	cmd(u).buttons = UnitCommand.ability_button(2)
	await ticks(1)
	cmd(u).buttons = 0


func test_grapple_to_wall() -> void:
	add_wall(Vector3(0, 1.5, -10), Vector3(8, 3, 1), true)
	var me := spawn(CHAIN, 0, Vector3.ZERO)
	await ticks(2)
	var e := CHAIN.get_slot(2)
	var land := -9.5 + CHAIN.radius + 0.15
	check(me.grapple_endpoint(e, Vector3(0, 0, -20)).distance_to(Vector3(0, 0, land)) < 0.05, "the landing point stands off the wall")
	await _grapple(me, Vector3(0, 0, -20))
	check(me.charges[2] == 1, "a launch spends one charge")
	await secs(e.cast_time + 0.1)
	check(me.is_grappling(), "the chain pulls her")
	check(absf(me.grapple_anchor.z + 9.5) < 0.1, "the chain holds the wall face")
	await secs(0.6)
	check(not me.is_grappling() and absf(me.global_position.z - land) < 0.15, "she lands in front of the wall (z %.2f)" % me.global_position.z)
	check(me.alive and absf(me.global_position.x) < 0.1, "straight line, still standing")


func test_grapple_rejects() -> void:
	var me := spawn(CHAIN, 0, Vector3.ZERO)
	var why := []
	me.cast_rejected.connect(func(_s: int, r: String) -> void: why.append(r))
	await ticks(2)
	# Nothing in reach.
	await _grapple(me, Vector3(0, 0, -20))
	await ticks(2)
	check(me.charges[2] == 2 and not me.is_casting() and not why.is_empty(), "no wall: no cast, no charge, a message")
	check(me.cooldowns[2] > 0.0 and me.cooldowns[2] <= Unit.GRAPPLE_RETRY, "a short retry wait")
	# A wall out of range.
	add_wall(Vector3(0, 1.5, -15), Vector3(8, 3, 1), true)
	await ticks(2)
	check(not me.grapple_endpoint(CHAIN.get_slot(2), Vector3(0, 0, -20)).is_finite(), "a wall beyond 12 m does not count")
	# A wall that is not marked as an anchor.
	add_wall(Vector3(8, 1.5, 0), Vector3(1, 3, 8), false)
	await ticks(2)
	check(not me.grapple_endpoint(CHAIN.get_slot(2), Vector3(20, 0, 0)).is_finite(), "an unmarked wall does not hold")
	check(me.grapple_problem.contains("cannot hold"), "and says why")
	# An unmarked wall in front of a marked one blocks the chain: no passing through.
	add_wall(Vector3(-10, 1.5, 0), Vector3(1, 3, 8), true)
	add_wall(Vector3(-5, 1.5, 0), Vector3(0.5, 3, 8), false)
	await ticks(2)
	check(not me.grapple_endpoint(CHAIN.get_slot(2), Vector3(-20, 0, 0)).is_finite(), "the chain never passes through a wall")
	# A low block under the chain: the chain reaches, the body would not.
	add_wall(Vector3(0, 1.5, 10), Vector3(8, 3, 1), true)
	add_wall(Vector3(0, 0.3, 5), Vector3(4, 0.6, 1), false)
	await ticks(2)
	check(not me.grapple_endpoint(CHAIN.get_slot(2), Vector3(0, 0, 20)).is_finite() and me.grapple_problem.contains("blocked"), "a blocked route is refused")
	# Rooted: no launch, the charge stays.
	add_wall(Vector3(0, 1.5, -11), Vector3(8, 3, 1), true)
	await ticks(2)
	me.cooldowns[2] = 0.0
	me.apply_root(1.0)
	await _grapple(me, Vector3(0, 0, -20))
	await secs(0.3)
	check(me.charges[2] == 2 and not me.is_grappling(), "rooted: no launch, no charge spent")


func test_grapple_interrupt() -> void:
	add_wall(Vector3(0, 1.5, -11.5), Vector3(8, 3, 1), true)
	var me := spawn(CHAIN, 0, Vector3.ZERO)
	await ticks(2)
	await _grapple(me, Vector3(0, 0, -20))
	await secs(CHAIN.get_slot(2).cast_time + 0.1)
	check(me.is_grappling(), "in flight")
	me.apply_stun(0.5)
	var at := me.global_position
	await secs(0.2)
	check(not me.is_grappling() and me.global_position.distance_to(at) < 0.1, "a stun stops the pull where she is")
	check(me.charges[2] == 1, "the launched charge stays spent")
	await secs(0.5)
	await _grapple(me, Vector3(0, 0, -20))
	await secs(CHAIN.get_slot(2).cast_time + 0.05)
	check(me.is_grappling(), "second launch")
	me.apply_root(0.5)
	at = me.global_position
	await secs(0.2)
	check(not me.is_grappling() and me.global_position.distance_to(at) < 0.1, "a root pulls her down too")
	check(me.charges[2] == 0, "both charges spent")
	await _grapple(me, Vector3(0, 0, -20))
	await ticks(2)
	check(not me.is_casting(), "no charges left: no cast")


func test_grapple_redirect() -> void:
	add_wall(Vector3(0, 1.5, -11.5), Vector3(6, 3, 1), true)
	add_wall(Vector3(10, 1.5, -4), Vector3(1, 3, 16), true)
	var me := spawn(CHAIN, 0, Vector3.ZERO)
	await ticks(2)
	await _grapple(me, Vector3(0, 0, -20))
	await secs(0.33)
	check(me.is_grappling(), "flying toward the first wall")
	await _grapple(me, me.global_position + Vector3(20, 0, 0))
	check(me.charges[2] == 0, "the redirect spends the second charge")
	await secs(0.8)
	check(not me.is_grappling() and me.global_position.x > 8.5, "she ends at the second wall (x %.2f)" % me.global_position.x)
	check(me.global_position.z > -11.0, "and never reached the first one")


func test_grapple_charges() -> void:
	add_wall(Vector3(0, 1.5, -6), Vector3(8, 3, 1), true)
	add_wall(Vector3(0, 1.5, 6), Vector3(8, 3, 1), true)
	var me := spawn(CHAIN, 0, Vector3.ZERO)
	var e := CHAIN.get_slot(2)
	await ticks(2)
	await _grapple(me, Vector3(0, 0, -20))
	await secs(0.6)
	await _grapple(me, Vector3(0, 0, 20))
	await secs(0.8)
	check(me.charges[2] == 0 and me.global_position.z > 4.5, "two grapples back to back (z %.2f)" % me.global_position.z)
	check(me.ready_in(2) > e.cooldown - 2.0, "then a wait for the first charge (%.1f s)" % me.ready_in(2))
	await secs(me.ready_in(2) + 0.1)
	check(me.charges[2] == 1, "charges come back one at a time")
	await secs(e.cooldown)
	check(me.charges[2] == 2, "and the second after another full wait")
	me.set_dead(null)
	me.respawn()
	check(me.charges[2] == 2, "respawn refills charges")


func test_momentum() -> void:
	add_wall(Vector3(0, 1.5, -11), Vector3(8, 3, 1), true)
	var me := spawn(CHAIN, 0, Vector3.ZERO)
	var foe := spawn(DUMMY, 1, Vector3(3, 0, -9))
	await ticks(2)
	var lash := CHAIN.basic_attack
	var h := foe.health
	authority.apply_damage(me, foe, 100.0, lash)
	check(is_equal_approx(h - foe.health, 100.0), "a plain basic hit")
	await _grapple(me, Vector3(0, 0, -20))
	await secs(1.0)
	h = foe.health
	authority.apply_damage(me, foe, 100.0, lash)
	check(is_equal_approx(h - foe.health, 100.0 * (1.0 + CHAIN.passive_value)), "after a long grapple the next hit deals +%d%%" % roundi(CHAIN.passive_value * 100.0))
	h = foe.health
	authority.apply_damage(me, foe, 100.0, lash)
	check(is_equal_approx(h - foe.health, 100.0), "one stored hit only")
	# A short pull (under 4 m) does not count.
	var me2 := spawn(CHAIN, 0, Vector3(20, 0, -8))
	add_wall(Vector3(20, 1.5, -11.5), Vector3(4, 3, 1), true)
	await ticks(2)
	await _grapple(me2, Vector3(20, 0, -20))
	await secs(0.6)
	h = foe.health
	authority.apply_damage(me2, foe, 100.0, lash)
	check(is_equal_approx(h - foe.health, 100.0), "a short pull primes nothing")


func test_weaken() -> void:
	var me := spawn(CHAIN, 0, Vector3.ZERO)
	var foe := spawn(WARDEN, 1, Vector3(0, 0, -2))
	var dummy := spawn(DUMMY, 0, Vector3(0, 0, -4))
	await ticks(2)
	var h := dummy.health
	authority.apply_damage(foe, dummy, 100.0, null)
	var plain := h - dummy.health
	await _cast(me, 4, foe.global_position, CHAIN.get_slot(4).cast_time + 0.1)
	check(foe.weaken_timer > 0.0 and is_equal_approx(foe.weaken_amount, CHAIN.get_slot(4).weaken_amount), "Break the Seal weakens the champion struck")
	check(foe.stun_timer <= 0.0, "and does not stun")
	h = dummy.health
	authority.apply_damage(foe, dummy, 100.0, null)
	check(is_equal_approx(h - dummy.health, plain * (1.0 - CHAIN.get_slot(4).weaken_amount)), "a weakened champion deals 30% less")
	await secs(CHAIN.get_slot(4).weaken_duration + 0.1)
	check(foe.weaken_timer <= 0.0, "it wears off")


func test_covenant_line() -> void:
	var me := spawn(CHAIN, 0, Vector3.ZERO)
	var far := spawn(DUMMY, 1, Vector3(0.5, 0, -13))
	var side := spawn(DUMMY, 1, Vector3(3.5, 0, -6))
	await ticks(2)
	_level_up(me, Unit.ULT_LEVEL)
	var r := CHAIN.get_slot(3)
	await _cast(me, 3, Vector3(0, 0, -4), r.cast_time + 0.1)
	check(authority.areas.size() == 1 and authority.areas[0].ability == r, "the chain line is drawn")
	check(far.health == DUMMY.max_health, "nothing before the delay")
	await secs(r.area_delay + 0.1)
	check(far.health < DUMMY.max_health and far.root_timer > 0.0, "the far end of the line hits and roots, though the aim was short")
	check(side.health == DUMMY.max_health, "beside the line is safe")
	check(CombatAuthority.in_area(_line_at(me, r), Vector3(0, 0, -7), 0.3), "in_area: inside the strip")
	check(not CombatAuthority.in_area(_line_at(me, r), Vector3(0, 0, 2), 0.3), "in_area: behind the caster is outside")


func _line_at(me: Unit, r: AbilityDef) -> CombatAuthority.SimArea:
	var ar := CombatAuthority.SimArea.new()
	ar.ability = r
	ar.dir = Vector3(0, 0, -1)
	ar.center = me.global_position + ar.dir * r.range * 0.5
	return ar


func test_anchor_marking() -> void:
	var map := LaneMapBuilder.new()
	world.add_child(map)
	var n := GrappleAnchors.mark(map, LaneMapBuilder.BASE_Z + 1.0)
	check(n > 20, "lane and flank walls are anchors (%d)" % n)
	var floor_marked := false
	var base_marked := false
	for body: StaticBody3D in map.find_children("*", "StaticBody3D", true, false):
		if body.collision_layer & Unit.LAYER_ANCHOR:
			if body.global_position.y <= 0.0:
				floor_marked = true
			if absf(body.global_position.z) > LaneMapBuilder.BASE_Z + 1.0:
				base_marked = true
	check(not floor_marked, "the floor is never an anchor")
	check(not base_marked, "base plazas (spawn) are never anchors")
	# From the lane, a lane wall holds.
	var me := spawn(CHAIN, 0, Vector3(0, 0, 20))
	await ticks(2)
	check(me.grapple_endpoint(CHAIN.get_slot(2), Vector3(20, 0, 20)).is_finite(), "a chain to the lane wall holds")
	map.queue_free()


func test_chainbound_snapshot() -> void:
	var u := spawn(CHAIN, 1, Vector3(1, 0, 2))
	await ticks(2)
	u.charges[2] = 1
	u.recharge[2] = 5.25
	u.apply_weaken(0.3, 1.5)
	var snap := SnapshotCodec.decode(SnapshotCodec.encode(1, 0, 1, SnapshotCodec.encode_units([u])))
	var s: Array = snap.units[u.net_id]
	check((s[SnapshotCodec.CHARGES] as PackedInt32Array)[2] == 1, "charges survive the wire")
	check(absf((s[SnapshotCodec.RECHARGE] as PackedFloat32Array)[2] - 5.25) < 0.002, "recharge timer survives")
	check(absf(s[SnapshotCodec.WEAKEN] - 0.3) < 0.005 and absf(s[SnapshotCodec.WEAKEN_TIMER] - 1.5) < 0.002, "weaken survives")
	var v := spawn(CHAIN, 1, Vector3(5, 0, 2))
	await ticks(1)
	SnapshotCodec.apply(v, s)
	check(v.charges[2] == 1 and v.weaken_timer > 1.0, "a client unit takes them")
	var plain := spawn(SCRIBE, 0, Vector3(9, 0, 0))
	await ticks(1)
	var bytes := SnapshotCodec.encode_units([plain])
	check(SnapshotCodec.decode(SnapshotCodec.encode(1, 0, 1, bytes)).units[plain.net_id][SnapshotCodec.CHARGES] == null, "champions without charges send none")

func test_passive_snapshot() -> void:
	var u := spawn(LANTERN, 0, Vector3(1, 0, 2))
	var w := spawn(VEIL, 0, Vector3(3, 0, 2))
	await ticks(2)
	u.passive_stacks = 2.0
	w.refrain_slot = 2
	w.refrain_at = authority.time
	var snap := SnapshotCodec.decode(SnapshotCodec.encode(1, 0, 2, SnapshotCodec.encode_units([u, w])))
	check(snap.units[u.net_id][SnapshotCodec.STACKS] == 2.0, "passive stacks survive the wire")
	check(snap.units[w.net_id][SnapshotCodec.REFRAIN] == 2, "and the half-sung refrain")
	var v := spawn(LANTERN, 0, Vector3(5, 0, 2))
	await ticks(1)
	SnapshotCodec.apply(v, snap.units[u.net_id])
	check(v.passive_stacks == 2.0 and Hud.passive_readout(v) == "Embers 2/3", "a client shows them (%s)" % Hud.passive_readout(v))
	check(Hud.passive_readout(w) == "Refrain: War Song next", "the HUD names the other half (%s)" % Hud.passive_readout(w))
	await secs(CombatAuthority.REFRAIN_TIME + 0.2)
	check(w.refrain_slot == -1, "the refrain lapses")


func test_chainbound_bot_match() -> void:
	var mc := MatchController.new()
	mc.human_slot = false
	mc.lineup_ids = [&"chainbound", &"oathwarden", &"ruinscribe"]
	mc.bot_seed = 5
	var map := LaneMapBuilder.new()
	world.add_child(map)
	GrappleAnchors.mark(map, LaneMapBuilder.BASE_Z + 1.0)
	world.add_child(mc)
	mc.setup(authority, world)
	var grapples := [0]
	authority.grapple_started.connect(func(_c: Unit, _a: AbilityDef) -> void: grapples[0] += 1)
	mc.start()
	await secs(120.0)
	check(mc.champions.any(func(c: Unit) -> bool: return c.def == CHAIN), "Chainbound fields in a bot match")
	check(grapples[0] > 0, "bots use Chain Traverse (%d grapples in 120 s)" % grapples[0])
	for c: Unit in mc.champions:
		check(c.global_position.y > -1.0 and absf(c.global_position.x) < 30.0, "%s stays on the map" % c.def.id)
	map.queue_free()


# --- Phase 5: the full finished-item catalog -------------------------------

func _equip(u: Unit, id: StringName) -> ItemDef:
	var it: ItemDef = Unit.ECONOMY.items[_idx(id) - 1]
	u.items.append(it)
	u.recompute_stats()
	return it


func _hit(src: Unit, dst: Unit, amount: float, a: AbilityDef) -> float:
	var h := dst.health
	authority.apply_damage(src, dst, amount, a)
	return h - dst.health


func test_items_weapon() -> void:
	var u := _shop_champion(THORN, 0.0)
	var foe := spawn(WARDEN, 1, Vector3(0, 0, -3))
	await ticks(2)
	var bow := THORN.basic_attack
	var plain := _hit(u, foe, 50.0, bow)
	var giant := _equip(u, &"giantfall_spear")
	var power := 1.0 + giant.weapon_power / 100.0
	var with_giant := _hit(u, foe, 50.0, bow)
	var extra := minf(foe.max_health * giant.passive_value, 40.0) * 100.0 / (100.0 + foe.armor)
	check(absf(with_giant - plain * power - extra) < 0.6, "Giantfall Spear: a basic hit adds max-health damage (%.1f)" % (with_giant - plain * power))
	check(absf(_hit(u, foe, 50.0, bow) - plain * power) < 0.6, "once a second per target")
	u.items.clear()
	var ranger := _equip(u, &"rangers_covenant")
	_hit(u, foe, 10.0, bow)
	check(is_equal_approx(u.quick_amount, ranger.passive_value), "Ranger's Covenant: a champion hit speeds you up")
	u.items.clear()
	var writ := _equip(u, &"headsmans_writ")
	var base := _hit(u, foe, 50.0, bow)
	_hit(u, foe, 10.0, THORN.get_slot(1))
	var primed := _hit(u, foe, 50.0, bow)
	check(primed - base > writ.passive_value * 0.5, "Headsman's Writ: an ability hit primes the next basic (%.1f more)" % (primed - base))
	check(absf(_hit(u, foe, 50.0, bow) - base) < 0.6, "one primed hit only")
	u.items.clear()
	_equip(u, &"ashen_brand")
	_hit(u, foe, 10.0, bow)
	check(foe.heal_cut_timer > 0.0, "Ashen Brand: weapon damage cuts healing")
	foe.health = 100.0
	authority.heal(foe, 100.0)
	check(is_equal_approx(foe.health, 170.0), "healing is cut by 30%% (%.0f)" % foe.health)
	var other := spawn(DUMMY, 1, Vector3(5, 0, 0))
	await ticks(1)
	other.apply_heal_cut(0.1, 5.0)
	other.apply_heal_cut(0.3, 1.0)
	other.apply_heal_cut(0.2, 1.0)
	check(is_equal_approx(other.heal_cut, 0.3), "healing cuts never add up: the strongest counts")


func test_items_spell() -> void:
	var s := _shop_champion(SCRIBE, 0.0)
	var foe := spawn(WARDEN, 1, Vector3(0, 0, -3))
	await ticks(2)
	var cinder := _equip(s, &"cinder_reliquary")
	_hit(s, foe, 10.0, SCRIBE.get_slot(1))
	check(foe.burn_timer > 0.0 and foe.burn_source == s, "Cinder Reliquary: a spell hit burns")
	var h := foe.health
	await secs(1.0)
	var burned := h - foe.health
	check(burned > 0.0 and burned < cinder.passive_value, "the burn ticks (%.1f in 1 s)" % burned)
	_hit(s, foe, 10.0, SCRIBE.get_slot(1))
	check(is_equal_approx(foe.burn_dps, cinder.passive_value / CombatAuthority.BURN_TIME) and foe.burn_timer <= CombatAuthority.BURN_TIME, "a second burn refreshes, it does not stack")
	s.items.clear()
	foe.burn_timer = 0.0
	var glass := _equip(s, &"witchglass_lens")
	_hit(s, foe, 10.0, SCRIBE.basic_attack)
	check(foe.heal_cut_timer <= 0.0, "Witchglass Lens: basic hits do not cut healing")
	_hit(s, foe, 10.0, SCRIBE.get_slot(2))
	check(is_equal_approx(foe.heal_cut, glass.passive_value), "a spell ability hit does")
	s.items.clear()
	var thread := _equip(s, &"stormthread_spindle")
	var plain := _hit(s, foe, 20.0, SCRIBE.basic_attack)
	authority.release_ability(s, SCRIBE.get_slot(4), s.global_position + Vector3(0, 0, -5))
	var primed := _hit(s, foe, 20.0, SCRIBE.basic_attack)
	check(primed - plain > thread.passive_value * 0.5, "Stormthread Spindle: a cast primes the next basic (%.1f more)" % (primed - plain))


func test_items_defence() -> void:
	var u := _shop_champion(THORN, 0.0)
	var b := spawn(BARROW, 1, Vector3(-3, 0, 0))
	await ticks(2)
	_equip(b, &"spellward_mantle")
	_equip(b, &"bastion_plate")
	authority.apply_damage(u, b, b.max_health * 0.9, THORN.basic_attack)
	var first := b.shield
	check(first > 0.0, "Spellward Mantle and Bastion: a low-health shield")
	b.shield = 0.0
	authority.apply_damage(u, b, 5.0, THORN.basic_attack)
	check(b.shield == 0.0, "owning both never gives a second shield")
	var c := spawn(BARROW, 0, Vector3(8, 0, 0))
	await ticks(1)
	var cairn := _equip(c, &"cairnheart")
	c.health = c.max_health * 0.5
	c.last_champion_hit_at = authority.time
	var h := c.health
	await secs(2.0)
	check(c.health - h < 1.0, "Cairnheart: no recovery right after champion damage")
	await secs(CombatAuthority.CAIRN_QUIET)
	h = c.health
	await secs(1.0)
	check(absf(c.health - h - c.max_health * cairn.passive_value) < 2.0, "then 1.5%% max health a second (%.1f)" % (c.health - h))


func test_items_support() -> void:
	ItemShop.use_adventurer(true)
	var w := spawn(WARDEN, 0, Vector3.ZERO)
	var ally := spawn(SCRIBE, 0, Vector3(3, 0, 0))
	var foe := spawn(THORN, 1, Vector3(0, 0, -3))
	await ticks(2)
	var bulwark := _equip(w, &"pilgrims_bulwark")
	authority.give_shield(w, ally, 50.0, 3.0)
	check(is_equal_approx(w.shield, bulwark.passive_value), "Pilgrim's Bulwark: shielding an ally shields you")
	w.shield = 0.0
	authority.give_shield(w, ally, 50.0, 3.0)
	check(w.shield == 0.0, "on a cooldown")
	w.items.clear()
	var cantor := _equip(w, &"cantors_thread")
	ally.health = 100.0
	authority.heal(ally, 20.0, w)
	check(is_equal_approx(ally.quick_amount, cantor.passive_value), "Cantor's Thread: a healed ally moves faster")
	w.items.clear()
	var harness := _equip(w, &"oathkeepers_harness")
	ally.shield = 0.0
	authority.apply_damage(w, foe, 10.0, WARDEN.get_slot(2))  # Shield Slam stuns
	check(foe.stun_timer > 0.0 and is_equal_approx(ally.shield, harness.passive_value), "Oathkeeper's Harness: a stun shields the nearest ally")


func test_item_catalog() -> void:
	ItemShop.use_adventurer(true)
	var finished := 0
	for it: ItemDef in Unit.ECONOMY.items:
		if it.kind == ItemDef.Kind.FINISHED:
			finished += 1
			check(it.recipe.size() == 2, "%s has a two part recipe" % it.id)
			check(it.passive != ItemDef.Passive.NONE and not it.description.is_empty(), "%s has a described passive" % it.id)
	check(finished == 16, "sixteen finished items (%d)" % finished)
	for def: ChampionDef in MatchController.ROSTER + MatchController.PROTOTYPES:
		for id in def.adventurer_build:
			check(ItemShop.index_of(id) > 0, "%s builds %s, which exists" % [def.id, id])
	await ticks(1)


# --- Phase 6: Stillhand ---------------------------------------------------------

func test_stillhand_data() -> void:
	await _kit_data([STILL])
	check(STILL.get_slot(4).delivery == AbilityDef.Delivery.SELF, "Still Water is a self brace")
	check(MatchController.PROTOTYPES.has(STILL) and not MatchController.ROSTER.has(STILL), "Stillhand is a pick, never drawn at random")


func test_bellbreaker() -> void:
	var me := spawn(STILL, 0, Vector3.ZERO)
	var foe := spawn(SCRIBE, 1, Vector3(0, 0, -2.5))
	await ticks(2)
	aim(foe, me.global_position)
	cmd(foe).buttons = UnitCommand.ability_button(1)  # a slow wind up
	await ticks(2)
	cmd(foe).buttons = 0
	check(foe.is_casting(), "the foe is winding up")
	await _cast(me, 1, foe.global_position, STILL.get_slot(1).cast_time + 0.05)
	check(not foe.is_casting(), "Bellbreaker stops the cast")
	check(foe.health < SCRIBE.max_health, "and hits")
	check(foe.cooldowns[1] <= 0.0 or foe.cast_slot != 1, "the lost cast is not spent")


func test_still_water() -> void:
	var me := spawn(STILL, 0, Vector3.ZERO)
	var front := spawn(SCRIBE, 1, Vector3(0, 0, -3))
	var back := spawn(SCRIBE, 1, Vector3(0, 0, 3))
	await ticks(2)
	var h := me.health
	authority.apply_damage(front, me, 100.0, null)
	var plain := h - me.health
	var water := STILL.get_slot(4)
	await _cast(me, 4, Vector3(0, 0, -5), water.cast_time + 0.05)
	check(me.brace_timer > 0.0, "Still Water braces")
	h = me.health
	authority.apply_damage(back, me, 100.0, null)
	check(is_equal_approx(h - me.health, plain), "a hit from behind is not softened")
	h = me.health
	authority.apply_damage(front, me, 100.0, null)
	check(absf(h - me.health - plain * (1.0 - water.brace_reduction)) < 0.01, "the hit from the front deals %d%% less" % roundi(water.brace_reduction * 100.0))
	h = me.health
	authority.apply_damage(front, me, 100.0, null)
	check(is_equal_approx(h - me.health, plain), "only that one hit")
	me.cooldowns[4] = 0.0
	await _cast(me, 4, Vector3(0, 0, -5), water.brace_duration + 0.2)
	check(me.brace_timer <= 0.0, "an unused brace runs out")


func test_courtyard_push() -> void:
	add_wall(Vector3(0, 1.5, 4.0), Vector3(8, 3, 1))
	var me := spawn(STILL, 0, Vector3.ZERO)
	var foe := spawn(SCRIBE, 1, Vector3(0, 0, -2))
	var walled := spawn(SCRIBE, 1, Vector3(0, 0, 2))
	var far := spawn(SCRIBE, 1, Vector3(0, 0, -9))
	await ticks(2)
	_level_up(me, Unit.ULT_LEVEL)
	var r := STILL.get_slot(3)
	await _cast(me, 3, me.global_position, r.cast_time + r.area_delay + 0.5)
	check(foe.health < SCRIBE.max_health and walled.health < SCRIBE.max_health, "the kick hits all around")
	check(foe.global_position.z < -5.5, "an enemy is knocked away (%.1f m out)" % -foe.global_position.z)
	check(walled.global_position.z < 3.5, "a wall stops the knockback (%.1f)" % walled.global_position.z)
	check(far.health == SCRIBE.max_health, "out of reach is untouched")


func test_measured_breath() -> void:
	var me := spawn(STILL, 0, Vector3.ZERO)
	var foe := spawn(DUMMY, 1, Vector3(0, 0, -2))
	await ticks(2)
	authority.apply_damage(me, foe, 10.0, STILL.basic_attack)
	check(me.shield == 0.0, "a plain hit gives nothing")
	await _cast(me, 2, Vector3(0, 0, -6), 0.4)
	authority.apply_damage(me, foe, 10.0, STILL.basic_attack)
	check(is_equal_approx(me.shield, STILL.passive_value), "after a cast the next hit shields her for %d" % roundi(STILL.passive_value))
	me.shield = 0.0
	me.cooldowns[2] = 0.0
	await _cast(me, 2, Vector3(0, 0, 6), 0.4)
	authority.apply_damage(me, foe, 10.0, STILL.basic_attack)
	check(me.shield == 0.0, "not again within %d s" % roundi(CombatAuthority.MEASURED_COOLDOWN))


func test_brace_snapshot() -> void:
	var u := spawn(STILL, 0, Vector3(1, 0, 2))
	await ticks(2)
	u.apply_brace(0.6, 1.5)
	var s: Array = SnapshotCodec.decode(SnapshotCodec.encode(1, 0, 1, SnapshotCodec.encode_units([u]))).units[u.net_id]
	check(absf(s[SnapshotCodec.BRACE] - 0.6) < 0.005 and absf(s[SnapshotCodec.BRACE_TIMER] - 1.5) < 0.002, "a brace survives the wire")


func test_stillhand_bot_match() -> void:
	var mc := MatchController.new()
	mc.human_slot = false
	mc.lineup_ids = [&"stillhand", &"oathwarden", &"ruinscribe"]
	mc.bot_seed = 5
	var map := LaneMapBuilder.new()
	world.add_child(map)
	world.add_child(mc)
	mc.setup(authority, world)
	var used := {}
	authority.self_cast.connect(func(_c: Unit, a: AbilityDef) -> void: used[a.id] = true)
	authority.unit_damaged.connect(func(_t: Unit, _amt: float, src: Unit) -> void:
		if src and is_instance_valid(src) and src.def == STILL and src.cast_slot >= 0:
			used["cast"] = true)
	mc.start()
	await secs(150.0)
	check(mc.champions.any(func(c: Unit) -> bool: return c.def == STILL), "Stillhand fields in a bot match")
	check(used.has(&"still_water"), "bots brace with Still Water")
	for c: Unit in mc.champions:
		check(c.global_position.y > -1.0 and absf(c.global_position.x) < 30.0, "%s stays on the map" % c.def.id)
	map.queue_free()


# --- Phase 6: Brasswright, Banneret, Rootwarden ----------------------------------

func _summons(of: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in authority.units:
		if u.alive and u.summoner == of:
			out.append(u)
	return out


func test_phase6_data() -> void:
	await _kit_data([BRASS, BANNER, ROOT])
	for d: ChampionDef in [STILL, BRASS, BANNER, ROOT]:
		check(MatchController.PROTOTYPES.has(d), "%s is a pick (never random yet)" % d.id)
		check(not d.hero_name.is_empty() and not d.lore.is_empty(), "%s has lore" % d.id)
	var sentry := BRASS.get_slot(2).summon as ChampionDef
	check(sentry.kind == ChampionDef.Kind.SUMMON and sentry.respawn_time < 0.0 and sentry.move_speed == 0.0, "the sentry is a summon that stays put")


func test_field_sentry() -> void:
	var me := spawn(BRASS, 0, Vector3.ZERO)
	var foe := spawn(SCRIBE, 1, Vector3(0, 0, -12))
	var tower := spawn(TOWER, 1, Vector3(6, 0, -8))
	tower.controller = null
	await ticks(2)
	var cast := BRASS.get_slot(2)
	await _cast(me, 2, Vector3(0, 0, -6), cast.cast_time + 0.05)
	var mine := _summons(me)
	check(mine.size() == 1, "Field Sentry stands")
	if mine.is_empty():
		return
	var s: Unit = mine[0]
	check(s.global_position.distance_to(Vector3(0, 0, -6)) < 0.6, "where it was aimed (%.1f, %.1f)" % [s.global_position.x, s.global_position.z])
	await secs(2.0)
	check(foe.health < SCRIBE.max_health, "it shoots the enemy champion in reach (%.0f)" % (SCRIBE.max_health - foe.health))
	check(tower.health == TOWER.max_health, "never a structure")
	s.life_timer = 0.1
	await secs(0.2)
	check(not s.alive, "it falls when its time runs out")
	await secs(1.5)
	check(not is_instance_valid(s) or not authority.units.has(s), "and is cleared away")


func test_sentry_replaced() -> void:
	var me := spawn(BRASS, 0, Vector3.ZERO)
	await ticks(2)
	var cast := BRASS.get_slot(2)
	await _cast(me, 2, Vector3(0, 0, -5), cast.cast_time + cast.recovery + 0.05)
	me.cooldowns[2] = 0.0
	await _cast(me, 2, Vector3(4, 0, -4), cast.cast_time + 0.05)
	var mine := _summons(me)
	check(mine.size() == 1 and mine[0].global_position.x > 2.0, "a second sentry replaces the first (%d, x %.1f)" % [mine.size(), mine[0].global_position.x if mine.size() > 0 else -99.0])


func test_masterwork_in_place() -> void:
	add_wall(Vector3(0, 1.5, -8), Vector3(8, 3, 1))
	var me := spawn(BRASS, 0, Vector3.ZERO)
	await ticks(2)
	_level_up(me, Unit.ULT_LEVEL)
	var r := BRASS.get_slot(3)
	await _cast(me, 3, Vector3(0, 0, -20), r.cast_time + r.recovery + 0.05)
	var mine := _summons(me)
	check(mine.size() == 1 and mine[0].global_position.z > -7.6, "with no sentry out, one is placed, on this side of a wall (%.1f)" % (mine[0].global_position.z if mine.size() > 0 else 0.0))
	me.cooldowns[3] = 0.0
	me.cooldowns[2] = 0.0
	await _cast(me, 2, Vector3(4, 0, -3), BRASS.get_slot(2).cast_time + BRASS.get_slot(2).recovery + 0.05)
	await _cast(me, 3, Vector3(-6, 0, -6), r.cast_time + 0.05)
	mine = _summons(me)
	check(mine.size() == 1 and mine[0].def == r.summon and mine[0].global_position.distance_to(Vector3(4, 0, -3)) < 0.6, "Masterwork Battery overcharges the sentry where it stands")


func test_sentry_kill_credit() -> void:
	var me := spawn(BRASS, 0, Vector3.ZERO)
	var foe := spawn(SCRIBE, 1, Vector3(0, 0, -10))
	await ticks(2)
	await _cast(me, 2, Vector3(0, 0, -5), BRASS.get_slot(2).cast_time + 0.05)
	var killer := [null]
	authority.unit_died.connect(func(t: Unit, k: Unit) -> void:
		if t == foe:
			killer[0] = k)
	foe.health = 5.0
	await secs(2.0)
	check(not foe.alive and killer[0] == me, "a sentry kill counts for the Brasswright")


func test_breach_falloff() -> void:
	var me := spawn(BRASS, 0, Vector3.ZERO)
	var first := spawn(DUMMY, 1, Vector3(0, 0, -5))
	var second := spawn(DUMMY, 1, Vector3(0, 0, -9))
	await ticks(2)
	var q := BRASS.get_slot(1)
	await _cast(me, 1, Vector3(0, 0, -15), q.cast_time + 0.5)
	check(is_equal_approx(DUMMY.max_health - first.health, q.damage), "Breach Bolt: the first takes it all (%.0f)" % (DUMMY.max_health - first.health))
	check(is_equal_approx(DUMMY.max_health - second.health, q.damage * q.pierce_falloff), "the next takes %d%% (%.0f)" % [roundi(q.pierce_falloff * 100.0), DUMMY.max_health - second.health])


func test_calibration() -> void:
	var me := spawn(BRASS, 0, Vector3.ZERO)
	var foe := spawn(DUMMY, 1, Vector3(0, 0, -6))
	await ticks(2)
	for i in 6:
		authority.apply_damage(me, foe, 1.0, BRASS.basic_attack)
	check(is_equal_approx(me.passive_stacks, CombatAuthority.CALIBRATE_MAX), "Calibration: basic hits build up to %d" % roundi(CombatAuthority.CALIBRATE_MAX))
	var q := BRASS.get_slot(1)
	var h := foe.health
	await _cast(me, 1, foe.global_position, q.cast_time + 0.4)
	check(absf(h - foe.health - q.damage * (1.0 + 4.0 * BRASS.passive_value)) < 0.5, "Breach Bolt spends it: +%d%% (%.0f)" % [roundi(400.0 * BRASS.passive_value), h - foe.health])
	check(me.passive_stacks == 0.0, "and it starts over")
	me.cooldowns[1] = 0.0
	h = foe.health
	await _cast(me, 1, foe.global_position, q.cast_time + 0.4)
	check(is_equal_approx(h - foe.health, q.damage), "a bolt with no calibration is plain")


func test_emergency_vent() -> void:
	var me := spawn(BRASS, 0, Vector3.ZERO)
	var foe := spawn(SCRIBE, 1, Vector3(0, 0, -2.5))
	await ticks(2)
	var vent := BRASS.get_slot(4)
	await _cast(me, 4, foe.global_position, vent.cast_time + 0.05)
	check(is_equal_approx(foe.slow_amount, vent.slow_amount), "Emergency Vent slows the chaser")
	check(is_equal_approx(me.quick_amount, vent.self_quick), "and speeds you up")


func test_rally_standard() -> void:
	var me := spawn(BANNER, 0, Vector3.ZERO)
	var ally := spawn(SCRIBE, 0, Vector3(3, 0, -4))
	var far := spawn(SCRIBE, 0, Vector3(20, 0, 0))
	var foe := spawn(SCRIBE, 1, Vector3(0, 0, -8))
	await ticks(2)
	await _cast(me, 2, Vector3(0, 0, -4), BANNER.get_slot(2).cast_time + 0.1)
	var mine := _summons(me)
	check(mine.size() == 1, "Rally Standard stands")
	await ticks(3)
	var pole := mine[0].def
	check(is_equal_approx(ally.quick_amount, pole.passive_value), "allies near it move %d%% faster" % roundi(pole.passive_value * 100.0))
	check(far.quick_amount == 0.0, "not far away")
	check(foe.quick_amount == 0.0, "never enemies")
	authority.apply_damage(foe, mine[0], 9999.0, null)
	check(not mine[0].alive, "enemies can break it")


func test_ordered_retreat() -> void:
	var me := spawn(BANNER, 0, Vector3.ZERO)
	var hurt := spawn(SCRIBE, 0, Vector3(3, 0, 0))
	var fine := spawn(SCRIBE, 0, Vector3(-3, 0, 0))
	await ticks(2)
	hurt.health = 200.0
	var f := BANNER.get_slot(4)
	await _cast(me, 4, Vector3(0, 0, -5), f.cast_time + 0.05)
	check(is_equal_approx(me.shield, f.shield_amount), "Ordered Retreat shields the Banneret")
	check(is_equal_approx(hurt.shield, f.shield_amount) and fine.shield == 0.0, "and the most hurt ally near")


func test_break_their_line() -> void:
	var me := spawn(BANNER, 0, Vector3.ZERO)
	var first := spawn(SCRIBE, 1, Vector3(0, 0, -5))
	var behind := spawn(SCRIBE, 1, Vector3(0, 0, -8))
	await ticks(2)
	_level_up(me, Unit.ULT_LEVEL)
	aim(me, Vector3(0, 0, -20))
	var r := BANNER.get_slot(3)
	await _cast(me, 3, Vector3(0, 0, -20), r.cast_time + r.dash_duration + 0.4)
	check(first.health < SCRIBE.max_health, "the charge hits the first champion")
	check(me.global_position.z > -5.5, "and stops there (%.1f)" % me.global_position.z)
	check(first.global_position.z < -7.0, "driving it back (%.1f)" % first.global_position.z)
	check(behind.health == SCRIBE.max_health or behind.health > SCRIBE.max_health - 1.0, "the one behind is not run through")


func test_hold_formation() -> void:
	var me := spawn(BANNER, 0, Vector3.ZERO)
	var foe := spawn(DUMMY, 1, Vector3(0, 0, -2))
	var hitter := spawn(SCRIBE, 1, Vector3(0, 0, -6))
	await ticks(2)
	authority.apply_damage(me, foe, 1.0, BANNER.basic_attack)
	check(me.passive_stacks == 0.0, "alone, a hit builds nothing")
	var h := me.health
	authority.apply_damage(hitter, me, 100.0, null)
	var plain := h - me.health
	var ally := spawn(SCRIBE, 0, Vector3(3, 0, 0))
	await ticks(2)
	for i in 4:
		authority.apply_damage(me, foe, 1.0, BANNER.basic_attack)
	check(is_equal_approx(me.passive_stacks, CombatAuthority.FORMATION_MAX), "Hold Formation: beside an ally, up to %d" % roundi(CombatAuthority.FORMATION_MAX))
	h = me.health
	authority.apply_damage(hitter, me, 100.0, null)
	check(absf(h - me.health - plain * (1.0 - 3.0 * BANNER.passive_value)) < 0.05, "%d%% less damage taken" % roundi(300.0 * BANNER.passive_value))
	await secs(CombatAuthority.FORMATION_TIME + 0.2)
	check(me.passive_stacks == 0.0, "it fades when the line breaks")
	ally.queue_free()


func test_grasping_root() -> void:
	var me := spawn(ROOT, 0, Vector3.ZERO)
	var on := spawn(SCRIBE, 1, Vector3(0, 0, -7))
	var off := spawn(SCRIBE, 1, Vector3(3, 0, -7))
	await ticks(2)
	var q := ROOT.get_slot(1)
	await _cast(me, 1, Vector3(0, 0, -9), q.cast_time + q.area_delay + 0.1)
	check(on.root_timer > 0.0 and on.health < SCRIBE.max_health, "Grasping Root roots an enemy on the line")
	check(off.root_timer <= 0.0 and off.health == SCRIBE.max_health, "and not one beside it")


func test_elder_shape() -> void:
	var me := spawn(ROOT, 0, Vector3.ZERO)
	await ticks(2)
	_level_up(me, Unit.ULT_LEVEL)
	me.health = me.max_health * 0.5
	var base := me.max_health
	var r := ROOT.get_slot(3)
	await _cast(me, 3, Vector3(0, 0, -5), r.cast_time + 0.05)
	check(is_equal_approx(me.max_health, base + r.transform_health), "Elder Shape: %d more max health" % roundi(r.transform_health))
	check(absf(me.health / me.max_health - 0.5) < 0.01, "health keeps its share")
	check(me.get_slot(0) == r.transform_basic and me.get_slot(1) != null, "the paw replaces the staff, Q stays")
	await secs(r.transform_duration)
	check(is_equal_approx(me.max_health, base) and me.get_slot(0) == ROOT.basic_attack, "it ends after %d s" % roundi(r.transform_duration))
	check(absf(me.health / me.max_health - 0.5) < 0.02, "still the same share")


func test_deep_roots() -> void:
	var me := spawn(ROOT, 0, Vector3.ZERO)
	await ticks(2)
	check(me.shield == 0.0, "no grove, no bark")
	await _cast(me, 2, me.global_position, ROOT.get_slot(2).cast_time + 0.2)
	check(is_equal_approx(me.shield, ROOT.passive_value), "Deep Roots: in her grove she gains a %d shield" % roundi(ROOT.passive_value))


func test_barkskin() -> void:
	var me := spawn(ROOT, 0, Vector3.ZERO)
	var ally := spawn(SCRIBE, 0, Vector3(4, 0, 0))
	await ticks(2)
	var f := ROOT.get_slot(4)
	ally.health = 150.0
	await _cast(me, 4, Vector3(0, 0, -5), f.cast_time + f.recovery + 0.05)
	check(is_equal_approx(ally.shield, f.shield_amount) and me.shield == 0.0, "Barkskin goes to the most hurt ally")
	me.cooldowns[4] = 0.0
	ally.health = ally.max_health
	ally.shield = 0.0
	me.health = 200.0
	await _cast(me, 4, Vector3(0, 0, -5), f.cast_time + 0.05)
	check(is_equal_approx(me.shield, f.shield_amount), "or to her, when she is the one hurt (%.0f, ally %.0f, cd %.1f)" % [me.shield, ally.shield, me.cooldowns[4]])


func test_phase6_bot_match() -> void:
	var mc := MatchController.new()
	mc.human_slot = false
	mc.lineup_ids = [&"brasswright", &"banneret", &"rootwarden"]
	mc.bot_seed = 7
	var map := LaneMapBuilder.new()
	world.add_child(map)
	world.add_child(mc)
	mc.setup(authority, world)
	var seen := {}
	authority.summoned.connect(func(u: Unit, _c: Unit) -> void: seen[u.def.id] = true)
	authority.self_cast.connect(func(_c: Unit, a: AbilityDef) -> void: seen[a.id] = true)
	mc.start()
	await secs(180.0)
	check(seen.has(&"field_sentry"), "bots set down sentries")
	check(seen.has(&"rally_banner"), "bots plant the standard")
	check(seen.has(&"barkskin") or seen.has(&"ordered_retreat"), "bots shield")
	for c: Unit in mc.champions:
		check(c.global_position.y > -1.0 and absf(c.global_position.x) < 30.0, "%s stays on the map" % c.def.id)
	var stray := authority.units.filter(func(u: Unit) -> bool: return u.def.kind == ChampionDef.Kind.SUMMON and u.alive and u.life_timer > 20.0)
	check(stray.is_empty(), "no summon outlives its time")
	map.queue_free()


func test_three_lane_match() -> void:
	var mc := MatchController.new()
	mc.human_slot = false
	mc.three_lane = true
	mc.lineup_ids = [&"ruinscribe", &"oathwarden", &"thornwright"]
	mc.bot_seed = 3
	var map := ThreeLaneBuilder.new()
	world.add_child(map)
	world.add_child(mc)
	mc.setup(authority, world)
	mc.start()
	check(mc.lane_towers[0].size() == 3 and mc.lane_towers[1].size() == 3, "a tower in every lane for both teams")
	check(mc.cores[0].is_protected(), "the core starts protected")
	await secs(45.0)
	for lx: float in ThreeLaneBuilder.LANES:
		var n := authority.units.filter(func(u: Unit) -> bool: return u.alive and u.def.kind == ChampionDef.Kind.MINION and absf(u.global_position.x - lx) < 8.0).size()
		check(n >= 4, "minions march in the lane at x %d (%d)" % [roundi(lx), n])
	for c: Unit in mc.champions:
		var lx := mc.info.lane_x(c)
		check(absf(c.global_position.x - lx) < 9.0 and absf(c.global_position.z) < ThreeLaneBuilder.BASE_Z, "%s plays its lane (x %.0f, z %.0f, lane %d)" % [c.name, c.global_position.x, c.global_position.z, roundi(lx)])
	mc.lane_towers[0][0].set_dead(null)
	check(mc.cores[0].is_protected(), "one tower down: the core still holds")
	mc.lane_towers[0][1].set_dead(null)
	check(not mc.cores[0].is_protected(), "two down: the core is open")
	map.queue_free()

