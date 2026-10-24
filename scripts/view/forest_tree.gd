class_name ForestTree
## A stylised autumn broadleaf built from code: a tapering trunk, two or three
## limbs and a crown of overlapping leaf masses with a mottled, wind-moving
## shader. Original procedural shapes, no textures from outside. View only.

const CROWNS := [
	[Color(0.78, 0.40, 0.12), Color(0.98, 0.66, 0.26)],  # orange
	[Color(0.70, 0.52, 0.12), Color(0.96, 0.80, 0.34)],  # gold
	[Color(0.55, 0.20, 0.09), Color(0.86, 0.40, 0.16)],  # rust
	[Color(0.36, 0.38, 0.14), Color(0.66, 0.62, 0.26)],  # late green
	[Color(0.38, 0.24, 0.62), Color(0.80, 0.66, 1.0)],   # spirit tree: amethyst, faintly lit
]
const SPIRIT := 4

static var _bark: StandardMaterial3D
static var _leaf_shader: Shader
static var _leaf_mats: Array[ShaderMaterial] = []


static func add(parent: Node3D, base: Vector3, height: float, rng: RandomNumberGenerator, crown := -1) -> Node3D:
	var root := Node3D.new()
	root.position = base
	root.rotation.y = rng.randf() * TAU
	parent.add_child(root)
	var trunk_h := height * 0.5
	var r0 := 0.12 + height * 0.024
	_cyl(root, r0 * 0.55, r0, trunk_h, Vector3(0, trunk_h * 0.5, 0), Vector3.ZERO, _bark_mat())
	# Root flare so the trunk sits in the ground instead of on it.
	_cyl(root, r0 * 0.9, r0 * 1.3, 0.35, Vector3(0, 0.12, 0), Vector3.ZERO, _bark_mat())
	var leaf := _leaf_mat(crown if crown >= 0 else rng.randi() % SPIRIT)
	var top := Vector3(0, trunk_h, 0)
	var limbs := 2 + rng.randi() % 2
	for i in limbs:
		var a := TAU * (float(i) / limbs) + rng.randf_range(-0.4, 0.4)
		var lean := rng.randf_range(30.0, 50.0)
		var len := height * rng.randf_range(0.22, 0.32)
		var dir := Vector3(cos(a), 0, sin(a)).rotated(Vector3.UP, 0.0)
		var tilt := Basis(Vector3(-dir.z, 0, dir.x), deg_to_rad(lean))
		var mid := top - Vector3(0, height * 0.12, 0) + tilt * Vector3(0, len * 0.5, 0)
		var limb := _cyl(root, r0 * 0.2, r0 * 0.45, len, mid, Vector3.ZERO, _bark_mat())
		limb.basis = tilt
		var tip := top - Vector3(0, height * 0.12, 0) + tilt * Vector3(0, len, 0)
		_blob(root, tip + Vector3(0, height * 0.08, 0), height * rng.randf_range(0.15, 0.2), leaf, rng)
	# A tall layered crown: a big middle mass, a top, and side masses at
	# different heights so the outline is irregular, not a cap.
	_blob(root, top + Vector3(0, height * 0.2, 0), height * rng.randf_range(0.21, 0.25), leaf, rng)
	_blob(root, top + Vector3(rng.randf_range(-0.1, 0.1) * height, height * 0.42, 0), height * rng.randf_range(0.15, 0.19), leaf, rng)
	for i in 4:
		var a := TAU * i / 4.0 + rng.randf_range(-0.5, 0.5)
		var off := Vector3(cos(a), 0, sin(a)) * height * rng.randf_range(0.14, 0.22)
		_blob(root, top + off + Vector3(0, height * rng.randf_range(0.05, 0.32), 0), height * rng.randf_range(0.12, 0.17), leaf, rng)
	return root


static func _cyl(root: Node3D, top: float, bottom: float, h: float, pos: Vector3, rot: Vector3, m: Material) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 9
	c.rings = 2
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = rot
	root.add_child(mi)
	return mi


static func _blob(root: Node3D, pos: Vector3, r: float, m: Material, rng: RandomNumberGenerator) -> void:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.1
	s.radial_segments = 14
	s.rings = 7
	var mi := MeshInstance3D.new()
	mi.mesh = s
	mi.material_override = m
	mi.position = pos
	mi.rotation.y = rng.randf() * TAU
	root.add_child(mi)


static func _bark_mat() -> StandardMaterial3D:
	if _bark:
		return _bark
	_bark = StandardMaterial3D.new()
	var nt := NoiseTexture2D.new()
	nt.width = 128
	nt.height = 256
	nt.seamless = true
	var n := FastNoiseLite.new()
	n.frequency = 0.05
	n.fractal_octaves = 3
	nt.noise = n
	var g := Gradient.new()
	g.set_color(0, Color(0.16, 0.11, 0.08))
	g.set_color(1, Color(0.42, 0.33, 0.25))
	nt.color_ramp = g
	_bark.albedo_texture = nt
	_bark.uv1_scale = Vector3(3.0, 0.6, 1.0)
	_bark.roughness = 0.95
	return _bark


static func _leaf_mat(i: int) -> ShaderMaterial:
	if _leaf_mats.is_empty():
		_leaf_shader = load("res://scripts/view/shaders/leaves.gdshader")
		var nt := NoiseTexture2D.new()
		nt.width = 256
		nt.height = 256
		nt.seamless = true
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_CELLULAR
		n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
		n.frequency = 0.045
		n.fractal_octaves = 2
		nt.noise = n
		for c: Array in CROWNS:
			var m := ShaderMaterial.new()
			m.shader = _leaf_shader
			m.set_shader_parameter("deep", c[0])
			m.set_shader_parameter("lit", c[1])
			m.set_shader_parameter("clumps", nt)
			m.set_shader_parameter("glow", 0.9 if _leaf_mats.size() == SPIRIT else 0.0)
			_leaf_mats.append(m)
	return _leaf_mats[i]
