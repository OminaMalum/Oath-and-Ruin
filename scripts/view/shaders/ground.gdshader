shader_type spatial;
// The match map floor (LaneMapBuilder): one surface, four CC0 texture sets
// picked by world position. Cobbles down the lane, flagstones round the
// towers and in the bases, earth and fallen leaves in the flanks. Edges are
// broken up with noise and blended by stone height so cobbles end as stones,
// not as a soft fade. Works on Forward+ and Compatibility.

uniform sampler2D cobble_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cobble_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cobble_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float cobble_scale = 0.45;
uniform sampler2D plaza_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D plaza_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D plaza_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float plaza_scale = 0.33;
uniform sampler2D dirt_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float dirt_scale = 0.33;
uniform sampler2D leaves_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D leaves_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D leaves_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float leaves_scale = 0.28;
uniform sampler2D mask_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D rune_strip : hint_default_transparent, filter_linear_mipmap, repeat_enable;
uniform vec3 rune_col : source_color = vec3(0.72, 0.58, 0.92);

uniform float lane_half = 6.4;
uniform float base_z = 46.0;
uniform float tower_z = 32.0;
uniform float tower_r = 5.0;
uniform float core_z = 56.0;
uniform float camp_x = -28.0;
// Three lane map: lane_step is the spacing of the side lanes (0 = one lane),
// wall_lines the x of the wall feet that get darker earth, base_x and
// base_end the base plaza half width and far end, out_x the outer wall.
uniform float lane_step = 0.0;
uniform vec4 wall_lines = vec4(7.0, 11.0, 19.0, 999.0);
uniform float base_x = 20.0;
uniform float base_end = 80.0;
uniform float out_x = 21.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Height-aware blend: b is the wanted share of the second layer (0..1), the
// heights come from the albedo brightness so stones poke through mortar.
float hblend(float b, float h1, float h2) {
	return smoothstep(0.0, 1.0, clamp((b - 0.5) * 3.0 + (h2 - h1) * 1.5 + 0.5, 0.0, 1.0));
}

float luma(vec3 c) {
	return dot(c, vec3(0.3, 0.5, 0.2));
}

void fragment() {
	vec2 p = wpos.xz;
	float n1 = texture(mask_noise, p * 0.021).r;
	float n2 = texture(mask_noise, p * 0.083 + vec2(0.37, 0.11)).r;
	float ax = abs(p.x);
	float az = abs(p.y);
	// Distance across to the nearest lane centre.
	float lx = lane_step > 0.0 ? min(ax, abs(ax - lane_step)) : ax;

	// Layer weights before the height blend.
	float lane = 1.0 - smoothstep(lane_half - 0.8, lane_half + 0.4, lx + (n2 - 0.5) * 2.6);
	lane *= 1.0 - smoothstep(base_z - 1.0, base_z + 1.0, az);
	float tower_d = length(vec2(lx, az - tower_z));
	float plaza = 1.0 - smoothstep(tower_r - 0.8, tower_r + 0.8, tower_d + (n2 - 0.5) * 2.0);
	float in_base = (1.0 - smoothstep(base_x, base_x + 1.5, ax)) * (1.0 - smoothstep(base_end, base_end + 1.5, az));
	plaza = max(plaza, smoothstep(base_z - 1.5, base_z + 0.5, az + (n2 - 0.5) * 2.0) * in_base);
	float camp = 1.0 - smoothstep(4.0, 7.0, length(vec2(p.x - camp_x, p.y)) + (n2 - 0.5) * 2.0);
	plaza = max(plaza, camp * 0.85);
	float leaf = smoothstep(0.42, 0.62, n1 + (n2 - 0.5) * 0.25);

	vec2 uc = p * cobble_scale;
	vec2 up = p * plaza_scale;
	vec2 ud = p * dirt_scale;
	vec2 ul = p * leaves_scale;
	// Cobbles cover most of the screen, so they get a second, rotated and
	// offset sample blended in by noise to hide the repeat.
	vec2 uc2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * uc * 0.83 + vec2(0.31, 0.57);
	float anti = smoothstep(0.35, 0.65, n1 + (n2 - 0.5) * 0.6);
	vec3 cd = mix(texture(cobble_d, uc).rgb, texture(cobble_d, uc2).rgb, anti);
	vec3 pd = texture(plaza_d, up).rgb;
	vec3 dd = texture(dirt_d, ud).rgb;
	vec3 ld = texture(leaves_d, ul).rgb;

	// Off the paths: earth and leaves; then stone paths on top.
	float t_leaf = hblend(leaf, luma(dd), luma(ld));
	vec3 col = mix(dd, ld, t_leaf);
	vec3 nrm = mix(texture(dirt_n, ud).rgb, texture(leaves_n, ul).rgb, t_leaf);
	vec3 arm = mix(texture(dirt_arm, ud).rgb, texture(leaves_arm, ul).rgb, t_leaf);
	float h_soft = luma(col);

	float t_lane = hblend(lane, h_soft, luma(cd) + 0.1);
	col = mix(col, cd, t_lane);
	nrm = mix(nrm, mix(texture(cobble_n, uc).rgb, texture(cobble_n, uc2).rgb, anti), t_lane);
	arm = mix(arm, mix(texture(cobble_arm, uc).rgb, texture(cobble_arm, uc2).rgb, anti), t_lane);

	float t_plaza = hblend(plaza, luma(col), luma(pd) + 0.1);
	col = mix(col, pd * vec3(1.02, 1.0, 0.96), t_plaza);
	nrm = mix(nrm, texture(plaza_n, up).rgb, t_plaza);
	arm = mix(arm, texture(plaza_arm, up).rgb, t_plaza);

	// Large scale tint so repeats do not line up, and darker earth at the
	// wall feet (lane walls at 7 m, flank walls at 11 m and 19 m).
	col *= mix(0.86, 1.08, texture(mask_noise, p * 0.006).r);
	float wall_d = min(min(abs(ax - wall_lines.x), abs(ax - wall_lines.y)), min(abs(ax - wall_lines.z), abs(ax - wall_lines.w)));
	col *= mix(0.72, 1.0, smoothstep(0.0, 1.6, wall_d));

	// Outside the walls: the valley floor, darker and greener so it reads as
	// forest ground at a distance, not sand.
	float outside = max(smoothstep(out_x, out_x + 3.0, ax), smoothstep(base_end + 1.0, base_end + 4.0, az));
	col = mix(col, col * vec3(0.62, 0.7, 0.5), outside);
	// Mid lane: an old ward circle of runes set into the cobbles, faintly lit.
	// Flat in the floor shader, so it adds no geometry to the fighting space.
	float rr = length(p);
	float ang = atan(p.y, p.x) / 6.2831853 + 0.5;
	vec2 ruv = vec2(ang * 5.0, (rr - 3.55) / 0.55);
	float band = step(0.0, ruv.y) * step(ruv.y, 1.0);
	float glyph = texture(rune_strip, ruv).a * band;
	float rim = (1.0 - smoothstep(0.0, 0.05, abs(rr - 3.45))) + (1.0 - smoothstep(0.0, 0.05, abs(rr - 4.2)));
	float ward = clamp(glyph + rim * 0.8, 0.0, 1.0);
	col = mix(col, col * 0.5, ward * 0.7);
	EMISSION = rune_col * ward * 0.45;
	ALBEDO = col;
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = 1.0;
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.3;
	ROUGHNESS = arm.g;
	METALLIC = 0.0;
}
