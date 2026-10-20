class_name MainMenu
extends Control
## First screen: big, plain choices.

signal chosen(mode: String)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.08, 0.07)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.add_theme_constant_override("separation", 18)
	box.custom_minimum_size = Vector2(520, 0)
	box.position = Vector2(-260, -220)
	add_child(box)
	var title := Label.new()
	title.text = "Oath & Ruin"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(0.92, 0.84, 0.66))
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Working title. Prototype build."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 20)
	sub.add_theme_color_override("font_color", Color(0.75, 0.72, 0.65))
	box.add_child(sub)
	for item in [["3v3 Bot Match", "match"], ["Training Court", "court"], ["Quit", "quit"]]:
		var b := Button.new()
		b.text = item[0]
		b.custom_minimum_size = Vector2(520, 72)
		b.add_theme_font_size_override("font_size", 30)
		var mode: String = item[1]
		b.pressed.connect(func() -> void: chosen.emit(mode))
		box.add_child(b)
	(box.get_child(2) as Button).grab_focus.call_deferred()
