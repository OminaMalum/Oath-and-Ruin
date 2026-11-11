class_name SummonController
extends UnitController
## A summon. Placed ones (a sentry, a banner) stand where they were put;
## walking ones (Willing Dead) keep near their owner and close in to strike.
## Targets, in order: the enemy champion its owner is fighting, then the
## nearest enemy champion, then the nearest minion or summon. Never
## structures: summons guard a fight, they do not siege.
## A summon whose basic attack deals no damage (a banner) only stands.

## A walking summon looks this far for a target, never strays further than
## LEASH from its owner, and trails FOLLOW behind it when there is no fight.
const SIGHT := 8.0
const LEASH := 12.0
const FOLLOW := 2.5

var authority: CombatAuthority
var current: Unit


func _init(a: CombatAuthority) -> void:
	authority = a


func _valid(unit: Unit, u: Unit, reach: float) -> bool:
	if u == null or not is_instance_valid(u) or not u.alive or not authority.are_enemies(unit, u) \
			or u.def.kind == ChampionDef.Kind.STRUCTURE or u.def.kind == ChampionDef.Kind.DUMMY:
		return false
	if flat_distance(unit.global_position, u.global_position) > reach + u.def.radius:
		return false
	var owner := unit.summoner
	return owner == null or not is_instance_valid(owner) or unit.def.move_speed <= 0.0 \
			or flat_distance(owner.global_position, u.global_position) <= LEASH


func get_command(unit: Unit) -> UnitCommand:
	var c := UnitCommand.new()
	c.aim_yaw = unit.aim_yaw
	var a := unit.def.basic_attack
	if a == null or a.damage <= 0.0:
		return c
	var mobile := unit.def.move_speed > 0.0
	var reach := SIGHT if mobile else a.range
	var owner := unit.summoner
	var has_owner := owner != null and is_instance_valid(owner) and owner.alive
	# 1. The champion the owner is trading with (it hit the owner, or the owner hit it).
	if has_owner:
		var foe := owner.last_attacker
		if foe and is_instance_valid(foe) and foe.def.kind == ChampionDef.Kind.CHAMPION \
				and authority.time - owner.last_attacked_at <= 2.0 and _valid(unit, foe, reach):
			current = foe
	# 2. Keep a valid target, else the nearest champion, then minion or summon.
	if not _valid(unit, current, reach):
		current = null
		var best := INF
		for want in [[ChampionDef.Kind.CHAMPION], [ChampionDef.Kind.MINION, ChampionDef.Kind.SUMMON, ChampionDef.Kind.NEUTRAL]]:
			for u in authority.units:
				if u.def.kind in want and _valid(unit, u, reach):
					var d := flat_distance(unit.global_position, u.global_position)
					if d < best:
						best = d
						current = u
			if current:
				break
	var pos := unit.global_position
	if current:
		c.aim_yaw = yaw_towards(pos, current.global_position)
		c.target_id = current.net_id
		c.aim_point = current.global_position
		if flat_distance(pos, current.global_position) <= a.range + current.def.radius - 0.3:
			c.buttons = UnitCommand.BTN_ATTACK
		elif mobile:
			c.move = world_to_move((current.global_position - pos).normalized(), c.aim_yaw)
	elif mobile and has_owner and flat_distance(pos, owner.global_position) > FOLLOW:
		var spot := owner.global_position - owner.forward() * FOLLOW * 0.6
		c.aim_yaw = yaw_towards(pos, spot)
		c.aim_point = spot
		c.move = world_to_move((spot - pos).normalized(), c.aim_yaw)
	return c
