extends Node
## Registers input actions in code so the bindings live in one readable place.

const KEYS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"ability_1_preview": [KEY_Q],
	"ability_2": [KEY_E],
	"upgrade_1": [KEY_1],
	"upgrade_2": [KEY_2],
	"restart": [KEY_R],
	"menu": [KEY_M],
	"toggle_bot": [KEY_F1],
	"toggle_help": [KEY_F2],
	"release_mouse": [KEY_ESCAPE],
}
const MOUSE := {
	"attack": [MOUSE_BUTTON_LEFT],
	"ability_1_quick": [MOUSE_BUTTON_RIGHT],
}


func _ready() -> void:
	for action: String in KEYS:
		_ensure(action)
		for k: Key in KEYS[action]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(action, e)
	for action: String in MOUSE:
		_ensure(action)
		for b: MouseButton in MOUSE[action]:
			var e := InputEventMouseButton.new()
			e.button_index = b
			InputMap.action_add_event(action, e)


func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
