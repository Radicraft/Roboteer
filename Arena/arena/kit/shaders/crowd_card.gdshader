// Venue kit crowd card (docs/wave-a-kit-notes.md). One MultiMesh per crowd layer.
//
// Each instance is one person: a quad from x -0.5..0.5, y 0..1, turned to face the camera
// around Y (so it never leans into the row behind it) and stretched by 1/cos(pitch) so a
// card rendered from 40 degrees above reads at its true height from the 50 degree fight
// camera. Presentation only: TIME and uniforms, nothing from the simulation.
//
// STAGING (owner feedback 2026-09-24: "the crowds look pretty bad and fake"). A crowd in a
// broadcast is read mostly DARK: through rim light, the arena's spill on the front rows,
// phone screens, flashes and movement, not through fully lit bodies. So:
//   * the body is dark by default (`body_light`), lit by a warm SPILL that falls off with
//     distance beyond the wall and with height up the stand;
//   * a RIM from behind and above is found from the card's own alpha edge;
//   * it hazes toward `haze_color` and desaturates with distance from the camera;
//   * `softness` biases the mip so the front rows sit a touch out of focus;
//   * reactions RIPPLE outward from `react_pos` at `ripple_speed` m/s, not all at once.
//   (react_age is fed from GDScript each frame rather than compared with TIME, so the two
//   clocks can never drift apart.)
//
// INSTANCE_CUSTOM: x = person variant (atlas column), y = phase 0..1,
//                  z = excitability 0..1, w = scale, negative = mirrored.
// COLOR:           per-person tint.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_lambert_wrap, specular_schlick_ggx, skip_vertex_transform;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D emit_atlas : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform vec2 grid = vec2(16.0, 4.0);
uniform vec2 card_size = vec2(1.05, 2.1);
uniform float feet_anchor = 0.086;
uniform float max_stretch = 1.75;
uniform float alpha_cut = 0.5;
uniform float anim_rate = 1.0;

// Reactions.
uniform float excitement : hint_range(0.0, 1.0) = 0.0;
uniform float flinch : hint_range(0.0, 1.0) = 0.0;
uniform vec3 react_pos = vec3(0.0);
// Seconds since the last reaction started (the kit counts it on the frame clock).
uniform float react_age = 100.0;
uniform float react_strength = 0.0;
uniform float ripple_speed = 9.0;

// Staging.
uniform float silhouette : hint_range(0.0, 1.0) = 0.0;
uniform vec3 silhouette_color : source_color = vec3(0.012, 0.014, 0.02);
uniform float body_light = 0.3;
uniform vec3 spill_color : source_color = vec3(1.0, 0.7, 0.42);
uniform float spill_strength = 0.5;
uniform float arena_half = 5.1;
uniform float spill_depth = 3.5;
uniform float spill_height = 3.2;
uniform vec3 rim_color : source_color = vec3(0.45, 0.55, 0.78);
uniform float rim_strength = 0.6;
uniform float rim_px = 2.0;
uniform vec3 haze_color : source_color = vec3(0.025, 0.04, 0.08);
uniform float haze_near = 6.0;
uniform float haze_far = 30.0;
uniform float haze_max = 0.8;
uniform float desat_far = 0.6;
uniform float softness = 0.6;
uniform float phone_glow = 3.0;
uniform vec3 phone_color : source_color = vec3(0.75, 0.85, 1.0);
// B/C "broadcast": the house is dark, read through rim light, phones, flags and light
// sweeping over the stands; the first rows by the wall keep a little of their colour.
uniform float broadcast : hint_range(0.0, 1.0) = 0.0;
uniform vec3 sweep_color : source_color = vec3(1.0, 0.86, 0.66);
uniform float sweep_strength = 1.2;
// Pose changes dissolve over this long instead of popping (seconds).
uniform float fade_s = 0.36;
// Clothing colour kept under a dark grade: saturation of the atlas before lighting.
uniform float saturation = 1.0;

varying flat vec2 v_cell;
varying flat vec4 v_rows;
varying float v_sweep;
varying flat float v_flip;
varying vec3 v_tint;
varying float v_spill;
varying float v_haze;

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
	// The ripple: this person's share of the last reaction arrives when the wave does.
	float lt = react_age - distance(origin.xz, react_pos.xz) / ripple_speed - phase * 0.25;
	float wave = lt > 0.0 ? exp(-lt / 1.4) * smoothstep(0.0, 0.12, lt) : 0.0;
	float e = clamp(max(excitement * (0.35 + 0.65 * excit), react_strength * wave * (0.55 + 0.45 * excit)), 0.0, 1.0);
	float t = TIME * anim_rate * (0.8 + 0.4 * excit) + phase * 23.0;

	float bob = sin(t * 2.1) * 0.008 + max(0.0, sin(t * 8.5 + phase * 6.2832)) * 0.08 * e;
	float lean = sin(t * 1.3 + phase * 4.0) * 0.02;

	vec3 world = origin
		+ right * ((VERTEX.x + lean * VERTEX.y) * card_size.x * scale)
		+ vec3(0.0, 1.0, 0.0) * ((VERTEX.y - feet_anchor) * card_size.y * scale * stretch + bob * scale);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	vec3 n = normalize(fwd + vec3(0.0, 0.7, 0.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	// The pose now and 1/3, 2/3, 3/3 of fade_s ago: the fragment picks one per pixel by a
	// dither, so a change dissolves over fade_s instead of popping in one frame.
	for (int i = 0; i < 4; i++) {
		float ti = t - float(i) * fade_s * 0.3333 * anim_rate * (0.8 + 0.4 * excit);
		float r = step(0.5, fract(ti * 0.23 + phase));
		float sl = floor(ti * (0.35 + 2.5 * e) + phase * 5.0);
		if (hash11(sl + INSTANCE_CUSTOM.x * 7.31 + phase * 91.7) < e) {
			r = flinch > 0.5 ? 3.0 : 2.0;
		}
		v_rows[i] = r;
	}
	float row = v_rows[0];
	// Light sweeping round the house: two beams at their own speeds.
	float ang = atan(origin.x, origin.z);
	float sw = pow(max(0.0, cos(ang - TIME * 0.42)), 60.0)
		+ 0.7 * pow(max(0.0, cos(ang * 2.0 + TIME * 0.27 + 1.3)), 90.0);
	v_sweep = sw * broadcast;
	v_cell = vec2(INSTANCE_CUSTOM.x, row);
	v_flip = INSTANCE_CUSTOM.w < 0.0 ? -1.0 : 1.0;
	v_tint = COLOR.rgb;
	// Spill: the arena's light reaches the first few metres past the wall, low down.
	float beyond = max(abs(origin.x), abs(origin.z)) - arena_half;
	v_spill = (1.0 - smoothstep(0.0, spill_depth, beyond)) * (1.0 - smoothstep(0.0, spill_height, origin.y));
	v_haze = smoothstep(haze_near, haze_far, length(to_cam)) * haze_max;
}

void fragment() {
	vec2 uv = UV;
	if (v_flip < 0.0) {
		uv.x = 1.0 - uv.x;
	}
	uv = clamp(uv, vec2(0.006, 0.004), vec2(0.994, 0.996));
	// Dissolve between the last four poses (see vertex): ordered 4x4 dither.
	ivec2 fc = ivec2(FRAGCOORD.xy) % 4;
	int bayer[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	float dth = (float(bayer[fc.y * 4 + fc.x]) + 0.5) / 16.0;
	int pick = int(dth * 4.0);
	vec2 cell = vec2(v_cell.x, v_rows[pick]);
	vec2 auv = (cell + uv) / grid;
	vec4 c = texture(atlas, auv, softness);
	// Rim: where the alpha falls away above and to the sides, light from behind catches.
	vec2 texel = rim_px / (vec2(textureSize(atlas, 0)));
	vec2 lo = (cell + vec2(0.004)) / grid;
	vec2 hi = (cell + vec2(0.996)) / grid;
	float up = texture(atlas, clamp(auv - vec2(0.0, texel.y), lo, hi), 1.0).a;
	float l = texture(atlas, clamp(auv - vec2(texel.x, 0.0), lo, hi), 1.0).a;
	float r = texture(atlas, clamp(auv + vec2(texel.x, 0.0), lo, hi), 1.0).a;
	// Mostly the top edge (heads, shoulders, raised arms): a light from behind and above.
	// The sides only a little, or the card reads as a sticker with a white cut line.
	float rim = clamp(c.a * ((1.0 - up) * 0.9 + (2.0 - l - r) * 0.12), 0.0, 1.0) * (1.0 - v_haze * 0.6);

	vec3 body = c.rgb * v_tint;
	float lum = dot(body, vec3(0.299, 0.587, 0.114));
	body = max(mix(vec3(lum), body, saturation), vec3(0.0));
	body = mix(body, vec3(lum), desat_far * v_haze);
	vec3 lit = body * body_light;
	vec3 col = mix(lit, silhouette_color, max(silhouette, broadcast * (0.92 - 0.6 * v_spill)));
	col = mix(col, haze_color, v_haze);
	// The atlas paints the phone screen white; the sparkle is the speck's job, so the
	// card's screen stays a dark glass with only a faint glow.
	// Sampled a mip or two blurrier than the screen itself, so the phone's white body and
	// the albedo's own blur are covered too.
	float phone_px = smoothstep(0.03, 0.25, texture(emit_atlas, auv, 1.5).r);
	col = mix(col, vec3(0.015), phone_px);
	ALBEDO = col;
	ROUGHNESS = 0.9;
	SPECULAR = 0.15;
	float phone = texture(emit_atlas, auv).r;
	vec3 spill = body * spill_color * spill_strength * v_spill * (1.0 - silhouette * 0.85);
	EMISSION = spill + rim_color * rim * rim_strength * (0.35 + 0.65 * (1.0 - v_spill))
		+ phone_color * phone * phone_glow
		+ sweep_color * v_sweep * sweep_strength * (0.05 * (c.rgb * v_tint) + rim * 1.6);
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
}
