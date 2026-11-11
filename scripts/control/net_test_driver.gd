class_name NetTestDriver
extends UnitController
## Drives a networked client in automated tests. Uses the client's
## replicated view of the world, like a player would.
##   attack: approach the nearest enemy champion and fire at it
##   strafe: walk side to side, never attack
##   idle:   do nothing
##   cheat:  send impossible input (huge move vector, far aim, junk buttons)

var authority: CombatAuthority
var mode: String
var _t: float = 0.0


func _init(a: CombatAuthority, m: String) -> void:
	authority = a
	mode = m


func get_command(unit: Unit) -> UnitCommand:
	_t += 1.0 / Engine.physics_ticks_per_second
	var c := UnitCommand.new()
	c.aim_yaw = unit.aim_yaw
	c.aim_point = unit.global_position + unit.forward() * 8.0
	match mode:
		"strafe":
			c.move = Vector2(1.0 if fmod(_t, 4.0) < 2.0 else -1.0, 0.0)
		"cheat":
			c.move = Vector2(50.0, 50.0)
			c.aim_point = Vector3(5000, 0, -5000)
			c.buttons = 0xFFFF
		"attack":
			var target: Unit = null
			var best := INF
			for u in authority.units:
				if u.alive and u.team != unit.team and u.def.look == ChampionDef.Look.SPELLCASTER:
					var d := unit.global_position.distance_to(u.global_position)
					if d < best:
						best = d
						target = u
			if target:
				var to := target.global_position - unit.global_position
				c.aim_yaw = atan2(-to.x, -to.z)
				c.aim_point = target.global_position
				c.move = Vector2(0, 1) if best > 10.0 else Vector2.ZERO
				if best < 16.0:
					c.buttons = UnitCommand.BTN_ATTACK
				if best < 13.0 and unit.cooldowns.size() > 1 and unit.cooldowns[1] <= 0.0:
					c.buttons |= UnitCommand.BTN_ABILITY_1
	return c
