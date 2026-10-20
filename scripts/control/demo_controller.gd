class_name DemoController
extends UnitController
## Drives a champion for captures and soak runs: strafes, aims at the
## nearest visible enemy, holds the basic attack in range and uses the
## ability when it is ready. Same command path as a player.

var authority: CombatAuthority
var sight_range: float = 25.0
var _t: float = 0.0


func _init(a: CombatAuthority) -> void:
	authority = a


func get_command(unit: Unit) -> UnitCommand:
	_t += 1.0 / Engine.physics_ticks_per_second
	var c := UnitCommand.new()
	c.aim_yaw = unit.aim_yaw
	c.aim_point = unit.global_position + unit.forward() * 8.0
	var target: Unit = null
	var best := sight_range
	for u in authority.units:
		if u.alive and authority.are_enemies(unit, u):
			var d := unit.global_position.distance_to(u.global_position)
			if d < best:
				best = d
				target = u
	if target == null:
		return c
	var to := target.global_position - unit.global_position
	c.aim_yaw = atan2(-to.x, -to.z)
	c.aim_point = target.global_position
	c.move = Vector2(sin(_t * 1.3), 0.25 if best > 12.0 else -0.1)
	if best <= unit.def.basic_attack.range - 1.0:
		c.buttons |= UnitCommand.BTN_ATTACK
	if unit.def.slot_count() > 1 and unit.cooldowns[1] <= 0.0 and best <= unit.get_slot(1).range:
		c.buttons |= UnitCommand.BTN_ABILITY_1
	return c
