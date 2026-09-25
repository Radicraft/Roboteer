// Worn hazard stripes on the arena wall tops (docs/wave-a-kit-notes.md, the Yard relight).
// A visual sleeve over the top of each wall: 45 degree yellow and black bands in WORLD
// space (so the four walls and every face of the sleeve line up without UVs), paint
// chipped through to concrete where the noise says, dirt that deepens down the face.
shader_type spatial;
render_mode specular_schlick_ggx;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 yellow : source_color = vec3(0.8, 0.7, 0.06);
uniform vec3 black : source_color = vec3(0.035, 0.035, 0.04);
uniform vec3 concrete : source_color = vec3(0.3, 0.29, 0.27);
uniform float pitch_m = 0.3;
uniform float wear = 0.32;
uniform float top_y = 0.66;
uniform float grime_depth = 0.16;

varying vec3 v_world;
varying vec3 v_normal;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Along the wall: x on the north and south walls, z on the east and west ones.
	float along = abs(v_normal.x) > 0.5 ? v_world.z : (abs(v_normal.z) > 0.5 ? v_world.x
		: (abs(v_world.x) > abs(v_world.z) ? v_world.z : v_world.x));
	float band = step(0.5, fract((along + (top_y - v_world.y) + v_world.x * 0.0) / pitch_m));
	vec3 paint = mix(yellow, black, band);
	float n = texture(noise_tex, v_world.xz * 0.9 + v_world.y * 1.7 + along * 0.31).r;
	float n2 = texture(noise_tex, vec2(along * 2.3, v_world.y * 4.1)).r;
	float chipped = smoothstep(1.0 - wear, 1.0 - wear + 0.06, n * 0.7 + n2 * 0.45);
	vec3 col = mix(paint, concrete * (0.7 + 0.5 * n2), chipped);
	float depth = clamp((top_y - v_world.y) / grime_depth, 0.0, 1.0);
	col *= mix(1.0, 0.55, depth) * (0.75 + 0.35 * n);
	ALBEDO = col;
	ROUGHNESS = mix(0.62, 0.9, chipped);
	SPECULAR = 0.4;
}
