// Soft round additive sprite for the stage's beam dust (Arena/workshop/stage.gd).
//
// WHY THIS EXISTS. On the simulator (gl_compatibility over OpenGL ES 3, low tier) the beam
// dust drew as OPAQUE TAN RECTANGLES: first as a StandardMaterial3D whose only source of
// alpha was a runtime gradient texture, and then again as a shader that billboarded itself
// by writing MODELVIEW_MATRIX, which that renderer does not apply to particles, so the
// quads stayed as world space rectangles and the alpha never reached the pixels.
//
// This version cannot produce an opaque quad in any renderer. See the header of
// ground_fog.gdshader for the full rule; the short version is that the emitted colour is
// itself multiplied by the falloff and the authored alpha, ALPHA is the falloff, the
// billboard is done engine side by GPUParticles3D.transform_align, and nothing outside the
// core built ins is used: no texture fetch, no MODELVIEW_MATRIX write, no INV_VIEW_MATRIX,
// no INSTANCE_CUSTOM, no derivatives.

shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 base_colour : source_color = vec4(1.0);
uniform float alpha_scale = 0.35;
uniform float use_particle_alpha = 1.0;
uniform float strength = 1.0;
// Higher is softer.
uniform float softness = 1.6;
// A very slow breath across the whole emitter. 0 turns it off.
uniform float twinkle = 0.25;
uniform float twinkle_speed = 0.6;
uniform float seed = 0.0;
uniform float near_fade_begin = 0.10;
uniform float near_fade_end = 0.45;

varying vec4 v_col;

void vertex() {
	v_col = COLOR;
}

void fragment() {
	float d = clamp(length(UV - vec2(0.5)) * 2.0, 0.0, 1.0);
	float shape = pow(1.0 - d, softness);
	float breath = 1.0 - twinkle + twinkle * (0.5 + 0.5 * sin(TIME * twinkle_speed + seed));
	float near = smoothstep(near_fade_begin, near_fade_end, length(VERTEX));

	float fall = clamp(shape * breath * near, 0.0, 1.0);
	float life = mix(1.0, clamp(v_col.a / max(alpha_scale, 0.0001), 0.0, 1.0), use_particle_alpha);
	float amount = alpha_scale * life * strength;

	ALBEDO = base_colour.rgb * fall * amount;
	ALPHA = fall;
}
