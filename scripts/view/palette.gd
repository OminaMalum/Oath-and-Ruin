class_name Palette
## Shared colours. Restrained jewel tones over weathered neutrals.

const STONE := Color(0.40, 0.38, 0.34)
const STONE_DARK := Color(0.28, 0.27, 0.25)
const STONE_WARM := Color(0.48, 0.43, 0.36)
const MOSS := Color(0.33, 0.40, 0.22)
const LEATHER := Color(0.42, 0.29, 0.19)
const LEATHER_DARK := Color(0.27, 0.19, 0.13)
const WOOD := Color(0.38, 0.27, 0.17)
const STRAW := Color(0.74, 0.62, 0.38)
const IRON := Color(0.30, 0.31, 0.33)
const BRASS := Color(0.70, 0.55, 0.30)
const AUTUMN := Color(0.80, 0.45, 0.16)
const AUTUMN_DEEP := Color(0.62, 0.30, 0.12)
const LAPIS := Color(0.16, 0.26, 0.52)
const TEAL := Color(0.25, 0.80, 0.78)
const AMBER := Color(1.0, 0.62, 0.20)

## Team colours for telegraphs and bars: allies teal, enemies amber.
## (Deliberately not a red and blue pair side by side.)
const ALLY := Color(0.30, 0.85, 0.85)
const ENEMY := Color(1.0, 0.55, 0.15)
const SELF_HEALTH := Color(0.40, 0.85, 0.35)


static func mat(c: Color, rough: float = 0.85, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


static func glow(c: Color, energy: float = 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


static func ground_decal(c: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c, alpha)
	m.no_depth_test = false
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
