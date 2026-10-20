class_name ScriptedController
extends UnitController
## Plays back a fixed command. Used by tests; anything that sets the fields
## goes through the same path as a human or a bot.

var command := UnitCommand.new()


func get_command(_unit: Unit) -> UnitCommand:
	var c := UnitCommand.new()
	c.move = command.move
	c.aim_yaw = command.aim_yaw
	c.aim_point = command.aim_point
	c.buttons = command.buttons
	return c
