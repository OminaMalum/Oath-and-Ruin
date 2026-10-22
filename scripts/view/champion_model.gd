class_name ChampionModel
## Dresses an imported champion model (assets/champions/<id>.glb, built to
## docs/ASSET_CONTRACT.md) in game materials. The model's material names say
## what each part is made of; this swaps them for CC0 textured materials, puts
## the team colour on the "Team" parts and the champion's accent on "Glow".
## Every material is a fresh copy, because the view fades and flashes them
## per unit.

const DIR := "res://assets/champions/"

## material name: [texture set or "", tint, roughness, metallic, uv scale]
const LOOKS := {
	"Robe": ["poly_wool_herringbone", Color(0.6, 0.11, 0.1), 0.95, 0.0, 3.0],
	"RobeInner": ["", Color(0.03, 0.02, 0.025), 1.0, 0.0, 1.0],
	"Team": ["poly_wool_herringbone", Color(0.95, 0.95, 0.95), 0.9, 0.0, 3.0],
	"Leather": ["brown_leather", Color(0.85, 0.7, 0.6), 0.6, 0.0, 2.5],
	"Cloth": ["hessian_230", Color(0.55, 0.5, 0.42), 0.95, 0.0, 3.0],
	"Wood": ["bark_willow_02", Color(0.55, 0.42, 0.34), 0.8, 0.0, 1.2],
	"Skin": ["", Color(0.66, 0.5, 0.42), 0.55, 0.0, 1.0],
	"Brass": ["", Color(0.8, 0.6, 0.3), 0.32, 1.0, 1.0],
	"Paper": ["", Color(0.88, 0.82, 0.66), 0.9, 0.0, 1.0],
	"Trim": ["", Color(0.86, 0.64, 0.3), 0.4, 0.7, 1.0],
}
const SETS := {
	"poly_wool_herringbone": "poly_wool_herringbone", "brown_leather": "brown_leather", "hessian_230": "hessian_230",
	"bark_willow_02": "bark_willow_02",
}


static func path_for(id: StringName) -> String:
	var p := "%s%s.glb" % [DIR, id]
	return p if ResourceLoader.exists(p) else ""


## Swaps the materials on every mesh under `root`. Returns
## {"materials": Array[StandardMaterial3D], "glow": StandardMaterial3D}.
static func dress(root: Node, team: int, accent: Color) -> Dictionary:
	var mats: Array[StandardMaterial3D] = []
	var glow := Palette.glow(accent, 1.4)
	var eyes := Palette.glow(accent.lightened(0.35), 3.0)
	var team_col := Palette.team_color(team).darkened(0.25) if team < 2 else Color(0.45, 0.4, 0.32)
	var made := {}
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			var nm := src.resource_name if src else ""
			var m: StandardMaterial3D
			if made.has(nm):
				m = made[nm]
			elif nm == "Glow":
				m = glow
			elif nm == "Eyes":
				m = eyes
			elif LOOKS.has(nm):
				m = _make(LOOKS[nm], team_col if nm == "Team" else Color.WHITE)
			else:
				m = Palette.mat(Color(0.5, 0.5, 0.5))
			made[nm] = m
			mi.set_surface_override_material(i, m)
			if not mats.has(m):
				mats.append(m)
	return {"materials": mats, "glow": glow}


static func _make(look: Array, team_tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var tint: Color = look[1]
	m.albedo_color = Color(tint.r * team_tint.r, tint.g * team_tint.g, tint.b * team_tint.b)
	m.roughness = look[2]
	m.metallic = look[3]
	var set_id: String = look[0]
	if not set_id.is_empty():
		var base := "res://assets/env/textures/%s_" % SETS[set_id]
		m.albedo_texture = load(base + "diff_1k.jpg")
		m.normal_enabled = true
		m.normal_texture = load(base + "nor_gl_1k.jpg")
		m.normal_scale = 0.8
		m.roughness_texture = load(base + "arm_1k.jpg")
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.ao_enabled = true
		m.ao_texture = m.roughness_texture
		m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		var s: float = look[4]
		m.uv1_scale = Vector3(s, s, s)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	else:
		m.rim_enabled = look[3] < 0.5
		m.rim = 0.25
	return m
