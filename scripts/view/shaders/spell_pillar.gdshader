shader_type spatial;
// A column of light for a detonation: bright at the base, gone at the top,
// with streaks of energy running up it. Additive and unlit.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 col : source_color = vec3(0.25, 0.8, 0.78);
uniform float energy = 2.0;
uniform float alpha = 1.0;
uniform sampler2D streaks : hint_default_white, filter_linear_mipmap, repeat_enable;

void fragment() {
	float up = UV.y;  // 0 at the top of a CylinderMesh, 1 at the bottom
	float s = texture(streaks, vec2(UV.x * 3.0, UV.y * 0.6 + TIME * 1.8)).r;
	float body = pow(up, 2.2) * (0.45 + s * 0.9);
	float edge = 1.0 - abs(dot(NORMAL, VIEW));
	ALBEDO = col * energy * body * (0.4 + edge * 0.9) * alpha;
}
