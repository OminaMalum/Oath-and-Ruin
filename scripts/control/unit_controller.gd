class_name UnitController
extends RefCounted
## Produces a UnitCommand for its unit every simulation tick.

func get_command(_unit: Unit) -> UnitCommand:
	return UnitCommand.new()


## World direction (flat) to the move vector a command expects for a unit
## facing yaw: x = strafe right, y = forward.
static func world_to_move(dir: Vector3, yaw: float) -> Vector2:
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var flat := Vector3(dir.x, 0.0, dir.z).limit_length(1.0)
	return Vector2(flat.dot(right), flat.dot(fwd))


static func yaw_towards(from: Vector3, to: Vector3) -> float:
	var d := to - from
	return atan2(-d.x, -d.z)


static func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
