class_name Art
## Environment art: CC0 Poly Haven textures, sky and props (see ASSET_MANIFEST.csv),
## loaded once and shared. Everything here is view only; the sim never reads it.
## Materials handed to units that fade for the camera must be duplicated by the
## caller (UnitView does), since a fade changes the material's alpha.

const TEX := "res://assets/env/textures/"
const MODELS := "res://assets/env/models/"
const SKY := "res://assets/env/hdri/qwantani_late_afternoon_puresky_2k.hdr"

## Texture sets: id -> metres covered by one repeat of the texture.
const SETS := {
	"cobble": ["cobblestone_floor_04", 2.2],
	"plaza": ["grey_stone_path", 3.0],
	"dirt": ["forest_ground_04", 3.0],
	"leaves": ["brown_mud_leaves_01", 3.5],
	"wall": ["castle_wall_varriation", 3.0],
	"slate": ["castle_wall_slates", 2.0],
}

static var _cache := {}


static func tex(set_id: String, map: String) -> Texture2D:
	var key := "tex:%s:%s" % [set_id, map]
	if not _cache.has(key):
		_cache[key] = load("%s%s_%s_1k.jpg" % [TEX, SETS[set_id][0], map])
	return _cache[key]


## A PBR stone material mapped in world space, so blocks of any size share the
## same grain and nothing stretches. `tint` multiplies the photo colour.
static func stone(set_id: String, tint := Color.WHITE) -> StandardMaterial3D:
	var key := "stone:%s:%s" % [set_id, tint.to_html()]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex(set_id, "diff")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = tex(set_id, "nor_gl")
	m.normal_scale = 1.0
	var arm := tex(set_id, "arm")
	m.ao_enabled = true
	m.ao_texture = arm
	m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.ao_light_affect = 0.4
	m.roughness_texture = arm
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.roughness = 1.0
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	var s := 1.0 / float(SETS[set_id][1])
	m.uv1_scale = Vector3(s, s, s)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[key] = m
	return m


## The whole map floor in one material: cobbled lane, flagstone plazas round
## towers and bases, earth and fallen leaves in the flanks. One surface, so
## there are no stacked floor planes to flicker against each other.
static func ground() -> ShaderMaterial:
	if _cache.has("ground"):
		return _cache["ground"]
	var m := ShaderMaterial.new()
	m.shader = load("res://scripts/view/shaders/ground.gdshader")
	for id: String in ["cobble", "plaza", "dirt", "leaves"]:
		m.set_shader_parameter(id + "_d", tex(id, "diff"))
		m.set_shader_parameter(id + "_n", tex(id, "nor_gl"))
		m.set_shader_parameter(id + "_arm", tex(id, "arm"))
		m.set_shader_parameter(id + "_scale", 1.0 / float(SETS[id][1]))
	var nt := NoiseTexture2D.new()
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	var n := FastNoiseLite.new()
	n.seed = 5
	n.frequency = 0.012
	n.fractal_octaves = 4
	nt.noise = n
	m.set_shader_parameter("mask_noise", nt)
	m.set_shader_parameter("rune_strip", Runes.strip())
	_cache["ground"] = m
	return m


## A mesh from one node of a Poly Haven glTF (sets hold several rocks or
## plants side by side; each node is one usable piece).
static func mesh(model: String, part := "") -> Mesh:
	var key := "mesh:%s:%s" % [model, part]
	if _cache.has(key):
		return _cache[key]
	var scene: PackedScene = load("%s%s/%s.gltf" % [MODELS, model, model])
	var root := scene.instantiate()
	var found: Mesh = null
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if part.is_empty() or mi.name == part:
			found = (mi as MeshInstance3D).mesh
			break
	# Leaf cards are alpha scissored; without coverage their edges crawl and
	# sparkle as the camera moves. Alpha to coverage smooths them under MSAA.
	if found:
		for i in found.get_surface_count():
			var m := found.surface_get_material(i) as BaseMaterial3D
			if m and m.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
				m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE_AND_TO_ONE
				m.alpha_antialiasing_edge = 0.3
	root.free()
	_cache[key] = found
	return found


## Late afternoon: a CC0 sky photo for light and reflections, a warm low sun,
## soft fog for depth. SSAO only shows on the Forward+ renderer.
static func environment(parent: Node) -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := PanoramaSkyMaterial.new()
	sm.panorama = load(SKY)
	sm.energy_multiplier = 1.0
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.86, 0.76, 0.62)
	env.fog_depth_begin = 45.0
	env.fog_depth_end = 240.0
	env.fog_density = 0.35
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.15
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.86, 0.66)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 70.0
	sun.directional_shadow_blend_splits = true
	sun.rotation_degrees = Vector3(-38, -38, 0)
	parent.add_child(sun)
