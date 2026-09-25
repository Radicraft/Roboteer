shader_type spatial;
// The showroom floor (wave A, docs/wave-a-stage-notes.md): dark steel plates laid in a
// staggered bond, with dark rough seams, rivet rows along every plate edge, a per plate
// tone and roughness offset, two octaves of roughness breakup and a few wet patches.
//
// Why it exists: SSR (high tier) and the room probe (every tier with probes) need a floor
// whose roughness VARIES, or the reflection is one smeared sheet. The owner's targets
// (docs/look/img2/menu-b-faceoff.webp) read as premium largely because of this floor.
//
// Procedural, no textures: nothing to upload, identical on every renderer. Every feature
// is anti aliased with fwidth and fades out with distance, so the far floor never shimmers.
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 base_colour : source_color = vec3(0.028, 0.030, 0.035);
uniform float roughness_base = 0.22;
uniform float metallic_base = 0.55;
// Plate size in metres, and the seam half width.
uniform vec2 plate = vec2(1.2, 2.4);
uniform float seam_width = 0.004;
uniform float seam_roughness = 0.75;
// Rivets: inset from the edge, spacing along it, radius.
uniform float rivet_inset = 0.035;
uniform float rivet_spacing = 0.2;
uniform float rivet_radius = 0.009;
// Breakup and wet patches.
uniform float breakup = 0.09;
uniform float plate_variation = 0.12;
uniform float wet = 0.6;
uniform float wet_roughness = 0.07;
// Detail fades between these distances from the camera.
uniform float detail_fade_start = 7.0;
uniform float detail_fade_end = 16.0;

varying vec3 world_pos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float cam_dist = length(VERTEX);
	float detail = 1.0 - smoothstep(detail_fade_start, detail_fade_end, cam_dist);

	// Staggered bond: every other row is offset half a plate.
	vec2 q = p / plate;
	float row = floor(q.y);
	q.x += mod(row, 2.0) * 0.5;
	vec2 id = floor(q);
	vec2 f = fract(q);
	vec2 to_edge = min(f, 1.0 - f) * plate;           // metres to the nearest edge, per axis
	float edge = min(to_edge.x, to_edge.y);
	float aa = max(fwidth(edge), 1e-4);
	float seam = (1.0 - smoothstep(seam_width, seam_width + aa * 1.5, edge)) * detail;

	// Rivets: a row just inside every edge.
	vec2 local = f * plate;                           // metres inside this plate
	float rivet = 0.0;
	vec2 rivet_normal = vec2(0.0);
	// Along the long edges (x near an edge), spaced along y; and the short edges likewise.
	for (int axis = 0; axis < 2; axis++) {
		float across = axis == 0 ? local.x : local.y;
		float along = axis == 0 ? local.y : local.x;
		float size_across = axis == 0 ? plate.x : plate.y;
		float nearest = across < size_across * 0.5 ? rivet_inset : size_across - rivet_inset;
		float cell = (floor(along / rivet_spacing) + 0.5) * rivet_spacing;
		vec2 d = axis == 0 ? vec2(across - nearest, along - cell) : vec2(along - cell, across - nearest);
		float r = length(d);
		float raa = max(fwidth(r), 1e-4);
		float dome = 1.0 - smoothstep(rivet_radius - raa, rivet_radius + raa, r);
		if (dome > rivet) {
			rivet = dome;
			rivet_normal = d / rivet_radius;
		}
	}
	rivet *= detail;

	// Per plate tone and roughness; two octaves of breakup; wet patches.
	float plate_rand = hash12(id + 17.0);
	float tone = 1.0 + (plate_rand - 0.5) * 2.0 * plate_variation;
	float n = vnoise(p * 2.7) * 0.6 + vnoise(p * 11.0 + 5.0) * 0.4;
	float scratch = vnoise(vec2(p.x * 38.0, p.y * 2.0) + plate_rand * 10.0);
	float wet_mask = smoothstep(0.58, 0.78, vnoise(p * 0.45 + 3.1)) * wet;

	float rough = roughness_base + (n - 0.5) * 2.0 * breakup * detail
		+ (plate_rand - 0.5) * 0.08;
	rough = mix(rough, wet_roughness, wet_mask);
	rough += smoothstep(0.7, 0.9, scratch) * 0.12 * detail;
	rough = mix(rough, seam_roughness, seam);
	rough = mix(rough, 0.35, rivet);

	vec3 albedo = base_colour * tone * (1.0 - 0.6 * seam);
	albedo *= 1.0 - 0.25 * wet_mask;                  // wet steel reads darker
	albedo = mix(albedo, base_colour * 2.2, rivet * 0.6);

	ALBEDO = albedo;
	ROUGHNESS = clamp(rough, 0.04, 1.0);
	METALLIC = mix(metallic_base, 0.2, seam);
	SPECULAR = 0.5;

	// Rivet domes tilt the normal; the seam is a shallow groove.
	vec2 tilt = rivet_normal * rivet * 0.7;
	NORMAL_MAP = normalize(vec3(tilt.x, -tilt.y, 1.0)) * 0.5 + 0.5;
}
