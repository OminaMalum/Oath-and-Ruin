class_name MatchHud
extends Control
## Match layer over the combat HUD: clock, kills, structure health, a marker
## on the next enemy structure, the scoreboard (hold Tab) and the results screen.

var match_ctl: MatchController
var rig: CameraRig
var _font: Font
var _banner: String = ""
var _banner_t: float = 0.0
var _banner_col := Color.WHITE
## Screenshots: keep the scoreboard up without Tab (--scoreboard).
static var force_scoreboard: bool = false


func setup(m: MatchController, r: CameraRig) -> void:
	match_ctl = m
	rig = r
	m.match_over.connect(func(_w: int) -> void:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_add_result_buttons())
	m.announce.connect(func(text: String, team: int) -> void:
		_banner = text
		_banner_t = 4.0
		_banner_col = Palette.team_color(team) if team >= 0 else Color(0.92, 0.84, 0.66))


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func _process(d: float) -> void:
	_banner_t -= d
	queue_redraw()


func _text(pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_CENTER, width := -1.0) -> void:
	draw_string_outline(_font, pos, s, align, width, size, 6, Color(0, 0, 0, 0.85))
	draw_string(_font, pos, s, align, width, size, col)


func _draw() -> void:
	if match_ctl == null:
		return
	var vs := get_viewport_rect().size
	var st := match_ctl.stats
	var t := int(st.duration)
	# Top bar: Oath kills | clock | Ruin kills, with tower and core health under each side.
	var cx := vs.x * 0.5
	draw_rect(Rect2(cx - 230, 8, 460, 70), Color(0.08, 0.07, 0.06, 0.75))
	_text(Vector2(cx - 100, 44), "%d:%02d" % [t / 60, t % 60], 30, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 200)
	for team in 2:
		var x := cx - 220 if team == 0 else cx + 100
		var col := Palette.team_color(team)
		_text(Vector2(x, 38), "%s  %d" % [Palette.TEAM_NAMES[team], st.kills[team]] if team == 0 else "%d  %s" % [st.kills[team], Palette.TEAM_NAMES[team]], 26, col, HORIZONTAL_ALIGNMENT_LEFT if team == 0 else HORIZONTAL_ALIGNMENT_RIGHT, 120)
		var tw: Unit = match_ctl.towers[team]
		var co: Unit = match_ctl.cores[team]
		_small_bar(Rect2(x, 50, 56, 8), tw.health / tw.max_health if tw.alive else 0.0, col)
		_small_bar(Rect2(x + 64, 50, 56, 8), co.health / co.max_health if co.alive else 0.0, col)
	_text(Vector2(cx - 220, 74), "tower  core", 14, Color(0.85, 0.85, 0.8), HORIZONTAL_ALIGNMENT_LEFT)
	_marker()
	_objective_marker(vs)
	if _banner_t > 0.0:
		_text(Vector2(0, 128), _banner, 30, Color(_banner_col, clampf(_banner_t, 0.0, 1.0)), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	if match_ctl.over:
		_results(vs)
	elif match_ctl.authority.time < INTRO_TIME:
		_intro(vs, match_ctl.authority.time)
	elif force_scoreboard or Input.is_action_pressed("scoreboard"):
		_scoreboard(vs)


## Every champion in one table: level, kills, deaths, gold and items. Own
## team first; enemy gold is not shown. Big type, one row per champion.
func _scoreboard(vs: Vector2) -> void:
	var me: Unit = rig.target if rig else null
	var mine := me.team if me else 0
	var row_h := 48.0
	var w := 1040.0
	var x := vs.x * 0.5 - w * 0.5
	var h := 60.0 + row_h * 6 + 30.0
	var y := vs.y * 0.5 - h * 0.5
	draw_rect(Rect2(x - 2, y - 2, w + 4, h + 4), Palette.BRASS)
	draw_rect(Rect2(x, y, w, h), Color(0.08, 0.07, 0.06, 0.94))
	var cols := [[24, "Champion"], [300, "Level"], [400, "Kills"], [490, "Deaths"], [600, "Gold"], [710, "Items"]]
	for col in cols:
		_text(Vector2(x + col[0], y + 40), col[1], 22, Color(0.8, 0.77, 0.7), HORIZONTAL_ALIGNMENT_LEFT)
	var row := 0
	for team in [mine, 1 - mine]:
		if row == 3:
			draw_rect(Rect2(x + 16, y + 58 + row * row_h + 8, w - 32, 2), Color(0.4, 0.36, 0.3))
		for u in match_ctl.champions:
			if u.team != team:
				continue
			var ry := y + 60 + row * row_h + (14.0 if row >= 3 else 0.0)
			var st: Dictionary = match_ctl.stats.champions.get(u.name, {})
			var tc := Palette.team_color(team)
			if u == me:
				draw_rect(Rect2(x + 8, ry + 4, w - 16, row_h - 4), Color(1, 1, 1, 0.07))
			var nm := u.def.display_name + ("  (you)" if u == me else "")
			if not u.alive:
				nm += "  %d s" % ceili(maxf(u.respawn_timer, 0.0))
			_text(Vector2(x + 24, ry + 36), nm, 24, tc if u.alive else tc.darkened(0.35), HORIZONTAL_ALIGNMENT_LEFT, 270)
			_text(Vector2(x + 300, ry + 36), str(u.level), 24, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
			_text(Vector2(x + 400, ry + 36), str(st.get("kills", 0)), 24, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
			_text(Vector2(x + 490, ry + 36), str(st.get("deaths", 0)), 24, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
			if team == mine:
				_text(Vector2(x + 600, ry + 36), str(floori(u.gold)), 24, Palette.GOLD, HORIZONTAL_ALIGNMENT_LEFT)
			var names := PackedStringArray()
			for it in u.items:
				names.append(it.short_name)
			_text(Vector2(x + 710, ry + 36), ", ".join(names) if names.size() > 0 else "none yet", 22,
					Color(0.92, 0.9, 0.84) if names.size() > 0 else Color(0.55, 0.53, 0.5), HORIZONTAL_ALIGNMENT_LEFT, w - 730)
			row += 1


func _small_bar(r: Rect2, f: float, col: Color) -> void:
	draw_rect(r.grow(1), Color(0, 0, 0, 0.8))
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(f, 0, 1), r.size.y)), col)


## A diamond over the next enemy structure on the lane, so the destination is
## always findable from behind the champion. Clamped to the screen edge.
func _marker() -> void:
	if rig == null or rig.camera == null or match_ctl.over:
		return
	var enemy := 1
	var target: Unit = match_ctl.towers[enemy] if match_ctl.towers[enemy].alive else match_ctl.cores[enemy]
	if not target.alive:
		return
	var p3 := target.global_position + Vector3(0, target.def.height + 1.5, 0)
	var vs := get_viewport_rect().size
	var p: Vector2
	if rig.camera.is_position_behind(p3):
		p = Vector2(vs.x * 0.5, vs.y - 160)
	else:
		p = rig.camera.unproject_position(p3)
	p = p.clamp(Vector2(40, 100), vs - Vector2(40, 170))
	var col := Palette.team_color(enemy)
	var d := 12.0
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0)]), Color(col, 0.9))
	var dist := UnitController.flat_distance(match_ctl.player().global_position, target.global_position)
	_text(p + Vector2(-80, 32), "%s  %d m" % [target.def.display_name, roundi(dist)], 18, Color(0.95, 0.92, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 160)


## The objective: warning countdown in the top bar, a marker over the camp
## while it is open, and a capture bar with the owning team's colour.
func _objective_marker(vs: Vector2) -> void:
	var m := match_ctl
	var cx := vs.x * 0.5
	match m.beast_state:
		MatchController.Beast.SLEEPING:
			if m.beast_timer <= MatchController.BEAST_WARNING:
				_text(Vector2(cx - 200, 98), "Shrinebearer wakes in %d" % ceili(m.beast_timer), 20, Color(0.92, 0.84, 0.66), HORIZONTAL_ALIGNMENT_CENTER, 400)
			return
		MatchController.Beast.OUT:
			if m.siege and is_instance_valid(m.siege) and m.siege.alive:
				_text(Vector2(cx - 200, 98), "%s Shrinebearer marching" % Palette.TEAM_NAMES[m.siege.team], 20, Palette.team_color(m.siege.team), HORIZONTAL_ALIGNMENT_CENTER, 400)
			return
	if rig == null or rig.camera == null:
		return
	var p3 := m.objective_position() + Vector3(0, 5.0, 0)
	var p := Vector2(vs.x * 0.5, vs.y - 160) if rig.camera.is_position_behind(p3) else rig.camera.unproject_position(p3)
	p = p.clamp(Vector2(40, 100), vs - Vector2(40, 170))
	var col := Color(0.85, 0.75, 1.0)
	var d := 12.0
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0)]), col)
	var label := "Shrinebearer"
	if m.beast_state == MatchController.Beast.CAPTURE:
		label = "Claim  %d s left" % ceili(m.beast_timer)
		if m.capture_team >= 0:
			_small_bar(Rect2(p + Vector2(-50, 40), Vector2(100, 8)), m.capture_progress / MatchController.CAPTURE_TIME, Palette.team_color(m.capture_team))
	_text(p + Vector2(-90, 32), label, 18, Color(0.95, 0.92, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 180)


const INTRO_TIME := 7.0


## The first seconds of a match: who is on the field and how hard the bots are.
func _intro(vs: Vector2, t: float) -> void:
	var a := clampf((INTRO_TIME - t) / 1.0, 0.0, 1.0)
	var w := minf(760.0, vs.x - 40.0)
	var x := (vs.x - w) * 0.5
	var y := vs.y * 0.24
	draw_rect(Rect2(x, y, w, 250), Color(0.12, 0.10, 0.09, 0.9 * a))
	draw_rect(Rect2(x, y, w, 250), Color(Palette.BRASS, a), false, 2.0)
	var names: Array[String] = []
	for d in match_ctl.team_roster(0):
		names.append(d.display_name)
	var cream := Color(0.95, 0.92, 0.85, a)
	_text(Vector2(x, y + 52), "Oath and Ruin both field", 26, cream, HORIZONTAL_ALIGNMENT_CENTER, w)
	_text(Vector2(x, y + 110), "   ".join(names), 38, Color(0.92, 0.84, 0.66, a), HORIZONTAL_ALIGNMENT_CENTER, w)
	var me: Unit = match_ctl.player()
	if match_ctl.human_slot and me:
		_text(Vector2(x, y + 165), "You play %s for Oath" % me.def.display_name, 26, Color(Palette.team_color(0), a), HORIZONTAL_ALIGNMENT_CENTER, w)
		_text(Vector2(x, y + 215), "Enemy bots: %s" % Settings.DIFFICULTY_NAMES[match_ctl.difficulty], 24, cream, HORIZONTAL_ALIGNMENT_CENTER, w)
	else:
		_text(Vector2(x, y + 175), "Six bots, watching", 26, cream, HORIZONTAL_ALIGNMENT_CENTER, w)


const RESULT_H := 640.0


func _result_box(vs: Vector2) -> Rect2:
	var w := minf(1000.0, vs.x - 40.0)
	return Rect2((vs.x - w) * 0.5, maxf(20.0, (vs.y - RESULT_H) * 0.5), w, RESULT_H)


## Play again and Main menu as real buttons (F5 and M still work).
func _add_result_buttons() -> void:
	var r := _result_box(get_viewport_rect().size)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.position = Vector2(r.position.x + r.size.x * 0.5 - 340, r.end.y - 84)
	row.custom_minimum_size = Vector2(680, 64)
	for item in [["Play again  (F5)", false], ["Main menu  (M)", true]]:
		var b := Button.new()
		b.text = item[0]
		b.custom_minimum_size = Vector2(328, 64)
		b.add_theme_font_size_override("font_size", 26)
		var to_menu: bool = item[1]
		b.pressed.connect(func() -> void:
			if to_menu:
				Session.mode = ""
			get_tree().reload_current_scene())
		row.add_child(b)
	add_child(row)
	(row.get_child(0) as Button).grab_focus()


func _results(vs: Vector2) -> void:
	var st := match_ctl.stats
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.03, 0.03, 0.03, 0.6))
	var r := _result_box(vs)
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	draw_rect(r, Color(0.12, 0.10, 0.09, 0.96))
	draw_rect(r, Palette.BRASS, false, 2.0)
	var title := "No winner"
	if match_ctl.human_slot:
		title = "Victory" if match_ctl.winner == 0 else "Defeat"
	elif match_ctl.winner >= 0:
		title = "%s wins" % Palette.TEAM_NAMES[match_ctl.winner]
	_text(Vector2(x, y + 58), title, 46, Palette.team_color(maxi(match_ctl.winner, 0)), HORIZONTAL_ALIGNMENT_CENTER, w)
	var t := int(st.duration)
	var cream := Color(0.95, 0.92, 0.85)
	_text(Vector2(x, y + 98), "%s after %d:%02d" % [String(st.reason).capitalize(), t / 60, t % 60], 24, cream, HORIZONTAL_ALIGNMENT_CENTER, w)
	# One table per team: champion, level, kills / deaths, damage, gold.
	var cols := [x + 40, x + w * 0.42, x + w * 0.55, x + w * 0.71, x + w * 0.86]
	var me: Unit = match_ctl.player() if match_ctl.human_slot else null
	var ty := y + 150
	for team in 2:
		var col := Palette.team_color(team)
		_text(Vector2(cols[0], ty), "%s   %d kills" % [Palette.TEAM_NAMES[team], st.kills[team]], 28, col, HORIZONTAL_ALIGNMENT_LEFT)
		var heads := ["Level", "K / D", "Damage", "Gold"]
		for i in heads.size():
			_text(Vector2(cols[i + 1], ty), heads[i], 20, Color(0.75, 0.72, 0.65), HORIZONTAL_ALIGNMENT_LEFT)
		ty += 38
		for u: Unit in match_ctl.champions:
			if u.team != team:
				continue
			var c: Dictionary = st.champions.get(u.name, {})
			if c.is_empty():
				continue
			if u == me:
				draw_rect(Rect2(x + 24, ty - 26, w - 48, 34), Color(col, 0.18))
			var label: String = u.def.display_name + ("  (you)" if u == me else "")
			_text(Vector2(cols[0], ty), label, 24, cream, HORIZONTAL_ALIGNMENT_LEFT)
			_text(Vector2(cols[1], ty), str(c.level), 24, cream, HORIZONTAL_ALIGNMENT_LEFT)
			_text(Vector2(cols[2], ty), "%d / %d" % [c.kills, c.deaths], 24, cream, HORIZONTAL_ALIGNMENT_LEFT)
			_text(Vector2(cols[3], ty), str(roundi(c.damage_to_champions)), 24, cream, HORIZONTAL_ALIGNMENT_LEFT)
			_text(Vector2(cols[4], ty), str(roundi(c.gold_earned)), 24, cream, HORIZONTAL_ALIGNMENT_LEFT)
			ty += 36
		ty += 30
	_text(Vector2(x, ty + 8), "Structures standing  Oath %d : %d Ruin      Shrinebearer  Oath %d : %d Ruin" % [st.structures_left[0], st.structures_left[1], st.objective_captures[0], st.objective_captures[1]], 22, cream, HORIZONTAL_ALIGNMENT_CENTER, w)

