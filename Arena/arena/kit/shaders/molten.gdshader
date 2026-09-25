// Molten metal (the Furnace's crucible pour and the mould it fills): an emissive, slowly
// crawling crust of noise, white-yellow in the hot seams, deep orange where it cools.
// Presentation only: TIME and a noise texture.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 hot : source_color = vec3(1.0, 0.85, 0.45);
uniform vec3 warm : source_color = vec3(1.0, 0.35, 0.05);
uniform vec3 crust : source_color = vec3(0.18, 0.04, 0.01);
uniform float energy = 3.0;
uniform vec2 flow = vec2(0.0, 0.6);
uniform float scale = 1.0;

void fragment() {
	vec2 uv = UV * scale + flow * TIME;
	float n = texture(noise_tex, uv).r * 0.6 + texture(noise_tex, uv * 2.7 - flow * TIME * 0.5).r * 0.4;
	vec3 col = mix(crust, warm, smoothstep(0.25, 0.55, n));
	col = mix(col, hot, smoothstep(0.62, 0.85, n));
	ALBEDO = col * energy;
}
