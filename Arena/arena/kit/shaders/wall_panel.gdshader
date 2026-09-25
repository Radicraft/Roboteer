// Arena wall faces as designed panels (docs/wave-a-kit-notes.md): a visual sleeve over each
// arena wall, patterned in WORLD space so the four walls line up without UVs.
//   style 0  x-braced steel panels (the Grinder): a frame per bay, a raised X in each
//   style 1  padded panels (the Coliseum): quilted pads with a stitched seam
//   style 2  riveted plate (the Crush and the Furnace): big plates, rivet rows
shader_type spatial;
render_mode specular_schlick_ggx;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform int style = 0;
uniform vec3 base_color : source_color = vec3(0.34, 0.37, 0.42);
uniform vec3 rib_color : source_color = vec3(0.5, 0.54, 0.6);
uniform float bay_m = 1.25;
uniform float wall_h = 0.65;
uniform float metallic_v = 0.55;
uniform float rough_v = 0.45;
uniform float grime = 0.35;

varying vec3 v_world;
varying vec3 v_normal;

float line(float d, float w) {
	return 1.0 - smoothstep(w * 0.6, w, abs(d));
}

void fragment() {
	bool ew = abs(v_normal.x) > 0.5;
	float along = ew ? v_world.z : v_world.x;
	float u = fract(along / bay_m);
	float v = clamp(v_world.y / wall_h, 0.0, 1.0);
	float n = texture(noise_tex, vec2(along * 0.37, v_world.y * 1.9)).r;
	vec3 col = base_color;
	float rib = 0.0;
	float groove = 0.0;
	if (style == 0) {
		rib = max(line(u - v, 0.06), line(u - (1.0 - v), 0.06));
		groove = max(line(u, 0.025), line(u - 1.0, 0.025));
		groove = max(groove, max(line(v - 0.04, 0.03), line(v - 0.96, 0.03)));
	} else if (style == 1) {
		float qv = fract(v * 2.0);
		rib = (1.0 - line(u - 0.5, 0.5)) * 0.0;
		groove = max(line(u, 0.03), line(u - 1.0, 0.03));
		groove = max(groove, line(qv, 0.05) * 0.8);
		col *= 0.85 + 0.3 * sin(u * 3.14159) * sin(qv * 3.14159);
	} else {
		groove = max(line(u, 0.012), line(u - 1.0, 0.012));
		float rv = fract(along / 0.18);
		rib = line(rv - 0.5, 0.18) * max(line(v - 0.1, 0.05), line(v - 0.9, 0.05));
	}
	col = mix(col, rib_color, rib);
	col *= 1.0 - groove * 0.75;
	col *= 1.0 - grime * (1.0 - v) * (0.6 + 0.4 * n);
	ALBEDO = col;
	METALLIC = metallic_v * (1.0 - groove * 0.5);
	ROUGHNESS = mix(rough_v, rough_v * 0.7, rib) + 0.2 * (1.0 - n) * grime;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
