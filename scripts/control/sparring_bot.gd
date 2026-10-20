class_name SparringBot
extends UnitController
## The simplest bot: stand ground, face the nearest visible enemy and use the
## basic attack only when that enemy is inside its range. It obeys the same
## cooldowns and windups because it only issues commands.

var authority: CombatAuthority
var enabled: bool = true
## The bot only "sees" enemies this close (no map-wide knowledge).
var sight_range: float = 20.0


func _init(a: CombatAuthority) -> void:
	authority = a


func get_command(unit: Unit) -> UnitCommand:
	var c := UnitCommand.new()
	c.aim_yaw = unit.aim_yaw
	c.aim_point = unit.global_position + unit.forward() * 5.0
	if not enabled:
		return c
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
	var basic := unit.def.basic_attack
	if basic and best <= basic.range - 0.5:
		c.buttons |= UnitCommand.BTN_ATTACK
	return c
