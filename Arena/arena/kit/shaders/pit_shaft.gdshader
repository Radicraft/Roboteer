// Drop Zone: the lining of the open pit's shaft (docs/wave-a-kit-notes.md, pass 4). The
// arena's pit walls are plain concrete lit by one red light, so from the fight camera the
// open pit read as a flat red square. This lining sits a centimetre inside them and paints
// the depth: dark scorched concrete at the lip, getting hotter toward a glowing floor far
// down, with ring seams and vertical ribs catching the glow. Unshaded, so it costs one
// pass and reads the same on every tier. No collision (a mesh only).
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

uniform float depth = 2.8;
uniform vec3 hot : source_color = vec3(1.0, 0.24, 0.05);
uniform vec3 cool : source_color = vec3(0.05, 0.03, 0.035);
uniform float glow = 3.2;
uniform float rib_step = 0.3;
uniform float seam_step = 0.7;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float d = clamp(-v_world.y / depth, 0.0, 1.0);        // 0 at the lip, 1 at the bottom
	float heat = pow(d, 2.2);
	// Along the wall: whichever horizontal axis varies on this face.
	float along = abs(NORMAL.x) > abs(NORMAL.z) ? v_world.z : v_world.x;
	if (abs(dot(NORMAL, vec3(0.0, 1.0, 0.0))) > 0.5) {
		along = v_world.x;
	}
	float rib = smoothstep(0.42, 0.5, abs(fract(along / rib_step) - 0.5));
	float seam = 1.0 - smoothstep(0.0, 0.035, abs(fract(-v_world.y / seam_step) - 0.5) * seam_step * 2.0 - 0.0);
	float n = texture(noise_tex, vec2(along * 0.6, v_world.y * 0.6)).r;
	vec3 base = mix(cool, hot * glow, heat);
	base *= 0.75 + 0.5 * n;
	base = mix(base, base * 1.8 + hot * 0.4 * heat, rib * 0.6);
	base *= 1.0 - seam * 0.55;
	ALBEDO = base;
}
