class_name SettingsPanel
extends PanelContainer
## Volume, mouse sensitivity and fullscreen. Changes apply at once and are
## saved when the panel closes. Used by the main menu and the pause menu.

signal closed

const TEXT := Color(0.95, 0.92, 0.85)


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.10, 0.09, 0.97)
	sb.border_color = Palette.BRASS
	sb.set_border_width_all(2)
	sb.set_content_margin_all(28)
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(620, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	add_child(box)
	box.add_child(_label("Settings", 40, Color(0.92, 0.84, 0.66)))
	var vol_value := _label("", 24, TEXT)
	box.add_child(_row("Volume", vol_value))
	var vol := _slider(0.0, 1.0, 0.05, Settings.volume)
	vol.value_changed.connect(func(v: float) -> void:
		Settings.volume = v
		Settings.apply()
		vol_value.text = "%d%%" % roundi(v * 100.0))
	vol_value.text = "%d%%" % roundi(Settings.volume * 100.0)
	box.add_child(vol)
	var sens_value := _label("", 24, TEXT)
	box.add_child(_row("Mouse sensitivity", sens_value))
	var sens := _slider(0.4, 2.5, 0.05, Settings.mouse_sensitivity)
	sens.value_changed.connect(func(v: float) -> void:
		Settings.mouse_sensitivity = v
		sens_value.text = "%.2fx" % v)
	sens_value.text = "%.2fx" % Settings.mouse_sensitivity
	box.add_child(sens)
	# A plain button that says its state: the default switch was too faint to read.
	var full := Button.new()
	full.custom_minimum_size = Vector2(0, 60)
	full.add_theme_font_size_override("font_size", 26)
	full.text = "Fullscreen: %s" % ("On" if Settings.fullscreen else "Off")
	full.pressed.connect(func() -> void:
		Settings.fullscreen = not Settings.fullscreen
		Settings.apply()
		full.text = "Fullscreen: %s" % ("On" if Settings.fullscreen else "Off"))
	box.add_child(full)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0, 64)
	back.add_theme_font_size_override("font_size", 28)
	back.pressed.connect(close)
	box.add_child(back)
	back.grab_focus.call_deferred()


func close() -> void:
	Settings.save()
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("release_mouse"):
		get_viewport().set_input_as_handled()
		close()


func _label(t: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _row(name: String, value: Label) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := _label(name, 26, TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	return row


func _slider(lo: float, hi: float, step: float, v: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = v
	s.custom_minimum_size = Vector2(0, 36)
	return s
