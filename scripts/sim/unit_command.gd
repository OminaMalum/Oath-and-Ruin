class_name UnitCommand
extends RefCounted
## One tick of intent for a unit. Humans, bots, tests and (later) network
## clients all produce these; only the authority turns them into results.

const BTN_ATTACK := 1
const BTN_ABILITY_1 := 2

## x = strafe right, y = forward, relative to aim_yaw. Length <= 1.
var move: Vector2 = Vector2.ZERO
## Facing in radians around +Y (0 faces -Z, Godot forward).
var aim_yaw: float = 0.0
## World point the unit wants to hit.
var aim_point: Vector3 = Vector3.ZERO
var buttons: int = 0
## Optional unit to lock on to (homing attacks only; towers use it).
var target_id: int = 0


func pressed(button: int) -> bool:
	return buttons & button != 0


func to_dict() -> Dictionary:
	return {"m": move, "y": aim_yaw, "a": aim_point, "b": buttons, "t": target_id}


const ALL_BUTTONS := BTN_ATTACK | BTN_ABILITY_1


## Rebuilds a command from untrusted data. Wrong types, NaN or infinite
## values and unknown buttons are dropped; move is clamped to length 1.
## Range and cooldown limits are enforced later by the unit rules.
static func from_dict(d: Dictionary) -> UnitCommand:
	var c := UnitCommand.new()
	var m: Variant = d.get("m")
	if m is Vector2 and (m as Vector2).is_finite():
		c.move = (m as Vector2).limit_length(1.0)
	var y: Variant = d.get("y")
	if (y is float or y is int) and is_finite(float(y)):
		c.aim_yaw = wrapf(float(y), -PI, PI)
	var a: Variant = d.get("a")
	if a is Vector3 and (a as Vector3).is_finite():
		c.aim_point = a
	var b: Variant = d.get("b")
	if b is int:
		c.buttons = int(b) & ALL_BUTTONS
	var t: Variant = d.get("t")
	if t is int:
		c.target_id = maxi(0, t)
	return c
