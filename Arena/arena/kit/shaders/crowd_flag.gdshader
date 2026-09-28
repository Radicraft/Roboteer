// Venue kit crowd flags (wave C crowd, B/C "broadcast" options): a cloth strip on a short
// pole held up over a person, swinging and rippling. Presentation only (TIME + uniforms).
//
// Mesh: x 0..1 along the cloth, y 0..1 up it. INSTANCE_CUSTOM: x = phase, y = big (0/1),
// z = size, w = seed. COLOR: the flag's colour (instance colour).
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_lambert_wrap;

uniform float excitement : hint_range(0.0, 1.0) = 0.0;
uniform float arena_half = 5.1;
uniform vec3 spill_color : source_color = vec3(1.0, 0.7, 0.42);
uniform float spill_strength = 0.5;
uniform float spill_depth = 3.5;
uniform float spill_height = 3.2;
uniform float body_light = 0.3;
uniform vec3 sweep_color : source_color = vec3(1.0, 0.86, 0.66);
uniform float sweep_strength = 1.2;

varying float v_spill;
varying float v_sweep;
varying float v_shade;
varying float v_pole;

void vertex() {
	float phase = INSTANCE_CUSTOM.x;
	float big = INSTANCE_CUSTOM.y;
	float size = INSTANCE_CUSTOM.z;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float w = mix(0.42, 0.7, big) * size;
	float h = mix(0.28, 0.45, big) * size;
	float base = 1.5;
	float pole = 0.62;
	v_pole = UV.x < -0.5 ? 1.0 : 0.0;
	float t = TIME * (1.0 + 0.8 * excitement) + phase * 30.0;
	// the whole flag swings about the hand
	float swing = sin(t * 1.7) * mix(0.25, 0.55, excitement);
	vec2 local = vec2(UV.x * w, base + pole - h + UV.y * h);
	if (v_pole > 0.5) {
		// the pole, from the hand to the flag's top
		local = vec2((-UV.x - 1.5) * 0.025, base + UV.y * pole);
	}
	vec2 pivot = vec2(0.0, base);
	vec2 d = local - pivot;
	float c = cos(swing);
	float s = sin(swing);
	local = pivot + vec2(c * d.x - s * d.y, s * d.x + c * d.y);
	// the cloth ripples, more toward its free end
	float ux = max(UV.x, 0.0);
	float ripple = (sin(ux * 7.0 - t * 5.5) * 0.08 * ux + sin(ux * 13.0 - t * 8.0 + UV.y * 3.0) * 0.025 * ux) * (1.0 - v_pole);
	VERTEX = vec3(local.x, local.y, ripple + 0.12);
	NORMAL = normalize(vec3(-cos(UV.x * 7.0 - t * 5.5) * 0.5 * UV.x, 0.0, 1.0));
	v_shade = 0.75 + 0.25 * sin(UV.x * 7.0 - t * 5.5);
	float beyond = max(abs(origin.x), abs(origin.z)) - arena_half;
	v_spill = (1.0 - smoothstep(0.0, spill_depth, beyond)) * (1.0 - smoothstep(0.0, spill_height, origin.y));
	float ang = atan(origin.x, origin.z);
	v_sweep = pow(max(0.0, cos(ang - TIME * 0.42)), 60.0)
		+ 0.7 * pow(max(0.0, cos(ang * 2.0 + TIME * 0.27 + 1.3)), 90.0);
}

void fragment() {
	vec3 col = mix(COLOR.rgb, vec3(0.02), v_pole);
	ALBEDO = col * body_light * v_shade;
	ROUGHNESS = 0.9;
	// The cloth glows a little in its own colour where the house light catches it.
	EMISSION = col * (0.02 + spill_strength * (0.05 + v_spill) * 0.3
		+ sweep_color * v_sweep * sweep_strength * 0.8) * v_shade;
}
