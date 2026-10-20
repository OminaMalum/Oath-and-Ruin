class_name ChampionDef
extends Resource
## Base stats and kit for a champion (or any unit that uses the same rules).

enum Look { SPELLCASTER, TRAINING_DUMMY, MINION_MELEE, MINION_CASTER, TOWER, CORE, SHRINEBEARER, BREAKER }
## What rules apply: who can be targeted by whom, who respawns, who moves.
enum Kind { CHAMPION, MINION, STRUCTURE, DUMMY, NEUTRAL }

@export var id: StringName
@export var display_name: String = ""
@export var role: String = ""
@export var look: Look = Look.SPELLCASTER
@export var kind: Kind = Kind.CHAMPION

@export_group("Stats")
@export var max_health: float = 600.0
@export var move_speed: float = 6.0
@export var radius: float = 0.45
@export var height: float = 1.8
## Negative: never respawns (minions are removed, structures stay as ruins).
@export var respawn_time: float = 5.0
## Health per second while standing in the own team's fountain.
@export var fountain_heal: float = 0.0

@export_group("Kit")
@export var basic_attack: AbilityDef
## Regular abilities in slot order (slot 1 = Q).
@export var abilities: Array[AbilityDef] = []

@export_group("Presentation")
@export var primary_color: Color = Color(0.45, 0.32, 0.22)
@export var accent_color: Color = Color(0.25, 0.75, 0.72)


## Slot 0 is the basic attack, 1.. are abilities.
func get_slot(slot: int) -> AbilityDef:
	if slot == 0:
		return basic_attack
	var i := slot - 1
	if i >= 0 and i < abilities.size():
		return abilities[i]
	return null


func slot_count() -> int:
	return 1 + abilities.size()
