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
	box.custom_minimum_size = Vector2(1000, 0)
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
	# Two columns so nine champions and the match choices fit a 720p screen:
	# picks on the left, difficulty and modes on the right.
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 48)
	box.add_child(cols)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 14)
	cols.add_child(left)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 14)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	cols.add_child(right)
	box.remove_child(pick_label)
	left.add_child(pick_label)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	left.add_child(grid)
	var row := grid
	var group := ButtonGroup.new()
	# Who the picked champion is: name, title, class and a few lines of story.
	var who := Label.new()
	who.add_theme_font_size_override("font_size", 24)
	who.add_theme_color_override("font_color", Color(0.92, 0.84, 0.66))
	var story := Label.new()
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story.custom_minimum_size = Vector2(519, 0)
	story.add_theme_font_size_override("font_size", 20)
	story.add_theme_color_override("font_color", Color(0.85, 0.82, 0.76))
	var show_lore := func(id: StringName) -> void:
		var d := load("res://data/champions/%s.tres" % id) as ChampionDef
		if d == null or d.hero_name.is_empty():
			who.text = ""
			story.text = ""
			return
		who.text = "%s, %s" % [d.hero_name, d.title]
		story.text = "%s.  %s" % [d.ancestry, d.lore]
	for c in [["Ruinscribe", "Ranged caster", &"ruinscribe"], ["Oathwarden", "Frontline", &"oathwarden"], ["Ashrunner", "Skirmisher", &"ashrunner"],
			["Lanternkeeper", "Support", &"lanternkeeper"], ["Thornwright", "Marksman", &"thornwright"], ["Gravebinder", "Controller", &"gravebinder"],
			["Barrowking", "Frontline", &"barrowking"], ["Veilsinger", "Support", &"veilsinger"], ["Stormscald", "Spellcaster", &"stormscald"]]:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.text = "%s\n%s" % [c[0], c[1]]
		b.custom_minimum_size = Vector2(165, 84)
		b.add_theme_font_size_override("font_size", 22)
		var id: StringName = c[2]
		b.button_pressed = Session.champion == id
		b.pressed.connect(func() -> void:
			Session.champion = id
			show_lore.call(id))
		row.add_child(b)
	# Prototype champions: playable, marked as unfinished, never drawn at random.
	for c in [["Chainbound", "Prototype", &"chainbound"]]:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.text = "%s  (%s)" % [c[0], c[1]]
		b.custom_minimum_size = Vector2(519, 52)
		b.add_theme_font_size_override("font_size", 22)
		var id: StringName = c[2]
		b.button_pressed = Session.champion == id
		b.pressed.connect(func() -> void:
			Session.champion = id
			show_lore.call(id))
		left.add_child(b)
	left.add_child(who)
	left.add_child(story)
	show_lore.call(Session.champion)
	# Enemy bot difficulty: three toggles in a row, saved with the settings.
	var diff_row := HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 12)
	diff_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var diff_label := Label.new()
	diff_label.text = "Enemy bots"
	diff_label.add_theme_font_size_override("font_size", 24)
	diff_label.add_theme_color_override("font_color", Color(0.85, 0.80, 0.70))
	diff_row.add_child(diff_label)
	var diff_group := ButtonGroup.new()
	var record := Label.new()
	for i in 3:
		var d := Button.new()
		d.toggle_mode = true
		d.button_group = diff_group
		d.text = Settings.DIFFICULTY_NAMES[i]
		d.custom_minimum_size = Vector2(120, 56)
		d.add_theme_font_size_override("font_size", 22)
		d.button_pressed = Settings.difficulty == i
		var level := i
		d.pressed.connect(func() -> void:
			Settings.difficulty = level
			Settings.save()
			record.text = Settings.record_text())
		diff_row.add_child(d)
	right.add_child(diff_row)
	# Shop catalog: the adventurer items or the four classic ones.
	var items_row := HBoxContainer.new()
	items_row.add_theme_constant_override("separation", 12)
	items_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var items_label := Label.new()
	items_label.text = "Items"
	items_label.add_theme_font_size_override("font_size", 24)
	items_label.add_theme_color_override("font_color", Color(0.85, 0.80, 0.70))
	items_row.add_child(items_label)
	var items_group := ButtonGroup.new()
	for opt in [["Adventurer", true], ["Classic", false]]:
		var ib := Button.new()
		ib.toggle_mode = true
		ib.button_group = items_group
		ib.text = opt[0]
		ib.custom_minimum_size = Vector2(170, 56)
		ib.add_theme_font_size_override("font_size", 22)
		ib.button_pressed = Settings.adventurer_items == opt[1]
		var on: bool = opt[1]
		ib.pressed.connect(func() -> void:
			Settings.adventurer_items = on
			Settings.save()
			ItemShop.use_adventurer(on))
		items_row.add_child(ib)
	right.add_child(items_row)
	var start: Button
	for item in [["3v3 Bot Match", "match"], ["Training Court", "court"], ["Settings", "settings"], ["Quit", "quit"]]:
		var b := Button.new()
		b.text = item[0]
		b.custom_minimum_size = Vector2(440, 64)
		b.add_theme_font_size_override("font_size", 30)
		var mode: String = item[1]
		if mode == "settings":
			b.pressed.connect(_open_settings.bind(center, b))
		else:
			b.pressed.connect(func() -> void: chosen.emit(mode))
		right.add_child(b)
		if start == null:
			start = b
	record.text = Settings.record_text()
	record.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	record.add_theme_font_size_override("font_size", 22)
	record.add_theme_color_override("font_color", Color(0.75, 0.72, 0.65))
	right.add_child(record)
	start.grab_focus.call_deferred()
	if OS.get_cmdline_user_args().has("--settings"):  # screenshots
		_open_settings.call_deferred(center, start)


## The settings panel takes the place of the menu until Back.
func _open_settings(center: CenterContainer, from: Button) -> void:
	var menu := center.get_child(0) as Control
	menu.visible = false
	var panel := SettingsPanel.new()
	center.add_child(panel)
	panel.closed.connect(func() -> void:
		menu.visible = true
		from.grab_focus())
