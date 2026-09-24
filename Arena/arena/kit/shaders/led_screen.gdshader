// An LED wall: the feed through an RGB pixel mask, slightly glossy glass on top.
shader_type spatial;
render_mode specular_schlick_ggx;

uniform sampler2D feed : source_color, filter_linear;
uniform vec2 pixels = vec2(192.0, 108.0);
uniform float brightness = 2.2;
uniform float mask_strength = 0.55;
uniform float on = 1.0;

void fragment() {
	vec2 uv = UV;
	vec3 col = texture(feed, uv).rgb;
	vec2 cell = fract(uv * pixels);
	float dot_mask = smoothstep(0.5, 0.25, length(cell - 0.5));
	col *= mix(1.0, dot_mask * 1.6, mask_strength);
	ALBEDO = vec3(0.01);
	ROUGHNESS = 0.25;
	SPECULAR = 0.4;
	EMISSION = col * brightness * on;
}
