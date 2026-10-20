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
var _notice: String = ""
var _notice_t: float = 0.0
var _hits_taken: Array[Dictionary] = []  # {from: Vector3, t}
var _font: Font


func setup(a: CombatAuthority, p: Unit, r: CameraRig, b: SparringBot) -> void:
	authority = a
	player = p
	rig = r
	bot = b
	a.unit_damaged.connect(_on_damaged)
	a.damage_blocked.connect(func(t: Unit, src: Unit) -> void:
		if src == player and t.protectors.size() > 0:
			notice("%s is protected by its tower" % t.def.display_name))
	p.cast_rejected.connect(func(_slot: int, reason: String) -> void: notice(reason))


## A short message above the ability bar explaining why something did not happen.
func notice(text: String) -> void:
	_notice = text
	_notice_t = 1.4


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func _on_damaged(target: Unit, amount: float, source: Unit) -> void:
	if target == player and source and is_instance_valid(source):
		_hits_taken.append({"from": source.global_position, "t": 0.0})
	_numbers.append({"pos": target.global_position + Vector3(0, target.def.height + 0.4, 0),
		"text": str(roundi(amount)), "t": 0.0, "enemy": target.team != player.team})


func _process(delta: float) -> void:
	for n in _numbers:
		n.t += delta
		n.pos += Vector3(0, 1.2 * delta, 0)
	_numbers = _numbers.filter(func(n: Dictionary) -> bool: return n.t < 0.9)
	for h in _hits_taken:
		h.t += delta
	_hits_taken = _hits_taken.filter(func(h: Dictionary) -> bool: return h.t < 1.2)
	_notice_t -= delta
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
		# Far units drop their bars and names: the top bar covers distant structures.
		var dist := cam.global_position.distance_to(top)
		if dist > 48.0:
			continue
		var p := cam.unproject_position(top)
		var minion := u.def.kind == ChampionDef.Kind.MINION and u.def.look != ChampionDef.Look.BREAKER
		var w := 56.0 if minion else 90.0
		var col := Palette.ALLY if u.team == player.team else (Palette.NEUTRAL if u.team >= 2 else Palette.ENEMY)
		_bar(Rect2(p - Vector2(w * 0.5, 0), Vector2(w, 8 if minion else 10)), u.health / u.max_health, col)
		# Names only for champions, structures and big units, and only up close.
		# Structures are named by the match HUD's next-target marker instead.
		if not minion and u.def.kind != ChampionDef.Kind.STRUCTURE and u.def.look != ChampionDef.Look.TRAINING_DUMMY and dist < 30.0:
			_text(p + Vector2(-100, -8), u.def.display_name, SMALL, Color(0.95, 0.92, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 200)
	for n in _numbers:
		if cam.is_position_behind(n.pos):
			continue
		var p := cam.unproject_position(n.pos)
		var a: float = 1.0 - n.t / 0.9
		var col := Color(1, 0.9, 0.55, a) if n.enemy else Color(1, 0.45, 0.35, a)
		_text(p + Vector2(10, -14), n.text, 30, col, HORIZONTAL_ALIGNMENT_CENTER, 100)

	# Reticle: white normally, amber on an enemy in range, grey with a label
	# when the enemy is out of range or a wall is in the way.
	var c := vs * 0.5
	var aim := _aim_state()
	var rc := Color(0.95, 0.93, 0.88)
	var tip_text := ""
	match aim:
		"in_range":
			rc = Palette.ENEMY
		"out_of_range":
			rc = Color(0.6, 0.6, 0.6)
			tip_text = "Out of range"
		"blocked":
			rc = Color(0.6, 0.6, 0.6)
			tip_text = "Blocked"
	draw_arc(c, 11, 0, TAU, 32, Color(0, 0, 0, 0.6), 4)
	draw_arc(c, 11, 0, TAU, 32, rc, 2)
	draw_circle(c, 2.5, rc)
	if aim == "blocked":
		draw_line(c + Vector2(-9, 9), c + Vector2(9, -9), Color(0, 0, 0, 0.7), 4)
		draw_line(c + Vector2(-9, 9), c + Vector2(9, -9), rc, 2)
	if not tip_text.is_empty():
		_text(c + Vector2(-100, 40), tip_text, SMALL, rc, HORIZONTAL_ALIGNMENT_CENTER, 200)
	# Where hits on you came from: a wedge around the reticle.
	for h in _hits_taken:
		var to: Vector3 = (h.from as Vector3) - player.global_position
		var ang := atan2(-to.x, -to.z) - rig.yaw  # 0 = straight ahead
		var dir := Vector2(-sin(ang), -cos(ang))
		var alpha := 1.0 - (h.t as float) / 1.2
		var tip := c + dir * 150.0
		var side := Vector2(-dir.y, dir.x) * 26.0
		var base_pt := c + dir * 118.0
		draw_colored_polygon(PackedVector2Array([tip, base_pt + side, base_pt - side]), Color(1.0, 0.35, 0.25, 0.8 * alpha))

	# Own health, bottom centre.
	var hb := Rect2(Vector2(c.x - 220, vs.y - 128), Vector2(440, 26))
	_bar(hb, player.health / player.max_health, Palette.SELF_HEALTH)
	_text(Vector2(hb.position.x, hb.position.y + 21), "%d / %d" % [ceili(player.health), roundi(player.max_health)], FONT_SIZE, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, hb.size.x)
	_text(Vector2(hb.position.x - 230, hb.position.y + 21), player.def.display_name, FONT_SIZE, Color(0.95, 0.88, 0.7), HORIZONTAL_ALIGNMENT_RIGHT, 220)
	if player.xp > 0.0 or player.level > 1:
		# Level and progress to the next one, right of the health bar.
		var lv_text := "Level %d" % player.level
		_text(Vector2(hb.position.x + hb.size.x + 14, hb.position.y + 21), lv_text, FONT_SIZE, Color(0.95, 0.88, 0.7), HORIZONTAL_ALIGNMENT_LEFT, 160)
		if player.level < Unit.LEVEL_XP.size():
			var lo := Unit.LEVEL_XP[player.level - 1]
			var hi := Unit.LEVEL_XP[player.level]
			_bar(Rect2(Vector2(hb.position.x + hb.size.x + 14, hb.position.y + 30), Vector2(120, 6)), (player.xp - lo) / (hi - lo), Palette.BRASS)
	if player.upgrade_pending:
		# The upgrade offer: two big cards above the ability bar, keys 1 and 2.
		var opts := player.upgrade_options()
		_text(Vector2(0, vs.y - 312), "Level %d: choose an upgrade for %s" % [Unit.UPGRADE_LEVEL, player.def.get_slot(1).display_name], FONT_SIZE, Color(0.95, 0.88, 0.7), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		for i in opts.size():
			var card := Rect2(Vector2(c.x - 410 + i * 420, vs.y - 290), Vector2(400, 140))
			draw_rect(card.grow(2), Palette.BRASS)
			draw_rect(card, Color(0.13, 0.11, 0.10, 0.95))
			_text(card.position + Vector2(16, 36), "%d   %s" % [i + 1, opts[i].display_name], 28, Palette.TEAL, HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 32)
			var desc := opts[i].description.trim_prefix("Upgrade: ")
			var font := get_theme_default_font()
			draw_multiline_string(font, card.position + Vector2(16, 72), desc, HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 32, 20, 3, Color(0.92, 0.90, 0.84))

	# Ability slots.
	var q := player.get_slot(1)
	var keys := ["LMB", "Q hold / RMB" if q and q.delivery == AbilityDef.Delivery.GROUND_AREA else "Q / RMB"]
	var slot_w := 150.0
	var x0 := c.x - (slot_w * player.def.slot_count() + 12 * (player.def.slot_count() - 1)) * 0.5
	for i in player.def.slot_count():
		var a := player.get_slot(i)
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
	if _notice_t > 0.0:
		_text(Vector2(0, vs.y - 140), _notice, FONT_SIZE, Color(1.0, 0.85, 0.55, clampf(_notice_t * 2.0, 0, 1)), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
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
			"Left mouse (hold)  %s" % player.get_slot(0).display_name,
			("Q hold and release, or right mouse  %s" if player.get_slot(1).delivery == AbilityDef.Delivery.GROUND_AREA \
				else "Q or right mouse  %s") % player.get_slot(1).display_name,
			"1 or 2  pick an upgrade when offered" if player.upgrade_pending else "",
			("F1  dummies fight back: %s" % ("ON" if bot.enabled else "OFF")) if bot else "",
			"F2  hide this     Esc  free the mouse",
		]
		for i in lines.size():
			_text(Vector2(24, 40 + i * 30), lines[i], FONT_SIZE, Color(0.95, 0.92, 0.85), HORIZONTAL_ALIGNMENT_LEFT)
	_text(Vector2(vs.x - 260, 36), "%d fps" % Engine.get_frames_per_second(), SMALL, Color(0.8, 0.8, 0.8), HORIZONTAL_ALIGNMENT_RIGHT, 236)


## "none", "in_range", "out_of_range" or "blocked" for the basic attack,
## judged the way the game will judge the shot: from the champion's muzzle,
## flat, against walls and range.
func _aim_state() -> String:
	if not player.alive or player.def.basic_attack == null:
		return "none"
	var aim := rig.get_aim_point(player)
	var muzzle := player.muzzle_position()
	var flat := Vector3(aim.x - muzzle.x, 0.0, aim.z - muzzle.z)
	var vp := get_viewport()
	var centre := vp.get_visible_rect().size * 0.5
	var from := rig.camera.project_ray_origin(centre)
	var to := from + rig.camera.project_ray_normal(centre) * 80.0
	var space := rig.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, Unit.LAYER_WORLD | Unit.LAYER_UNITS, [player.get_rid()]))
	var enemy: Unit = null
	if not hit.is_empty() and hit.collider is Unit and (hit.collider as Unit).team != player.team:
		enemy = hit.collider
	# Would the bolt's flat path hit a wall before reaching the aim point?
	var reach := minf(flat.length(), player.def.basic_attack.range)
	if reach > 1.0:
		var end := muzzle + flat.normalized() * reach
		var wall := space.intersect_ray(PhysicsRayQueryParameters3D.create(muzzle, end, Unit.LAYER_WORLD))
		if not wall.is_empty() and (enemy != null or reach - muzzle.distance_to(wall.position) > 1.5):
			return "blocked"
	if enemy:
		var d := UnitController.flat_distance(player.global_position, enemy.global_position) - enemy.def.radius
		return "in_range" if d <= player.def.basic_attack.range else "out_of_range"
	return "none"
