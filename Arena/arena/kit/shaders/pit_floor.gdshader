// Drop Zone: the glowing floor far down the open shaft (pass 4): a white-hot heart under a
// dark grate whose bars stand out against it. Unshaded, no collision.
shader_type spatial;
render_mode unshaded, fog_disabled;

uniform vec3 hot : source_color = vec3(1.0, 0.3, 0.06);
uniform float glow = 5.0;
uniform float half_size = 1.2;
uniform float bar_step = 0.3;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_world.xz / half_size;                        // -1..1 across the pit
	float r = length(p);
	float heart = 1.0 - smoothstep(0.0, 1.3, r);
	float n = texture(noise_tex, v_world.xz * 0.35 + vec2(TIME * 0.03, TIME * 0.02)).r;
	float bars = smoothstep(0.4, 0.46, abs(fract(v_world.x / bar_step) - 0.5));
	vec3 c = hot * glow * (0.35 + 0.9 * heart) * (0.7 + 0.6 * n);
	c += vec3(1.0, 0.75, 0.45) * pow(heart, 3.0) * glow * 0.4;
	c = mix(c, vec3(0.03, 0.015, 0.01), bars * 0.85);
	ALBEDO = c;
}
