class_name UnitController
extends RefCounted
## Produces a UnitCommand for its unit every simulation tick.

func get_command(_unit: Unit) -> UnitCommand:
	return UnitCommand.new()
