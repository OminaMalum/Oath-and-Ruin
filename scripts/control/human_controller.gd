class_name HumanController
extends UnitController
## Keyboard and mouse to UnitCommand. Aim comes from the camera rig.

var rig: CameraRig


func _init(camera_rig: CameraRig) -> void:
	rig = camera_rig


func get_command(unit: Unit) -> UnitCommand:
	var c := UnitCommand.new()
	c.aim_yaw = rig.yaw
	c.aim_point = rig.get_aim_point(unit)
	if not rig.mouse_captured():
		return c  # menus or alt-tab: stand still, do not fire
	c.move = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	if Input.is_action_pressed("attack"):
		c.buttons |= UnitCommand.BTN_ATTACK
	if Input.is_action_just_pressed("ability_1"):
		c.buttons |= UnitCommand.BTN_ABILITY_1
	return c
