class_name ItemDef
extends Resource
## One shop item: a flat stat bonus bought with gold at the own fountain.
## Bonuses stack by adding; the unit recomputes its stats on every change.

@export var id: StringName
@export var display_name: String = ""
## One word for tight spots (the scoreboard).
@export var short_name: String = ""
## One plain line for the shop panel.
@export var description: String = ""
@export var cost: int = 600
@export_group("Bonuses")
## Added to max health.
@export var health: float = 0.0
## 0.12 = 12% more damage, on top of the level bonus.
@export var damage: float = 0.0
## 0.15 = ability cooldowns (Q, E, R) 15% shorter. Basic attacks unchanged.
@export var cooldown: float = 0.0
## 0.08 = 8% faster walking. Dashes unchanged.
@export var move_speed: float = 0.0
