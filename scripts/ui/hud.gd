class_name Hud
extends Control
## Compact HUD drawn in code: reticle, own health, ability slots with
## cooldowns, world health bars, damage numbers and respawn timer.
## Large, high-contrast type throughout. Reads state, never writes it.

const FONT_SIZE := 22
const SMALL := 18

var authority: CombatAuthority
var player: Unit
var rig: CameraRig
var bot: SparringBot
var show_help: bool = true
## Connection message from the network session; empty when fine.
var status: String = ""

var _numbers: Array[Dictionary] = []
var _font: Font


func setup(a: CombatAuthority, p: Unit, r: CameraRig, b: SparringBot) -> void:
	authority = a
	player = p
	rig = r
	bot = b
	a.unit_damaged.connect(_on_damaged)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func _on_damaged(target: Unit, amount: float, _source: Unit) -> void:
	_numbers.append({"pos": target.global_position + Vector3(0, target.def.height + 0.4, 0),
		"text": str(roundi(amount)), "t": 0.0, "enemy": target.team != player.team})


func _process(delta: float) -> void:
	for n in _numbers:
		n.t += delta
		n.pos += Vector3(0, 1.2 * delta, 0)
	_numbers = _numbers.filter(func(n: Dictionary) -> bool: return n.t < 0.9)
	queue_redraw()


func _text(pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_CENTER, width := -1.0) -> void:
	# Dark outline keeps text readable over bright ground.
	draw_string_outline(_font, pos, s, align, width, size, 6, Color(0, 0, 0, 0.85))
	draw_string(_font, pos, s, align, width, size, col)


func _bar(rect: Rect2, frac: float, col: Color) -> void:
	draw_rect(rect.grow(2), Color(0.05, 0.04, 0.03, 0.85))
	draw_rect(rect, Color(0.18, 0.15, 0.12, 0.9))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(frac, 0, 1), rect.size.y)), col)


func _draw() -> void:
	if player == null or rig == null or rig.camera == null:
		return
	var vs := get_viewport_rect().size
	var cam := rig.camera
	# World bars and names.
	for u in authority.units:
		if not u.alive or u == player:
			continue  # own health is on the bottom bar; no duplicate over the head
		var top := u.get_global_transform_interpolated().origin + Vector3(0, u.def.height + 0.35, 0)
		if cam.is_position_behind(top):
			continue
		var p := cam.unproject_position(top)
		var w := 90.0 if u != player else 70.0
		var col := Palette.SELF_HEALTH if u == player else (Palette.ALLY if u.team == player.team else Palette.ENEMY)
		_bar(Rect2(p - Vector2(w * 0.5, 0), Vector2(w, 10)), u.health / u.def.max_health, col)
		if u.def.look != ChampionDef.Look.TRAINING_DUMMY:  # names for champions only; less clutter
			_text(p + Vector2(-100, -8), u.def.display_name, SMALL, Color(0.95, 0.92, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 200)
	for n in _numbers:
		if cam.is_position_behind(n.pos):
			continue
		var p := cam.unproject_position(n.pos)
		var a: float = 1.0 - n.t / 0.9
		var col := Color(1, 0.9, 0.55, a) if n.enemy else Color(1, 0.45, 0.35, a)
		_text(p + Vector2(10, -14), n.text, 30, col, HORIZONTAL_ALIGNMENT_CENTER, 100)

	# Reticle.
	var c := vs * 0.5
	var over_enemy := _reticle_on_enemy()
	var rc := Palette.ENEMY if over_enemy else Color(0.95, 0.93, 0.88)
	draw_arc(c, 11, 0, TAU, 32, Color(0, 0, 0, 0.6), 4)
	draw_arc(c, 11, 0, TAU, 32, rc, 2)
	draw_circle(c, 2.5, rc)

	# Own health, bottom centre.
	var hb := Rect2(Vector2(c.x - 220, vs.y - 128), Vector2(440, 26))
	_bar(hb, player.health / player.def.max_health, Palette.SELF_HEALTH)
	_text(Vector2(hb.position.x, hb.position.y + 21), "%d / %d" % [ceili(player.health), roundi(player.def.max_health)], FONT_SIZE, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, hb.size.x)
	_text(Vector2(hb.position.x - 230, hb.position.y + 21), player.def.display_name, FONT_SIZE, Color(0.95, 0.88, 0.7), HORIZONTAL_ALIGNMENT_RIGHT, 220)

	# Ability slots.
	var keys := ["LMB", "Q / RMB"]
	var slot_w := 150.0
	var x0 := c.x - (slot_w * player.def.slot_count() + 12 * (player.def.slot_count() - 1)) * 0.5
	for i in player.def.slot_count():
		var a := player.def.get_slot(i)
		var r := Rect2(Vector2(x0 + i * (slot_w + 12), vs.y - 92), Vector2(slot_w, 70))
		var cd := player.cooldowns[i] if player.alive else 0.0
		var casting := player.cast_slot == i and player.is_casting()
		draw_rect(r.grow(2), Palette.BRASS if casting else Color(0.08, 0.07, 0.06, 0.9))
		draw_rect(r, Color(0.16, 0.14, 0.12, 0.92))
		if cd > 0.0:
			var f := player.cooldown_fraction(i)
			draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * f)), Color(0, 0, 0, 0.55))
		_text(r.position + Vector2(0, 26), a.display_name, SMALL, Color(0.95, 0.92, 0.85), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		var label: String = keys[i] if i < keys.size() else ""
		if cd > 0.0 and a.cooldown >= 1.5:
			label = "%.1f" % cd
		_text(r.position + Vector2(0, 58), label, FONT_SIZE, Palette.TEAL if cd <= 0.0 else Color(0.85, 0.85, 0.85), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	if player.slow_timer > 0.0:
		_text(Vector2(hb.position.x, hb.position.y - 10), "Slowed", FONT_SIZE, Palette.AMBER, HORIZONTAL_ALIGNMENT_CENTER, hb.size.x)

	if not player.alive:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.05, 0.04, 0.04, 0.45))
		_text(Vector2(0, vs.y * 0.42), "Defeated", 48, Color(0.95, 0.85, 0.7), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		_text(Vector2(0, vs.y * 0.42 + 46), "Respawning in %.1f" % maxf(player.respawn_timer, 0.0), 30, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, vs.x)

	if not status.is_empty():
		_text(Vector2(0, vs.y * 0.22), status, 30, Palette.AMBER, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	if not rig.mouse_captured() and not rig.follow_unit_yaw:
		_text(Vector2(0, vs.y * 0.30), "Click to play", 36, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	if show_help:
		var lines := [
			"WASD  move     Mouse  aim and turn",
			"Left mouse (hold)  Arcane Bolt",
			"Q or right mouse  Binding Glyph",
			"F1  dummies fight back: %s" % ("ON" if bot and bot.enabled else "OFF") if bot else "Online test (server rules)",
			"F2  hide this     Esc  free the mouse",
		]
		for i in lines.size():
			_text(Vector2(24, 40 + i * 30), lines[i], FONT_SIZE, Color(0.95, 0.92, 0.85), HORIZONTAL_ALIGNMENT_LEFT)
	_text(Vector2(vs.x - 260, 36), "%d fps" % Engine.get_frames_per_second(), SMALL, Color(0.8, 0.8, 0.8), HORIZONTAL_ALIGNMENT_RIGHT, 236)


func _reticle_on_enemy() -> bool:
	var vp := get_viewport()
	var centre := vp.get_visible_rect().size * 0.5
	var from := rig.camera.project_ray_origin(centre)
	var to := from + rig.camera.project_ray_normal(centre) * 80.0
	var q := PhysicsRayQueryParameters3D.create(from, to, Unit.LAYER_WORLD | Unit.LAYER_UNITS, [player.get_rid()])
	var hit := rig.get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit.collider is Unit and (hit.collider as Unit).team != player.team
