class_name PauseMenu
extends Control
## Esc during play: Resume, Settings, Surrender (bot match), Main menu, Quit.
## Offline the whole game pauses underneath; a network client keeps running
## (the server does not stop for one player).

const TEXT := Color(0.95, 0.92, 0.85)

var match_ctl: MatchController
var can_pause := true
var _box: VBoxContainer
var _surrender: Button
var _settings: SettingsPanel
var _was_captured := false


func setup(m: MatchController, pause_tree: bool) -> void:
	match_ctl = m
	can_pause = pause_tree


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.02, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.10, 0.09, 0.97)
	sb.border_color = Palette.BRASS
	sb.set_border_width_all(2)
	sb.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 14)
	_box.custom_minimum_size = Vector2(460, 0)
	panel.add_child(_box)
	var title := Label.new()
	title.text = "Paused" if can_pause else "Menu"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.92, 0.84, 0.66))
	_box.add_child(title)
	_button("Resume", close)
	_button("Settings", _open_settings)
	if match_ctl and match_ctl.human_slot:
		_surrender = _button("Surrender", _on_surrender)
	_button("Main menu", func() -> void:
		get_tree().paused = false
		Session.mode = ""
		get_tree().reload_current_scene())
	_button("Quit game", func() -> void: get_tree().quit())


func _button(t: String, f: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(0, 64)
	b.add_theme_font_size_override("font_size", 28)
	b.pressed.connect(f)
	_box.add_child(b)
	return b


func is_open() -> bool:
	return visible


func open() -> void:
	if visible or (match_ctl and match_ctl.over):
		return
	_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	visible = true
	if _surrender:
		_surrender.text = "Surrender"
	if can_pause:
		get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	(_box.get_child(1) as Button).grab_focus()


func close() -> void:
	if not visible:
		return
	if _settings:
		_settings.queue_free()
		_settings = null
	visible = false
	get_tree().paused = false
	if _was_captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _open_settings() -> void:
	_box.get_parent().visible = false
	_settings = SettingsPanel.new()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	center.add_child(_settings)
	_settings.closed.connect(func() -> void:
		_settings = null
		center.queue_free()
		_box.get_parent().visible = true
		(_box.get_child(2) as Button).grab_focus())


## Two presses so a stray click does not end the match.
func _on_surrender() -> void:
	if _surrender.text == "Surrender":
		_surrender.text = "Press again to surrender"
		return
	close()
	match_ctl.surrender(0)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("release_mouse") or _settings:
		return
	get_viewport().set_input_as_handled()
	if visible:
		close()
	else:
		open()
