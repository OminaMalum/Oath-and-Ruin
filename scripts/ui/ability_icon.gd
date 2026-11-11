class_name AbilityIcon
## A drawn sign for an ability, picked by what the ability does: a bolt or an
## arrow for shots, a ring for ground bursts, a crescent for swings, chevrons
## for dashes, a dome for wards, stones for walls, a hook for grapples, a
## shield or rising marks for self casts, a figure for summons. Vector shapes
## drawn in code, so there is no icon art to license and every new ability
## gets a sign for free. A small plus marks anything that heals.


## Which sign `a` gets (also used by tests).
static func kind(a: AbilityDef, weapon: bool) -> String:
	match a.delivery:
		AbilityDef.Delivery.PROJECTILE:
			return "arrow" if weapon else "bolt"
		AbilityDef.Delivery.GROUND_AREA:
			return "beam" if a.line_width > 0.0 else "burst"
		AbilityDef.Delivery.MELEE_ARC:
			return "swing"
		AbilityDef.Delivery.DASH:
			return "dash"
		AbilityDef.Delivery.WARD:
			return "ward"
		AbilityDef.Delivery.WALL:
			return "wall"
		AbilityDef.Delivery.GRAPPLE:
			return "hook"
		AbilityDef.Delivery.SUMMON:
			return "summon"
		AbilityDef.Delivery.SELF:
			if a.shield_mode != AbilityDef.ShieldMode.NONE or a.brace_duration > 0.0:
				return "shield"
			return "claws" if a.transform_duration > 0.0 else "rise"
	return "bolt"


static func heals(a: AbilityDef) -> bool:
	return a.ally_heal > 0.0 or a.heal_per_second > 0.0


## Draws the sign for `a` inside `r` on `ci` (inside its _draw).
static func draw(ci: CanvasItem, r: Rect2, a: AbilityDef, col: Color, weapon := false) -> void:
	var s := minf(r.size.x, r.size.y)
	var o := r.position + (r.size - Vector2(s, s)) * 0.5
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	var w := func(k: float) -> float: return maxf(k * s, 1.5)
	var pale := col.lightened(0.45)
	match kind(a, weapon):
		"bolt":
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.54, 0.26), p.call(0.74, 0.46), p.call(0.12, 0.88)]), Color(col, col.a * 0.7))
			ci.draw_circle(p.call(0.66, 0.34), 0.19 * s, col)
			ci.draw_circle(p.call(0.66, 0.34), 0.09 * s, pale)
		"arrow":
			ci.draw_line(p.call(0.16, 0.84), p.call(0.70, 0.30), col, w.call(0.08))
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.90, 0.10), p.call(0.58, 0.22), p.call(0.78, 0.42)]), pale)
			ci.draw_line(p.call(0.16, 0.84), p.call(0.14, 0.62), col, w.call(0.07))
			ci.draw_line(p.call(0.16, 0.84), p.call(0.38, 0.86), col, w.call(0.07))
		"burst":
			ci.draw_arc(p.call(0.5, 0.58), 0.32 * s, 0, TAU, 28, col, w.call(0.08))
			ci.draw_circle(p.call(0.5, 0.58), 0.12 * s, pale)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.38, 0.04), p.call(0.62, 0.04), p.call(0.5, 0.24)]), pale)
		"beam":
			ci.draw_line(p.call(0.14, 0.86), p.call(0.86, 0.14), Color(col, col.a * 0.75), w.call(0.24))
			ci.draw_line(p.call(0.14, 0.86), p.call(0.86, 0.14), pale, w.call(0.08))
		"swing":
			ci.draw_arc(p.call(0.26, 0.78), 0.58 * s, deg_to_rad(-88), deg_to_rad(-2), 20, col, w.call(0.13))
			ci.draw_arc(p.call(0.26, 0.78), 0.36 * s, deg_to_rad(-80), deg_to_rad(-10), 16, Color(pale, pale.a * 0.8), w.call(0.06))
		"dash":
			for i in 3:
				var x := 0.14 + 0.24 * i
				var c := Color(col, col.a * (0.45 + 0.27 * i))
				ci.draw_polyline(PackedVector2Array([p.call(x, 0.22), p.call(x + 0.24, 0.5), p.call(x, 0.78)]), c, w.call(0.1))
		"ward":
			ci.draw_arc(p.call(0.5, 0.74), 0.38 * s, PI, TAU, 24, col, w.call(0.09))
			ci.draw_line(p.call(0.08, 0.74), p.call(0.92, 0.74), pale, w.call(0.08))
		"wall":
			var hs: Array[float] = [0.46, 0.64, 0.46]
			for i in 3:
				var x := 0.1 + 0.29 * i
				ci.draw_rect(Rect2(p.call(x, 0.86 - hs[i]), Vector2(0.22, hs[i]) * s), col if i != 1 else pale)
		"hook":
			ci.draw_arc(p.call(0.64, 0.38), 0.22 * s, deg_to_rad(-210), deg_to_rad(50), 20, pale, w.call(0.1))
			for i in 3:
				ci.draw_arc(p.call(0.40 - 0.13 * i, 0.60 + 0.13 * i), 0.07 * s, 0, TAU, 12, col, w.call(0.05))
		"summon":
			ci.draw_circle(p.call(0.5, 0.24), 0.14 * s, pale)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.28, 0.82), p.call(0.72, 0.82), p.call(0.62, 0.42), p.call(0.38, 0.42)]), col)
			ci.draw_line(p.call(0.12, 0.9), p.call(0.88, 0.9), Color(pale, pale.a * 0.8), w.call(0.06))
		"shield":
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.5, 0.08), p.call(0.86, 0.22), p.call(0.80, 0.62), p.call(0.5, 0.92), p.call(0.20, 0.62), p.call(0.14, 0.22)]), col)
			ci.draw_line(p.call(0.5, 0.2), p.call(0.5, 0.78), pale, w.call(0.07))
		"claws":
			for i in 3:
				var x := 0.2 + 0.24 * i
				ci.draw_line(p.call(x + 0.14, 0.12), p.call(x - 0.06, 0.88), col if i != 1 else pale, w.call(0.1))
		_:
			for i in 2:
				var y := 0.5 + 0.3 * i
				ci.draw_polyline(PackedVector2Array([p.call(0.18, y), p.call(0.5, y - 0.36), p.call(0.82, y)]), col if i == 1 else pale, w.call(0.1))
	if heals(a):
		var c: Vector2 = p.call(0.84, 0.84)
		ci.draw_circle(c, 0.17 * s, Color(0.05, 0.05, 0.05, col.a))
		ci.draw_line(c - Vector2(0.11 * s, 0), c + Vector2(0.11 * s, 0), Color(0.55, 0.95, 0.5, col.a), w.call(0.07))
		ci.draw_line(c - Vector2(0, 0.11 * s), c + Vector2(0, 0.11 * s), Color(0.55, 0.95, 0.5, col.a), w.call(0.07))
