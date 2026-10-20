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


func pressed(button: int) -> bool:
	return buttons & button != 0


func to_dict() -> Dictionary:
	return {"m": move, "y": aim_yaw, "a": aim_point, "b": buttons}


static func from_dict(d: Dictionary) -> UnitCommand:
	var c := UnitCommand.new()
	c.move = (d.get("m", Vector2.ZERO) as Vector2).limit_length(1.0)
	c.aim_yaw = d.get("y", 0.0)
	c.aim_point = d.get("a", Vector3.ZERO)
	c.buttons = d.get("b", 0)
	return c
