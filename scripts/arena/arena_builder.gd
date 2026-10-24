class_name ArenaBuilder
extends Node3D
## The Proving Court: a small ruined courtyard built from primitives.
## About 44 x 44 m. Open, flat combat ground in the middle; cover and
## history (broken pillars, an old arch, overgrowth) around the edges.
## All collision is on layer 1 (world).

const HALF := 22.0
const FLOOR_THICK := 1.0

var _stone_mats: Array[StandardMaterial3D] = []


func _ready() -> void:
	_stone_mats = [_stone(Palette.STONE), _stone(Palette.STONE_DARK), _stone(Palette.STONE_WARM)]
	_environment()
	_floor()
	_walls()
	_pillars()
	_arch()
	_props()
	_trees()


func _stone(c: Color) -> StandardMaterial3D:
	# Weathering from procedural noise, mapped in world space so blocks of
	# any size share the same grain. No image textures involved.
	var m := StandardMaterial3D.new()
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	var n := FastNoiseLite.new()
	n.frequency = 0.03
	n.fractal_octaves = 4
	tex.noise = n
	var ramp := Gradient.new()
	ramp.set_color(0, c.darkened(0.35))
	ramp.set_color(1, c.lightened(0.05))
	tex.color_ramp = ramp
	m.albedo_texture = tex
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.25, 0.25, 0.25)
	m.roughness = 0.92
	return m


func _environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.38, 0.52, 0.72)
	sm.sky_horizon_color = Color(0.80, 0.74, 0.62)
	sm.ground_horizon_color = Color(0.55, 0.50, 0.42)
	sm.ground_bottom_color = Color(0.25, 0.22, 0.18)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.78, 0.72, 0.62)
	env.fog_density = 0.002
	env.fog_sky_affect = 0.2
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.88, 0.70)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	sun.rotation_degrees = Vector3(-48, -35, 0)
	add_child(sun)


func _static_box(size: Vector3, pos: Vector3, m: Material, rot_deg := Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Unit.LAYER_WORLD
	body.collision_mask = 0
	body.position = pos
	body.rotation_degrees = rot_deg
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	body.add_child(mi)
	add_child(body)
	return body


func _static_cyl(r: float, h: float, pos: Vector3, m: Material, rot_deg := Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Unit.LAYER_WORLD
	body.collision_mask = 0
	body.position = pos
	body.rotation_degrees = rot_deg
	var shape := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = r
	cs.height = h
	shape.shape = cs
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 14
	mi.mesh = cm
	mi.material_override = m
	body.add_child(mi)
	add_child(body)
	return body


func _deco(mesh: Mesh, m: Material, pos: Vector3, scale_v := Vector3.ONE, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.scale = scale_v
	mi.rotation_degrees = rot_deg
	add_child(mi)
	return mi


func _floor() -> void:
	_static_box(Vector3(HALF * 2 + 8, FLOOR_THICK, HALF * 2 + 8), Vector3(0, -FLOOR_THICK * 0.5, 0), _stone_mats[0])
	# Worn inlaid circle in the middle: a landmark for orientation.
	var ring := TorusMesh.new()
	ring.inner_radius = 5.6
	ring.outer_radius = 6.0
	ring.rings = 64
	_deco(ring, Palette.mat(Palette.BRASS.darkened(0.35), 0.6, 0.6), Vector3(0, 0.0, 0), Vector3(1, 0.04, 1))
	var inner := CylinderMesh.new()
	inner.top_radius = 5.6
	inner.bottom_radius = 5.6
	inner.height = 0.02
	inner.radial_segments = 48
	_deco(inner, _stone_mats[2], Vector3(0, 0.005, 0))


## Uneven, broken perimeter walls with gaps. Heights vary so the line reads
## as a ruin, not a box.
func _walls() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for side in 4:
		var x := -HALF
		while x < HALF:
			var w := rng.randf_range(2.5, 5.0)
			var h := rng.randf_range(1.4, 3.6)
			if rng.randf() < 0.15:
				h = rng.randf_range(0.5, 0.9)  # tumbled section
			var centre := x + w * 0.5
			var pos := Vector3(centre, h * 0.5, -HALF) if side == 0 else Vector3(centre, h * 0.5, HALF)
			var size := Vector3(w, h, 1.2)
			if side >= 2:
				pos = Vector3(-HALF if side == 2 else HALF, h * 0.5, centre)
				size = Vector3(1.2, h, w)
			_static_box(size, pos, _stone_mats[rng.randi() % 3])
			if rng.randf() < 0.45:
				var moss := SphereMesh.new()
				moss.radius = 0.6
				moss.height = 1.2
				_deco(moss, Palette.mat(Palette.MOSS), pos + Vector3(0, h * 0.5, 0), Vector3(w * 0.6, 0.25, 0.9))
			x += w


func _pillars() -> void:
	var spots := [Vector3(-11, 0, -9), Vector3(11, 0, -9), Vector3(-11, 0, 9), Vector3(11, 0, 9)]
	var heights := [4.2, 2.1, 1.3, 3.4]
	for i in spots.size():
		var h: float = heights[i]
		_static_cyl(0.75, h, spots[i] + Vector3(0, h * 0.5, 0), _stone_mats[i % 3])
		_static_box(Vector3(2.0, 0.4, 2.0), spots[i] + Vector3(0, 0.2, 0), _stone_mats[1])
	# A fallen drum of a pillar: low cover you can shoot over the end of.
	_static_cyl(0.7, 3.6, Vector3(-5, 0.7, 13), _stone_mats[2], Vector3(0, 30, 90))


## Old gate on the north wall, with lapis banners.
func _arch() -> void:
	var z := -HALF + 0.2
	_static_box(Vector3(1.6, 6.0, 1.6), Vector3(-3.2, 3.0, z), _stone_mats[0])
	_static_box(Vector3(1.6, 6.0, 1.6), Vector3(3.2, 3.0, z), _stone_mats[0])
	_static_box(Vector3(8.2, 1.2, 1.8), Vector3(0, 6.6, z), _stone_mats[2])
	var cloth := Palette.mat(Palette.LAPIS)
	var brass := Palette.mat(Palette.BRASS, 0.45, 0.8)
	for x in [-3.2, 3.2]:
		_deco(BoxMesh.new(), cloth, Vector3(x, 4.2, z + 0.85), Vector3(1.1, 2.8, 0.05))
		_deco(BoxMesh.new(), brass, Vector3(x, 5.65, z + 0.85), Vector3(1.3, 0.08, 0.08))
		var sigil := CylinderMesh.new()
		sigil.top_radius = 0.28
		sigil.bottom_radius = 0.28
		sigil.height = 0.02
		_deco(sigil, brass, Vector3(x, 4.6, z + 0.89), Vector3.ONE, Vector3(90, 0, 0))


func _props() -> void:
	# Braziers either side of the arch: warm light, readable landmarks.
	for x in [-7.0, 7.0]:
		var p := Vector3(x, 0, -HALF + 3.0)
		_static_cyl(0.45, 1.1, p + Vector3(0, 0.55, 0), _stone_mats[1])
		var bowl := CylinderMesh.new()
		bowl.top_radius = 0.7
		bowl.bottom_radius = 0.4
		bowl.height = 0.4
		_deco(bowl, Palette.mat(Palette.IRON, 0.5, 0.7), p + Vector3(0, 1.3, 0))
		var flame := SphereMesh.new()
		flame.radius = 0.35
		flame.height = 0.9
		_deco(flame, Palette.glow(Palette.AMBER, 4.0), p + Vector3(0, 1.7, 0))
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.7, 0.4)
		light.light_energy = 2.0
		light.omni_range = 8.0
		light.position = p + Vector3(0, 2.2, 0)
		add_child(light)
	# Rubble near the walls (decoration only; kept out of the fighting space).
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 22:
		var a := rng.randf() * TAU
		var r := rng.randf_range(16.5, 20.0)
		var s := rng.randf_range(0.3, 0.8)
		_deco(BoxMesh.new(), _stone_mats[rng.randi() % 3], Vector3(cos(a) * r, s * 0.4, sin(a) * r),
			Vector3(s, s * 0.7, s * 1.2), Vector3(rng.randf() * 30, rng.randf() * 180, rng.randf() * 30))


## Autumn trees outside the corners, so they frame the court without
## blocking sightlines inside it.
func _trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var bark := Palette.mat(Palette.WOOD.darkened(0.2))
	var leaves := [Palette.mat(Palette.AUTUMN), Palette.mat(Palette.AUTUMN_DEEP), Palette.mat(Color(0.72, 0.58, 0.20))]
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		for k in 2:
			var base := Vector3(corner.x * (HALF + 3.0 + k * 3.5), 0, corner.y * (HALF + 1.5 + k * 2.0))
			var h := rng.randf_range(5.0, 7.5)
			var trunk := CylinderMesh.new()
			trunk.top_radius = 0.25
			trunk.bottom_radius = 0.45
			trunk.height = h
			_deco(trunk, bark, base + Vector3(0, h * 0.5, 0))
			for j in 4:
				var blob := SphereMesh.new()
				blob.radius = rng.randf_range(1.4, 2.2)
				blob.height = blob.radius * 1.7
				_deco(blob, leaves[rng.randi() % 3], base + Vector3(rng.randf_range(-1.2, 1.2), h + rng.randf_range(-0.8, 0.8), rng.randf_range(-1.2, 1.2)))
