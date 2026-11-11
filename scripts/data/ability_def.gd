class_name AbilityDef
extends Resource
## Tuning for one ability. Every number a designer would tune lives here,
## kept separate on purpose: damage, range, cast time, recovery, cooldown,
## projectile speed and targeting are independent knobs.

## PROJECTILE flies from the muzzle. GROUND_AREA bursts at a point after a delay.
## MELEE_ARC hits every enemy in a cone in front at release. DASH carries the
## caster along its move direction and hits enemies it passes through. WARD
## plants a circle on the caster that shields allied champions inside. WALL
## raises a line across the aim at a ground point that stops enemy shots.
## GRAPPLE throws a chain at a marked wall within range and pulls the caster
## to a safe point in front of it (see Unit.grapple_endpoint).
enum Delivery { PROJECTILE, GROUND_AREA, MELEE_ARC, DASH, WARD, WALL, GRAPPLE, SELF, SUMMON }

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var delivery: Delivery = Delivery.PROJECTILE
## Ultimates sit in the last slot (R) and unlock at Unit.ULT_LEVEL.
@export var is_ultimate: bool = false
## Item power this ability scales with: CHAMPION uses ChampionDef.power,
## NONE ignores items (and armor and magic resist).
enum Scaling { CHAMPION, WEAPON, SPELL, NONE }
@export var scaling: Scaling = Scaling.CHAMPION

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
## Piercing: damage multiplier for every enemy after the first.
@export var pierce_falloff: float = 1.0

@export_group("Ground area")
@export var area_radius: float = 2.5
## Time the telegraph is visible on the ground before it detonates.
@export var area_delay: float = 0.8
## On the burst: every enemy hit is dragged up to this far toward the centre.
@export var pull_distance: float = 0.0
## Above 0 the area is a line instead of a circle: this wide, `range` long,
## running from the caster along the aim.
@export var line_width: float = 0.0
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
## Taunt: the target must walk to the caster and basic attack it, nothing else.
@export var taunt_duration: float = 0.0
## Charm: the target walks straight away from the caster and cannot act.
@export var charm_duration: float = 0.0
## Weaken: a champion hit deals this much less damage (0.3 = 30% less).
@export var weaken_amount: float = 0.0
@export var weaken_duration: float = 0.0
## A hit on a champion stops the cast it is winding up.
@export var interrupts: bool = false
## Enemies hit are pushed this far away from the caster or the area centre
## (walls stop them).
@export var push_distance: float = 0.0

@export_group("Melee arc")
## Full width of the cone in degrees (120 = 60 each side of the aim).
@export var arc_degrees: float = 120.0

@export_group("Dash")
@export var dash_distance: float = 8.0
@export var dash_duration: float = 0.22
## The first enemy champion met ends the dash (push_distance knocks it back).
@export var stop_on_champion: bool = false

@export_group("Charges")
## Above 1 the ability holds this many uses; `cooldown` brings one back at a
## time, and `charge_lock` is the short gap between two uses.
@export var max_charges: int = 1
@export var charge_lock: float = 0.3

@export_group("Grapple")
## Travel speed toward the anchor (range is how far the chain reaches).
@export var grapple_speed: float = 24.0
## Travel shorter than this does not count as meaningful (no MOMENTUM).
@export var grapple_min_travel: float = 4.0

@export_group("Ward")
## How long the ward stands (area_radius sets its size).
@export var ward_duration: float = 3.5
## Fraction of damage removed for allied champions inside (0.35 = 35% less).
@export var ward_reduction: float = 0.35
## Health per second for allied champions inside the ward (0 = none).
@export var heal_per_second: float = 0.0
## Slow on enemies standing inside (0.35 = 35%), kept up while they stay.
@export var enemy_slow: float = 0.0
## Allied champions inside attack faster (0.35 = basic attacks come 35% sooner).
@export var ally_haste: float = 0.0
## Allied champions inside move faster (0.2 = 20%).
@export var ally_quick: float = 0.0

@export_group("Wall")
## Length of a WALL across the aim (ward_duration sets how long it stands).
@export var wall_length: float = 7.0

@export_group("Self")
## SELF delivery: brace. The next champion hit from the front within
## brace_duration deals brace_reduction less (0.6 = 60% less).
@export var brace_reduction: float = 0.0
@export var brace_duration: float = 0.0
## Shields on release: SELF the caster, SELF_AND_ALLY the caster and the most
## hurt allied champion within area_radius, MOST_HURT whichever of those needs
## it most.
enum ShieldMode { NONE, SELF, SELF_AND_ALLY, MOST_HURT }
@export var shield_mode: ShieldMode = ShieldMode.NONE
@export var shield_amount: float = 0.0
@export var shield_duration: float = 3.0
## The caster moves this much faster (any delivery), for self_quick_duration.
@export var self_quick: float = 0.0
@export var self_quick_duration: float = 0.0
## Transform: for transform_duration the caster gains transform_health max
## health (health keeps its share) and swings transform_basic instead.
@export var transform_duration: float = 0.0
@export var transform_health: float = 0.0
@export var transform_basic: Resource

@export_group("Summon")
## The unit placed at the aim point (a ChampionDef of kind SUMMON).
@export var summon: Resource
@export var summon_duration: float = 10.0
## Most of this summon one caster keeps; a new one replaces the oldest.
@export var summon_max: int = 1
## Replace an existing summon of the same group where it stands (an
## upgrade, Masterwork Battery); with none out, place it at the aim.
@export var summon_in_place: bool = false
## Summons sharing a group count together against summon_max.
@export var summon_group: StringName = &""

@export_group("Upgrades")
## The two versions offered at UPGRADE_LEVEL (AbilityDef resources); picking
## one replaces this ability. Typed as Resource: a script holding a typed array
## of its own class keeps itself alive and leaks at exit.
@export var upgrades: Array[Resource] = []
