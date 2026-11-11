shader_type spatial;
// A spell circle drawn on a flat quad: two rims, a band of runes, six
// spokes and an inner ring. `progress` draws it in clockwise; `alpha` fades
// it. Additive and unlit, so it reads as light on the ground, never as a
// solid surface. The runes come from Runes.strip() (original glyphs).
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 col : source_color = vec3(0.25, 0.8, 0.78);
uniform float energy = 1.6;
uniform float progress = 1.0;
uniform float alpha = 1.0;
uniform float spin = 0.0;
uniform sampler2D runes : hint_default_transparent, filter_linear_mipmap, repeat_enable;

float ring(float r, float at, float w) {
	return 1.0 - smoothstep(0.0, w, abs(r - at));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float ang = atan(p.y, p.x) + spin;
	float a01 = fract(ang / 6.2831853 + 0.5);
	float shape = ring(r, 0.96, 0.025) + ring(r, 0.88, 0.012) + ring(r, 0.62, 0.014) * 0.8 + ring(r, 0.3, 0.02) * 0.7;
	// Rune band between the rims.
	vec2 ruv = vec2(a01 * 9.0, (r - 0.66) / 0.2);
	float band = step(0.0, ruv.y) * step(ruv.y, 1.0);
	shape += texture(runes, ruv).a * band * 0.9;
	// Six spokes from the inner ring to the middle ring.
	float spoke = abs(sin(ang * 3.0));
	shape += (1.0 - smoothstep(0.0, 0.035, spoke * r)) * step(0.3, r) * step(r, 0.62) * 0.6;
	// Drawn in around the circle as `progress` runs 0 to 1.
	float drawn = step(a01, progress);
	float fade = drawn * alpha * step(r, 1.0);
	ALBEDO = col * energy * clamp(shape, 0.0, 1.5) * fade;
}
