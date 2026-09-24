// rb_painted: the painted-metal master (wave A, materials lead).
//
// Used by the `livery` slot (the player's colour, clear-coated) and the `dark_metal` slot
// (black powder coat, no lacquer). docs/wave-a-materials-notes.md has the why; the mask
// convention it reads is docs/wave-a-contracts.md section 1.
//
// Layers, bottom to top, all decided per pixel:
//   bare metal  <- exposed where the paint has chipped through
//   primer      <- a thin ring around every chip
//   paint       <- the livery colour, with the paint job overlay (the old detail map)
//   clear coat  <- lacquer: a sharp reflection above the colour, micro-scratched
//   grime       <- cavity dirt from the AO channel
//
// Where paint wears comes from ONE of two sources:
//
//   A. The part's BAKED MASK (primary; docs/wave-a-contracts.md 1.2). One RGB texture per
//      mesh on UV2, Cycles-baked by Tools/blender/rkit.py `bake_masks`: R edge (0 flat, 1
//      on a bevel crest, 4 mm radius), G AO (1 open), B cavity (1 in a seam). PartVisuals
//      binds it per mesh and sets `mask_enabled`. Independent of triangle size and of
//      screen size, so it also holds at fight distance and on the GL tier.
//   B. No mask (every part not yet rebuilt): the product of three things:
//   1. EXPOSURE, from the vertex colour: 1 - COLOR.r (white = clean, see the contract),
//      floored at `wear_unmasked` so a bevelled part with no bake still gets a light edge.
//   2. The EDGE BAND, measured here from geometry: signed mean curvature per pixel,
//      |dN|/|dP| from screen derivatives. It finds a 4 to 8 mm bevel as a band of about
//      100 to 250 rad/m and a flat plate as zero, whatever the triangle size. It is only
//      trusted while a pixel is smaller than the bevel; past that it fades to exposure.
//   3. CHIP NOISE from the surface texture (B), rank-equalised, so `wear` is literally the
//      fraction of the edge band that is chipped.
//
// Renderer tiers (CURRENT_RENDERER, Godot 4.4+):
//   Forward+   everything.
//   Mobile     everything; the same cost (it is one texture fetch and some ALU).
//   Compat.    no curvature (derivatives on the simulator's software rasterizer cost more
//              than the rest of the shader), so no chips at all, and no scratch breakup in
//              the clear coat. The sim is a functional check, not a look.

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

group_uniforms paint;
uniform vec4 albedo : source_color = vec4(0.8, 0.2, 0.1, 1.0);
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.04, 1.0) = 0.40;
// +- this much roughness from the surface texture's R channel.
uniform float roughness_range : hint_range(0.0, 0.3) = 0.08;
uniform vec2 uv1_scale = vec2(1.0, 1.0);
// Packed LINEAR data: R roughness breakup, G clear-coat scratches, B chip noise, A grime.
uniform sampler2D surface_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

group_uniforms mask;
// The part's baked mask on UV2 (source A above). Bound per mesh by PartVisuals.
uniform bool mask_enabled = false;
uniform sampler2D mask_tex : hint_default_black, filter_linear_mipmap, repeat_disable;

group_uniforms clearcoat;
uniform float clearcoat : hint_range(0.0, 1.0) = 1.0;
// Never 0.0 on the base: godot#95207.
uniform float clearcoat_roughness : hint_range(0.0, 1.0) = 0.05;
// Extra clear-coat roughness inside a micro-scratch.
uniform float clearcoat_scratch : hint_range(0.0, 1.0) = 0.25;

group_uniforms paint_job;
// The paint job overlay, formerly StandardMaterial3D's detail layer (Arena/bot/livery.gd).
uniform bool detail_enabled = false;
// 0 = MIX: mix(paint, overlay.rgb, overlay.a); 1 = MUL: mix(paint, paint * overlay.rgb, overlay.a)
uniform int detail_blend = 0;
uniform sampler2D detail_albedo : source_color, hint_default_transparent, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool detail_normal_enabled = false;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_scale : hint_range(0.0, 2.0) = 0.5;

group_uniforms wear;
// Fraction of the edge band that is chipped through. 0 = showroom, 0.6 = campaigned, 1 = scrap.
uniform float wear : hint_range(0.0, 1.0) = 0.45;
// Exposure a part with no vertex mask (COLOR.r = 1) still gets on its bevels.
uniform float wear_unmasked : hint_range(0.0, 1.0) = 0.5;
// Curvature band, rad/m. A 6 mm bevel reads about 130; a 50 mm tube 20.
uniform float curvature_lo = 45.0;
uniform float curvature_hi = 150.0;
// Pixel footprint (m/px) past which the curvature is no longer trusted.
uniform float curvature_max_px = 0.0035;
uniform vec4 primer_color : source_color = vec4(0.55, 0.56, 0.55, 1.0);
uniform float primer_roughness : hint_range(0.0, 1.0) = 0.72;
uniform vec4 bare_color : source_color = vec4(0.78, 0.79, 0.80, 1.0);
uniform float bare_roughness : hint_range(0.0, 1.0) = 0.34;
// How much of the chip is primer ring rather than bare metal.
uniform float primer_ring : hint_range(0.0, 1.0) = 0.35;

group_uniforms grime;
// Cavity grime at COLOR.g = 0: albedo x (1 - 0.2 * grime), roughness + 0.15 * grime.
uniform float grime : hint_range(0.0, 1.0) = 0.8;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.8;

void fragment() {
	vec2 uv = UV * uv1_scale;
	vec4 s = texture(surface_tex, uv);

	// ---- paint
	vec3 paint = albedo.rgb;
	if (detail_enabled) {
		vec4 d = texture(detail_albedo, uv);
		paint = detail_blend == 0 ? mix(paint, d.rgb, d.a) : mix(paint, paint * d.rgb, d.a);
	}
	float rough = roughness + (s.r - 0.5) * 2.0 * roughness_range;
	float cc_rough = clearcoat_roughness;
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	cc_rough += s.g * clearcoat_scratch;
#endif

	// ---- where the paint is worn
	float occ = COLOR.g;
	float cavity = 0.0;
	float exposure = max(1.0 - COLOR.r, wear_unmasked);
	vec3 m = vec3(0.0, 1.0, 0.0);
	if (mask_enabled) {
		m = texture(mask_tex, UV2).rgb;
		occ = m.g;
		cavity = m.b;
	}
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	vec3 n = normalize(NORMAL);
	vec3 dpx = dFdx(VERTEX);
	vec3 dpy = dFdy(VERTEX);
	float dp2 = dot(dpx, dpx) + dot(dpy, dpy);
	// Signed: positive where the surface turns away from the viewer's side (convex).
	float k = (dot(dFdx(n), dpx) + dot(dFdy(n), dpy)) / max(dp2, 1e-12);
	float px = sqrt(dp2 * 0.5);
	float trust = 1.0 - smoothstep(curvature_max_px * 0.6, curvature_max_px, px);
	float edge = smoothstep(curvature_lo, curvature_hi, k);
	// Trusted: the band is the geometry's own edge. Untrusted (far away, a bevel under
	// about two pixels): no chips at all. A chip that small is sub-pixel anyway, and the
	// alternative (vertex exposure alone) spreads wear across whole faces, because a
	// vertex value interpolates over the full length of a long triangle (measured on the
	// test board, docs/wave-a-materials-notes.md).
	exposure = exposure * edge * trust;
	if (mask_enabled) {
		exposure = m.r;
	}
#else
	// No curvature here, and vertex exposure alone bleeds across whole faces (it did on
	// the board), so the simulator's tier shows clean paint. Grime and clear coat stay.
	exposure = mask_enabled ? m.r : 0.0;
#endif
	float e = clamp(exposure * wear, 0.0, 1.0);
	float aa = max(fwidth(s.b), 0.02);
	float primer_m = 1.0 - smoothstep(e - aa, e + aa, s.b);
	float e_bare = e * (1.0 - primer_ring);
	float bare_m = 1.0 - smoothstep(e_bare - aa, e_bare + aa, s.b);
	bare_m *= step(0.001, e_bare);
	primer_m *= step(0.001, e);

	vec3 col = mix(paint, primer_color.rgb, primer_m);
	col = mix(col, bare_color.rgb, bare_m);
	float metal = mix(metallic, 0.0, primer_m);
	metal = mix(metal, 1.0, bare_m);
	rough = mix(rough, primer_roughness, primer_m);
	rough = mix(rough, bare_roughness, bare_m);
	float cc = clearcoat * (1.0 - primer_m);

	// ---- cavity grime (AO, and the seams the mask calls cavity)
	float g = max(1.0 - occ, cavity) * grime * mix(0.6, 1.0, s.a);
	col *= 1.0 - 0.2 * g;
	rough = clamp(rough + 0.15 * g, 0.04, 1.0);

	ALBEDO = col;
	METALLIC = metal;
	ROUGHNESS = rough;
	CLEARCOAT = cc;
	CLEARCOAT_ROUGHNESS = clamp(cc_rough, 0.0, 1.0);
	AO = mix(1.0, occ, ao_strength);
	AO_LIGHT_AFFECT = 0.0;
	if (detail_normal_enabled) {
		NORMAL_MAP = texture(detail_normal, uv).rgb;
		NORMAL_MAP_DEPTH = normal_scale * (1.0 - primer_m);
	}
}
