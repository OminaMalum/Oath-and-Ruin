class_name ItemDef
extends Resource
## One shop item, bought with gold at the own fountain (or while dead).
## Bonuses stack by adding; the unit recomputes its stats on every change.
## Adventurer items (kind other than CLASSIC) also have recipes: a finished
## item or boots uses the owned components in its recipe, so the price paid
## is the total minus those components.

enum Kind {CLASSIC, COMPONENT, STARTER, BOOTS, FINISHED}
## Item passives the combat authority knows. Numbers live in the fields below.
enum Passive {NONE, DUELIST, CODEX, BASTION, LANTERN, GIANTFALL, RANGER, WRIT, ASHEN, CINDER, WITCHGLASS,
	STORMTHREAD, SPELLWARD, CAIRNHEART, BULWARK, CANTOR, HARNESS}

@export var id: StringName
@export var display_name: String = ""
## One word for tight spots (the scoreboard).
@export var short_name: String = ""
## One plain line for the shop panel.
@export var description: String = ""
## Total price, components included.
@export var cost: int = 600
@export var kind: Kind = Kind.CLASSIC
## Components this item is built from (duplicates allowed: two of the same).
@export var recipe: Array[Resource] = []
@export_group("Bonuses")
## Added to max health.
@export var health: float = 0.0
## 0.12 = 12% more damage, on top of the level bonus.
@export var damage: float = 0.0
## 0.15 = ability cooldowns (Q, E, R) 15% shorter. Basic attacks unchanged.
@export var cooldown: float = 0.0
## 0.08 = 8% faster walking. Dashes unchanged.
@export var move_speed: float = 0.0
@export_group("Adventurer stats")
## Points: weapon abilities deal (100 + weapon power)% damage.
@export var weapon_power: float = 0.0
## Points: spell abilities deal (100 + spell power)% damage.
@export var spell_power: float = 0.0
## Points: weapon damage taken x 100 / (100 + armor).
@export var armor: float = 0.0
## Points: spell damage taken x 100 / (100 + magic resist).
@export var magic_resist: float = 0.0
## 0.2 = basic attacks 20% faster.
@export var attack_speed: float = 0.0
## Points: ability cooldowns x 100 / (100 + haste), item haste capped.
@export var haste: float = 0.0
@export_group("Passive")
@export var passive: Passive = Passive.NONE
## Damage, shield or bonus size, depending on the passive.
@export var passive_value: float = 0.0
## Seconds before the passive can trigger again.
@export var passive_cooldown: float = 0.0
