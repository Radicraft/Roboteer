// The cold sky deck the venue's reflection probe sees (docs/wave-a-kit-notes.md): a soft
// disc of night-cloud glow high over the arena (a town's light on low cloud), faint to the
// eye from the fight camera, which never looks that high, but it is what the steel floor
// reflects, so the plates read cool instead of black. Faces down.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform vec3 deck_color : source_color = vec3(0.35, 0.5, 0.85);
uniform float energy = 0.6;

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float fall = pow(clamp(1.0 - r, 0.0, 1.0), 1.4);
	ALBEDO = deck_color * energy * fall;
}
