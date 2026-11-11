class_name MinionController
extends UnitController
## Minions walk their lane and fight the nearest enemy they can see:
## minions first, then structures, then champions. Siege units (Breakers and
## the claimed Shrinebearer) ignore everything but structures they can hurt,
## so defenders have to come and stop them.

var authority: CombatAuthority
var path: PackedVector3Array
var sight: float = 9.0
var structures_only: bool = false
var _idx: int = 0


func _init(a: CombatAuthority, lane_path: PackedVector3Array) -> void:
	authority = a
	path = lane_path


func _priority(u: Unit) -> int:
	match u.def.kind:
		ChampionDef.Kind.MINION, ChampionDef.Kind.SUMMON:
			return 0
		ChampionDef.Kind.STRUCTURE:
			return 1
		_:
			return 2


func get_command(unit: Unit) -> UnitCommand:
	var c := UnitCommand.new()
	c.aim_yaw = unit.aim_yaw
	var pos := unit.global_position
	var target: Unit = null
	var best_p := 99
	var best_d := INF
	for u in authority.units:
		if not u.alive or not authority.are_enemies(unit, u) or u.def.kind == ChampionDef.Kind.DUMMY:
			continue
		if structures_only and (u.def.kind != ChampionDef.Kind.STRUCTURE or u.is_protected()):
			continue
		var d := flat_distance(pos, u.global_position) - u.def.radius
		if d > sight:
			continue
		var p := _priority(u)
		if p < best_p or (p == best_p and d < best_d):
			best_p = p
			best_d = d
			target = u
	var dir := Vector3.ZERO
	if target:
		c.aim_yaw = yaw_towards(pos, target.global_position)
		c.aim_point = target.global_position
		c.target_id = target.net_id
		if best_d <= unit.def.basic_attack.range - 0.4:
			c.buttons = UnitCommand.BTN_ATTACK
		else:
			dir = (target.global_position - pos).normalized()
	else:
		while _idx < path.size() - 1 and flat_distance(pos, path[_idx]) < 2.0:
			_idx += 1
		dir = (path[_idx] - pos).normalized()
		c.aim_yaw = yaw_towards(pos, path[_idx])
		c.aim_point = path[_idx]
	if dir != Vector3.ZERO:
		# Keep a little space from friendly minions so a wave reads as a group.
		for u in authority.units:
			if u != unit and u.alive and u.team == unit.team and u.def.kind == ChampionDef.Kind.MINION:
				var away := pos - u.global_position
				away.y = 0.0
				var d := away.length()
				if d < 1.2 and d > 0.01:
					dir += away.normalized() * (1.2 - d)
		c.move = world_to_move(dir.normalized(), c.aim_yaw)
	return c
