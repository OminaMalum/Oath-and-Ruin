class_name SummonController
extends UnitController
## A placed summon that stands where it was put (a sentry, a banner).
## Targets, in order: the enemy champion its owner is fighting, then the
## nearest enemy champion, then the nearest minion or summon. Never
## structures: sentries guard a fight, they do not siege.
## A summon whose basic attack deals no damage (a banner) only stands.

var authority: CombatAuthority
var current: Unit


func _init(a: CombatAuthority) -> void:
	authority = a


func _in_range(unit: Unit, u: Unit) -> bool:
	return u != null and is_instance_valid(u) and u.alive and authority.are_enemies(unit, u) \
		and u.def.kind != ChampionDef.Kind.STRUCTURE and u.def.kind != ChampionDef.Kind.DUMMY \
		and flat_distance(unit.global_position, u.global_position) <= unit.def.basic_attack.range + u.def.radius


func get_command(unit: Unit) -> UnitCommand:
	var c := UnitCommand.new()
	c.aim_yaw = unit.aim_yaw
	var a := unit.def.basic_attack
	if a == null or a.damage <= 0.0:
		return c
	# 1. The champion the owner is trading with (it hit the owner, or the owner hit it).
	var owner := unit.summoner
	if owner and is_instance_valid(owner) and owner.alive:
		var foe := owner.last_attacker
		if foe and is_instance_valid(foe) and foe.def.kind == ChampionDef.Kind.CHAMPION \
				and authority.time - owner.last_attacked_at <= 2.0 and _in_range(unit, foe):
			current = foe
	# 2. Keep a valid target, else the nearest champion, then minion or summon.
	if not _in_range(unit, current):
		current = null
		var best := INF
		for want in [[ChampionDef.Kind.CHAMPION], [ChampionDef.Kind.MINION, ChampionDef.Kind.SUMMON, ChampionDef.Kind.NEUTRAL]]:
			for u in authority.units:
				if u.def.kind in want and _in_range(unit, u):
					var d := flat_distance(unit.global_position, u.global_position)
					if d < best:
						best = d
						current = u
			if current:
				break
	if current:
		c.aim_yaw = yaw_towards(unit.global_position, current.global_position)
		c.target_id = current.net_id
		c.aim_point = current.global_position
		c.buttons = UnitCommand.BTN_ATTACK
	return c
