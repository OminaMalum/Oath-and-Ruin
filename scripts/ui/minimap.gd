class_name Minimap
extends Control
## The whole map from above, in the top right corner: walls, both teams'
## towers and cores, minion waves, champions and the Shrinebearer. Own base
## at the bottom, like the lane ahead of the camera at the start.
##
## It shows what the viewer's team can see: allies always, enemy champions
## only while one of the team's units (a champion, a minion, a structure) is
## within SIGHT of them. Minions and structures are always shown, since the
## top bar already tells everyone how the structures stand. View only.

const MAX_SIZE := Vector2(236, 400)
const MARGIN := 16.0
const TOP := 52.0
## How far the viewer's team sees an enemy champion (metres).
const SIGHT := 22.0
const FLASH_TIME := 1.6

var match_ctl: MatchController
var authority: CombatAuthority
var rig: CameraRig
var _walls: Array[Rect2] = []   # world x, z
var _bounds := Rect2(-20, -80, 40, 160)
var _px := 2.0                  # pixels per metre
var _hit_at := {}               # structure Unit -> time it was last hit
var _font: Font


func setup(m: MatchController, r: CameraRig, map_root: Node) -> void:
	match_ctl = m
	authority = m.authority
	rig = r
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_walls = wall_rects(map_root)
	if not _walls.is_empty():
		_bounds = _walls[0]
		for w in _walls:
			_bounds = _bounds.merge(w)
		_bounds = _bounds.grow(1.5)
	_px = minf(MAX_SIZE.x / _bounds.size.x, MAX_SIZE.y / _bounds.size.y)
	authority.unit_damaged.connect(func(t: Unit, _a: float, _s: Unit) -> void:
		if t.def.kind == ChampionDef.Kind.STRUCTURE:
			_hit_at[t] = authority.time)


## Every standing wall of the map as a rectangle on the ground (x, z): the
## collision boxes tall enough to block a champion. Floors and low plinths
## are left out.
static func wall_rects(map_root: Node) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if map_root == null:
		return out
	for body in map_root.find_children("*", "StaticBody3D", true, false):
		for shape in body.get_children():
			var cs := shape as CollisionShape3D
			if cs == null or not (cs.shape is BoxShape3D):
				continue
			var size := (cs.shape as BoxShape3D).size
			var xf: Transform3D = (body as Node3D).transform * cs.transform
			var box := xf * AABB(-size * 0.5, size)
			if box.end.y < 1.5 or box.size.y < 1.2:
				continue
			out.append(Rect2(box.position.x, box.position.z, box.size.x, box.size.z))
	return out


## Size on screen, from the map's shape.
func map_size() -> Vector2:
	return _bounds.size * _px


## World position to a point inside the minimap.
func to_map(world: Vector3) -> Vector2:
	return Vector2(world.x - _bounds.position.x, world.z - _bounds.position.y) * _px


## True when `u` is known to `team`: its own side, or an enemy within SIGHT
## of any of the team's living units.
func seen_by(team: int, u: Unit) -> bool:
	if u.team == team:
		return true
	for o in authority.units:
		if o.team == team and o.alive and UnitController.flat_distance(o.global_position, u.global_position) <= SIGHT:
			return true
	return false


func _process(_d: float) -> void:
	var vs := get_viewport_rect().size
	size = map_size()
	position = Vector2(vs.x - size.x - MARGIN, TOP)
	visible = not HumanController.shop_open and not match_ctl.over
	queue_redraw()


func _draw() -> void:
	if match_ctl == null:
		return
	var me: Unit = rig.target if rig else null
	var my_team := me.team if me else 0
	var sz := map_size()
	draw_rect(Rect2(Vector2(-3, -3), sz + Vector2(6, 6)), Color(Palette.BRASS, 0.9))
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.10, 0.09, 0.08, 0.88))
	for w in _walls:
		draw_rect(Rect2((w.position - _bounds.position) * _px, w.size * _px), Color(0.42, 0.39, 0.34, 0.95))
	# Fountains: a ring in the team's colour at each end.
	for team in 2:
		draw_arc(to_map(match_ctl.info.fountain(team)), 7.0, 0, TAU, 20, Color(Palette.team_color(team), 0.7), 2.0)
	_draw_objective()
	var now := authority.time
	# Structures: towers square, cores a larger diamond; a ruin is a dim outline.
	for s in match_ctl.structures:
		var p := to_map(s.global_position)
		var col := Palette.team_color(s.team)
		var core := s.def.look == ChampionDef.Look.CORE
		var r := 8.0 if core else 6.0
		if not s.alive:
			draw_rect(Rect2(p - Vector2(r, r) * 0.7, Vector2(r, r) * 1.4), Color(col, 0.35), false, 1.5)
			continue
		var hit := now - float(_hit_at.get(s, -100.0)) < FLASH_TIME
		if hit and fmod(now, 0.4) < 0.2:
			col = Color(1, 1, 1)
		if core:
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)]), col)
		else:
			draw_rect(Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), Color(0, 0, 0, 0.8))
			draw_rect(Rect2(p - Vector2(r - 1.5, r - 1.5), Vector2(r - 1.5, r - 1.5) * 2.0), col)
		if hit:
			draw_arc(p, r + 5.0, 0, TAU, 20, Color(1, 1, 1, 0.8), 2.0)
	# Minions and summons: small dots. Big siege units a little larger.
	for u in authority.units:
		if not u.alive or u.team > 1:
			continue
		var k := u.def.kind
		if k != ChampionDef.Kind.MINION and k != ChampionDef.Kind.SUMMON:
			continue
		var big := u.def.look == ChampionDef.Look.BREAKER or u.def.look == ChampionDef.Look.SHRINEBEARER
		draw_circle(to_map(u.global_position), 4.5 if big else 2.2, Palette.team_color(u.team))
	# Champions on top. Enemies only while the team sees them.
	for c in match_ctl.champions:
		if not c.alive or c == me or not seen_by(my_team, c):
			continue
		_draw_champion(c, false)
	if me and me.alive:
		_draw_champion(me, true)


func _draw_champion(c: Unit, mine: bool) -> void:
	var p := to_map(c.get_global_transform_interpolated().origin)
	var col := Palette.team_color(c.team)
	if mine:
		# Which way the camera looks: a soft wedge ahead of the marker.
		var yaw := rig.yaw if rig and not rig.follow_unit_yaw else c.rotation.y
		var dir := Vector2(-sin(yaw), -cos(yaw))
		var side := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([p, p + dir * 30.0 + side * 15.0, p + dir * 30.0 - side * 15.0]), Color(1, 1, 1, 0.16))
		draw_circle(p, 9.5, Color(1, 1, 1))
	else:
		draw_circle(p, 8.5, Color(0, 0, 0, 0.85))
	draw_circle(p, 7.0, col)
	# The champion's initial, so three allied dots can be told apart.
	var letter := c.def.display_name.substr(0, 1)
	draw_string(_font, p + Vector2(-7, 5), letter, HORIZONTAL_ALIGNMENT_CENTER, 14, 14, Color(0.05, 0.05, 0.05))


## The camp: a dim amethyst mark while it sleeps, bright while it is open,
## the capture colour while a team claims it.
func _draw_objective() -> void:
	var p := to_map(match_ctl.objective_position())
	var r := 7.0
	var col := Color(Palette.NEUTRAL, 0.35)
	match match_ctl.beast_state:
		MatchController.Beast.AWAKE:
			col = Palette.NEUTRAL
		MatchController.Beast.CAPTURE:
			col = Palette.team_color(match_ctl.capture_team) if match_ctl.capture_team >= 0 else Color(1, 1, 1)
		MatchController.Beast.SLEEPING:
			if match_ctl.beast_timer <= MatchController.BEAST_WARNING and fmod(authority.time, 1.0) < 0.5:
				col = Color(Palette.NEUTRAL, 0.8)
	var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
	draw_colored_polygon(pts, col)
	if match_ctl.beast_state in [MatchController.Beast.AWAKE, MatchController.Beast.CAPTURE]:
		draw_arc(p, r + 4.0 + 2.0 * sin(authority.time * 4.0), 0, TAU, 20, Color(col, 0.8), 1.5)
