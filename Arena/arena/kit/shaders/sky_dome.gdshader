// The night over the venue: a dome drawn behind everything. Horizon glow (the town's
// sodium haze), a navy zenith, faint cloud banks from a noise texture, a few stars.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, fog_disabled, shadows_disabled;

uniform vec3 zenith_color : source_color = vec3(0.012, 0.02, 0.045);
uniform vec3 mid_color : source_color = vec3(0.03, 0.055, 0.1);
uniform vec3 horizon_color : source_color = vec3(0.22, 0.13, 0.08);
uniform float horizon_height = 0.12;
uniform float glow_strength = 1.0;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 glow_dir = vec3(0.7, 0.0, 0.7);

varying vec3 v_dir;

void vertex() {
	v_dir = normalize(VERTEX);
}

void fragment() {
	vec3 d = normalize(v_dir);
	float h = clamp(d.y, -0.2, 1.0);
	vec3 col = mix(mid_color, zenith_color, smoothstep(0.15, 0.7, h));
	float band = exp(-max(h, 0.0) / horizon_height);
	float toward = 0.55 + 0.45 * max(dot(normalize(vec3(d.x, 0.0, d.z)), normalize(glow_dir)), 0.0);
	col += horizon_color * band * toward * glow_strength;
	vec2 cuv = d.xz / max(d.y + 0.25, 0.08) * 0.08;
	float cloud = texture(noise_tex, cuv + vec2(TIME * 0.002, 0.0)).r;
	col = mix(col, col * 0.55 + horizon_color * 0.18 * band, smoothstep(0.55, 0.8, cloud) * 0.7);
	float star = step(0.9965, fract(sin(dot(floor(d.xz / max(d.y, 0.1) * 180.0), vec2(12.9898, 78.233))) * 43758.5453));
	col += vec3(0.6, 0.7, 0.9) * star * smoothstep(0.25, 0.6, h) * (1.0 - smoothstep(0.5, 0.8, cloud));
	ALBEDO = col;
}
