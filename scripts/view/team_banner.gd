class_name TeamBanner
## A hanging team banner: heavy cloth with a swallowtail foot, darker side
## bands, gold edging and the team's sign, swaying slowly in the wind. One
## shader draws all of it, so there is no banner art to license.
##
## The signs: Oath carries an unbroken ring round an upright crystal, Ruin a
## ring broken in three round a split crystal. Both read as a shape first, so
## the team is clear by the sign as well as by the colour.
##
## The cloth hangs from its node's origin (the middle of its top edge) and
## faces +z. Banners on one map share a material per team; towers ask for
## their own so a tower that fades in front of the camera takes its banners
## with it.

const GOLD := Color(0.86, 0.68, 0.32)

static var _shader: Shader
static var _shared := {}  # "team:w:h" -> ShaderMaterial


## The cloth for `team`, `size` metres wide and long. `sway` scales the swing
## (less for cloth close to a wall).
static func cloth(size: Vector2, team: int, sway := 1.0, own_material := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	pm.subdivide_width = 8
	pm.subdivide_depth = 16
	pm.orientation = PlaneMesh.FACE_Z
	pm.center_offset = Vector3(0, -size.y * 0.5, 0)
	mi.mesh = pm
	mi.material_override = material(size, team, sway, own_material)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# The swing moves the cloth outside the flat mesh's bounds.
	mi.extra_cull_margin = 0.6
	return mi


static func material(size: Vector2, team: int, sway := 1.0, own := false) -> ShaderMaterial:
	var key := "%d:%.2f:%.2f:%.2f" % [team, size.x, size.y, sway]
	if not own and _shared.has(key):
		return _shared[key]
	var sm := ShaderMaterial.new()
	sm.shader = shader()
	var col := Palette.team_color(team)
	sm.set_shader_parameter("col", col.darkened(0.42))
	sm.set_shader_parameter("band", col.darkened(0.66))
	sm.set_shader_parameter("trim", GOLD)
	sm.set_shader_parameter("size", size)
	sm.set_shader_parameter("sway", sway)
	sm.set_shader_parameter("sigil", 0 if team == 0 else 1)
	if not own:
		_shared[key] = sm
	return sm


static func shader() -> Shader:
	if _shader:
		return _shader
	_shader = Shader.new()
	_shader.code = """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 col : source_color = vec4(0.1, 0.4, 0.4, 1.0);
uniform vec4 band : source_color = vec4(0.05, 0.2, 0.2, 1.0);
uniform vec4 trim : source_color = vec4(0.86, 0.68, 0.32, 1.0);
uniform vec2 size = vec2(1.1, 2.9);
uniform float sway = 1.0;
uniform int sigil = 0;
// 1 solid, lower lets the scene show through a screen door (a faded tower).
uniform float fade = 1.0;
varying vec2 uvv;
varying float fold;

float wave(vec2 p, float t) {
	return sin(t * 1.5 + p.y * 2.1 + p.x * 1.4) * 0.085 + sin(t * 2.7 + p.x * 4.6 - p.y * 1.3) * 0.028;
}

void vertex() {
	// Every banner swings on its own beat, from where it stands.
	float t = TIME + dot(NODE_POSITION_WORLD, vec3(0.61, 0.0, 0.37));
	vec2 p = VERTEX.xy;
	// Fixed along the top edge: the lower the cloth, the more it moves.
	float hang = clamp(-p.y / size.y, 0.0, 1.0);
	float k = sway * hang * sqrt(hang);
	float w = wave(p, t);
	float e = 0.05;
	float dx = (wave(p + vec2(e, 0.0), t) - w) / e;
	float dy = (wave(p + vec2(0.0, e), t) - w) / e;
	VERTEX.z += w * k;
	VERTEX.x += sin(t * 1.1 + p.y * 1.7) * 0.02 * k;
	NORMAL = normalize(vec3(-dx * k, -dy * k, 1.0));
	uvv = vec2(p.x / size.x + 0.5, -p.y / size.y);
	fold = w * k;
}

float diamond(vec2 q, vec2 r) {
	return abs(q.x) / r.x + abs(q.y) / r.y;
}

void fragment() {
	// Swallowtail: a notch cut up into the foot.
	float side = abs(uvv.x - 0.5) * 2.0;
	float notch = 0.17;
	float foot = 1.0 - notch * (1.0 - side);
	if (uvv.y > foot) {
		discard;
	}
	if (fade < 0.995) {
		float d = fract(dot(floor(FRAGCOORD.xy), vec2(0.5, 0.25)));
		if (d >= fade) {
			discard;
		}
	}
	float w = size.x;
	vec2 m = vec2((uvv.x - 0.5) * size.x, uvv.y * size.y);  // metres from top centre
	// Field with darker side bands and a soft fall of light down the cloth.
	vec3 c = mix(col.rgb, band.rgb, smoothstep(0.30, 0.31, abs(uvv.x - 0.5)));
	c *= mix(1.08, 0.82, uvv.y);
	// A coarse weave, faint enough not to shimmer far away.
	c *= 0.97 + 0.03 * sin(m.x * 90.0) * sin(m.y * 90.0);
	// Gold: the hanging sleeve at the top, the edges, the foot and a thin
	// line inside each band.
	float edge_w = 0.035 * w;
	float g = step(m.y, 0.07);
	g = max(g, step(0.5 * w - edge_w, abs(m.x)));
	g = max(g, step((foot - uvv.y) * size.y, edge_w * 1.3));
	g = max(g, step(abs(abs(m.x) - 0.31 * w), 0.008 * w));
	// The sign, a third of the way down.
	vec2 q = m - vec2(0.0, 0.36 * size.y);
	float r = 0.27 * w;
	float ring = step(abs(length(q) - r), 0.032 * w);
	float s = 0.0;
	if (sigil == 0) {
		s = max(ring, step(diamond(q, vec2(0.10, 0.19) * w), 1.0));
	} else {
		float a = atan(q.y, q.x) / TAU + 0.5;
		ring *= step(0.13, fract(a * 3.0 + 0.2));
		float cut = q.x * 0.8 + q.y * 0.6;
		vec2 q2 = q - sign(cut) * vec2(0.035, -0.03) * w;
		s = max(ring, step(diamond(q2, vec2(0.10, 0.19) * w), 1.0) * step(0.014 * w, abs(cut)));
	}
	g = max(g, s);
	c = mix(c, trim.rgb, g);
	// Folds: the cloth is a little darker where it swings back.
	c *= 1.0 - clamp(-fold * 2.2, 0.0, 0.25);
	ALBEDO = c;
	ROUGHNESS = mix(0.95, 0.5, g);
	METALLIC = g * 0.55;
	EMISSION = trim.rgb * s * 0.12;
}
"""
	return _shader
