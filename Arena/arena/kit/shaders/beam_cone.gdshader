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

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge = pow(facing, edge_power);
	float along = pow(clamp(1.0 - UV.y, 0.0, 1.0), length_falloff) * smoothstep(0.0, 0.04, UV.y);
	vec2 nuv = vec2(UV.x * 2.0 + TIME * 0.02, UV.y * 1.5 - TIME * 0.035);
	float n = 0.65 + 0.35 * texture(noise_tex, nuv).r;
	// Depth fade where the beam meets the floor or a stand.
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	float scene_dist = -view.z;
	float frag_dist = -VERTEX.z;
	float soft = clamp((scene_dist - frag_dist) / soft_distance, 0.0, 1.0);
	ALBEDO = beam_color * strength * edge * along * n * soft;
}
