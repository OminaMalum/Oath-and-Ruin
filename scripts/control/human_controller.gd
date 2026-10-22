class_name HumanController
extends UnitController
## Keyboard and mouse to UnitCommand. Aim comes from the camera rig.
## Q: for a ground-target ability, hold to preview where it lands and release
## to cast; for any other ability (dash, ward) Q casts on press.
## Right mouse: cast the ability immediately (no preview).
## B: open or close the shop panel; while it is open, 1 to 4 buy an item.

var rig: CameraRig
## Slot being previewed while its key is held (-1: none). Views read this.
var preview_slot: int = -1
## Shop panel open (the HUD draws it). Static: there is one local player.
static var shop_open: bool = false


func _init(camera_rig: CameraRig) -> void:
	rig = camera_rig


func get_command(unit: Unit) -> UnitCommand:
	var c := UnitCommand.new()
	c.aim_yaw = rig.yaw
	c.aim_point = rig.get_aim_point(unit)
	if not rig.mouse_captured():
		preview_slot = -1
		return c  # menus or alt-tab: stand still, do not fire
	c.move = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	if Input.is_action_pressed("attack"):
		c.buttons |= UnitCommand.BTN_ATTACK
	var q := unit.get_slot(1)
	if q and q.delivery != AbilityDef.Delivery.GROUND_AREA:
		if Input.is_action_just_pressed("ability_1_preview"):
			c.buttons |= UnitCommand.BTN_ABILITY_1
	elif Input.is_action_pressed("ability_1_preview"):
		preview_slot = 1
	elif preview_slot == 1:
		preview_slot = -1
		c.buttons |= UnitCommand.BTN_ABILITY_1  # released: cast where the preview was
	if Input.is_action_just_pressed("shop"):
		shop_open = not shop_open
	if shop_open:
		for i in 4:
			if Input.is_action_just_pressed("buy_%d" % (i + 1)):
				c.buy_item = i + 1
	elif Input.is_action_just_pressed("upgrade_1"):
		c.upgrade_choice = 1
	elif Input.is_action_just_pressed("upgrade_2"):
		c.upgrade_choice = 2
	if Input.is_action_just_pressed("ability_1_quick"):
		c.buttons |= UnitCommand.BTN_ABILITY_1
	if Input.is_action_just_pressed("ability_2"):
		c.buttons |= UnitCommand.BTN_ABILITY_2
	if Input.is_action_just_pressed("ability_3"):
		c.buttons |= UnitCommand.BTN_ABILITY_3
	return c


func commands_while_dead() -> bool:
	return true
