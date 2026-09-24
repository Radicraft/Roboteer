// Venue kit crowd card (docs/wave-a-kit-notes.md). One MultiMesh per crowd layer.
//
// Each instance is one person: a quad from x -0.5..0.5, y 0..1 (feet at the origin),
// turned to face the camera around Y (so it never leans into the row behind it) and
// stretched by 1/cos(pitch) so a card rendered from 40 degrees above reads at its true
// height from the 50 degree fight camera. Presentation only: TIME and uniforms, nothing
// from the simulation.
//
// INSTANCE_CUSTOM: x = person variant (atlas column), y = phase 0..1,
//                  z = excitability 0..1, w = scale, negative = mirrored.
// COLOR:           per-person tint (clothes and light variation).
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_lambert_wrap, specular_schlick_ggx, skip_vertex_transform;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D emit_atlas : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform vec2 grid = vec2(16.0, 4.0);
// World size of one atlas cell at scale 1.
uniform vec2 card_size = vec2(1.05, 2.1);
uniform float excitement : hint_range(0.0, 1.0) = 0.0;
// 0 = the crowd cheers when excited, 1 = it flinches ("ooh").
uniform float flinch : hint_range(0.0, 1.0) = 0.0;
uniform float silhouette : hint_range(0.0, 1.0) = 0.0;
uniform vec3 silhouette_color : source_color = vec3(0.015, 0.018, 0.026);
// Emission share of the albedo: the crowd never goes fully black in a dark stand.
uniform float self_light = 0.18;
uniform float phone_glow = 2.5;
uniform float alpha_cut = 0.45;
uniform float anim_rate = 1.0;
uniform float max_stretch = 1.75;
// Where the feet are in the cell, as a fraction of its height from the bottom edge.
uniform float feet_anchor = 0.086;

varying flat vec2 v_cell;
varying flat float v_flip;
varying vec3 v_tint;

float hash11(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 to_cam = cam - origin;
	vec2 flat_dir = to_cam.xz;
	float horiz = max(length(flat_dir), 0.001);
	vec3 fwd = vec3(flat_dir.x / horiz, 0.0, flat_dir.y / horiz);
	vec3 right = vec3(fwd.z, 0.0, -fwd.x);
	float pitch = atan(to_cam.y, horiz);
	float stretch = clamp(1.0 / max(cos(pitch), 0.2), 1.0, max_stretch);

	float scale = abs(INSTANCE_CUSTOM.w);
	float phase = INSTANCE_CUSTOM.y;
	float excit = INSTANCE_CUSTOM.z;
	float e = clamp(excitement * (0.45 + 0.75 * excit), 0.0, 1.0);
	float t = TIME * anim_rate * (0.8 + 0.4 * excit) + phase * 23.0;

	// Idle sway, and a jump when the crowd is up.
	float bob = sin(t * 2.1) * 0.01 + max(0.0, sin(t * 8.5 + phase * 6.2832)) * 0.09 * e;
	float lean = sin(t * 1.3 + phase * 4.0) * 0.02;

	vec3 world = origin
		+ right * ((VERTEX.x + lean * VERTEX.y) * card_size.x * scale)
		+ vec3(0.0, 1.0, 0.0) * ((VERTEX.y - feet_anchor) * card_size.y * scale * stretch + bob * scale);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	vec3 n = normalize(fwd + vec3(0.0, 0.7, 0.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	// Frame: idle and bob alternate at each person's own pace; excitement swaps in the
	// cheer (or flinch) row for a share of the crowd that grows with it.
	float row = step(0.5, fract(t * 0.23 + phase));
	float slot = floor(t * (0.35 + 2.5 * e) + phase * 5.0);
	if (hash11(slot + INSTANCE_CUSTOM.x * 7.31 + phase * 91.7) < e) {
		row = flinch > 0.5 ? 3.0 : 2.0;
	}
	v_cell = vec2(INSTANCE_CUSTOM.x, row);
	v_flip = INSTANCE_CUSTOM.w < 0.0 ? -1.0 : 1.0;
	v_tint = COLOR.rgb;
}

void fragment() {
	vec2 uv = UV;
	if (v_flip < 0.0) {
		uv.x = 1.0 - uv.x;
	}
	uv = clamp(uv, vec2(0.006, 0.004), vec2(0.994, 0.996));
	vec2 auv = (v_cell + uv) / grid;
	vec4 c = texture(atlas, auv);
	vec3 col = c.rgb * v_tint;
	col = mix(col, silhouette_color, silhouette);
	ALBEDO = col;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	float phone = texture(emit_atlas, auv).r * (1.0 - silhouette);
	EMISSION = col * self_light * (1.0 - silhouette) + vec3(0.75, 0.85, 1.0) * phone * phone_glow;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
}
