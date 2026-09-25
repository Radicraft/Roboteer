// A light beam through haze, as an additive cone card (docs/aaa/arenas.md section 7:
// beams are cards, not volumetrics, on every tier). The cone's UV.y runs 0 at the lamp
// to 1 at the far end. Soft where it meets geometry, soft at the silhouette edge.
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, fog_disabled;

uniform vec3 beam_color : source_color = vec3(1.0, 0.62, 0.28);
uniform float strength = 0.35;
uniform float edge_power = 1.6;
uniform float length_falloff = 1.4;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;
uniform float soft_distance = 1.2;
// Fade out as the camera gets close to or inside the cone (it read as grey fog).
uniform float near_fade = 5.0;
// Rays: bright streaks along the cone (dust caught in the light), drifting slowly. 0 = a
// smooth cone, 1 = hard shafts.
uniform float streaks = 0.0;
uniform float streak_count = 7.0;
// Motes: tiny sparkles drifting through the shaft.
uniform float motes = 0.0;

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge = pow(facing, edge_power);
	float along = pow(clamp(1.0 - UV.y, 0.0, 1.0), length_falloff) * smoothstep(0.0, 0.04, UV.y);
	vec2 nuv = vec2(UV.x * 2.0 + TIME * 0.02, UV.y * 1.5 - TIME * 0.035);
	float n = 0.65 + 0.35 * texture(noise_tex, nuv).r;
	if (streaks > 0.0) {
		float ray = texture(noise_tex, vec2(UV.x * streak_count * 0.25 + TIME * 0.004, UV.y * 0.08)).r;
		ray = smoothstep(0.45, 0.75, ray);
		n *= mix(1.0, 0.25 + 1.9 * ray, streaks);
	}
	if (motes > 0.0) {
		vec2 muv = vec2(UV.x * 24.0, UV.y * 18.0 + TIME * 0.12);
		float sp = texture(noise_tex, muv).r;
		n += motes * smoothstep(0.82, 0.9, sp) * 3.0;
	}
	// Depth fade where the beam meets the floor or a stand.
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	float scene_dist = -view.z;
	float frag_dist = -VERTEX.z;
	float soft = clamp((scene_dist - frag_dist) / soft_distance, 0.0, 1.0);
	soft *= smoothstep(near_fade * 0.3, near_fade, frag_dist);
	ALBEDO = beam_color * strength * edge * along * n * soft;
}
