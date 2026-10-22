class_name Grass
## Short grass clumps for wall feet and corners, drawn with one MultiMesh.
## The blades are built here from triangles (original geometry); the shader
## colours them root to tip and moves them in the wind.

static var _mesh: ArrayMesh
static var _mat: ShaderMaterial


static func clump_mesh() -> ArrayMesh:
	if _mesh:
		return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	for b in 9:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.0, 0.16)
		var root := Vector3(cos(a) * r, 0.0, sin(a) * r)
		var h := rng.randf_range(0.22, 0.42)
		var w := rng.randf_range(0.025, 0.04)
		var face := rng.randf() * TAU
		var side := Vector3(cos(face), 0, sin(face)) * w
		var bend := Vector3(cos(a), 0, sin(a)) * h * rng.randf_range(0.15, 0.4)
		var segs := 3
		var prev_l := root - side
		var prev_r := root + side
		for s in segs:
			var t1 := float(s + 1) / segs
			var c := root + Vector3(0, h * t1, 0) + bend * t1 * t1
			var half := side * (1.0 - t1 * 0.9)
			var l := c - half
			var rr := c + half
			var t0 := float(s) / segs
			for v: Array in [[prev_l, t0], [prev_r, t0], [rr, t1], [prev_l, t0], [rr, t1], [l, t1]]:
				st.set_normal(Vector3(0, 1, 0))
				st.set_uv(Vector2(0.0, v[1]))
				st.add_vertex(v[0])
			prev_l = l
			prev_r = rr
	_mesh = st.commit()
	return _mesh


static func material() -> ShaderMaterial:
	if _mat:
		return _mat
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://scripts/view/shaders/grass.gdshader")
	return _mat
