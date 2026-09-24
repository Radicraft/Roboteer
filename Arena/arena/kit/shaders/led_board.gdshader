// The perimeter LED boards just behind the arena wall (docs/wave-a-kit-notes.md). One
// strip mesh round the arena; UV.x is metres along the strip, UV.y 0 at the top edge.
// Shows the four invented boards from boards.png, each `board_len` metres long, and every
// `cycle_s` seconds rolls them on by one. On a big moment the whole ring flashes warm.
shader_type spatial;
render_mode specular_schlick_ggx;

uniform sampler2D boards : source_color, filter_linear_mipmap_anisotropic;
uniform float board_len = 2.0;
uniform float cycle_s = 7.0;
uniform float brightness = 1.6;
uniform float excitement : hint_range(0.0, 1.0) = 0.0;
uniform vec3 flash_color : source_color = vec3(1.0, 0.62, 0.18);
uniform vec2 pixels_per_m = vec2(48.0, 48.0);

void fragment() {
	float slot = floor(UV.x / board_len);
	float roll = TIME / cycle_s;
	float step_i = floor(roll);
	// A short vertical roll between boards.
	float tr = smoothstep(0.92, 1.0, fract(roll));
	float v = UV.y + tr;
	float idx = mod(slot + step_i + floor(v), 4.0);
	vec2 buv = vec2(fract(UV.x / board_len), (idx + fract(v)) / 4.0);
	vec3 col = texture(boards, buv).rgb;
	// LED pitch.
	vec2 cell = fract(vec2(UV.x, UV.y * 0.5) * pixels_per_m);
	float led = smoothstep(0.55, 0.2, length(cell - 0.5));
	col *= mix(1.0, 0.45 + led * 0.9, 0.5);
	float flash = excitement * (0.5 + 0.5 * sin(TIME * 18.0 + UV.x * 0.8));
	col = mix(col, flash_color, clamp(flash * 0.55 - 0.1, 0.0, 1.0));
	ALBEDO = vec3(0.02);
	ROUGHNESS = 0.3;
	EMISSION = col * brightness;
}
