class_name NeutralController
extends UnitController
## The wild Shrinebearer: stays home, slams the nearest champion within its
## leash. It never chases and never leaves the camp.

const LEASH := 10.0

var authority: CombatAuthority


func _init(a: CombatAuthority) -> void:
	authority = a


func get_command(unit: Unit) -> UnitCommand:
	var c := UnitCommand.new()
	c.aim_yaw = unit.aim_yaw
	var best := LEASH
	for u in authority.units:
		if u.alive and u.def.kind == ChampionDef.Kind.CHAMPION:
			var d := flat_distance(unit.global_position, u.global_position)
			if d < best:
				best = d
				c.aim_point = u.global_position
				c.aim_yaw = yaw_towards(unit.global_position, u.global_position)
				c.buttons = UnitCommand.BTN_ATTACK
	return c
