// Venue kit specks: phone screens held up in the dark, camera flashes, distant lamps.
// Additive camera-facing points; the glow pass does the rest. Presentation only.
//
// INSTANCE_CUSTOM: x = kind (0 phone, 1 flash, 2 steady lamp), y = phase 0..1,
//                  z = size in metres, w = brightness.
// COLOR: the speck's colour.
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled;

uniform sampler2D glow_tex : source_color, filter_linear_mipmap;
uniform float excitement : hint_range(0.0, 1.0) = 0.0;
// Extra flash probability right after a big moment.
uniform float flash_burst : hint_range(0.0, 1.0) = 0.0;
uniform float intensity = 1.0;

varying float v_level;
varying vec3 v_col;

float hash11(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float kind = INSTANCE_CUSTOM.x;
	float phase = INSTANCE_CUSTOM.y;
	float size = INSTANCE_CUSTOM.z;
	float level = INSTANCE_CUSTOM.w;
	if (kind < 0.5) {
		// Phone: held up more when the crowd is up, sways, sometimes put away.
		float t = TIME * 0.15 + phase * 31.0;
		float held = step(0.35 - excitement * 0.5, hash11(floor(t) + phase * 17.0));
		level *= held * (0.75 + 0.25 * sin(TIME * 2.0 + phase * 40.0));
		origin.y += sin(TIME * 1.7 + phase * 20.0) * 0.04;
	} else if (kind < 1.5) {
		// Flash: a hashed blink. Each 0.25 s slot fires with a small chance that jumps
		// on a big moment, then decays fast inside the slot.
		float rate = 4.0;
		float t = TIME * rate + phase * 97.0;
		float slot = floor(t);
		float p = 0.012 + 0.25 * flash_burst + 0.03 * excitement;
		float on = step(hash11(slot * 1.37 + phase * 53.0), p);
		level *= on * exp(-fract(t) * 9.0) * 4.0;
	} else {
		level *= 0.9 + 0.1 * sin(TIME * 3.0 + phase * 60.0);
	}
	vec4 view = VIEW_MATRIX * vec4(origin, 1.0);
	view.xy += VERTEX.xy * size;
	VERTEX = view.xyz;
	v_level = level * intensity;
	v_col = COLOR.rgb;
}

void fragment() {
	float g = texture(glow_tex, UV).a;
	ALBEDO = v_col * g * v_level;
}
