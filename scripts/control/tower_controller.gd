class_name TowerController
extends UnitController
## Tower targeting, in the order players learn it:
## 1. an enemy champion who hit an allied champion near the tower in the last 2 s
## 2. otherwise keep the current target while it stays valid
## 3. otherwise the nearest enemy minion, then the nearest enemy champion

const AGGRO_MEMORY := 2.0

var authority: CombatAuthority
var current: Unit


func _init(a: CombatAuthority) -> void:
	authority = a


func _in_range(tower: Unit, u: Unit) -> bool:
	return u != null and is_instance_valid(u) and u.alive and authority.are_enemies(tower, u) \
		and flat_distance(tower.global_position, u.global_position) <= tower.def.basic_attack.range + u.def.radius


func get_command(unit: Unit) -> UnitCommand:
	var c := UnitCommand.new()
	c.aim_yaw = unit.aim_yaw
	var r := unit.def.basic_attack.range
	# 1. Defend allied champions.
	for ally in authority.units:
		if ally.alive and ally.team == unit.team and ally.def.kind == ChampionDef.Kind.CHAMPION \
				and flat_distance(unit.global_position, ally.global_position) <= r \
				and authority.time - ally.last_attacked_at <= AGGRO_MEMORY \
				and ally.last_attacker and is_instance_valid(ally.last_attacker) \
				and ally.last_attacker.def.kind == ChampionDef.Kind.CHAMPION and _in_range(unit, ally.last_attacker):
			current = ally.last_attacker
	# 2. Keep a valid target.
	if not _in_range(unit, current):
		current = null
		var best := INF
		for want in [ChampionDef.Kind.MINION, ChampionDef.Kind.CHAMPION]:
			for u in authority.units:
				if u.def.kind == want and _in_range(unit, u):
					var d := flat_distance(unit.global_position, u.global_position)
					if d < best:
						best = d
						current = u
			if current:
				break
	if current:
		c.target_id = current.net_id
		c.aim_point = current.global_position
		c.buttons = UnitCommand.BTN_ATTACK
	return c
