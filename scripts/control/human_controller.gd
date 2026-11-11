class_name HumanController
extends UnitController
## Keyboard and mouse to UnitCommand. Aim comes from the camera rig.
## Q: for a ground-target ability, hold to preview where it lands and release
## to cast; for any other ability (dash, ward) Q casts on press.
## Right mouse: cast the ability immediately (no preview).
## T (or a click on the HUD recall button): recall to the fountain (stand
## still; moving or casting cancels it).
## B: open or close the shop panel; while it is open, 1 to 4 buy an item.
## With the adventurer catalog the shop frees the mouse: click an item to buy
## it, right click an owned one to sell it, 1 buys the suggested next step.

var rig: CameraRig
## Slot being previewed while its key is held (-1: none). Views read this.
var preview_slot: int = -1
## Shop panel open (the HUD draws it). Static: there is one local player.
static var shop_open: bool = false
## Clicks on the shop panel (the HUD sets them), sent with the next command.
static var pending_buy: int = 0
static var pending_sell: int = 0
## A click on the HUD recall button, sent with the next command.
static var pending_recall: bool = false


## Opens or closes the shop. The adventurer shop needs the mouse pointer.
static func set_shop(open: bool) -> void:
	shop_open = open
	if ItemShop.adventurer() and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED


func _init(camera_rig: CameraRig) -> void:
	rig = camera_rig


func get_command(unit: Unit) -> UnitCommand:
	var c := UnitCommand.new()
	c.aim_yaw = rig.yaw
	c.aim_point = rig.get_aim_point(unit)
	if Input.is_action_just_pressed("shop"):
		set_shop(not shop_open)
	c.buy_item = pending_buy
	c.sell_item = pending_sell
	pending_buy = 0
	pending_sell = 0
	if pending_recall:
		c.buttons |= UnitCommand.BTN_RECALL
		pending_recall = false
	if shop_open and ItemShop.adventurer() and Input.is_action_just_pressed("buy_1"):
		c.buy_item = ItemShop.next_step(unit)
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
	if Input.is_action_just_pressed("recall"):
		c.buttons |= UnitCommand.BTN_RECALL
	if shop_open and not ItemShop.adventurer():
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
	if Input.is_action_just_pressed("ability_4"):
		c.buttons |= UnitCommand.BTN_ABILITY_4
	return c


func commands_while_dead() -> bool:
	return true
