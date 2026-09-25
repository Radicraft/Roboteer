shader_type spatial;
// The hall's back wall (pass 2, WorkshopStage._build_hall): black, with a faint cold spill
// of light at its foot that breaks into soft pools along the wall, as if uplights at floor
// level were grazing it. It is emission, not light, so it costs nothing and lights nothing;
// its job is to give the barrier and the ribs in front of it something to stand against,
// so the back of the frame reads as a building with depth rather than a black void.
render_mode unshaded, cull_back;

uniform vec3 spill_colour : source_color = vec3(0.35, 0.45, 0.62);
uniform float spill_energy = 0.1;
// Metres above the floor where the spill has faded out.
uniform float spill_height = 2.6;
// Distance between the pools along the wall, and how much they vary.
uniform float pool_spacing = 3.4;
uniform float pool_contrast = 0.75;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float h = clamp(world_pos.y / spill_height, 0.0, 1.0);
	float rise = pow(1.0 - h, 2.2);
	// Soft pools: a cosine along the wall, sharpened, so the spill is patchy.
	float along = 0.5 + 0.5 * cos(6.2831853 * world_pos.x / pool_spacing);
	float pools = mix(1.0, pow(along, 3.0), pool_contrast);
	// Unshaded: ALBEDO is the output colour (EMISSION is ignored in unshaded mode).
	ALBEDO = spill_colour * spill_energy * rise * pools;
}
