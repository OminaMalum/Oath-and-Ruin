shader_type spatial;
// Stylised leaf mass for ForestTree: mottled clumps from noise, darker
// underneath, light leaking through at the edges, and a slow sway.

uniform vec3 deep : source_color = vec3(0.7, 0.35, 0.1);
uniform vec3 lit : source_color = vec3(1.0, 0.65, 0.25);
uniform float glow = 0.0;
uniform sampler2D clumps : hint_default_white, filter_linear_mipmap, repeat_enable;

varying vec3 wpos;
varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * 0.9 + wpos.x * 0.15 + wpos.z * 0.11;
	VERTEX += NORMAL * (sin(t) * 0.04 + sin(t * 2.3 + wpos.y) * 0.025);
	VERTEX.x += sin(t * 0.7) * 0.05 * max(VERTEX.y, 0.0);
}

void fragment() {
	vec2 uv = wpos.xz * 0.18 + vec2(wpos.y * 0.21, -wpos.y * 0.17);
	float c = texture(clumps, uv).r;
	float c2 = texture(clumps, uv * 2.7 + 0.3).r;
	float up = clamp(dot(normalize(lpos), vec3(0.0, 1.0, 0.0)) * 0.5 + 0.5, 0.0, 1.0);
	// Cellular distance: 0 at a clump centre. Invert so clump centres catch light.
	float k = clamp(1.0 - (c * 0.7 + c2 * 0.3) * 1.3, 0.0, 1.0);
	vec3 col = mix(deep * 0.55, deep, smoothstep(0.15, 0.55, k));
	col = mix(col, lit, smoothstep(0.55, 0.9, k) * (0.45 + up * 0.55));
	col *= mix(0.6, 1.0, up);
	ALBEDO = col;
	ROUGHNESS = 0.8;
	SPECULAR = 0.2;
	BACKLIGHT = col * 0.35;
	EMISSION = lit * glow * smoothstep(0.5, 0.95, k);
	// Pinch the normal toward the clump pattern so the blob shades as many
	// small masses rather than one smooth ball.
	NORMAL_MAP = normalize(vec3(c - 0.5, c2 - 0.5, 0.6)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.2;
}
