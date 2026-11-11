class_name Runes
## Glowing rune script for walls, plinths and crystals. The glyphs are drawn
## here from seeded straight strokes on a small grid (an original, made up
## script), so nothing is copied from any real alphabet or game.

static var _strip: ImageTexture
static var _mats := {}


## A strip of 12 glyphs, white on transparent, 1024 x 96.
static func strip() -> ImageTexture:
	if _strip:
		return _strip
	var w := 1024
	var h := 96
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1919
	var cell := w / 12
	for g in 12:
		var ox := g * cell + 14
		var pts: Array[Vector2] = []
		for yy in 4:
			for xx in 3:
				pts.append(Vector2(ox + xx * 28, 10 + yy * 25))
		var strokes := 3 + rng.randi() % 3
		var a := pts[rng.randi() % pts.size()]
		for s in strokes:
			var b := pts[rng.randi() % pts.size()]
			if b == a:
				continue
			_line(img, a, b, 4.0)
			a = b if rng.randf() < 0.7 else pts[rng.randi() % pts.size()]
		if rng.randf() < 0.4:
			_dot(img, pts[rng.randi() % pts.size()], 6.0)
	img.generate_mipmaps()
	_strip = ImageTexture.create_from_image(img)
	return _strip


static func _line(img: Image, a: Vector2, b: Vector2, r: float) -> void:
	var n := int(a.distance_to(b))
	for i in n + 1:
		_dot(img, a.lerp(b, float(i) / maxf(n, 1)), r)


static func _dot(img: Image, c: Vector2, r: float) -> void:
	for y in range(int(c.y - r - 1), int(c.y + r + 2)):
		for x in range(int(c.x - r - 1), int(c.x + r + 2)):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var d := Vector2(x, y).distance_to(c)
			var al := clampf(r + 0.5 - d, 0.0, 1.0)
			if al > img.get_pixel(x, y).a:
				img.set_pixel(x, y, Color(1, 1, 1, al))


## Additive, self lit rune material in `col`.
static func material(col: Color, energy := 1.2) -> StandardMaterial3D:
	var key := "%s:%f" % [col.to_html(), energy]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = strip()
	m.albedo_color = Color(col.r * energy, col.g * energy, col.b * energy, 1.0)
	m.cull_mode = BaseMaterial3D.CULL_BACK
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m


## A band of runes on a flat face. `normal` is the face's outward direction
## (X or Z axis); the band floats 1 cm off the face.
static func band(parent: Node3D, center: Vector3, normal: Vector3, length: float, height: float, col: Color,
		glyph_offset := 0.0) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(length, height)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	var m := material(col).duplicate() as StandardMaterial3D
	m.uv1_scale = Vector3(length / (height * 10.6), 1, 1)
	m.uv1_offset = Vector3(glyph_offset, 0, 0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = center + normal * 0.012
	mi.basis = Basis.looking_at(-normal, Vector3.UP)
	parent.add_child(mi)
	return mi
