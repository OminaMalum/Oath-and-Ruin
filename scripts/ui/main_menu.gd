class_name MainMenu
extends Control
## First screen. Left: the champions. Middle: the picked one's model.
## Right: who they are and what each ability does, one at a time in big
## type. Bottom: bot difficulty, item set and the modes.

signal chosen(mode: String)

const NAMES := [["Ruinscribe", "Ranged caster", &"ruinscribe"], ["Oathwarden", "Frontline", &"oathwarden"], ["Ashrunner", "Skirmisher", &"ashrunner"],
	["Lanternkeeper", "Support", &"lanternkeeper"], ["Thornwright", "Marksman", &"thornwright"], ["Gravebinder", "Controller", &"gravebinder"],
	["Barrowking", "Frontline", &"barrowking"], ["Veilsinger", "Support", &"veilsinger"], ["Stormscald", "Spellcaster", &"stormscald"]]
## Kit tiles in keyboard order: [label on the tile, slot] (-1 = the passive).
const KIT_KEYS := [["Passive", -1], ["LMB", 0], ["Q", 1], ["E", 2], ["F", 4], ["R", 3]]

var _preview: ChampionPreview
var _name: Label
var _who: Label
var _stats: Label
var _lore: Label
var _kit_row: HBoxContainer
var _kit_group: ButtonGroup
var _ability_name: Label
var _ability_text: Label
var _ability_counter: Label
var _def: ChampionDef
var _root_box: Control


func _ready() -> void:
	# Anchors and offsets together: set_anchors_preset alone kept the zero
	# offsets, so the menu sat in the top left corner at any window size.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	_root_box = box
	box.add_child(_title())
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	box.add_child(cols)
	cols.add_child(_champion_grid())
	cols.add_child(_preview_column())
	cols.add_child(_kit_panel())
	box.add_child(_options_row())
	var start := _mode_row(box, center)
	_show(Session.champion)
	start.grab_focus.call_deferred()
	if OS.get_cmdline_user_args().has("--settings"):  # screenshots
		_open_settings.call_deferred(center, start)


## Warm dark vignette with the seal faint behind everything.
func _background() -> void:
	var bg := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.17, 0.14, 0.11))
	g.set_color(1, Color(0.045, 0.04, 0.035))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.42)
	gt.fill_to = Vector2(1.0, 1.0)
	gt.width = 256
	gt.height = 256
	bg.texture = gt
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)


func _title() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	var mark := TextureRect.new()
	mark.texture = load("res://assets/ui/logo_mark.png")
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.custom_minimum_size = Vector2(72, 72)
	row.add_child(mark)
	var word := TextureRect.new()
	word.texture = load("res://assets/ui/logo_word.png")
	word.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	word.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	word.custom_minimum_size = Vector2(440, 46)
	word.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(word)
	var sub := UiStyle.label("Prototype build", 20, UiStyle.DIM)
	sub.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(sub)
	return row


func _champion_grid() -> Control:
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	left.add_child(UiStyle.label("Choose your champion", 24, UiStyle.GOLD))
	var group := ButtonGroup.new()
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	left.add_child(grid)
	var picks: Array = NAMES.duplicate()
	# Prototype champions: playable, marked as new, never drawn at random.
	for d: ChampionDef in MatchController.PROTOTYPES:
		picks.append([d.display_name, "New", d.id])
	for c: Array in picks:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.text = "%s\n%s" % [c[0], c[1]]
		b.custom_minimum_size = Vector2(162, 76)
		UiStyle.button(b, 21)
		var id: StringName = c[2]
		b.button_pressed = Session.champion == id
		b.pressed.connect(func() -> void:
			Session.champion = id
			_show(id))
		grid.add_child(b)
	return left


func _preview_column() -> Control:
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 4)
	_preview = ChampionPreview.new()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--preview-yaw="):  # screenshots
			_preview.fixed_yaw = float(a.get_slice("=", 1))
	mid.add_child(_preview)
	_lore = UiStyle.label("", 20, Color(0.85, 0.82, 0.76))
	_lore.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lore.custom_minimum_size = Vector2(400, 168)
	_lore.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	mid.add_child(_lore)
	return mid


func _kit_panel() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel())
	panel.custom_minimum_size = Vector2(548, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	_name = UiStyle.label("", 38, UiStyle.GOLD)
	v.add_child(_name)
	_who = UiStyle.label("", 22, UiStyle.CREAM)
	v.add_child(_who)
	_stats = UiStyle.label("", 20, UiStyle.DIM)
	v.add_child(_stats)
	var sep := ColorRect.new()
	sep.color = Color(Palette.BRASS, 0.5)
	sep.custom_minimum_size = Vector2(0, 2)
	v.add_child(sep)
	v.add_child(UiStyle.label("Abilities: point at one to read it", 20, UiStyle.DIM))
	_kit_row = HBoxContainer.new()
	_kit_row.add_theme_constant_override("separation", 6)
	v.add_child(_kit_row)
	_ability_name = UiStyle.label("", 28, Color(0.6, 0.95, 0.92))
	v.add_child(_ability_name)
	_ability_text = UiStyle.label("", 21, UiStyle.CREAM)
	_ability_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ability_text.custom_minimum_size = Vector2(506, 156)
	_ability_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	v.add_child(_ability_text)
	_ability_counter = UiStyle.label("", 20, Color(1.0, 0.8, 0.55))
	_ability_counter.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ability_counter.custom_minimum_size = Vector2(506, 86)
	_ability_counter.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	v.add_child(_ability_counter)
	return panel


## What a kit tile shows: {name, text, counter}. A description's
## "Counterplay:" part is split off so it can be read as its own line.
static func kit_entry(d: ChampionDef, slot: int) -> Dictionary:
	if slot < 0:
		return {"name": d.passive_name, "text": d.passive_description, "counter": ""}
	var a := d.get_slot(slot)
	if a == null:
		return {}
	return kit_entry_of(a)


static func kit_entry_of(a: AbilityDef) -> Dictionary:
	var text := a.description.strip_edges()
	var counter := ""
	var cut := text.find("Counterplay:")
	if cut >= 0:
		counter = "How to beat it: " + text.substr(cut + 12).strip_edges()
		text = text.substr(0, cut).strip_edges()
	return {"name": a.display_name, "text": text, "counter": counter}


func _show(id: StringName) -> void:
	_def = load("res://data/champions/%s.tres" % id) as ChampionDef
	if _def == null:
		return
	_preview.show_champion(id)
	_name.text = _def.display_name
	_who.text = "%s, %s" % [_def.hero_name, _def.title] if not _def.hero_name.is_empty() else _def.role
	var reach := _def.basic_attack.range if _def.basic_attack else 0.0
	_stats.text = "%s     Health %d     Speed %.1f     Reach %d m" % [_def.role, roundi(_def.max_health), _def.move_speed, roundi(reach)]
	_lore.text = ("%s.  %s" % [_def.ancestry, _def.lore]) if not _def.lore.is_empty() else ""
	for c in _kit_row.get_children():
		c.queue_free()
	_kit_group = ButtonGroup.new()
	var first: Button
	for k: Array in KIT_KEYS:
		var slot: int = k[1]
		var e := kit_entry(_def, slot)
		if e.is_empty() or String(e.name).is_empty():
			continue
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = _kit_group
		b.text = k[0]
		b.custom_minimum_size = Vector2(80, 52)
		UiStyle.button(b, 20)
		var pick := func() -> void:
			b.button_pressed = true
			_show_ability(slot)
		b.pressed.connect(pick)
		b.mouse_entered.connect(pick)
		b.focus_entered.connect(pick)
		_kit_row.add_child(b)
		if first == null or slot == 1:
			first = b
	if first:
		first.button_pressed = true
	_show_ability(1 if _def.get_slot(1) else -1)


func _show_ability(slot: int) -> void:
	var e := kit_entry(_def, slot)
	if e.is_empty():
		return
	var tag := "Passive" if slot < 0 else ("Ultimate, from level %d" % Unit.ULT_LEVEL if _def.get_slot(slot).is_ultimate else "")
	_ability_name.text = e.name + ("   (%s)" % tag if not tag.is_empty() else "")
	_ability_text.text = e.text
	_ability_counter.text = e.counter


func _toggle_row(title: String, options: Array, picked: int, on_pick: Callable, width: float) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(UiStyle.label(title, 22, UiStyle.GOLD))
	var group := ButtonGroup.new()
	for i in options.size():
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.text = options[i]
		b.custom_minimum_size = Vector2(width, 50)
		UiStyle.button(b, 21)
		b.button_pressed = i == picked
		var index := i
		b.pressed.connect(func() -> void: on_pick.call(index))
		row.add_child(b)
	return row


func _options_row() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 36)
	var record := UiStyle.label(Settings.record_text(), 20, UiStyle.DIM)
	# Enemy bot difficulty: three toggles in a row, saved with the settings.
	row.add_child(_toggle_row("Enemy bots", Settings.DIFFICULTY_NAMES, Settings.difficulty, func(i: int) -> void:
		Settings.difficulty = i
		Settings.save()
		record.text = Settings.record_text(), 112))
	# Shop catalog: the adventurer items or the four classic ones.
	row.add_child(_toggle_row("Items", ["Adventurer", "Classic"], 0 if Settings.adventurer_items else 1, func(i: int) -> void:
		Settings.adventurer_items = i == 0
		Settings.save()
		ItemShop.use_adventurer(i == 0), 150))
	row.add_child(record)
	return row


func _mode_row(box: Control, center: CenterContainer) -> Button:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	var start: Button
	for item in [["Play 3v3 Bot Match", "match", 380], ["Three Lane Map", "match3", 240], ["Training Court", "court", 240], ["Settings", "settings", 170], ["Quit", "quit", 130]]:
		var b := Button.new()
		b.text = item[0]
		b.custom_minimum_size = Vector2(item[2], 62)
		UiStyle.button(b, 28, item[1] == "match")
		var mode: String = item[1]
		if mode == "settings":
			b.pressed.connect(_open_settings.bind(center, b))
		else:
			b.pressed.connect(func() -> void: chosen.emit(mode))
		row.add_child(b)
		if start == null:
			start = b
	return start


## The settings panel takes the place of the menu until Back.
func _open_settings(center: CenterContainer, from: Button) -> void:
	_root_box.visible = false
	var panel := SettingsPanel.new()
	center.add_child(panel)
	panel.closed.connect(func() -> void:
		_root_box.visible = true
		from.grab_focus())
