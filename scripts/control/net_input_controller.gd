class_name NetInputController
extends UnitController
## Server side: commands received from one client, applied one per tick in
## client tick order. Each packet repeats the client's last few commands, so a
## lost packet costs nothing as long as a later one arrives. The tick of the
## command applied last is sent back in snapshots (the ack) so the client can
## replay only what the server has not seen yet.
##
## If commands stop arriving (loss, stall, disconnect) the unit repeats the
## last command briefly, then stops moving and attacking after TIMEOUT
## instead of running on stale input.

const TIMEOUT := 0.5
## Commands queued beyond this are dropped, oldest first, so a burst after a
## stall cannot leave this player permanently further behind.
const MAX_QUEUE := 6

var latest := UnitCommand.new()
## Newest client tick received.
var latest_client_tick: int = -1
## Client tick of the command the unit used on the last server tick.
var applied_tick: int = 0
## Server ticks that had no new command and reused the previous one.
var starved_ticks: int = 0
## Client ticks never applied (lost in every redundant packet, or dropped
## from a full queue).
var skipped_ticks: int = 0
var _queue := {}  # client tick -> UnitCommand, all newer than applied_tick
var _age: float = 999.0


func receive(client_tick: int, cmd: UnitCommand) -> void:
	if client_tick <= applied_tick or _queue.has(client_tick):
		return  # late, duplicate or already applied
	_queue[client_tick] = cmd
	latest_client_tick = maxi(latest_client_tick, client_tick)
	_age = 0.0
	while _queue.size() > MAX_QUEUE:
		_queue.erase(_queue.keys().min())


func reset() -> void:
	latest = UnitCommand.new()
	latest_client_tick = -1
	applied_tick = 0
	_queue.clear()
	_age = 999.0


func get_command(unit: Unit) -> UnitCommand:
	_age += 1.0 / Engine.physics_ticks_per_second
	if not _queue.is_empty():
		var t: int = _queue.keys().min()
		if applied_tick > 0:
			skipped_ticks += t - applied_tick - 1
		latest = _queue[t]
		_queue.erase(t)
		applied_tick = t
		return latest
	if _age > TIMEOUT:
		var idle := UnitCommand.new()
		idle.aim_yaw = unit.aim_yaw
		idle.aim_point = unit.aim_point
		return idle
	starved_ticks += 1
	# Repeat movement and held attack, never a one-tick press, so a gap in
	# packets cannot cast an ability twice.
	var again := UnitCommand.new()
	again.move = latest.move
	again.aim_yaw = latest.aim_yaw
	again.aim_point = latest.aim_point
	again.buttons = latest.buttons & UnitCommand.BTN_ATTACK
	again.target_id = latest.target_id
	return again
