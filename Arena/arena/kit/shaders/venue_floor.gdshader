// The venue's grade of the arena floor (docs/wave-a-kit-notes.md, the Yard relight).
// The kit swaps the floor slab's material_override for this one at build time: the same
// PBR plate set the arena used, planar in world XZ (the slab has no UVs), multiplied by
// ONE unique map over the whole floor (oil, tyre marks, weld seams, grime at the wall
// feet) whose alpha makes the oily spots wet and glossy. Presentation only: the slab's
// body, shape and physics material are untouched.
shader_type spatial;
render_mode specular_schlick_ggx;

uniform sampler2D plate_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D plate_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D plate_rough : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D plate_ao : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D floor_map : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
// Metres per plate texture repeat, and the metres the floor map covers.
uniform float plate_tile_m = 2.5;
uniform float map_extent = 10.4;
uniform vec3 tint : source_color = vec3(0.5, 0.49, 0.47);
uniform float map_strength : hint_range(0.0, 1.0) = 1.0;
uniform float metallic_base = 0.25;
uniform float rough_min = 0.1;
uniform float rough_scale = 1.0;
uniform float normal_depth = 0.6;
// A painted-in fall-off of the floods' pool, so the tiers without the real flood lights
// still read as a lit centre and dark wall feet.
uniform float pool_radius = 3.2;
uniform float pool_edge = 0.62;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Planar XZ: the top face's tangent frame in model space (the slab is never rotated).
	TANGENT = vec3(1.0, 0.0, 0.0);
	BINORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 puv = v_world.xz / plate_tile_m;
	vec3 plate = texture(plate_albedo, puv).rgb;
	vec2 muv = v_world.xz / map_extent + 0.5;
	vec4 m = texture(floor_map, muv);
	vec3 mul = mix(vec3(1.0), m.rgb, map_strength);
	float r = length(v_world.xz);
	float pool = mix(pool_edge, 1.0, 1.0 - smoothstep(pool_radius * 0.55, pool_radius * 1.55, r));
	ALBEDO = plate * tint * mul * pool;
	float rough = texture(plate_rough, puv).r * rough_scale;
	ROUGHNESS = clamp(mix(rough, rough_min, m.a * map_strength), 0.04, 1.0);
	METALLIC = metallic_base * (1.0 - m.a * 0.5);
	SPECULAR = 0.5;
	AO = texture(plate_ao, puv).r;
	AO_LIGHT_AFFECT = 0.4;
	NORMAL_MAP = texture(plate_normal, puv).rgb;
	NORMAL_MAP_DEPTH = normal_depth * (1.0 - m.a * 0.6);
}
