class_name ChampionModel
## Dresses an imported champion model (assets/champions/<id>.glb, built to
## docs/ASSET_CONTRACT.md) in game materials. The model's material names say
## what each part is made of; this swaps them for CC0 textured materials, puts
## the team colour on the "Team" parts, the champion's primary colour on
## "Robe" and its accent on "Glow".
## Every material is a fresh copy, because the view fades and flashes them
## per unit.

const DIR := "res://assets/champions/"
const UNIT_DIR := "res://assets/units/"

## material name: [texture set or "", tint, roughness, metallic, uv scale, (optional) bump only]
const LOOKS := {
	"Robe": ["poly_wool_herringbone", Color(1.5, 1.5, 1.5), 0.95, 0.0, 3.0],
	"RobeDark": ["poly_wool_herringbone", Color(0.75, 0.75, 0.75), 0.95, 0.0, 3.0],
	"RobeInner": ["", Color(0.03, 0.02, 0.025), 1.0, 0.0, 1.0],
	"Team": ["poly_wool_herringbone", Color(0.95, 0.95, 0.95), 0.9, 0.0, 3.0],
	"Leather": ["brown_leather", Color(0.85, 0.7, 0.6), 0.6, 0.0, 2.5],
	"Cloth": ["hessian_230", Color(0.55, 0.5, 0.42), 0.95, 0.0, 3.0],
	"ClothDark": ["hessian_230", Color(0.2, 0.19, 0.18), 0.95, 0.0, 3.0],
	"Wood": ["bark_willow_02", Color(0.55, 0.42, 0.34), 0.8, 0.0, 1.2],
	"Skin": ["", Color(0.66, 0.5, 0.42), 0.55, 0.0, 1.0],
	"Brass": ["forged_steel", Color(0.8, 0.6, 0.3), 0.6, 1.0, 2.0],
	"Paper": ["", Color(0.88, 0.82, 0.66), 0.9, 0.0, 1.0],
	"Trim": ["forged_steel", Color(0.86, 0.64, 0.3), 0.7, 0.8, 2.0],
	# Worn plate (tools/make_steel_maps.py): satin with rubbed patches and
	# scratches instead of the flat chrome of a bare metal value.
	"Steel": ["forged_steel", Color(0.62, 0.63, 0.65), 0.75, 0.9, 2.0],
	"Iron": ["forged_steel", Color(0.32, 0.32, 0.34), 0.95, 0.75, 2.0],
	# Woven hessian bumps read as rings of mail once it is metal.
	"Mail": ["hessian_230", Color(0.38, 0.4, 0.43), 0.5, 0.85, 8.0, true],
	"Bone": ["", Color(0.84, 0.79, 0.66), 0.6, 0.0, 1.0],
	"Fur": ["poly_wool_herringbone", Color(0.42, 0.36, 0.3), 1.0, 0.0, 4.0],
	"Feather": ["", Color(0.22, 0.2, 0.18), 0.8, 0.0, 1.0],
	# Chainbound: muted mauve tiefling skin, near black hair, dark horn.
	"Tiefling": ["", Color(0.4, 0.3, 0.38), 0.6, 0.0, 1.0],
	"Hair": ["", Color(0.07, 0.06, 0.08), 0.7, 0.0, 1.0],
	"HairCopper": ["", Color(0.36, 0.14, 0.06), 0.7, 0.0, 1.0],
	"Horn": ["", Color(0.17, 0.14, 0.13), 0.45, 0.0, 1.0],
	"Stone": ["castle_wall_slates", Color(0.7, 0.68, 0.66), 0.9, 0.0, 4.0],
}
const SETS := {
	"poly_wool_herringbone": "poly_wool_herringbone", "brown_leather": "brown_leather", "hessian_230": "hessian_230",
	"bark_willow_02": "bark_willow_02", "castle_wall_slates": "castle_wall_slates", "forged_steel": "forged_steel",
}


static func path_for(id: StringName) -> String:
	for d in [DIR, UNIT_DIR]:
		var p := "%s%s.glb" % [d, id]
		if ResourceLoader.exists(p):
			return p
	return ""


## Swaps the materials on every mesh under `root`. Returns
## {"materials": Array[StandardMaterial3D], "glow": StandardMaterial3D}.
static func dress(root: Node, team: int, accent: Color, primary := Color(0.4, 0.12, 0.11)) -> Dictionary:
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
			elif nm == "TeamGlow":
				m = Palette.glow(team_col.lightened(0.35), 1.3)
			elif nm == "Glass":
				m = Palette.glow(accent.lightened(0.45), 0.8)
			elif LOOKS.has(nm):
				m = _make(LOOKS[nm], team_col if nm == "Team" else (primary if nm.begins_with("Robe") and nm != "RobeInner" else Color.WHITE))
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
		if look.size() < 6 or not look[5]:
			m.albedo_texture = load(base + "diff_1k.jpg")
		m.normal_enabled = true
		m.normal_texture = load(base + "nor_gl_1k.jpg")
		m.normal_scale = 1.4 if look.size() > 5 and look[5] else 0.8
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
