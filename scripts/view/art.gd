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


## The same floor laid out for the three lane map: three cobbled lanes,
## plazas round the six towers, the camp clearing and both bases.
static func ground_three() -> ShaderMaterial:
	if _cache.has("ground3"):
		return _cache["ground3"]
	var m: ShaderMaterial = ground().duplicate()
	m.set_shader_parameter("lane_half", ThreeLaneBuilder.LANE_HALF - 0.4)
	m.set_shader_parameter("lane_step", absf(ThreeLaneBuilder.LANES[0]))
	m.set_shader_parameter("base_z", ThreeLaneBuilder.BASE_Z)
	m.set_shader_parameter("tower_z", ThreeLaneBuilder.TOWER_Z)
	m.set_shader_parameter("core_z", ThreeLaneBuilder.CORE_Z)
	m.set_shader_parameter("camp_x", ThreeLaneBuilder.CAMP.x)
	var e := ThreeLaneBuilder.LANE_HALF + 0.75
	m.set_shader_parameter("wall_lines", Vector4(e, absf(ThreeLaneBuilder.LANES[0]) - e, ThreeLaneBuilder.OUTER, 999.0))
	m.set_shader_parameter("base_x", ThreeLaneBuilder.OUTER)
	m.set_shader_parameter("base_end", ThreeLaneBuilder.END_Z)
	m.set_shader_parameter("out_x", ThreeLaneBuilder.OUTER + 1.0)
	_cache["ground3"] = m
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
	env.ambient_light_energy = 0.4
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.1
	env.tonemap_white = 8.0
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.8
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
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.82, 0.6)
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 70.0
	sun.directional_shadow_blend_splits = true
	# Low golden hour sun from the side of the lane, so neither team fights
	# into it and every unit gets a lit and a shaded half.
	sun.rotation_degrees = Vector3(-28, 90, 0)
	parent.add_child(sun)
	if "--ultra" in OS.get_cmdline_user_args():
		_ultra(env, sun, parent)
	if "--bench" in OS.get_cmdline_user_args():
		parent.add_child(BenchProbe.new())


## Godot at its best, for comparing looks on a strong PC (start with -- --ultra):
## global illumination (SDFGI) so sunlight bounces off the stone, light shafts
## through volumetric fog, screen space reflections and indirect light, larger
## sharper shadows and temporal anti aliasing. Too heavy for every PC, so it is
## off unless asked for.
static func _ultra(env: Environment, sun: DirectionalLight3D, parent: Node) -> void:
	env.sdfgi_enabled = true
	env.sdfgi_use_occlusion = true
	env.sdfgi_bounce_feedback = 0.6
	env.sdfgi_cascades = 6
	env.sdfgi_min_cell_size = 0.15
	env.sdfgi_energy = 1.0
	env.ssil_enabled = true
	env.ssil_radius = 4.0
	env.ssil_intensity = 0.9
	env.ssr_enabled = true
	env.ssr_max_steps = 96
	env.ambient_light_energy = 0.45
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color(0.95, 0.85, 0.72)
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 90.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_ambient_inject = 0.4
	env.volumetric_fog_sky_affect = 0.2
	env.fog_density = 0.2
	env.glow_intensity = 0.7
	env.glow_bloom = 0.06
	env.sky.radiance_size = Sky.RADIANCE_SIZE_512
	sun.light_volumetric_fog_energy = 2.5
	sun.shadow_blur = 1.0
	sun.directional_shadow_max_distance = 120.0
	RenderingServer.directional_shadow_atlas_set_size(8192, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_ULTRA)
	RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_ULTRA, true, 0.5, 2, 50.0, 300.0)
	if parent.is_inside_tree():
		_ultra_viewport(parent.get_viewport())
	else:
		parent.tree_entered.connect(func() -> void: _ultra_viewport(parent.get_viewport()), CONNECT_ONE_SHOT)


static func _ultra_viewport(vp: Viewport) -> void:
	vp.use_taa = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.mesh_lod_threshold = 0.0
	vp.positional_shadow_atlas_size = 8192
