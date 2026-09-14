// Dry ice billboards for the menu/workshop stage (Arena/workshop/stage.gd).
//
// HARD RULE THIS FILE EXISTS TO ENFORCE (agent S, 2026-09-14, after TWO simulator
// sightings of opaque tan rectangles): an opaque quad must be impossible in ANY renderer.
// So:
//
//   * the emitted COLOUR is itself multiplied by the falloff and by the authored alpha
//     (`ALBEDO = base_colour * fall * amount`), and ALPHA is the falloff. If the renderer
//     honours ALPHA the quad draws at base * fall^2 * amount; if it ignores ALPHA entirely
//     it still draws at base * fall * amount, which is soft edged and faint. There is no
//     path that produces a hard edged solid rectangle;
//   * NOTHING outside the core built ins is used. No MODELVIEW_MATRIX write, no
//     INV_VIEW_MATRIX, no INSTANCE_CUSTOM, no texture fetch, no derivatives, no screen or
//     depth texture. The billboard is done by the PARTICLE SYSTEM
//     (GPUParticles3D.transform_align = TRANSFORM_ALIGN_Z_BILLBOARD), which is computed
//     engine side into the instance transform and therefore works on Forward+ and on
//     gl_compatibility alike;
//   * the particle's own alpha is used only as a normalised life fade, and if it comes
//     back wrong the quad falls back to the authored `alpha_scale` constant rather than to 1.
//
// The three sprite variants are now per EMITTER (`stretch`, `softness`, `bite`) rather than
// per particle, because picking them per particle needed INSTANCE_CUSTOM.

shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// The quad's colour before anything is done to it.
uniform vec4 base_colour : source_color = vec4(0.82, 0.88, 1.0, 1.0);
// The authored per quad alpha, as a CONSTANT. This is the same number that went into the
// process material's colour, and it is what the quad falls back to if the particle colour
// is not what this shader expects.
uniform float alpha_scale = 0.03;
// 1 = use the particle's colour alpha as a life fade, 0 = ignore it.
uniform float use_particle_alpha = 1.0;
// Global multiplier, turned down while real volumetric fog draws underneath.
uniform float strength = 1.0;
// Sprite variant. softness = how soft the edge is, stretch = how elongated the blob is,
// bite = how hard the noise eats into it.
uniform float softness = 1.2;
uniform float stretch = 1.0;
uniform float bite = 0.5;
uniform float noise_scale = 1.35;
uniform vec2 scroll = vec2(0.013, 0.021);
uniform float octave_mix = 0.35;
uniform float floor_lift = 0.30;
uniform float near_fade_begin = 0.22;
uniform float near_fade_end = 1.05;

varying vec4 v_col;
varying vec3 v_centre;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	v_col = COLOR;
	// MODEL_MATRIX is a core built in and is only READ: it anchors the noise field to where
	// the quad is in the world so neighbouring quads never show the same pattern. If it
	// came back as something unexpected the pattern would differ, nothing more.
	v_centre = MODEL_MATRIX[3].xyz;
}

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float d = clamp(length(vec2(uv.x * stretch, uv.y / stretch)) * 2.0, 0.0, 1.0);
	float shape = pow(1.0 - d, softness);

	vec2 q = v_centre.xz * noise_scale + UV * noise_scale * 1.6 + TIME * scroll;
	float n = mix(vnoise(q), vnoise(q * 2.3 + vec2(17.1, 9.7) - TIME * scroll * 1.7), octave_mix);
	n = mix(1.0, n, bite) * (1.0 - floor_lift) + floor_lift;

	// A quad right against the lens is a wash over the frame, never fog.
	float near = smoothstep(near_fade_begin, near_fade_end, length(VERTEX));

	// THE falloff. Everything the quad emits is multiplied by it.
	float fall = clamp(shape * n * near, 0.0, 1.0);
	// The particle's alpha carries the authored value times the life ramp, so dividing it
	// back out leaves just the ramp. A particle colour that is not what we expect clamps to
	// 1.0 and the quad simply keeps its authored alpha.
	float life = mix(1.0, clamp(v_col.a / max(alpha_scale, 0.0001), 0.0, 1.0), use_particle_alpha);
	float amount = alpha_scale * life * strength;

	ALBEDO = base_colour.rgb * fall * amount;
	ALPHA = fall;
}
