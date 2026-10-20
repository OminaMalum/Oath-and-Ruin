class_name MatchHud
extends Control
## Match layer over the combat HUD: clock, kills, structure health, a marker
## on the next enemy structure, and the results screen.

var match_ctl: MatchController
var rig: CameraRig
var _font: Font
var _banner: String = ""
var _banner_t: float = 0.0
var _banner_col := Color.WHITE


func setup(m: MatchController, r: CameraRig) -> void:
	match_ctl = m
	rig = r
	m.match_over.connect(func(_w: int) -> void:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE)
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
		_small_bar(Rect2(x, 50, 56, 8), tw.health / tw.def.max_health if tw.alive else 0.0, col)
		_small_bar(Rect2(x + 64, 50, 56, 8), co.health / co.def.max_health if co.alive else 0.0, col)
	_text(Vector2(cx - 220, 74), "tower  core", 14, Color(0.85, 0.85, 0.8), HORIZONTAL_ALIGNMENT_LEFT)
	_marker()
	_objective_marker(vs)
	if _banner_t > 0.0:
		_text(Vector2(0, 128), _banner, 30, Color(_banner_col, clampf(_banner_t, 0.0, 1.0)), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	if match_ctl.over:
		_results(vs)


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


func _results(vs: Vector2) -> void:
	var st := match_ctl.stats
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.03, 0.03, 0.03, 0.6))
	var w := 640.0
	var x := (vs.x - w) * 0.5
	var y := vs.y * 0.2
	draw_rect(Rect2(x, y, w, 470), Color(0.12, 0.10, 0.09, 0.95))
	draw_rect(Rect2(x, y, w, 470), Palette.BRASS, false, 2.0)
	var title := "Victory" if match_ctl.winner == 0 else ("Defeat" if match_ctl.winner == 1 else "No winner")
	_text(Vector2(x, y + 60), title, 48, Palette.team_color(maxi(match_ctl.winner, 0)), HORIZONTAL_ALIGNMENT_CENTER, w)
	var t := int(st.duration)
	var lines := [
		"%s, %d:%02d" % [st.reason.capitalize(), t / 60, t % 60],
		"Kills  Oath %d  :  %d Ruin" % [st.kills[0], st.kills[1]],
		"Minions slain  Oath %d  :  %d Ruin" % [st.minions_killed[0], st.minions_killed[1]],
		"Structures standing  Oath %d  :  %d Ruin" % [st.structures_left[0], st.structures_left[1]],
		"First champion fight at %s" % ("%d s" % roundi(st.first_champion_fight) if st.first_champion_fight >= 0 else "never"),
		"Shrinebearer claimed  Oath %d  :  %d Ruin" % [st.objective_captures[0], st.objective_captures[1]],
	]
	var me: Dictionary = st.champions.get(match_ctl.player().name, {})
	if not me.is_empty():
		lines.append("You: %d kills, %d deaths, %d damage to champions" % [me.kills, me.deaths, roundi(me.damage_to_champions)])
	for i in lines.size():
		_text(Vector2(x, y + 120 + i * 40), lines[i], 24, Color(0.95, 0.92, 0.85), HORIZONTAL_ALIGNMENT_CENTER, w)
	_text(Vector2(x, y + 445), "R  play again      M  menu", 24, Palette.TEAL, HORIZONTAL_ALIGNMENT_CENTER, w)
