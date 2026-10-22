class_name MainMenu
extends Control
## First screen: big, plain choices.

signal chosen(mode: String)


func _ready() -> void:
	# Anchors and offsets together: set_anchors_preset alone kept the zero
	# offsets, so the menu sat in the top left corner at any window size.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.08, 0.07)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	box.custom_minimum_size = Vector2(520, 0)
	center.add_child(box)
	var title := Label.new()
	title.text = "PactFall"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(0.92, 0.84, 0.66))
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Prototype build"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 20)
	sub.add_theme_color_override("font_color", Color(0.75, 0.72, 0.65))
	box.add_child(sub)
	# Champion pick: three big toggles, the role written under each name.
	var pick_label := Label.new()
	pick_label.text = "Your champion"
	pick_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pick_label.add_theme_font_size_override("font_size", 24)
	pick_label.add_theme_color_override("font_color", Color(0.85, 0.80, 0.70))
	box.add_child(pick_label)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	box.add_child(grid)
	var row := grid
	var group := ButtonGroup.new()
	for c in [["Ruinscribe", "Ranged caster", &"ruinscribe"], ["Oathwarden", "Frontline", &"oathwarden"], ["Ashrunner", "Skirmisher", &"ashrunner"],
			["Lanternkeeper", "Support", &"lanternkeeper"], ["Thornwright", "Marksman", &"thornwright"], ["Gravebinder", "Controller", &"gravebinder"]]:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.text = "%s\n%s" % [c[0], c[1]]
		b.custom_minimum_size = Vector2(165, 84)
		b.add_theme_font_size_override("font_size", 22)
		var id: StringName = c[2]
		b.button_pressed = Session.champion == id
		b.pressed.connect(func() -> void: Session.champion = id)
		row.add_child(b)
	for item in [["3v3 Bot Match", "match"], ["Training Court", "court"], ["Quit", "quit"]]:
		var b := Button.new()
		b.text = item[0]
		b.custom_minimum_size = Vector2(520, 72)
		b.add_theme_font_size_override("font_size", 30)
		var mode: String = item[1]
		b.pressed.connect(func() -> void: chosen.emit(mode))
		box.add_child(b)
	(box.get_child(4) as Button).grab_focus.call_deferred()  # 3v3 Bot Match
