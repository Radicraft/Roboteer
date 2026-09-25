shader_type spatial;
// The turntable plinth (pass 2, WorkshopStage._build_stage): a steel drum you can read, as
// in the M1 and G1 targets, instead of a gloss black disc that vanished into the floor.
// One mesh (the disc cylinder), two looks chosen by the surface's direction:
//   side  brushed steel in 16 bolted panels with dark seams and a bright chamfer at the lip
//   top   the black gloss the machine stands on (it reflects the machine and the softbox),
//         with a ring of lighter steel segments round its edge
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform float radius = 1.5;
uniform float height = 0.12;
uniform int panels = 16;
uniform vec3 side_colour : source_color = vec3(0.34, 0.35, 0.37);
uniform vec3 top_colour : source_color = vec3(0.018, 0.019, 0.022);
uniform vec3 band_colour : source_color = vec3(0.10, 0.105, 0.115);
uniform float band_inner = 0.9;   // share of the radius where the edge band starts

varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

float aa_step(float edge, float x) {
	float w = max(fwidth(x), 1e-5);
	return smoothstep(edge - w, edge + w, x);
}

void fragment() {
	float ang = atan(local_pos.z, local_pos.x);            // -pi..pi
	float seg = (ang / 6.2831853 + 0.5) * float(panels);
	float in_seg = fract(seg);
	float seam_d = min(in_seg, 1.0 - in_seg);               // 0 at a seam, in segments
	float r = length(local_pos.xz);
	if (local_normal.y > 0.5) {
		// Top: black gloss, with a segmented steel band round the edge.
		float band = aa_step(band_inner * radius, r);
		float band_seam = 1.0 - aa_step(0.012, seam_d * 6.2831853 * r / float(panels));
		vec3 col = mix(top_colour, band_colour, band);
		col *= 1.0 - 0.7 * band_seam * band;
		ALBEDO = col;
		METALLIC = mix(0.55, 0.8, band);
		ROUGHNESS = mix(0.34, 0.42, band);
	} else {
		// Side: brushed steel panels.
		float y = (local_pos.y / height) + 0.5;                  // 0 bottom .. 1 top
		float metres_along = seam_d * 6.2831853 * r / float(panels);
		float seam = 1.0 - aa_step(0.006, metres_along);
		// Bolt rows, one near the top and one near the bottom of each panel end.
		float bolt = 0.0;
		for (int k = 0; k < 2; k++) {
			float by = k == 0 ? 0.25 : 0.72;
			vec2 d = vec2(metres_along - 0.035, (y - by) * height);
			float bd = length(d);
			bolt = max(bolt, 1.0 - aa_step(0.0065, bd));
		}
		float lip = aa_step(0.86, y);                            // the chamfer at the top
		float brushed = fract(sin(floor(local_pos.y * 900.0) * 12.9898) * 43758.5453);
		vec3 col = side_colour * (0.92 + 0.16 * brushed);
		col = mix(col, side_colour * 1.7, lip);
		col *= 1.0 - 0.75 * seam;
		col = mix(col, side_colour * 1.5, bolt);
		ALBEDO = col;
		// Half metal: a full metal side only mirrors the dark room and reads black.
		METALLIC = 0.5;
		ROUGHNESS = mix(mix(0.4, 0.22, lip), 0.7, seam);
	}
}
