class_name AbilityDef
extends Resource
## Tuning for one ability. Every number a designer would tune lives here,
## kept separate on purpose: damage, range, cast time, recovery, cooldown,
## projectile speed and targeting are independent knobs.

enum Delivery { PROJECTILE, GROUND_AREA }

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var delivery: Delivery = Delivery.PROJECTILE

@export_group("Damage")
@export var damage: float = 0.0
@export var hits_enemies_only: bool = true

@export_group("Timing (seconds)")
## Windup before the effect is released. This is the readable tell.
@export var cast_time: float = 0.2
## Lockout after release before another action can start.
@export var recovery: float = 0.2
## Counted from the start of the cast (so it is also the attack interval
## for a held basic attack). Never shorter than cast_time + recovery in effect.
@export var cooldown: float = 1.0
## Movement speed multiplier during windup and recovery (0 roots the caster).
@export var move_mult_while_casting: float = 0.5

@export_group("Targeting")
## Max distance for a projectile's travel or a ground target's placement.
@export var range: float = 15.0

@export_group("Projectile")
@export var projectile_speed: float = 30.0
@export var projectile_radius: float = 0.3

@export_group("Ground area")
@export var area_radius: float = 2.5
## Time the telegraph is visible on the ground before it detonates.
@export var area_delay: float = 0.8

@export_group("Crowd control")
## Fraction of move speed removed (0.3 = 30% slow).
@export var slow_amount: float = 0.0
@export var slow_duration: float = 0.0
