class_name KitLooks
extends RefCounted
## Per kit spell looks, so each champion's spells read as their own: arrows
## for the archer, a crackling bolt and a sky strike for the storm caller,
## chains for the binder, a thrown blade, a raven, notes, embers, thorns and
## rock from the ground, grave smoke, and a weapon swoosh on melee swings.
## Built by SpellFx; view only, and its random jitter uses its own generator
## so nothing here can touch the sim.

## Ability id -> bolt look. Anything not listed keeps the arcane rings.
const BOLT := {
	&"longbow": "arrow", &"charged_shot": "arrow",
	&"spark_bolt": "spark",
	&"binding_chains": "chain", &"debt_collector": "chain",
	&"ember_knife": "knife",
	&"grave_bolt": "wisp",
	&"lute_note": "note", &"lure": "note",
	&"ravens_mark": "raven",
	&"censer_spark": "ember",
}
## Ability id -> what the ground spell does when it goes off.
const AREA := {
	&"called_lightning": "lightning", &"tempest": "lightning", &"tempest_second": "lightning", &"tempest_last": "lightning",
	&"bramble": "thorns", &"thornstorm": "thorns",
	&"grasping_earth": "rocks",
	&"grave_roar": "smoke", &"grave_pact": "smoke",
	&"covenant_severed": "severed",
}
## Ability id -> what a melee swing adds to the crescent.
const MELEE := {&"pactlash": "lash", &"break_the_seal": "seal"}

static var rng := RandomNumberGenerator.new()
static var _mats := {}


static func bolt_look(a: AbilityDef) -> String:
	return BOLT.get(a.id, "")


static func area_look(a: AbilityDef) -> String:
	return AREA.get(a.id, "")


static func melee_look(a: AbilityDef) -> String:
	return MELEE.get(a.id, "")


# ------------------------------------------------------------------ materials

static func lit(col: Color, rough := 0.6, metal := 0.0, glow := Color.BLACK, glow_e := 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s|%s" % [col, rough, metal, glow, glow_e]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	if glow_e > 0.0:
		m.emission_enabled = true
		m.emission = glow
		m.emission_energy_multiplier = glow_e
	_mats[key] = m
	return m


static func smoke_mat() -> StandardMaterial3D:
	if _mats.has("smoke"):
		return _mats["smoke"]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = Fire._soft_dot()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["smoke"] = m
	return m


static func ribbon_mat() -> StandardMaterial3D:
	if _mats.has("ribbon"):
		return _mats["ribbon"]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(2.5, 2.5, 2.5, 1.0)
	_mats["ribbon"] = m
	return m


static func _mesh(mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _cyl(r0: float, r1: float, h: float, seg := 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r0
	c.bottom_radius = r1
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


static func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


# ------------------------------------------------------------------ bolts
# Each builder adds its pieces under `host` (the drawn bolt, -Z is forward)
# and returns {"spin": Node3D or null, "tick": Callable or null, "trail": particles or null}.

static func build_bolt(look: String, host: Node3D, col: Color, a: AbilityDef, fx: Node3D) -> Dictionary:
	match look:
		"arrow":
			return _arrow(host, col, a.id == &"charged_shot", fx)
		"spark":
			return _spark(host, col, fx)
		"chain":
			return _chain(host, col, fx)
		"knife":
			return _knife(host, col, fx)
		"wisp":
			return _wisp(host, col, fx)
		"note":
			return _note(host, col, fx)
		"raven":
			return _raven(host, col, fx)
		"ember":
			return _ember(host, col, fx)
	return {}


## Hide WorldView's plain orb and cone so the look replaces them (its light stays).
static func hide_plain(host: Node3D) -> void:
	for c in host.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).visible = false


static func _arrow(host: Node3D, col: Color, charged: bool, fx: Node3D) -> Dictionary:
	hide_plain(host)
	var s := 1.5 if charged else 1.0
	var wood := lit(Color(0.42, 0.28, 0.16), 0.7)
	var steel := lit(Color(0.7, 0.72, 0.75), 0.3, 0.8)
	var arrow := Node3D.new()
	host.add_child(arrow)
	arrow.scale = Vector3.ONE * s
	arrow.add_child(_mesh(_cyl(0.018, 0.018, 0.95, 6), wood, Vector3(0, 0, 0.1), Vector3(90, 0, 0)))
	arrow.add_child(_mesh(_cyl(0.0, 0.05, 0.16, 6), steel, Vector3(0, 0, -0.44), Vector3(-90, 0, 0)))
	var fletch := lit(col.lightened(0.2), 0.8, 0.0, col, 0.6)
	for r in [0.0, 90.0]:
		arrow.add_child(_mesh(_box(Vector3(0.12, 0.004, 0.2)), fletch, Vector3(0, 0, 0.5), Vector3(0, 0, r)))
	# A thin light streak behind, longer and brighter on the charged shot.
	var streak := _mesh(_cyl(0.0, 0.035 if charged else 0.018, 2.2 if charged else 1.4, 6), SpellFx._add_mat(col.lightened(0.3), 2.2 if charged else 1.4),
			Vector3(0, 0, 1.25 if charged else 0.85), Vector3(-90, 0, 0))
	host.add_child(streak)
	if charged:
		arrow.add_child(_mesh(_cyl(0.05, 0.05, 0.9, 8), SpellFx._add_mat(col, 1.6), Vector3(0, 0, 0.05), Vector3(90, 0, 0)))
	var trail := _particles(fx, col, 30 if charged else 0, 0.35, 0.08, 0.12, Vector3(0, 0.3, 0))
	return {"spin": arrow, "spin_rate": 6.0, "trail": trail}


static func _spark(host: Node3D, col: Color, fx: Node3D) -> Dictionary:
	hide_plain(host)
	host.add_child(_mesh(_sphere(0.13), SpellFx._add_mat(col.lightened(0.5), 3.0)))
	var im := ImmediateMesh.new()
	var mi := _mesh(im, ribbon_mat())
	host.add_child(mi)
	var state := {"t": 0.0}
	var tick := func(dt: float) -> void:
		state.t -= dt
		if state.t > 0.0:
			return
		state.t = 0.045
		im.clear_surfaces()
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		var path := jag(im, Vector3.ZERO, Vector3(0, 0, 2.6), 8, 0.2, 0.08, col.lightened(0.5))
		halo(im, path, 0.3, Color(col, 0.3))
		for i in 2:
			var from := Vector3(0, 0, rng.randf_range(0.3, 1.4))
			jag(im, from, from + Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.3, 0.4), rng.randf_range(0.2, 0.6)), 3, 0.08, 0.025, col)
		im.surface_end()
	tick.call(1.0)
	var trail := _particles(fx, col.lightened(0.3), 24, 0.22, 0.05, 0.09, Vector3.ZERO, 2.0)
	return {"tick": tick, "trail": trail}


static func _chain(host: Node3D, col: Color, fx: Node3D) -> Dictionary:
	hide_plain(host)
	var iron := chain_iron(col)
	# The hook at the head.
	host.add_child(_mesh(_cyl(0.0, 0.09, 0.26, 6), iron, Vector3(0, 0, -0.1), Vector3(-90, 0, 0)))
	host.add_child(_mesh(_sphere(0.16), SpellFx._add_mat(col, 1.4)))
	return {"links": chain_links(fx, col, 120), "trail": null}


static func chain_iron(col: Color) -> StandardMaterial3D:
	return lit(Color(0.36, 0.36, 0.4), 0.45, 0.8, col, 0.5)


## A chain of up to `count` links drawn as one multimesh (one draw call);
## lay_chain places them.
static func chain_links(fx: Node3D, col: Color, count: int, size := 1.0) -> MultiMeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.035 * size
	torus.outer_radius = 0.07 * size
	torus.rings = 8
	torus.ring_segments = 4
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = torus
	mm.instance_count = count
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = chain_iron(col)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	fx.add_child(mi)
	mi.global_transform = Transform3D.IDENTITY
	mi.set_meta("step", 0.12 * size)
	return mi


## Lays the links from `from` to `to`. sag < 0 picks a thrown chain's sag.
static func lay_chain(links: MultiMeshInstance3D, from: Vector3, to: Vector3, sag := -1.0) -> void:
	var mm := links.multimesh
	var d := to - from
	var len := d.length()
	if len < 0.05:
		mm.visible_instance_count = 0
		return
	var step: float = links.get_meta("step", 0.12)
	var n := mini(int(len / step), mm.instance_count)
	var dir := d / len
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	var b0 := Basis.looking_at(dir, up)
	var b1 := b0 * Basis(Vector3.FORWARD, PI * 0.5)
	var s := minf(len * 0.03, 0.35) if sag < 0.0 else sag
	for i in n:
		var f := (float(i) + 0.5) / float(n)
		# A slight sag in the middle, as a thrown chain would have.
		var p := from + d * f - Vector3(0, sin(f * PI) * s, 0)
		mm.set_instance_transform(i, Transform3D(b1 if i % 2 == 1 else b0, p))
	mm.visible_instance_count = n


static func _knife(host: Node3D, col: Color, fx: Node3D) -> Dictionary:
	hide_plain(host)
	var spin := Node3D.new()
	host.add_child(spin)
	var steel := lit(Color(0.75, 0.74, 0.72), 0.25, 0.9, col, 0.8)
	spin.add_child(_mesh(_box(Vector3(0.38, 0.012, 0.07)), steel, Vector3(0.12, 0, 0)))
	spin.add_child(_mesh(_box(Vector3(0.12, 0.03, 0.04)), lit(Color(0.3, 0.2, 0.12), 0.7), Vector3(-0.12, 0, 0)))
	spin.add_child(_mesh(_cyl(0.32, 0.32, 0.01, 20), SpellFx._add_mat(col, 0.35)))
	var trail := _particles(fx, col.lightened(0.2), 40, 0.5, 0.05, 0.1, Vector3(0, -2.5, 0))
	return {"spin": spin, "spin_axis": Vector3.UP, "spin_rate": 22.0, "trail": trail}


static func _wisp(host: Node3D, col: Color, fx: Node3D) -> Dictionary:
	var spin := Node3D.new()
	host.add_child(spin)
	for i in 3:
		var a := TAU * i / 3.0
		spin.add_child(_mesh(_sphere(0.05), SpellFx._add_mat(col.lightened(0.4), 2.5), Vector3(cos(a), sin(a), 0) * 0.28))
	var smoke := _smoke(fx, Color(0.08, 0.06, 0.1, 0.55), 40, 0.7, 0.22, 0.35, Vector3(0, 0.5, 0))
	return {"spin": spin, "spin_rate": 10.0, "trail": smoke, "extra_trail": _particles(fx, col, 20, 0.4, 0.05, 0.1, Vector3.ZERO)}


static func _note(host: Node3D, col: Color, fx: Node3D) -> Dictionary:
	var spin := Node3D.new()
	host.add_child(spin)
	for i in 2:
		var a := PI * i
		spin.add_child(_mesh(_sphere(0.06), SpellFx._add_mat(col.lightened(0.3), 2.4), Vector3(cos(a), sin(a), 0) * 0.3))
	# Two rings that pulse like a plucked string.
	for r in [0.22, 0.34]:
		var t := TorusMesh.new()
		t.inner_radius = r * 0.93
		t.outer_radius = r
		t.rings = 24
		t.ring_segments = 3
		host.add_child(_mesh(t, SpellFx._add_mat(col, 1.4), Vector3.ZERO, Vector3(90, 0, 0)))
	var trail := _particles(fx, col.lightened(0.2), 36, 0.6, 0.04, 0.1, Vector3(0, 0.8, 0))
	return {"spin": spin, "spin_rate": 12.0, "trail": trail}


static func _raven(host: Node3D, col: Color, fx: Node3D) -> Dictionary:
	hide_plain(host)
	var black := lit(Color(0.05, 0.05, 0.07), 0.5, 0.0, col, 0.15)
	var bird := Node3D.new()
	host.add_child(bird)
	bird.add_child(_mesh(_sphere(0.1, 0.5), black, Vector3.ZERO))
	bird.get_child(0).scale = Vector3(0.8, 0.7, 1.9)
	bird.add_child(_mesh(_sphere(0.07), black, Vector3(0, 0.03, -0.2)))
	bird.add_child(_mesh(_cyl(0.0, 0.025, 0.09, 4), lit(Color(0.25, 0.22, 0.2), 0.5), Vector3(0, 0.02, -0.29), Vector3(-90, 0, 0)))
	for sx in [-1.0, 1.0]:
		bird.add_child(_mesh(_sphere(0.016), SpellFx._add_mat(col.lightened(0.4), 3.0), Vector3(sx * 0.035, 0.06, -0.25)))
	bird.add_child(_mesh(_box(Vector3(0.14, 0.01, 0.18)), black, Vector3(0, 0, 0.24)))
	var wings: Array[Node3D] = []
	for sx in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(sx * 0.05, 0.02, -0.02)
		bird.add_child(pivot)
		pivot.add_child(_mesh(_box(Vector3(0.36, 0.01, 0.16)), black, Vector3(sx * 0.18, 0, 0.02)))
		wings.append(pivot)
	var state := {"t": 0.0}
	var tick := func(dt: float) -> void:
		state.t += dt
		var flap := sin(state.t * 22.0) * 0.6
		wings[0].rotation.z = -flap
		wings[1].rotation.z = flap
	var trail := _smoke(fx, Color(0.04, 0.04, 0.06, 0.6), 16, 0.6, 0.08, 0.12, Vector3(0, -1.0, 0))
	return {"tick": tick, "trail": trail, "extra_trail": _particles(fx, col, 14, 0.4, 0.04, 0.07, Vector3.ZERO)}


static func _ember(host: Node3D, col: Color, fx: Node3D) -> Dictionary:
	var fire := col.lerp(Color(1.0, 0.55, 0.15), 0.5)
	host.add_child(_mesh(_sphere(0.2), SpellFx._add_mat(fire, 1.2)))
	var trail := _particles(fx, fire.lightened(0.2), 50, 0.5, 0.06, 0.16, Vector3(0, 1.5, 0))
	return {"trail": trail}


static func _sphere(r: float, h := 1.0) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0 * h
	s.radial_segments = 10
	s.rings = 6
	return s


## A trail of soft additive motes; amount 0 gives an empty emitter.
static func _particles(fx: Node3D, col: Color, amount: int, life: float, s0: float, s1: float, grav: Vector3, vel := 0.6) -> CPUParticles3D:
	var t := CPUParticles3D.new()
	t.local_coords = false
	t.amount = maxi(amount, 1)
	t.emitting = amount > 0
	t.lifetime = life
	t.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	t.emission_sphere_radius = 0.06
	t.direction = Vector3.UP
	t.spread = 180.0
	t.initial_velocity_min = vel * 0.3
	t.initial_velocity_max = vel
	t.gravity = grav
	t.damping_min = 1.0
	t.damping_max = 2.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	t.scale_amount_curve = curve
	t.scale_amount_min = s0 / 0.1
	t.scale_amount_max = s1 / 0.1
	var g := Gradient.new()
	g.set_color(0, Color(col.lightened(0.3), 0.9))
	g.set_color(1, Color(col, 0.0))
	t.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(0.1, 0.1)
	q.material = SpellFx._dot_mat()
	t.mesh = q
	t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.add_child(t)
	return t


## Dark drifting smoke (alpha blended, not added, so it reads as shadow).
static func _smoke(fx: Node3D, col: Color, amount: int, life: float, s0: float, s1: float, grav: Vector3) -> CPUParticles3D:
	var t := _particles(fx, col, amount, life, s0, s1, grav, 0.4)
	var g := Gradient.new()
	g.set_color(0, col)
	g.set_color(1, Color(col, 0.0))
	t.color_ramp = g
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.5))
	curve.add_point(Vector2(1.0, 1.0))
	t.scale_amount_curve = curve
	(t.mesh as QuadMesh).material = smoke_mat()
	return t


## A jagged two-ribbon bolt from a to b (crossed so it reads from any side).
static func jag(im: ImmediateMesh, a: Vector3, b: Vector3, segs: int, amp: float, width: float, col: Color) -> Array[Vector3]:
	var d := b - a
	var dir := d.normalized()
	var s1 := dir.cross(Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
	var s2 := dir.cross(s1).normalized()
	var pts: Array[Vector3] = [a]
	for i in range(1, segs):
		var f := float(i) / segs
		pts.append(a + d * f + s1 * rng.randf_range(-amp, amp) + s2 * rng.randf_range(-amp, amp))
	pts.append(b)
	for side in [s1, s2]:
		for i in pts.size() - 1:
			var w0 := width * (1.0 - 0.6 * float(i) / pts.size())
			var w1 := width * (1.0 - 0.6 * float(i + 1) / pts.size())
			var p0: Vector3 = pts[i]
			var p1: Vector3 = pts[i + 1]
			_quad(im, p0 - side * w0, p0 + side * w0, p1 + side * w1, p1 - side * w1, col)
	return pts


## A soft wide band along a jag path: bright in the middle, clear at the edges.
static func halo(im: ImmediateMesh, pts: Array[Vector3], width: float, col: Color) -> void:
	var dir := (pts[-1] - pts[0]).normalized()
	var s1 := dir.cross(Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
	var s2 := dir.cross(s1).normalized()
	var clear := Color(col, 0.0)
	for side in [s1, s2]:
		for i in pts.size() - 1:
			var p0: Vector3 = pts[i]
			var p1: Vector3 = pts[i + 1]
			for sd in [-1.0, 1.0]:
				var e: Vector3 = side * width * sd
				for v in [[p0, col], [p0 + e, clear], [p1 + e, clear], [p0, col], [p1 + e, clear], [p1, col]]:
					im.surface_set_color(v[1])
					im.surface_add_vertex(v[0])


static func _quad(im: ImmediateMesh, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	for v in [a, b, c, a, c, d]:
		im.surface_set_color(col)
		im.surface_add_vertex(v)


# ------------------------------------------------------------------ ground spells

## A bolt out of the sky onto `at`, with branches; it re-strikes a few times.
static func lightning(fx: Node3D, at: Vector3, col: Color, big: bool) -> Dictionary:
	var n := Node3D.new()
	fx.add_child(n)
	n.global_position = at
	var im := ImmediateMesh.new()
	n.add_child(_mesh(im, ribbon_mat()))
	var light := OmniLight3D.new()
	light.light_color = col.lightened(0.4)
	light.omni_range = 12.0 if big else 8.0
	light.position = Vector3(0, 3.0, 0)
	n.add_child(light)
	var state := {"t": 0.0}
	var c := col.lightened(0.55)
	var tick := func(k: float, dt: float) -> void:
		state.t -= dt
		var a := (1.0 - k) * (1.0 - k)
		light.light_energy = (8.0 if big else 5.0) * a * (0.6 + 0.4 * sin(k * 60.0))
		if state.t > 0.0:
			return
		state.t = 0.06
		im.clear_surfaces()
		if k > 0.75:
			return
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		var top := Vector3(rng.randf_range(-1.0, 1.0), 16.0, rng.randf_range(-1.0, 1.0))
		var w := 0.26 if big else 0.18
		var path := jag(im, top, Vector3.ZERO, 14, 0.7, w, Color(c, a))
		# A wide soft halo along the same path, in the caster's colour.
		halo(im, path, w * 4.0, Color(col, 0.35 * a))
		for i in (4 if big else 2):
			var f := rng.randf_range(0.25, 0.75)
			var from := top.lerp(Vector3.ZERO, f)
			var to := from + Vector3(rng.randf_range(-2.5, 2.5), -rng.randf_range(1.5, 4.0), rng.randf_range(-2.5, 2.5))
			to.y = maxf(to.y, 0.1)
			jag(im, from, to, 6, 0.4, w * 0.5, Color(col, a))
		im.surface_end()
	return {"node": n, "tick": tick}


## Spikes that burst out of the ground over the circle, hold, then sink.
static func spikes(fx: Node3D, at: Vector3, radius: float, col: Color, rock: bool) -> Node3D:
	var holder := Node3D.new()
	fx.add_child(holder)
	holder.global_position = at
	var mat := lit(Color(0.3, 0.27, 0.24), 0.95) if rock else lit(Color(0.26, 0.22, 0.12), 0.75, 0.0, col, 0.35)
	var count := int(clampf(radius * radius * (2.2 if rock else 3.5), 8.0, 42.0))
	for i in count:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * radius * 0.92
		var h := rng.randf_range(0.6, 1.3) * (1.1 if rock else 1.0)
		var base := rng.randf_range(0.1, 0.18) * (1.8 if rock else 1.0)
		var m := _cyl(0.0, base, h, 5 if rock else 6)
		var sp := _mesh(m, mat, Vector3(cos(a) * r, h * 0.45, sin(a) * r))
		# Lean outward from the middle, like they tore up through the floor.
		sp.rotation = Vector3(sin(a) * 0.35 * r / radius, rng.randf() * TAU, -cos(a) * 0.35 * r / radius)
		holder.add_child(sp)
	if not rock:
		# Thorny vines: a few small barbs tipped in the caster's glow.
		for i in int(count * 0.5):
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * radius
			holder.add_child(_mesh(_sphere(0.05), SpellFx._add_mat(col.lightened(0.3), 1.8), Vector3(cos(a) * r, rng.randf_range(0.2, 0.9), sin(a) * r)))
	holder.scale = Vector3(1, 0.01, 1)
	return holder


## Rolling dark grave smoke over the circle.
static func grave_smoke(fx: Node3D, at: Vector3, radius: float, col: Color) -> void:
	var p := _smoke(fx, Color(0.07, 0.05, 0.09, 0.7), int(30 + radius * 10), 1.4, 0.6, 1.4, Vector3(0, 0.8, 0))
	p.local_coords = true
	p.one_shot = true
	p.explosiveness = 0.85
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius * 0.8
	p.initial_velocity_max = 1.5
	p.global_position = at + Vector3(0, 0.3, 0)
	p.emitting = true
	p.finished.connect(p.queue_free)
	var g := _particles(fx, col, int(16 + radius * 4), 1.0, 0.06, 0.12, Vector3(0, 1.5, 0), 2.0)
	g.local_coords = true
	g.one_shot = true
	g.explosiveness = 0.8
	g.emission_sphere_radius = radius * 0.7
	g.global_position = at + Vector3(0, 0.3, 0)
	g.finished.connect(g.queue_free)


# ------------------------------------------------------------------ melee

## A bright crescent where the weapon passed, at weapon height, brightest at
## the leading edge. Returned with its material for the fade.
static func swoosh(range_m: float, arc_deg: float, col: Color, height: float) -> MeshInstance3D:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var seg := 24
	var half := deg_to_rad(arc_deg) * 0.5
	var r1 := range_m * 0.95
	for i in seg:
		var f0 := float(i) / seg
		var f1 := float(i + 1) / seg
		var a0 := -half + f0 * half * 2.0
		var a1 := -half + f1 * half * 2.0
		# Wider and brighter toward the end of the swing.
		var r0a := r1 * (1.0 - 0.45 * f0)
		var r0b := r1 * (1.0 - 0.45 * f1)
		var o0 := Vector3(sin(a0), 0, -cos(a0))
		var o1 := Vector3(sin(a1), 0, -cos(a1))
		var h0 := height + 0.25 * (1.0 - f0)
		var h1 := height + 0.25 * (1.0 - f1)
		var ca := Color(col, f0 * f0)
		var cb := Color(col, f1 * f1)
		var ci := Color(col, 0.0)
		var quad := [o0 * r0a + Vector3(0, h0, 0), o0 * r1 + Vector3(0, h0, 0), o1 * r1 + Vector3(0, h1, 0), o1 * r0b + Vector3(0, h1, 0)]
		var qc := [ci, ca, cb, ci]
		for k in [0, 1, 2, 0, 2, 3]:
			verts.append(quad[k])
			cols.append(qc[k])
	var am := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var m := ribbon_mat().duplicate() as StandardMaterial3D
	m.albedo_color = Color(2.2, 2.2, 2.2, 1.0)
	var mi := _mesh(am, m)
	return mi


# ------------------------------------------------------------------ Chainbound

## Lays links along a polyline, evenly spaced by the chain's step.
static func lay_path(links: MultiMeshInstance3D, pts: Array[Vector3]) -> void:
	var mm := links.multimesh
	var step: float = links.get_meta("step", 0.12)
	var n := 0
	var carry := 0.0
	for s in pts.size() - 1:
		var a := pts[s]
		var d := pts[s + 1] - a
		var len := d.length()
		if len < 0.001:
			continue
		var dir := d / len
		var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
		var b0 := Basis.looking_at(dir, up)
		var b1 := b0 * Basis(Vector3.FORWARD, PI * 0.5)
		var t := carry
		while t < len and n < mm.instance_count:
			mm.set_instance_transform(n, Transform3D(b1 if n % 2 == 1 else b0, a + dir * t))
			n += 1
			t += step
		carry = t - len
	mm.visible_instance_count = n


## Pactlash: the oath chain cracks round like a whip, its tip trailing the
## swing. Returns {"node", "tick"} for SpellFx's "tick" fade.
static func lash(fx: Node3D, at: Vector3, yaw: float, range_m: float, arc_deg: float, height: float, col: Color) -> Dictionary:
	var links := chain_links(fx, col, 40, 1.25)
	var tip := _mesh(_sphere(0.1), SpellFx._add_mat(col.lightened(0.3), 2.0))
	links.add_child(tip)
	var half := deg_to_rad(arc_deg) * 0.5
	var rot := Basis(Vector3.UP, yaw)
	var tick := func(k: float, _dt: float) -> void:
		var swing := 1.0 - pow(1.0 - minf(k / 0.55, 1.0), 2.0)
		var reach := range_m * 0.95 * (1.0 - clampf((k - 0.7) / 0.3, 0.0, 1.0))
		var pts: Array[Vector3] = []
		for i in 9:
			var f := float(i) / 8.0
			# The tip lags the hand, so the chain bows back along the swing.
			var ang := -half + half * 2.0 * swing - f * f * 0.6 * (1.0 - swing * 0.6)
			var r := lerpf(0.35, maxf(reach, 0.36), f)
			pts.append(at + rot * Vector3(sin(ang) * r, height + 0.12 * (1.0 - f), -cos(ang) * r))
		lay_path(links, pts)
		tip.global_position = pts[-1]
		tip.visible = reach > 0.4
	tick.call(0.0, 0.0)
	return {"node": links, "tick": tick}


## Break the Seal: a gilt seal appears in front of her and is torn in two,
## the halves spinning apart.
static func seal(fx: Node3D, at: Vector3, yaw: float, col: Color) -> Dictionary:
	var holder := Node3D.new()
	fx.add_child(holder)
	holder.global_position = at
	holder.rotation.y = yaw
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.72, 0.58, 0.3)
	m.metallic = 0.85
	m.roughness = 0.35
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var halves: Array[Node3D] = []
	for side in [-1.0, 1.0]:
		var piv := Node3D.new()
		holder.add_child(piv)
		var h := MeshInstance3D.new()
		h.mesh = _half_ring(0.5, 0.12, 0.07, side)
		h.material_override = m
		h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		piv.add_child(h)
		halves.append(piv)
	var core := _mesh(_sphere(0.16), SpellFx._add_mat(col.lightened(0.4), 2.2))
	holder.add_child(core)
	var tick := func(k: float, _dt: float) -> void:
		var grow := minf(k / 0.2, 1.0)
		var split := clampf((k - 0.22) / 0.78, 0.0, 1.0)
		var e := 1.0 - (1.0 - split) * (1.0 - split)
		for i in 2:
			var sd := -1.0 if i == 0 else 1.0
			halves[i].position = Vector3(sd * e * 1.3, -e * e * 0.5, 0)
			halves[i].rotation = Vector3(0, 0, -sd * e * 2.4)
			halves[i].scale = Vector3.ONE * lerpf(0.5, 1.0, grow) * (1.0 - clampf((k - 0.75) / 0.25, 0.0, 1.0))
		core.scale = Vector3.ONE * maxf(0.01, (1.0 - split) * grow)
	tick.call(0.0, 0.0)
	return {"node": holder, "tick": tick}


## Half of a thick ring in the XY plane (side -1 left, 1 right), facing -Z.
static func _half_ring(r: float, w: float, depth: float, side: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 14
	var ri := r - w
	for i in seg:
		# A small gap at the top and bottom: the crack it broke along.
		var a0 := lerpf(0.12, PI - 0.12, float(i) / seg)
		var a1 := lerpf(0.12, PI - 0.12, float(i + 1) / seg)
		var o0 := Vector3(sin(a0) * side, cos(a0), 0)
		var o1 := Vector3(sin(a1) * side, cos(a1), 0)
		var z := Vector3(0, 0, depth * 0.5)
		for face: Array in [
			[o0 * ri - z, o0 * r - z, o1 * r - z, o1 * ri - z, Vector3(0, 0, -1)],
			[o0 * ri + z, o1 * ri + z, o1 * r + z, o0 * r + z, Vector3(0, 0, 1)],
			[o0 * r - z, o0 * r + z, o1 * r + z, o1 * r - z, (o0 + o1).normalized()],
			[o0 * ri - z, o1 * ri - z, o1 * ri + z, o0 * ri + z, -(o0 + o1).normalized()],
		]:
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_normal(face[4])
				st.add_vertex(face[idx])
	return st.commit()


## Covenant Severed: chains tear up out of the floor along the line, each
## snapped off at the top. One multimesh for every link.
static func chain_stalks(fx: Node3D, from: Vector3, to: Vector3, width: float, col: Color) -> Node3D:
	var holder := Node3D.new()
	fx.add_child(holder)
	holder.global_position = from
	var along := to - from
	var side := along.cross(Vector3.UP).normalized()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.045
	torus.outer_radius = 0.09
	torus.rings = 8
	torus.ring_segments = 4
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = torus
	var stalks := 11
	var per := 16
	mm.instance_count = stalks * per
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = chain_iron(col)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)
	var glow := SpellFx._add_mat(col.lightened(0.3), 1.8)
	var n := 0
	for s in stalks:
		var f := (float(s) + rng.randf_range(0.2, 0.8)) / stalks
		var base := along * f + side * rng.randf_range(-0.4, 0.4) * width
		var lean := (side * rng.randf_range(-0.35, 0.35) + along.normalized() * rng.randf_range(-0.15, 0.15) + Vector3.UP).normalized()
		var count := rng.randi_range(9, per)
		var b0 := Basis.looking_at(lean, Vector3.FORWARD if absf(lean.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT)
		var b1 := b0 * Basis(Vector3.FORWARD, PI * 0.5)
		for i in count:
			mm.set_instance_transform(n, Transform3D(b1 if i % 2 == 1 else b0, base + lean * (0.1 + i * 0.15)))
			n += 1
		# The broken end glows where the link gave.
		holder.add_child(_mesh(_sphere(0.09), glow, base + lean * (0.1 + count * 0.15)))
	mm.visible_instance_count = n
	holder.scale = Vector3(1, 0.01, 1)
	return holder
