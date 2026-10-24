class_name ChampionDef
extends Resource
## Base stats and kit for a champion (or any unit that uses the same rules).

enum Look { SPELLCASTER, TRAINING_DUMMY, MINION_MELEE, MINION_CASTER, TOWER, CORE, SHRINEBEARER, BREAKER, WARDEN, SKIRMISHER, CLERIC, RANGER, WARLOCK, BARBARIAN, BARD, EVOKER }
## What rules apply: who can be targeted by whom, who respawns, who moves.
enum Kind { CHAMPION, MINION, STRUCTURE, DUMMY, NEUTRAL }
## Passive rules, resolved by the CombatAuthority. INSCRIBE: every third basic
## attack hit on the same target deals passive_value more (0.5 = +50%).
## RESOLVE: below half health this unit takes passive_value less damage.
## EMBER: a champion kill resets slot 1 and heals passive_value of max health.
## LANTERN: allied champions within passive_range (and this one) regain
## passive_value health per second. LONGSHOT: basic attacks deal passive_value
## more to targets beyond passive_range. TITHE: passive_value more damage to
## enemies that are rooted, slowed or stunned. BARROWBLOOD: below half health
## this unit regains passive_value health per second. ENCORE: allied champions
## within passive_range (and this one) move passive_value faster. STORMEYE:
## ground area bursts deal passive_value more to targets near their centre.
## MARGINALIA: a slot 1 hit inscribes a champion; a slot 2 hit on an
## inscribed one wipes the mark and shields this unit for passive_value.
## STAND_BEHIND: after a Q or E cast, the next basic hit on a champion shields
## the most hurt allied champion within passive_range for passive_value.
## QUARRY: basic hits on one champion stack marks (up to 3); the next slot 1
## hit on it spends them for passive_value more damage per mark.
## MOMENTUM: a grapple that carries the unit far enough primes the next basic
## hit on a champion (within a short time) for passive_value more damage.
## SEAM: a hit on a champion from behind (or one slot 2 primed) deals
## passive_value more, once per SEAM_COOLDOWN for each target.
## FLAME: healing another champion in a fight stores an ember (once per cast,
## up to 3); the next slot 1 cast shields allies near it for passive_value each.
## FURY: champion fighting fills fury (0 to 100, fades out of combat); at full
## fury the next slot 1 cast heals the unit for passive_value of max health.
## REFRAIN: slot 1 then slot 2 (or 2 then 1) within REFRAIN_TIME empowers the
## second cast (see CombatAuthority.empowered).
## RESIDUAL: slot 4 or ultimate hits on champions store charges (once per cast,
## up to 2); the next slot 1 cast spends them for passive_value more damage each.
enum Passive { NONE, INSCRIBE, RESOLVE, EMBER, LANTERN, LONGSHOT, TITHE, BARROWBLOOD, ENCORE, STORMEYE,
	MARGINALIA, STAND_BEHIND, QUARRY, MOMENTUM, SEAM, FLAME, FURY, REFRAIN, RESIDUAL }

@export var id: StringName
@export var display_name: String = ""
@export var role: String = ""
@export_group("Lore")
## The person behind the champion name, e.g. "Ilyra Voss".
@export var hero_name: String = ""
@export var title: String = ""
## Ancestry and class, e.g. "Human wizard".
@export var ancestry: String = ""
## Two or three short sentences for the menu.
@export_multiline var lore: String = ""
@export_group("")
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
@export var passive: Passive = Passive.NONE
@export var passive_name: String = ""
@export_multiline var passive_description: String = ""
@export var passive_value: float = 0.0
## Distance the passive works over (LANTERN aura, LONGSHOT threshold), metres.
@export var passive_range: float = 0.0
## Item ids in the order bots buy them (see data/economy.tres).
@export var item_build: Array[StringName] = []
## Bots' buy order with the adventurer catalog (finished items are built
## from their components on the way).
@export var adventurer_build: Array[StringName] = []
## Which item power the champion's abilities scale with (and so which
## defence reduces them). An ability can override it (AbilityDef.scaling).
enum Power { WEAPON, SPELL }
@export var power: Power = Power.SPELL

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
