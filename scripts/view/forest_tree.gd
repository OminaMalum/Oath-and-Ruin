class_name ForestTree
## A stylised broadleaf built from code: a leaning, tapering trunk that forks
## into limbs, and a crown made of many lumpy leaf clumps gathered round the
## limb tips. Each tree is one mesh (bark and leaves as two surfaces), so a
## forest costs two draw calls per tree. The crown's normals are bent toward
## its centre, so light falls over it as a few big soft masses, the way a
## painted tree reads, instead of as a pile of balls. Original procedural
## shapes, no textures from outside. View only.

## [deep, lit]. Restrained autumn: olive, old gold and rust lead; one in five
## is the faintly lit amethyst spirit tree (only placed on purpose).
const CROWNS := [
	[Color(0.62, 0.44, 0.17), Color(0.95, 0.72, 0.32)],  # old gold
	[Color(0.44, 0.46, 0.2), Color(0.76, 0.74, 0.36)],  # olive
	[Color(0.64, 0.3, 0.14), Color(0.92, 0.52, 0.24)],  # rust
	[Color(0.36, 0.42, 0.2), Color(0.64, 0.7, 0.36)],  # late green
	[Color(0.42, 0.34, 0.56), Color(0.76, 0.68, 0.92)],  # spirit tree: amethyst
]
const SPIRIT := 4
## How far the crown normals lean toward the crown's centre direction.
const SOFT := 0.72

static var _bark: StandardMaterial3D
static var _leaf_shader: Shader
static var _leaf_mats: Array[ShaderMaterial] = []
static var _ico: PackedVector3Array
static var _ico_idx: PackedInt32Array


static func add(parent: Node3D, base: Vector3, height: float, rng: RandomNumberGenerator, crown := -1) -> Node3D:
	var root := Node3D.new()
	root.position = base
	root.rotation.y = rng.randf() * TAU
	parent.add_child(root)
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Trunk: a gentle lean and bend, flared into the ground.
	var r0 := 0.12 + height * 0.026
	var trunk_h := height * rng.randf_range(0.42, 0.5)
	var lean := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * height * 0.05
	var trunk: Array[Vector3] = []
	for i in 6:
		var t := i / 5.0
		trunk.append(Vector3(0, t * trunk_h, 0) + lean * (t * t) + lean.rotated(Vector3.UP, 1.6) * sin(t * PI) * 0.4)
	_tube(bark, trunk, [r0 * 1.5, r0 * 1.05, r0, r0 * 0.9, r0 * 0.8, r0 * 0.7], 9)
	var top := trunk[-1]

	# Limbs fork out and up from the top of the trunk; clumps gather at their
	# tips and along them, so the crown has a shape with gaps in it.
	var centre := top + Vector3(0, height * 0.24, 0)
	var crown_r := height * 0.3
	var clumps: Array = []  # [position, radius]
	var limbs := 3 + rng.randi() % 2
	for i in limbs:
		var a := TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / limbs
		var out := Vector3(cos(a), 0, sin(a))
		var up := rng.randf_range(0.8, 1.3)
		var reach := height * rng.randf_range(0.2, 0.3)
		var start := trunk[4].lerp(top, rng.randf())
		var tip := start + (out * 0.75 + Vector3(0, up, 0)).normalized() * reach
		var mid := start.lerp(tip, 0.5) + Vector3(0, reach * 0.08, 0)
		_tube(bark, [start, mid, tip], [r0 * 0.55, r0 * 0.38, r0 * 0.2], 6)
		# A twig off each limb.
		var twig := mid + (out.rotated(Vector3.UP, rng.randf_range(-1.0, 1.0)) + Vector3(0, 0.8, 0)).normalized() * reach * 0.5
		_tube(bark, [mid, twig], [r0 * 0.22, r0 * 0.1], 5)
		clumps.append([tip + Vector3(0, height * 0.04, 0), height * rng.randf_range(0.13, 0.17)])
		clumps.append([twig, height * rng.randf_range(0.1, 0.13)])
		clumps.append([mid.lerp(tip, 0.5) + out * height * 0.06, height * rng.randf_range(0.09, 0.12)])
	# The top and a few fillers so the crown reads as one canopy from far off.
	clumps.append([centre + Vector3(0, height * 0.14, 0), height * rng.randf_range(0.15, 0.18)])
	clumps.append([centre, height * rng.randf_range(0.17, 0.2)])
	for i in 3:
		var a := rng.randf() * TAU
		clumps.append([centre + Vector3(cos(a), rng.randf_range(-0.2, 0.5), sin(a)) * crown_r * 0.6, height * rng.randf_range(0.1, 0.14)])
	for c: Array in clumps:
		_clump(leaves, c[0], float(c[1]) * 1.3, centre, rng)

	var mesh := ArrayMesh.new()
	bark.generate_tangents()
	bark.commit(mesh)
	leaves.commit(mesh)
	mesh.surface_set_material(0, _bark_mat())
	mesh.surface_set_material(1, _leaf_mat(crown if crown >= 0 else rng.randi() % SPIRIT))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	root.add_child(mi)
	return root


## A tube along points, radius per point, with UVs running up the bark.
static func _tube(st: SurfaceTool, pts: Array, radii: Array, seg: int) -> void:
	var rings: Array = []
	var v := 0.0
	for i in pts.size():
		var p: Vector3 = pts[i]
		var a: Vector3 = pts[maxi(i - 1, 0)]
		var b: Vector3 = pts[mini(i + 1, pts.size() - 1)]
		var t := (b - a).normalized()
		var ref := Vector3.FORWARD if absf(t.dot(Vector3.UP)) > 0.95 else Vector3.UP
		var x := t.cross(ref).normalized()
		var y := t.cross(x).normalized()
		if i > 0:
			v += (p - (pts[i - 1] as Vector3)).length()
		var ring: Array = []
		for k in seg + 1:
			var th := TAU * k / seg
			var n := x * cos(th) + y * sin(th)
			ring.append([p + n * float(radii[i]), n, Vector2(float(k) / seg, v)])
		rings.append(ring)
	for i in rings.size() - 1:
		for k in seg:
			for c: Array in [rings[i][k], rings[i + 1][k], rings[i][k + 1], rings[i][k + 1], rings[i + 1][k], rings[i + 1][k + 1]]:
				st.set_normal(c[1])
				st.set_uv(c[2])
				st.add_vertex(c[0])


## One lumpy clump of leaves: a displaced icosphere whose normals lean toward
## the crown centre's outward direction.
static func _clump(st: SurfaceTool, at: Vector3, r: float, centre: Vector3, rng: RandomNumberGenerator) -> void:
	_ensure_ico()
	var seed := rng.randf() * 100.0
	var pts := PackedVector3Array()
	pts.resize(_ico.size())
	for i in _ico.size():
		var d := _ico[i]
		var bump := 1.0 + 0.22 * sin(d.x * 5.1 + seed) * sin(d.y * 4.3 + seed * 1.7) * sin(d.z * 4.7 + seed * 0.6)
		bump *= 0.82 if d.y < -0.3 else 1.0  # flatter underneath
		pts[i] = at + d * r * bump
	for i in range(0, _ico_idx.size(), 3):
		for j in 3:
			var vi := _ico_idx[i + j]
			var p := pts[vi]
			var outward := (p - centre).normalized()
			st.set_normal(_ico[vi].lerp(outward, SOFT).normalized())
			st.add_vertex(p)


static func _ensure_ico() -> void:
	if not _ico.is_empty():
		return
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v: Array[Vector3] = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t),
		Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for i in v.size():
		v[i] = v[i].normalized()
	var f := [0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1]
	# One subdivision: 80 faces, enough for a lumpy outline at game distance.
	var mid := {}
	var out := PackedInt32Array()
	var get_mid := func(a: int, b: int) -> int:
		var key := mini(a, b) * 1000 + maxi(a, b)
		if not mid.has(key):
			mid[key] = v.size()
			v.append((v[a] + v[b]).normalized())
		return mid[key]
	for i in range(0, f.size(), 3):
		var a: int = f[i]
		var b: int = f[i + 1]
		var c: int = f[i + 2]
		var ab: int = get_mid.call(a, b)
		var bc: int = get_mid.call(b, c)
		var ca: int = get_mid.call(c, a)
		out.append_array([a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca])
	_ico = PackedVector3Array(v)
	_ico_idx = out


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
	g.set_color(0, Color(0.16, 0.12, 0.09))
	g.set_color(1, Color(0.38, 0.32, 0.26))
	nt.color_ramp = g
	_bark.albedo_texture = nt
	_bark.uv1_scale = Vector3(1.0, 0.5, 1.0)
	_bark.roughness = 0.95
	_bark.cull_mode = BaseMaterial3D.CULL_DISABLED
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
			m.set_shader_parameter("glow", 0.6 if _leaf_mats.size() == SPIRIT else 0.0)
			_leaf_mats.append(m)
	return _leaf_mats[i]
