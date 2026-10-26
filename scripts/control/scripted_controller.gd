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
	c.target_id = command.target_id
	c.upgrade_choice = command.upgrade_choice
	c.buy_item = command.buy_item
	c.sell_item = command.sell_item
	return c


func commands_while_dead() -> bool:
	return true
