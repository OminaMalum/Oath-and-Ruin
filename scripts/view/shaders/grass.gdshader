shader_type spatial;
render_mode cull_disabled;
// Grass clumps (Grass.clump_mesh): UV.y runs root to tip.

uniform vec3 root_col : source_color = vec3(0.16, 0.19, 0.07);
uniform vec3 tip_col : source_color = vec3(0.62, 0.62, 0.28);
uniform vec3 dry_col : source_color = vec3(0.72, 0.55, 0.26);

varying float tip;
varying vec3 wpos;

void vertex() {
	tip = UV.y;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * 1.7 + wpos.x * 0.6 + wpos.z * 0.45;
	VERTEX.x += sin(t) * 0.05 * tip * tip;
	VERTEX.z += cos(t * 0.8) * 0.035 * tip * tip;
}

void fragment() {
	float dry = clamp(sin(wpos.x * 0.37 + wpos.z * 0.21) * 0.5 + 0.5, 0.0, 1.0);
	vec3 top = mix(tip_col, dry_col, dry * 0.6);
	ALBEDO = mix(root_col, top, smoothstep(0.0, 1.0, tip));
	ROUGHNESS = 0.85;
	SPECULAR = 0.15;
	BACKLIGHT = top * 0.3 * tip;
	AO = mix(0.4, 1.0, tip);
}
