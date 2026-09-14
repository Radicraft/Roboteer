// The mover beam cones (Arena/workshop/stage.gd).
//
// Same hard rule as ground_fog.gdshader and soft_sprite.gdshader (agent S, 2026-09-14): a
// SOLID cone must be impossible in any renderer, so the emitted colour is itself multiplied
// by the falloff and by the calibrated beam alpha, and ALPHA is the falloff. If the renderer
// honours ALPHA the shaft draws at tint * fall^2 * strength; if it ignores it the shaft
// still draws at tint * fall * strength, which is faint and soft. Nothing outside the core
// built ins is used: no texture fetch, no MODELVIEW_MATRIX write, no INV_VIEW_MATRIX, no
// INSTANCE_CUSTOM, no derivatives, no screen or depth texture.
//
// `strength` still means exactly what it meant when this was an inline shader in stage.gd:
// the beam's alpha at the lens, driven by the CPU (BEAM_ALPHA, the haze gain, and the
// camera fade). workshop_test.gd asserts it stays under 0.10.

shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0);
uniform float strength = 0.1;
uniform float half_length = 4.0;
// 0.9, was 1.25: the falloff is applied twice now (once into the colour, once as ALPHA),
// so a gentler curve gives the same shaft.
uniform float fade_power = 0.9;
uniform float near_fade_begin = 0.25;
uniform float near_fade_end = 1.30;
// How much of the beam the drifting haze may take away, and how fast it drifts. 0.12 is a
// shimmer you notice over seconds; above about 0.2 it reads as a fault.
uniform float shimmer = 0.12;
uniform float shimmer_speed = 0.085;
// Per mover offset into the noise field, so the three shafts never shimmer in step.
uniform float seed = 0.0;

varying float along;

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
	// 0 at the lens, 1 at the far end, whatever the mesh UV convention is.
	along = clamp((VERTEX.y + half_length) / max(half_length * 2.0, 0.0001), 0.0, 1.0);
}

void fragment() {
	float fade = pow(1.0 - along, fade_power);
	float edge = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	// A shell right against the lens is a wash over the frame, never a beam: the CPU side
	// fades a cone the camera has entered, and this catches every other way a surface can
	// end up too close.
	float near = smoothstep(near_fade_begin, near_fade_end, length(VERTEX));
	// Haze drifting DOWN the shaft. Two samples at different rates so it never repeats.
	float n = mix(
		vnoise(vec2(along * 5.5 - TIME * shimmer_speed, seed)),
		vnoise(vec2(along * 11.0 + TIME * shimmer_speed * 0.6, seed * 1.7 + 4.3)),
		0.35);
	float haze = 1.0 - shimmer + shimmer * n;

	float fall = clamp(fade * near * haze * (0.35 + 0.65 * edge), 0.0, 1.0);
	ALBEDO = tint.rgb * fall * strength;
	ALPHA = fall;
}
