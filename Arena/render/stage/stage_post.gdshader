shader_type spatial;
// Stage vignette and film grain (wave A, docs/look/reference-study.md section 3.4).
//
// ONE full screen quad, MULTIPLIED over the frame after everything else in the stage's
// pass (render_priority is the maximum). It never samples the screen, so it costs one
// cheap fragment per pixel and it cannot erase the transparent haze the way a screen
// texture copy would (the copy is taken before transparents in Forward+).
//
// Corners are `vignette_amount` darker, starting at `vignette_start` of the half diagonal
// with a smooth falloff. Grain is luminance only, `grain_amount` either side of 1, in
// cells of `grain_px` pixels, re-rolled `grain_fps` times a second.
render_mode unshaded, blend_mul, depth_test_disabled, depth_draw_never, cull_disabled,
	shadows_disabled, fog_disabled;

uniform float vignette_amount = 0.22;
uniform float vignette_start = 0.60;
uniform float grain_amount = 0.015;
uniform float grain_px = 2.0;
uniform float grain_fps = 24.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	// Straight to clip space: the quad IS the screen, whatever the camera.
	POSITION = vec4(VERTEX.xy, 0.5, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = VIEWPORT_SIZE.x / max(VIEWPORT_SIZE.y, 1.0);
	vec2 c = (uv - 0.5) * vec2(aspect, 1.0);
	float half_diag = length(vec2(aspect, 1.0) * 0.5);
	float d = length(c) / half_diag;
	float vig = 1.0 - vignette_amount * smoothstep(vignette_start, 1.0, d);
	float grain = 1.0;
	if (grain_amount > 0.0) {
		vec2 cell = floor(FRAGCOORD.xy / max(grain_px, 1.0));
		float frame = floor(TIME * grain_fps);
		grain = 1.0 + (hash12(cell + frame * 17.31) - 0.5) * 2.0 * grain_amount;
	}
	ALBEDO = vec3(vig * grain);
}
