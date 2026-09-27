// The venue's own floor (docs/wave-a-kit-notes.md, the Yard relight, pass 2).
// The kit swaps the floor slab's material_override for this one at build time. The plate
// LAYOUT is one unique map over the whole floor (big irregular steel plates, seams, welds,
// a few corner bolts, oil, tyre marks, grime) plus its normal map and wet map; the arena's
// own scratched plate texture only adds fine scratches, at low contrast, planar in world
// XZ (the slab has no UVs). Dark steel, properly metallic, glossy where it is wet, so the
// sodium key and the floor glint light show as a sheen. Painted warm and cold pools stand
// in for the floods on the tiers without real lights. Presentation only: the slab's body,
// shape and physics material are untouched.
shader_type spatial;
render_mode specular_schlick_ggx;

uniform sampler2D plate_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D plate_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D plate_rough : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D plate_ao : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D floor_map : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D floor_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
// The wet / oil mask (was floor_map's alpha; its own small map since 2026-09-27).
uniform sampler2D floor_wet : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform bool has_floor_normal = false;
// Metres per scratch-texture repeat, and the metres the floor map covers.
uniform float plate_tile_m = 2.5;
uniform float map_extent = 10.4;
// The steel itself (linear albedo) and how much of the scratch texture shows through.
uniform vec3 steel : source_color = vec3(0.2, 0.205, 0.215);
uniform float scratch_contrast = 0.45;
uniform vec3 tint : source_color = vec3(1.0);
uniform float map_strength : hint_range(0.0, 1.0) = 1.0;
uniform float metallic_base = 0.6;
uniform float rough_dry = 0.5;
uniform float rough_min = 0.06;
uniform float wet_darken = 0.35;
// Oil is a dielectric film on the steel: in the wet spots the metal goes away (a metal
// reflecting the night sky reads as a black hole), the colour turns a dark warm brown
// and the roughness never drops below oil_rough, so the sheen is a soft glow.
uniform vec3 oil_color : source_color = vec3(0.07, 0.055, 0.04);
uniform float oil_rough = 0.14;
uniform float normal_depth = 1.0;
uniform float scratch_normal = 0.35;
// Painted fall-off of the light: centre pool, dark wall feet.
uniform float pool_radius = 3.2;
uniform float pool_edge = 0.62;
// A warm pool and a cold pool (x, z, radius), each tinting the albedo.
uniform vec3 warm_pool = vec3(1.5, 2.0, 3.2);
uniform vec3 warm_tint : source_color = vec3(1.18, 0.98, 0.78);
uniform vec3 cold_pool = vec3(-2.5, -1.0, 3.4);
uniform vec3 cold_tint : source_color = vec3(0.78, 0.9, 1.16);

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Planar XZ: the top face's tangent frame in model space (the slab is never rotated).
	TANGENT = vec3(1.0, 0.0, 0.0);
	BINORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 puv = v_world.xz / plate_tile_m;
	float scratch = dot(texture(plate_albedo, puv).rgb, vec3(0.333));
	vec2 muv = v_world.xz / map_extent + 0.5;
	vec4 m = texture(floor_map, muv);
	vec3 mul = mix(vec3(1.0), m.rgb, map_strength);
	float wet = texture(floor_wet, muv).r * map_strength;
	float r = length(v_world.xz);
	float pool = mix(pool_edge, 1.0, 1.0 - smoothstep(pool_radius * 0.55, pool_radius * 1.55, r));
	float w = 1.0 - smoothstep(warm_pool.z * 0.3, warm_pool.z, distance(v_world.xz, warm_pool.xy));
	float c = 1.0 - smoothstep(cold_pool.z * 0.3, cold_pool.z, distance(v_world.xz, cold_pool.xy));
	vec3 pools = mix(vec3(1.0), warm_tint, w) * mix(vec3(1.0), cold_tint, c * (1.0 - w));
	float detail = 1.0 + (scratch - 0.5) * 2.0 * scratch_contrast;
	vec3 dry = steel * tint * mul * pool * pools * detail * (1.0 - wet * wet_darken);
	float oil = smoothstep(0.45, 0.85, wet);
	ALBEDO = mix(dry, oil_color * pools * pool, oil * 0.7);
	float rough = mix(rough_dry, texture(plate_rough, puv).r, 0.5);
	ROUGHNESS = clamp(mix(rough, max(rough_min, oil * oil_rough), wet), 0.04, 1.0);
	METALLIC = metallic_base * (1.0 - wet * 0.45) * (1.0 - oil);
	SPECULAR = 0.5;
	AO = texture(plate_ao, puv).r;
	AO_LIGHT_AFFECT = 0.25;
	// Whiteout blend of the plates' normal and the fine scratches (flattened where wet).
	vec3 n1 = has_floor_normal ? texture(floor_normal, muv).rgb * 2.0 - 1.0 : vec3(0.0, 0.0, 1.0);
	vec3 n2 = texture(plate_normal, puv).rgb * 2.0 - 1.0;
	n2.xy *= scratch_normal * (1.0 - wet * 0.7);
	n1.xy *= normal_depth;
	vec3 n = normalize(vec3(n1.xy + n2.xy, n1.z * n2.z));
	NORMAL_MAP = n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
}
