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
var show_help: bool = false
## Connection message from the network session; empty when fine.
var status: String = ""

var _numbers: Array[Dictionary] = []
var _notice: String = ""
var _notice_t: float = 0.0
var _hits_taken: Array[Dictionary] = []  # {from: Vector3, t}
var _font: Font
## Adventurer shop hit boxes from the last draw: {rect, buy|sell, index}.
var _shop_hits: Array[Dictionary] = []
## Item under the mouse (shop, own items or the HUD item row) and where.
var _tip_item: ItemDef
var _mouse := Vector2.ZERO
## HUD hit boxes outside the shop: item row tiles and the recall button.
var _hud_hits: Array[Dictionary] = []
## Screenshots: hold the Alt panel open, or show the card of own item N.
var force_details: bool = false
var force_tip: int = 0
## Adventurer shop page: 0 parts (starters, boots, components), 1 finished.
var shop_tab: int = 0


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
	p.gold_earned.connect(func(g: float, at: Vector3) -> void:
		_numbers.append({"pos": at + Vector3(0, 2.2, 0), "text": "+%d gold" % roundi(g), "t": 0.0, "gold": true, "life": 1.4}))
	p.recall_cancelled.connect(func(reason: String) -> void: notice(reason))
	p.item_bought.connect(func(it: ItemDef) -> void: notice("Bought %s" % it.display_name))
	p.item_sold.connect(func(it: ItemDef, g: float) -> void: notice("Sold %s for %d gold" % [it.display_name, roundi(g)]))


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
	# Hierarchy: numbers only for what the viewer did or took. Other fights keep
	# their bars and tells but do not spray numbers over the scene.
	if target != player and source != player:
		return
	_numbers.append({"pos": target.global_position + Vector3(0, target.def.height + 0.4, 0),
		"text": str(roundi(amount)) if amount >= 0.5 else "Shield", "t": 0.0, "enemy": target.team != player.team})


func _process(delta: float) -> void:
	for n in _numbers:
		n.t += delta
		n.pos += Vector3(0, 1.2 * delta, 0)
	_numbers = _numbers.filter(func(n: Dictionary) -> bool: return n.t < n.get("life", 0.9))
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
	# World bars and names. Labels that would overlap an earlier one move up.
	var placed: Array[Rect2] = []
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
		var champ := u.def.kind == ChampionDef.Kind.CHAMPION
		var w := 48.0 if minion else (110.0 if champ else 90.0)
		if not minion:
			var box := Rect2(p - Vector2(w * 0.5, 22), Vector2(w, 34))
			for _try in 4:
				var clash := false
				for r in placed:
					if r.intersects(box):
						clash = true
						break
				if not clash:
					break
				box.position.y -= 34
			placed.append(box)
			p = box.position + Vector2(w * 0.5, 22)
		var tag := "stunned" if u.is_stunned() else ("taunted" if u.compel == Unit.Compel.TAUNT and u.compel_timer > 0.0 \
				else ("charmed" if u.compel == Unit.Compel.CHARM and u.compel_timer > 0.0 \
				else ("rooted" if u.root_timer > 0.0 else ("marked" if u.mark_timer > 0.0 else ""))))
		if not tag.is_empty():
			_text(p + Vector2(-100, 26), tag, SMALL, Color(1.0, 0.5, 0.4) if tag == "stunned" else Color(0.95, 0.85, 0.55), HORIZONTAL_ALIGNMENT_CENTER, 200)
		var col := Palette.ALLY if u.team == player.team else (Palette.NEUTRAL if u.team >= 2 else Palette.ENEMY)
		_bar(Rect2(p - Vector2(w * 0.5, 0), Vector2(w, 6 if minion else (12 if champ else 10))), u.health / u.max_health, col)
		# Names only for champions, structures and big units, and only up close.
		# Structures are named by the match HUD's next-target marker instead.
		if not minion and u.def.kind != ChampionDef.Kind.STRUCTURE and u.def.look != ChampionDef.Look.TRAINING_DUMMY and dist < 30.0:
			var nw := _font.get_string_size(u.def.display_name, HORIZONTAL_ALIGNMENT_CENTER, -1, SMALL).x + 12.0
			draw_rect(Rect2(p + Vector2(-nw * 0.5, -24), Vector2(nw, 22)), Color(0.05, 0.04, 0.03, 0.7))
			_text(p + Vector2(-100, -7), u.def.display_name, SMALL, col.lightened(0.35), HORIZONTAL_ALIGNMENT_CENTER, 200)
	for n in _numbers:
		if cam.is_position_behind(n.pos):
			continue
		var p := cam.unproject_position(n.pos)
		var a: float = 1.0 - n.t / n.get("life", 0.9)
		if n.get("gold", false):
			var gc := Palette.GOLD
			gc.a = a
			_text(p + Vector2(-90, -40), n.text, 30, Color(0, 0, 0, 0.7 * a), HORIZONTAL_ALIGNMENT_CENTER, 182)
			_text(p + Vector2(-92, -42), n.text, 30, gc, HORIZONTAL_ALIGNMENT_CENTER, 182)
			continue
		var col := Color(1, 0.9, 0.55, a) if n.enemy else Color(1, 0.45, 0.35, a)
		_text(p + Vector2(10, -14), n.text, 26, col, HORIZONTAL_ALIGNMENT_CENTER, 100)

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

	# Own health, bottom centre, on one translucent panel with the ability slots.
	var following := rig.follow_unit_yaw
	var hb := Rect2(Vector2(c.x - 220, vs.y - 128), Vector2(440, 26))
	draw_rect(Rect2(Vector2(c.x - 470, vs.y - 140), Vector2(1000 if player.shop_point.is_finite() else 940, 128)), Color(0.06, 0.05, 0.04, 0.55))
	_bar(hb, player.health / player.max_health, Palette.SELF_HEALTH)
	if player.shield > 0.0:
		# The shield sits after the health, pale gold, as far as the bar goes.
		var from := hb.size.x * clampf(player.health / player.max_health, 0.0, 1.0)
		var w := minf(hb.size.x * player.shield / player.max_health, hb.size.x - from)
		draw_rect(Rect2(hb.position + Vector2(from, 0), Vector2(maxf(w, 3.0), hb.size.y)), Color(0.98, 0.92, 0.72))
	_text(Vector2(hb.position.x, hb.position.y + 22), "%d / %d" % [ceili(player.health), ceili(player.max_health)], 24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, hb.size.x)
	_text(Vector2(hb.position.x - 230, hb.position.y + 21), player.def.display_name, FONT_SIZE, Color(0.95, 0.88, 0.7), HORIZONTAL_ALIGNMENT_RIGHT, 220)
	if player.xp > 0.0 or player.level > 1:
		# Level and progress to the next one, right of the health bar.
		var lv_text := "Level %d" % player.level
		_text(Vector2(hb.position.x + hb.size.x + 14, hb.position.y + 21), lv_text, FONT_SIZE, Color(0.95, 0.88, 0.7), HORIZONTAL_ALIGNMENT_LEFT, 160)
		if player.level < Unit.LEVEL_XP.size():
			var lo := Unit.LEVEL_XP[player.level - 1]
			var hi := Unit.LEVEL_XP[player.level]
			_bar(Rect2(Vector2(hb.position.x + hb.size.x + 14, hb.position.y + 26), Vector2(120, 6)), (player.xp - lo) / (hi - lo), Palette.BRASS)
	var shop := HumanController.shop_open and player.shop_point.is_finite() and not following
	if player.shop_point.is_finite():
		# Gold, right above the level, in big pale yellow digits.
		var gr := Rect2(Vector2(c.x + 300, vs.y - 182), Vector2(170, 38))
		draw_rect(gr, Color(0.06, 0.05, 0.04, 0.7))
		_text(gr.position + Vector2(0, 28), "%d gold" % floori(player.gold), 26, Palette.GOLD, HORIZONTAL_ALIGNMENT_CENTER, gr.size.x)
		if not shop and player.can_shop() and not following:
			var tr := Rect2(Vector2(c.x + 300, vs.y - 222), Vector2(170, 34))
			draw_rect(tr, Color(0.06, 0.05, 0.04, 0.7))
			_text(tr.position + Vector2(0, 25), "B  shop", FONT_SIZE, Palette.TEAL, HORIZONTAL_ALIGNMENT_CENTER, tr.size.x)
	if player.upgrade_pending and not shop:
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
	var keys := ["LMB", "Q hold / RMB" if q and q.delivery == AbilityDef.Delivery.GROUND_AREA else "Q / RMB", "E", "R", "F"]
	var slot_w := 150.0
	var n := player.def.slot_count()
	var x0 := c.x - (slot_w * n + 12 * (n - 1)) * 0.5
	# Drawn in keyboard order, so the ultimate (slot 3, R) sits last after F.
	var order := [0, 1, 2, 4, 3] if n == 5 else range(n)
	for pos in n:
		var i: int = order[pos]
		var a := player.get_slot(i)
		var r := Rect2(Vector2(x0 + pos * (slot_w + 12), vs.y - 92), Vector2(slot_w, 70))
		var cd := player.ready_in(i) if player.alive else 0.0
		var casting := player.cast_slot == i and player.is_casting()
		var locked := a.is_ultimate and not player.ultimate_ready_level()
		var unavailable := not player.alive or player.is_stunned()
		# Four states, each with its own look: ready (teal key, bright edge),
		# cooling (dark fill rising, time in big digits), locked (dark, a lock
		# mark and the level), unavailable (grey, dead or stunned).
		var edge := Palette.BRASS if casting else (Palette.TEAL if cd <= 0.0 and not locked and not unavailable else Color(0.08, 0.07, 0.06, 0.9))
		draw_rect(r.grow(2), edge)
		draw_rect(r, Color(0.16, 0.14, 0.12, 0.96) if not locked else Color(0.09, 0.08, 0.07, 0.96))
		if cd > 0.0 and not locked:
			var f := player.cooldown_fraction(i)
			draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * f)), Color(0, 0, 0, 0.6))
		if unavailable:
			draw_rect(r, Color(0.3, 0.3, 0.3, 0.5))
		# Long names shrink to fit the slot instead of being cut off.
		var name_size := SMALL
		while name_size > 14 and _font.get_string_size(a.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x > r.size.x - 10:
			name_size -= 1
		_text(r.position + Vector2(0, 24), a.display_name, name_size, Color(0.95, 0.92, 0.85) if not locked else Color(0.6, 0.58, 0.55), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		var label: String = keys[i] if i < keys.size() else ""
		var lcol := Palette.TEAL
		if locked:
			# A small padlock drawn in vector: a body and a shackle.
			var lp := r.position + Vector2(r.size.x * 0.5 - 38, 40)
			draw_rect(Rect2(lp + Vector2(0, 8), Vector2(14, 11)), Color(0.75, 0.72, 0.68))
			draw_arc(lp + Vector2(7, 8), 5, PI, TAU, 10, Color(0.75, 0.72, 0.68), 2.5)
			label = "Lv %d" % Unit.ULT_LEVEL
			lcol = Color(0.75, 0.72, 0.68)
		elif cd > 0.0 and a.cooldown >= 1.5 and not (player.is_charged(i) and player.charges[i] > 0):
			label = "%.1f" % cd
			lcol = Color(0.95, 0.9, 0.8)
		elif unavailable:
			lcol = Color(0.6, 0.6, 0.6)
		_text(r.position + Vector2(0, 58), label, 26 if cd > 0.0 and not locked else FONT_SIZE, lcol, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		if player.is_charged(i):
			# Charges: one big pip per use, filled while it is ready.
			for k in a.max_charges:
				var pc := r.position + Vector2(r.size.x - 16 - k * 20, 50)
				draw_circle(pc, 7, Color(0.05, 0.05, 0.05, 0.9))
				if k < player.charges[i]:
					draw_circle(pc, 5.5, Palette.TEAL)

	var pr := passive_readout(player)
	if not pr.is_empty() and not player.upgrade_pending:
		# The passive's count, left of the gold, on its own dark plate.
		var prr := Rect2(Vector2(c.x + 20, vs.y - 182), Vector2(270, 38))
		draw_rect(prr, Color(0.06, 0.05, 0.04, 0.7))
		_text(prr.position + Vector2(0, 27), pr, FONT_SIZE, Palette.TEAL, HORIZONTAL_ALIGNMENT_CENTER, prr.size.x)
	if player.recall_timer > 0.0:
		# Recall: a bar filling toward home above the ability bar.
		var rr := Rect2(Vector2(c.x - 200, vs.y - 236), Vector2(400, 22))
		var f := 1.0 - player.recall_timer / Unit.ECONOMY.recall_time
		_text(Vector2(rr.position.x, rr.position.y - 10), "Recalling home  %.1f" % player.recall_timer, FONT_SIZE, Palette.TEAL, HORIZONTAL_ALIGNMENT_CENTER, rr.size.x)
		draw_rect(rr.grow(2), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(rr.position, Vector2(rr.size.x * f, rr.size.y)), Palette.TEAL)
	_hud_hits.clear()
	if player.shop_point.is_finite():
		_draw_recall_button(Rect2(Vector2(x0 + n * (slot_w + 12), vs.y - 92), Vector2(110, 70)))
		if not player.upgrade_pending:
			_draw_item_row(Rect2(Vector2(c.x - 470, vs.y - 182), Vector2(480, 38)))
	if _notice_t > 0.0:
		_text(Vector2(0, vs.y - 140), _notice, FONT_SIZE, Color(1.0, 0.85, 0.55, clampf(_notice_t * 2.0, 0, 1)), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	if player.is_stunned():
		_text(Vector2(hb.position.x, hb.position.y - 10), "Stunned", FONT_SIZE, Color(1.0, 0.45, 0.35), HORIZONTAL_ALIGNMENT_CENTER, hb.size.x)
	elif player.compel_timer > 0.0 and player.compel == Unit.Compel.TAUNT:
		_text(Vector2(hb.position.x, hb.position.y - 10), "Taunted: you must attack the Barrowking", FONT_SIZE, Palette.AMBER, HORIZONTAL_ALIGNMENT_CENTER, hb.size.x)
	elif player.compel_timer > 0.0 and player.compel == Unit.Compel.CHARM:
		_text(Vector2(hb.position.x, hb.position.y - 10), "Charmed: you walk away", FONT_SIZE, Palette.AMBER, HORIZONTAL_ALIGNMENT_CENTER, hb.size.x)
	elif player.root_timer > 0.0:
		_text(Vector2(hb.position.x, hb.position.y - 10), "Rooted: you can attack but not move", FONT_SIZE, Palette.AMBER, HORIZONTAL_ALIGNMENT_CENTER, hb.size.x)
	elif player.mark_timer > 0.0:
		_text(Vector2(hb.position.x, hb.position.y - 10), "Marked: you take more damage", FONT_SIZE, Palette.AMBER, HORIZONTAL_ALIGNMENT_CENTER, hb.size.x)
	elif player.brace_timer > 0.0:
		_text(Vector2(hb.position.x, hb.position.y - 10), "Braced: the next hit from the front is softened", FONT_SIZE, Palette.TEAL, HORIZONTAL_ALIGNMENT_CENTER, hb.size.x)
	elif player.weaken_timer > 0.0:
		_text(Vector2(hb.position.x, hb.position.y - 10), "Weakened: you deal less damage", FONT_SIZE, Palette.AMBER, HORIZONTAL_ALIGNMENT_CENTER, hb.size.x)
	elif player.slow_timer > 0.0:
		_text(Vector2(hb.position.x, hb.position.y - 10), "Slowed", FONT_SIZE, Palette.AMBER, HORIZONTAL_ALIGNMENT_CENTER, hb.size.x)
	elif player.haste_timer > 0.0:
		_text(Vector2(hb.position.x, hb.position.y - 10), "Song: you attack faster", FONT_SIZE, Palette.TEAL, HORIZONTAL_ALIGNMENT_CENTER, hb.size.x)

	if not player.alive and not following:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.05, 0.04, 0.04, 0.45))
		var dy := vs.y * (0.16 if shop else 0.42)
		_text(Vector2(0, dy), "Defeated", 48, Color(0.95, 0.85, 0.7), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		_text(Vector2(0, dy + 46), "Respawning in %.1f" % maxf(player.respawn_timer, 0.0), 30, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		if player.shop_point.is_finite() and not shop:
			_text(Vector2(0, dy + 90), "Press B to shop while you wait", FONT_SIZE, Palette.TEAL, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	_shop_hits.clear()
	if shop and ItemShop.adventurer():
		_draw_adventurer_shop(vs, c)
	elif shop:
		_draw_shop(vs, c)
	if following:
		# Spectating a bot: a small line instead of the death overlay, so the
		# match stays in view.
		var fl := "Following %s (%s)" % [player.def.display_name, Palette.TEAM_NAMES[player.team]]
		if not player.alive:
			fl += ", respawning in %d s" % ceili(maxf(player.respawn_timer, 0.0))
		draw_rect(Rect2(Vector2(16, vs.y - 262), Vector2(_font.get_string_size(fl, HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL).x + 24, 30)), Color(0.06, 0.05, 0.04, 0.7))
		_text(Vector2(24, vs.y - 240), fl, SMALL, Color(0.92, 0.9, 0.84), HORIZONTAL_ALIGNMENT_LEFT)

	if not status.is_empty():
		_text(Vector2(0, vs.y * 0.22), status, 30, Palette.AMBER, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	if not rig.mouse_captured() and not rig.follow_unit_yaw and not HumanController.shop_open:
		_text(Vector2(0, vs.y * 0.30), "Click to play", 36, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	if not show_help:
		draw_rect(Rect2(Vector2(16, 16), Vector2(150, 30)), Color(0.06, 0.05, 0.04, 0.6))
		_text(Vector2(24, 38), "F2  controls", SMALL, Color(0.85, 0.82, 0.75), HORIZONTAL_ALIGNMENT_LEFT)
	else:
		var lines := [
			"WASD  move     Mouse  aim and turn",
			"Left mouse (hold)  %s" % player.get_slot(0).display_name,
			("Q hold and release, or right mouse  %s" if player.get_slot(1).delivery == AbilityDef.Delivery.GROUND_AREA \
				else "Q or right mouse  %s") % player.get_slot(1).display_name,
			("E  %s" % player.get_slot(2).display_name) if player.get_slot(2) else "",
			("F  %s" % player.get_slot(4).display_name) if player.get_slot(4) else "",
			("R  %s (ultimate, level %d)" % [player.get_slot(3).display_name, Unit.ULT_LEVEL]) if player.get_slot(3) else "",
			"1 or 2  pick an upgrade when offered" if player.upgrade_pending else "",
			"B  shop at your fountain or while dead, then 1 to 4 to buy" if player.shop_point.is_finite() else "",
			"T  recall home (stand still %d s)     Tab (hold)  scoreboard" % roundi(Unit.ECONOMY.recall_time) if player.shop_point.is_finite() else "",
			"Alt (hold)  item details     Mouse over an item in the shop  its details" if player.shop_point.is_finite() else "",
			("F1  dummies fight back: %s" % ("ON" if bot.enabled else "OFF")) if bot else "",
			"F2  hide this     Esc  menu",
			("%s: %s" % [player.def.passive_name, player.def.passive_description]) if not player.def.passive_name.is_empty() else "",
		]
		lines = lines.filter(func(l: String) -> bool: return not l.is_empty())
		draw_rect(Rect2(Vector2(16, 16), Vector2(720, 14 + lines.size() * 30)), Color(0.06, 0.05, 0.04, 0.75))
		for i in lines.size():
			_text(Vector2(24, 40 + i * 30), lines[i], FONT_SIZE, Color(0.95, 0.92, 0.85), HORIZONTAL_ALIGNMENT_LEFT)
	if (force_details or Input.is_action_pressed("item_details")) and not shop and player.shop_point.is_finite():
		_draw_item_details(vs, c)
	if force_tip > 0 and force_tip <= player.items.size():
		_draw_tooltip(player.items[force_tip - 1], Vector2(c.x - 300, vs.y - 170), vs)
	elif _tip_item and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		_draw_tooltip(_tip_item, _mouse, vs)
	# Frame rate: hidden in movie writer captures, where it would only measure
	# how fast frames were written offline, not how the game runs.
	if not OS.has_feature("movie"):
		_text(Vector2(vs.x - 260, 36), "%d fps" % Engine.get_frames_per_second(), SMALL, Color(0.8, 0.8, 0.8), HORIZONTAL_ALIGNMENT_RIGHT, 236)


## The shop: one big row per item with its key, name, what it does and its
## price. Owned items say so; ones you cannot afford yet are greyed with the
## gold still needed. Away from the fountain the header says where to go.
func _draw_shop(vs: Vector2, c: Vector2) -> void:
	var eco := Unit.ECONOMY
	var row_h := 54.0
	var w := 920.0
	var top := vs.y - 196.0 - 64.0 - row_h * eco.items.size()
	var panel := Rect2(Vector2(c.x - w * 0.5, top), Vector2(w, 64.0 + row_h * eco.items.size() + 12.0))
	draw_rect(panel.grow(2), Palette.BRASS)
	draw_rect(panel, Color(0.10, 0.09, 0.08, 0.95))
	var open := player.can_shop()
	var head := "Shop    %d gold    %d of %d slots used" % [floori(player.gold), player.items.size(), eco.slots] if open \
		else "The shop opens at your fountain or while you respawn"
	_text(panel.position + Vector2(20, 42), head, 26, Palette.GOLD if open else Color(0.85, 0.82, 0.75), HORIZONTAL_ALIGNMENT_LEFT, w - 140)
	_text(panel.position + Vector2(w - 130, 42), "B  close", FONT_SIZE, Palette.TEAL, HORIZONTAL_ALIGNMENT_RIGHT, 110)
	for i in eco.items.size():
		var it: ItemDef = eco.items[i]
		var r := Rect2(panel.position + Vector2(12, 60 + i * row_h), Vector2(w - 24, row_h - 8))
		var owned := player.items.has(it)
		var short := ceili(it.cost - player.gold)
		var ready := open and not owned and short <= 0 and player.items.size() < eco.slots
		draw_rect(r, Color(0.18, 0.16, 0.13, 0.95) if ready else Color(0.13, 0.12, 0.10, 0.95))
		if ready:
			draw_rect(Rect2(r.position, Vector2(6, r.size.y)), Palette.TEAL)
		var main := Color(0.96, 0.93, 0.86) if not owned else Color(0.62, 0.60, 0.56)
		if not ready and not owned:
			main = Color(0.75, 0.72, 0.68)
		_text(r.position + Vector2(18, 33), str(i + 1), 28, Palette.TEAL if ready else Color(0.6, 0.6, 0.58), HORIZONTAL_ALIGNMENT_LEFT, 30)
		_text(r.position + Vector2(60, 33), it.display_name, 26, main, HORIZONTAL_ALIGNMENT_LEFT, 250)
		_text(r.position + Vector2(310, 33), it.description, FONT_SIZE, main, HORIZONTAL_ALIGNMENT_LEFT, 380)
		var price := "Owned" if owned else ("%d" % it.cost if short <= 0 else "%d  (need %d)" % [it.cost, short])
		_text(r.position + Vector2(r.size.x - 200, 33), price, FONT_SIZE, Palette.GOLD if ready else main, HORIZONTAL_ALIGNMENT_RIGHT, 186)


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


## Adventurer shop: suggestion, catalog in columns, own items. Click to buy,
## right click an own item to sell, 1 buys the suggestion. Big type, one line
## per fact; the hovered item's full text sits at the bottom.
func _draw_adventurer_shop(vs: Vector2, c: Vector2) -> void:
	var eco := Unit.ECONOMY
	var w := minf(vs.x - 40.0, 1240.0)
	var top := 64.0
	var panel := Rect2(Vector2(c.x - w * 0.5, top), Vector2(w, vs.y - 215.0 - top))
	draw_rect(panel.grow(2), Palette.BRASS)
	draw_rect(panel, Color(0.10, 0.09, 0.08, 0.96))
	var open := player.can_shop()
	var x0 := panel.position.x + 16.0
	var y := panel.position.y + 38.0
	var head := "Shop    %d gold" % floori(player.gold) if open else "The shop opens at your fountain or while you respawn"
	_text(Vector2(x0, y), head, 26, Palette.GOLD if open else Color(0.85, 0.82, 0.75), HORIZONTAL_ALIGNMENT_LEFT, w - 300)
	_text(Vector2(x0, y), "B closes", FONT_SIZE, Palette.TEAL, HORIZONTAL_ALIGNMENT_RIGHT, w - 32)
	# Two pages, picked by clicking a tab: parts and boots, or finished items.
	var tab_w := 190.0
	for t in 2:
		var tr := Rect2(Vector2(panel.end.x - 16.0 - 130.0 - (2 - t) * (tab_w + 8.0), panel.position.y + 10.0), Vector2(tab_w, 38))
		var on := shop_tab == t
		draw_rect(tr, Color(0.22, 0.20, 0.16, 0.98) if on else Color(0.13, 0.12, 0.10, 0.95))
		if on:
			draw_rect(Rect2(Vector2(tr.position.x, tr.end.y - 4.0), Vector2(tr.size.x, 4.0)), Palette.TEAL)
		_text(tr.position + Vector2(0, 27), ["Parts and boots", "Finished items"][t], FONT_SIZE, Color(0.96, 0.93, 0.86) if on else Color(0.72, 0.70, 0.66), HORIZONTAL_ALIGNMENT_CENTER, tr.size.x)
		_shop_hits.append({"rect": tr, "tab": t})
	# Suggestion along the champion's build.
	y += 16.0
	var next := ItemShop.next_step(player)
	var sug := Rect2(Vector2(x0, y), Vector2(w - 32, 52))
	if next > 0:
		var it: ItemDef = eco.items[next - 1]
		var plan := player.purchase_plan(next)
		var ready: bool = (plan.problem as String).is_empty()
		draw_rect(sug, Color(0.18, 0.16, 0.13, 0.95) if ready else Color(0.13, 0.12, 0.10, 0.95))
		if ready:
			draw_rect(Rect2(sug.position, Vector2(6, sug.size.y)), Palette.TEAL)
		_text(sug.position + Vector2(18, 35), "1", 28, Palette.TEAL if ready else Color(0.6, 0.6, 0.58), HORIZONTAL_ALIGNMENT_LEFT, 30)
		_text(sug.position + Vector2(56, 35), "Next for you:  %s" % it.display_name, 24, Color(0.96, 0.93, 0.86), HORIZONTAL_ALIGNMENT_LEFT, sug.size.x - 300)
		_text(sug.position + Vector2(0, 35), _price_text(next, plan), FONT_SIZE, Palette.GOLD if ready else Color(0.75, 0.72, 0.68), HORIZONTAL_ALIGNMENT_RIGHT, sug.size.x - 16)
		_shop_hits.append({"rect": sug, "buy": next, "item": it})
	else:
		draw_rect(sug, Color(0.13, 0.12, 0.10, 0.95))
		_text(sug.position + Vector2(18, 35), "Your build is complete", 24, Color(0.75, 0.72, 0.68), HORIZONTAL_ALIGNMENT_LEFT, sug.size.x)
	y += 70.0
	# Catalog, four columns of up to four. Parts page: Starters | Boots |
	# Components (two columns). Finished page: Weapon | Spell | Defence | Utility.
	var cols := [["Starters", "starter", 1], ["Boots", "boots", 1], ["Components", "component", 2]]
	if shop_tab == 1:
		cols = [["Weapon", "weapon", 1], ["Spell", "spell", 1], ["Defence", "defence", 1], ["Utility", "utility", 1]]
	var col_w := (w - 32.0 - 3 * 10.0) / 4.0
	var cell_h := minf(70.0, (panel.end.y - y - 150.0) / 4.0)
	var cx := x0
	for col in cols:
		var group: String = col[1]
		var span: int = col[2]
		_text(Vector2(cx, y + 20), col[0], FONT_SIZE, Color(0.85, 0.80, 0.70), HORIZONTAL_ALIGNMENT_LEFT, col_w * span)
		var n := 0
		for i in eco.items.size():
			var it: ItemDef = eco.items[i]
			if shop_group(it) != group:
				continue
			var r := Rect2(Vector2(cx + (n / 4) * (col_w + 10.0), y + 32.0 + (n % 4) * (cell_h + 6.0)), Vector2(col_w, cell_h))
			_draw_item_cell(r, i + 1)
			n += 1
		cx += span * (col_w + 10.0)
	# Own items: right click sells.
	var iy := panel.end.y - 112.0
	_text(Vector2(x0, iy), "Your items  (right click to sell)", FONT_SIZE, Color(0.85, 0.80, 0.70), HORIZONTAL_ALIGNMENT_LEFT, w)
	var sw := (w - 32.0 - (eco.slots - 1) * 10.0) / eco.slots
	for s in eco.slots:
		var r := Rect2(Vector2(x0 + s * (sw + 10.0), iy + 10.0), Vector2(sw, 48))
		draw_rect(r, Color(0.16, 0.14, 0.12, 0.95))
		if s < player.items.size():
			var it: ItemDef = player.items[s]
			_text(r.position + Vector2(10, 22), it.display_name, 20, Color(0.96, 0.93, 0.86), HORIZONTAL_ALIGNMENT_LEFT, sw - 16)
			_text(r.position + Vector2(10, 43), "sell %d" % roundi(player.sell_value(s + 1)), 20, Palette.GOLD, HORIZONTAL_ALIGNMENT_LEFT, sw - 16)
			_shop_hits.append({"rect": r, "sell": s + 1, "item": it})
		else:
			_text(r.position + Vector2(0, 31), "empty", SMALL, Color(0.5, 0.48, 0.45), HORIZONTAL_ALIGNMENT_CENTER, sw)
	_text(Vector2(x0, panel.end.y - 14.0), "Mouse over an item for its details", SMALL, Color(0.72, 0.70, 0.66), HORIZONTAL_ALIGNMENT_LEFT, w - 32)


## Which shop column an adventurer item sits in.
static func shop_group(it: ItemDef) -> String:
	match it.kind:
		ItemDef.Kind.STARTER:
			return "starter"
		ItemDef.Kind.BOOTS:
			return "boots"
		ItemDef.Kind.COMPONENT:
			return "component"
	if it.passive in [ItemDef.Passive.ASHEN, ItemDef.Passive.LANTERN, ItemDef.Passive.CANTOR, ItemDef.Passive.HARNESS]:
		return "utility"
	if it.weapon_power > 0.0:
		return "weapon"
	if it.spell_power > 0.0:
		return "spell"
	return "defence"


func _draw_item_cell(r: Rect2, index: int) -> void:
	var it: ItemDef = Unit.ECONOMY.items[index - 1]
	var plan := player.purchase_plan(index)
	var owned := it.kind != ItemDef.Kind.COMPONENT and player.items.has(it)
	var ready: bool = (plan.problem as String).is_empty()
	draw_rect(r, Color(0.18, 0.16, 0.13, 0.95) if ready else Color(0.13, 0.12, 0.10, 0.95))
	if ready:
		draw_rect(Rect2(r.position, Vector2(5, r.size.y)), Palette.TEAL)
	var main := Color(0.96, 0.93, 0.86) if ready else Color(0.72, 0.70, 0.66)
	# Long names step down a size rather than being cut.
	var name_size := FONT_SIZE
	while name_size > 16 and _font.get_string_size(it.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x > r.size.x - 20:
		name_size -= 1
	_text(r.position + Vector2(12, 26), it.display_name, name_size, main, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 18)
	var line := "Owned" if owned else _price_text(index, plan)
	_text(r.position + Vector2(12, r.size.y - 10), line, 20, Palette.GOLD if ready else main, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 18)
	_shop_hits.append({"rect": r, "buy": index, "item": it})


## "160", "640 with your parts", "need 40 more".
func _price_text(index: int, plan: Dictionary) -> String:
	var it: ItemDef = Unit.ECONOMY.items[index - 1]
	var price: int = plan.price
	var short := ceili(price - player.gold)
	var s := "%d" % price
	if price < it.cost:
		s = "%d with your parts" % price
	if short > 0:
		s += ", need %d" % short
	return s


func _input(event: InputEvent) -> void:
	if player == null:
		return
	if event is InputEventMouseMotion:
		_mouse = event.position
		_tip_item = null
		for h in _hud_hits + _shop_hits:
			if (h.rect as Rect2).has_point(event.position) and h.has("item"):
				_tip_item = h.item
		return
	if not (event is InputEventMouseButton and event.pressed) or Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		return
	for h in _hud_hits:
		if h.has("recall") and event.button_index == MOUSE_BUTTON_LEFT and (h.rect as Rect2).has_point(event.position):
			HumanController.pending_recall = true
			get_viewport().set_input_as_handled()
			return
	if not (HumanController.shop_open and ItemShop.adventurer()):
		return
	for h in _shop_hits:
		if not (h.rect as Rect2).has_point(event.position):
			continue
		if event.button_index == MOUSE_BUTTON_LEFT and h.has("tab"):
			shop_tab = h.tab
		elif event.button_index == MOUSE_BUTTON_LEFT and h.has("buy"):
			HumanController.pending_buy = h.buy
		elif event.button_index == MOUSE_BUTTON_RIGHT and h.has("sell"):
			HumanController.pending_sell = h.sell
		get_viewport().set_input_as_handled()
		return


## The passive's stored count, when it has one worth watching (embers, fury,
## charges, the half-sung refrain). Empty otherwise.
static func passive_readout(u: Unit) -> String:
	match u.def.passive:
		ChampionDef.Passive.FLAME:
			return "Embers %d/%d" % [floori(u.passive_stacks), roundi(CombatAuthority.FLAME_MAX)] if u.passive_stacks >= 1.0 else ""
		ChampionDef.Passive.FURY:
			if u.passive_stacks >= CombatAuthority.FURY_MAX:
				return "Fury full: Q heals"
			return "Fury %d" % floori(u.passive_stacks) if u.passive_stacks >= 1.0 else ""
		ChampionDef.Passive.RESIDUAL:
			return "Charges %d/%d" % [floori(u.passive_stacks), roundi(CombatAuthority.RESIDUAL_MAX)] if u.passive_stacks >= 1.0 else ""
		ChampionDef.Passive.REFRAIN:
			if u.refrain_slot > 0:
				var other := u.get_slot(3 - u.refrain_slot)
				return "Refrain: %s next" % other.display_name if other else ""
	return ""


## Recall, right of the ability bar: key T, a teal edge when it can start,
## filling while it runs. Clickable while the mouse pointer is free.
func _draw_recall_button(r: Rect2) -> void:
	var home := player.can_shop()
	var running := player.recall_timer > 0.0
	var free := player.alive and not home and not player.is_stunned() and not player.is_casting()
	draw_rect(r.grow(2), Palette.BRASS if running else (Palette.TEAL if free else Color(0.08, 0.07, 0.06, 0.9)))
	draw_rect(r, Color(0.16, 0.14, 0.12, 0.96))
	if running:
		var f := 1.0 - player.recall_timer / Unit.ECONOMY.recall_time
		draw_rect(Rect2(r.position, Vector2(r.size.x * f, r.size.y)), Color(Palette.TEAL, 0.35))
	elif not free:
		draw_rect(r, Color(0.3, 0.3, 0.3, 0.5))
	_text(r.position + Vector2(0, 24), "Recall", SMALL, Color(0.95, 0.92, 0.85), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	var label := "%.1f" % player.recall_timer if running else ("Home" if home and player.alive else "T")
	_text(r.position + Vector2(0, 58), label, 26 if running else FONT_SIZE, Palette.TEAL if free or running else Color(0.6, 0.6, 0.6), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	_hud_hits.append({"rect": r, "recall": true})


## Own items in a row above the health bar: short names, a stripe in the
## shop column's colour. Hold Alt for the full details.
func _draw_item_row(area: Rect2) -> void:
	var slots: int = Unit.ECONOMY.slots
	if slots <= 0:
		return
	var gap := 8.0
	var tw := (area.size.x - gap * (slots - 1)) / slots
	for s in slots:
		var r := Rect2(area.position + Vector2(s * (tw + gap), 0), Vector2(tw, area.size.y))
		draw_rect(r, Color(0.06, 0.05, 0.04, 0.7))
		if s >= player.items.size():
			continue
		var it: ItemDef = player.items[s]
		draw_rect(Rect2(r.position, Vector2(4, r.size.y)), _group_color(it))
		var nm := it.short_name if not it.short_name.is_empty() else it.display_name
		var size := SMALL
		while size > 14 and _font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > tw - 12:
			size -= 1
		_text(r.position + Vector2(4, 26), nm, size, Color(0.96, 0.93, 0.86), HORIZONTAL_ALIGNMENT_CENTER, tw - 4)
		_hud_hits.append({"rect": r, "item": it})
	if not player.items.is_empty():
		_text(area.position + Vector2(0, -8), "Alt  item details", SMALL, Color(0.80, 0.77, 0.70), HORIZONTAL_ALIGNMENT_LEFT, area.size.x)


static func _group_color(it: ItemDef) -> Color:
	match shop_group(it):
		"weapon":
			return Palette.AMBER
		"spell":
			return Palette.TEAL
		"defence":
			return Color(0.75, 0.72, 0.66)
		"utility":
			return Palette.GOLD
	return Color(0.55, 0.52, 0.48)


## Held Alt: every own item, two columns of three, stats on one line and
## the passive below, in big type.
func _draw_item_details(vs: Vector2, c: Vector2) -> void:
	var w := minf(vs.x - 40.0, 1240.0)
	var items := player.items
	var x := c.x - w * 0.5
	var y := 64.0
	var col_w := (w - 48.0) * 0.5
	var lh := _font.get_height(20)
	var heights: Array[float] = []
	for it: ItemDef in items:
		heights.append(40.0 + _text_lines(_item_body(it, true), col_w - 24, 20) * lh + 14.0)
	var col_h := [0.0, 0.0]
	for k in heights.size():
		col_h[mini(k / 3, 1)] += heights[k]
	var panel := Rect2(Vector2(x, y), Vector2(w, 56.0 + maxf(maxf(col_h[0], col_h[1]), 40.0)))
	draw_rect(panel.grow(2), Palette.BRASS)
	draw_rect(panel, Color(0.10, 0.09, 0.08, 0.94))
	_text(Vector2(x + 16, y + 34), "Your items", 26, Palette.GOLD, HORIZONTAL_ALIGNMENT_LEFT, w - 32)
	if items.is_empty():
		_text(Vector2(x + 16, y + 76), "No items yet. Press B at your fountain to shop.", 20, Color(0.85, 0.82, 0.75), HORIZONTAL_ALIGNMENT_LEFT, w - 32)
		return
	var cy := [y + 52.0, y + 52.0]
	for k in items.size():
		var col := mini(k / 3, 1)
		var it: ItemDef = items[k]
		var bx := x + 16.0 + col * (col_w + 16.0)
		draw_rect(Rect2(Vector2(bx, cy[col] + 6), Vector2(4, heights[k] - 16)), _group_color(it))
		_text(Vector2(bx + 14, cy[col] + 30), it.display_name, 24, Color(0.96, 0.93, 0.86), HORIZONTAL_ALIGNMENT_LEFT, col_w - 20)
		draw_multiline_string(_font, Vector2(bx + 14, cy[col] + 40 + _font.get_ascent(20)), _item_body(it, true), HORIZONTAL_ALIGNMENT_LEFT, col_w - 24, 20, -1, Color(0.88, 0.86, 0.80))
		cy[col] += heights[k]


## Stats, recipe and the passive, one fact per line. Compact (the Alt
## panel): stats share one line and the recipe is left out.
func _item_body(it: ItemDef, compact := false) -> String:
	var lines := item_stat_lines(it)
	if compact and lines.size() > 1:
		lines = PackedStringArray(["    ".join(lines)])
	if it.kind == ItemDef.Kind.STARTER:
		lines.insert(0, "Starter item")
	if not it.recipe.is_empty() and not compact:
		var parts: PackedStringArray = []
		for r in it.recipe:
			parts.append((r as ItemDef).display_name)
		lines.append("Built from " + " + ".join(parts))
	var extra := item_passive_text(it)
	if not extra.is_empty():
		lines.append("Passive: " + extra)
	elif lines.is_empty():
		lines.append(it.description)
	return "\n".join(lines)


## The part of the description after its stats sentence (the passive), or
## empty when the item has no passive. Descriptions lead with the stats.
static func item_passive_text(it: ItemDef) -> String:
	if it.passive == ItemDef.Passive.NONE:
		return ""
	var at := it.description.find(". ")
	return it.description.substr(at + 2) if at >= 0 else it.description


## Lines `text` takes when wrapped to `width` (word wrap, rounded up a little).
func _text_lines(text: String, width: float, size: int) -> int:
	var n := 0
	for line in text.split("\n"):
		var words := line.split(" ")
		var cur := ""
		var count := 1
		for wd in words:
			var test := wd if cur.is_empty() else cur + " " + wd
			if _font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width and not cur.is_empty():
				count += 1
				cur = wd
			else:
				cur = test
		n += count
	return n


## "+30 weapon power", "+15% attack speed" ... for every bonus the item has.
static func item_stat_lines(it: ItemDef) -> PackedStringArray:
	var out: PackedStringArray = []
	if it.weapon_power > 0.0:
		out.append("+%d weapon power" % roundi(it.weapon_power))
	if it.spell_power > 0.0:
		out.append("+%d spell power" % roundi(it.spell_power))
	if it.health > 0.0:
		out.append("+%d health" % roundi(it.health))
	if it.armor > 0.0:
		out.append("+%d armor" % roundi(it.armor))
	if it.magic_resist > 0.0:
		out.append("+%d magic resist" % roundi(it.magic_resist))
	if it.attack_speed > 0.0:
		out.append("+%d%% attack speed" % roundi(it.attack_speed * 100.0))
	if it.haste > 0.0:
		out.append("+%d haste" % roundi(it.haste))
	if it.damage > 0.0:
		out.append("+%d%% damage" % roundi(it.damage * 100.0))
	if it.cooldown > 0.0:
		out.append("%d%% shorter cooldowns" % roundi(it.cooldown * 100.0))
	if it.move_speed > 0.0:
		out.append("+%d%% move speed" % roundi(it.move_speed * 100.0))
	return out


## The hover card: name, price, then the item body. Sits beside the pointer
## and stays on screen.
func _draw_tooltip(it: ItemDef, at: Vector2, vs: Vector2) -> void:
	var w := 420.0
	var body := _item_body(it)
	var bh := _text_lines(body, w - 32, 20) * _font.get_height(20)
	var size := Vector2(w, 78.0 + bh)
	var pos := at + Vector2(24, 24)
	if pos.x + size.x > vs.x - 8.0:
		pos.x = at.x - 24.0 - size.x
	pos.y = clampf(pos.y, 8.0, vs.y - size.y - 8.0)
	var r := Rect2(pos, size)
	draw_rect(r.grow(2), Palette.BRASS)
	draw_rect(r, Color(0.08, 0.07, 0.06, 0.97))
	_text(r.position + Vector2(16, 32), it.display_name, 24, Color(0.96, 0.93, 0.86), HORIZONTAL_ALIGNMENT_LEFT, w - 140)
	_text(r.position + Vector2(0, 32), "%d gold" % it.cost, 20, Palette.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, w - 16)
	draw_multiline_string(_font, r.position + Vector2(16, 64), body, HORIZONTAL_ALIGNMENT_LEFT, w - 32, 20, -1, Color(0.88, 0.86, 0.80))
