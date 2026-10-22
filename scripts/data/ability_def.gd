class_name AbilityDef
extends Resource
## Tuning for one ability. Every number a designer would tune lives here,
## kept separate on purpose: damage, range, cast time, recovery, cooldown,
## projectile speed and targeting are independent knobs.

## PROJECTILE flies from the muzzle. GROUND_AREA bursts at a point after a delay.
## MELEE_ARC hits every enemy in a cone in front at release. DASH carries the
## caster along its move direction and hits enemies it passes through. WARD
## plants a circle on the caster that shields allied champions inside.
enum Delivery { PROJECTILE, GROUND_AREA, MELEE_ARC, DASH, WARD }

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var delivery: Delivery = Delivery.PROJECTILE
## Ultimates sit in the last slot (R) and unlock at Unit.ULT_LEVEL.
@export var is_ultimate: bool = false

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

## Multiplier against structures (minions siege: 2.0).
@export var structure_damage_mult: float = 1.0

@export_group("Targeting")
## Max distance for a projectile's travel or a ground target's placement.
@export var range: float = 15.0

@export_group("Projectile")
@export var projectile_speed: float = 30.0
@export var projectile_radius: float = 0.3
## Homing shots follow their target and can only hit it (towers).
@export var homing: bool = false
## Piercing shots pass through every enemy on their line (each hit once).
@export var pierce: bool = false

@export_group("Ground area")
@export var area_radius: float = 2.5
## Time the telegraph is visible on the ground before it detonates.
@export var area_delay: float = 0.8
## On the burst: every enemy hit is dragged up to this far toward the centre.
@export var pull_distance: float = 0.0
## On the burst: health for each allied champion inside.
@export var ally_heal: float = 0.0
## On the burst: a second area left where it landed (a WARD-delivery
## AbilityDef, such as a slowing field). Resource-typed like `upgrades`.
@export var leaves: Resource

@export_group("Crowd control")
## Fraction of move speed removed (0.3 = 30% slow).
@export var slow_amount: float = 0.0
@export var slow_duration: float = 0.0
## Stun: the target cannot move or act, and its cast is interrupted.
@export var stun_duration: float = 0.0
## Root: the target cannot walk or dash, but can still attack and cast.
@export var root_duration: float = 0.0
## Mark: the target takes this much more damage from everyone (0.25 = 25%).
@export var mark_amount: float = 0.0
@export var mark_duration: float = 0.0

@export_group("Melee arc")
## Full width of the cone in degrees (120 = 60 each side of the aim).
@export var arc_degrees: float = 120.0

@export_group("Dash")
@export var dash_distance: float = 8.0
@export var dash_duration: float = 0.22

@export_group("Ward")
## How long the ward stands (area_radius sets its size).
@export var ward_duration: float = 3.5
## Fraction of damage removed for allied champions inside (0.35 = 35% less).
@export var ward_reduction: float = 0.35
## Health per second for allied champions inside the ward (0 = none).
@export var heal_per_second: float = 0.0
## Slow on enemies standing inside (0.35 = 35%), kept up while they stay.
@export var enemy_slow: float = 0.0

@export_group("Upgrades")
## The two versions offered at UPGRADE_LEVEL (AbilityDef resources); picking
## one replaces this ability. Typed as Resource: a script holding a typed array
## of its own class keeps itself alive and leaks at exit.
@export var upgrades: Array[Resource] = []
