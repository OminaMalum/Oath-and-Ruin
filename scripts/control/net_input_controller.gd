class_name NetInputController
extends UnitController
## Server side: the latest command received from a client. If commands stop
## arriving (loss, stall, disconnect) the unit stops moving and attacking
## after a short timeout instead of running on stale input.

const TIMEOUT := 0.5

var latest := UnitCommand.new()
var latest_client_tick: int = -1
var _age: float = 999.0


func receive(client_tick: int, cmd: UnitCommand) -> void:
	if client_tick <= latest_client_tick:
		return  # late or duplicate packet
	latest_client_tick = client_tick
	latest = cmd
	_age = 0.0


func reset() -> void:
	latest = UnitCommand.new()
	latest_client_tick = -1
	_age = 999.0


func get_command(unit: Unit) -> UnitCommand:
	_age += 1.0 / Engine.physics_ticks_per_second
	if _age > TIMEOUT:
		var idle := UnitCommand.new()
		idle.aim_yaw = unit.aim_yaw
		idle.aim_point = unit.aim_point
		return idle
	return latest
