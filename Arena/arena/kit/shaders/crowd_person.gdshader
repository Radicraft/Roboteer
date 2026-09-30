// Venue kit 3D crowd person (wave C crowd, option C "mix", docs/wave-c-crowd-notes.md).
//
// One MultiMesh per MakeHuman person and detail level (CrowdPeopleData), all sharing this
// material and one VERTEX ANIMATION TEXTURE: each person owns a shelf of 2F rows starting
// at their row (UV.y); row + f holds every vertex's position in frame f, row + F + f its
// normal; the column is UV.x. Clips (idle sway, clap, raise, cheer, flinch, boo, seated)
// play per instance with its own phase and rate, blended over the idle so nothing pops.
// Presentation only: TIME and uniforms the kit pushes, nothing from the simulation.
//
// INSTANCE_CUSTOM: x = phase 0..1 (+2 when seated), y = excitability 0..1,
//                  z = house 0..1 (how far into the dark house: dims the person),
//                  w = seed 0..1 (clothes, phone, rate, who reacts).
// UV2.x: zone (0 skin, 1 top, 2 bottom, 3 hat, 4 hair, 5 shoes, 6 scarf, 7 phone).
// Vertex COLOR: the baked albedo (sRGB).
shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_lambert_wrap, specular_schlick_ggx;

uniform sampler2D vat : filter_nearest, repeat_disable;
uniform float frames = 87.0;
uniform vec3 pos_min = vec3(-0.95, -0.6, -0.95);
uniform vec3 pos_max = vec3(0.95, 2.45, 0.95);
// Clip table: (first frame, frame count, seconds per frame).
uniform vec3 clip_idle = vec3(0.0, 16.0, 0.25);
uniform vec3 clip_clap_in = vec3(16.0, 6.0, 0.0833);
uniform vec3 clip_clap = vec3(22.0, 6.0, 0.0833);
uniform vec3 clip_raise = vec3(28.0, 7.0, 0.0833);
uniform vec3 clip_cheer = vec3(35.0, 8.0, 0.0833);
uniform vec3 clip_flinch = vec3(43.0, 6.0, 0.0833);
uniform vec3 clip_boo_in = vec3(49.0, 6.0, 0.0833);
uniform vec3 clip_boo = vec3(55.0, 8.0, 0.1);
uniform vec3 clip_sit = vec3(63.0, 12.0, 0.25);
uniform vec3 clip_sit_raise = vec3(75.0, 6.0, 0.0833);
uniform vec3 clip_sit_cheer = vec3(81.0, 6.0, 0.0833);

// The venue's frame: world -> arena space (the menu stage moves and turns the venue).
uniform mat4 world_to_arena = mat4(1.0);

// Reactions (shared names with the cards).
uniform float excitement : hint_range(0.0, 1.0) = 0.0;
uniform float flinch_age = 100.0;
uniform vec3 react_pos = vec3(0.0);
uniform float react_age = 100.0;
uniform float react_strength = 0.0;
// 0 a hit (the ripple), 1 a clear verdict (the house cheers), 2 a close one (the house boos).
uniform float react_kind = 0.0;
uniform float ripple_speed = 9.0;
// Where the fight is: heads and shoulders follow it (world space).
uniform vec3 focus_pos = vec3(0.0);
uniform float look_share = 1.0;
// Share of people who film big moments on a phone.
uniform float phone_share = 0.22;

// Staging (the card names, so a venue's crowd_staging lands on both).
uniform float body_light = 0.3;
// The mesh has real normals, so it takes the venue's light better than a card: lift it.
uniform float person_light = 1.8;
uniform vec3 spill_color : source_color = vec3(1.0, 0.7, 0.42);
uniform float spill_strength = 0.5;
uniform float arena_half = 5.1;
uniform float spill_depth = 3.5;
uniform float spill_height = 3.2;
uniform vec3 rim_color : source_color = vec3(0.45, 0.55, 0.78);
uniform float rim_strength = 0.6;
uniform vec3 haze_color : source_color = vec3(0.025, 0.04, 0.08);
uniform float haze_near = 6.0;
uniform float haze_far = 30.0;
uniform float haze_max = 0.8;
uniform float desat_far = 0.6;
uniform float saturation = 1.0;
uniform float recolour = 0.85;
uniform float keep_share = 0.3;
uniform vec3 phone_color : source_color = vec3(0.75, 0.85, 1.0);
uniform float phone_glow = 3.0;
// How dark the deepest "house" person gets (custom.z = 1): the seam blend with the cards.
uniform float house_dim = 0.55;
uniform int debug_view = 0;

// Clothes palette (linear): mostly muted night colours, a few loud ones.
const vec3 PALETTE[12] = vec3[](
	vec3(0.05, 0.05, 0.055), vec3(0.16, 0.16, 0.17), vec3(0.03, 0.05, 0.12),
	vec3(0.12, 0.03, 0.03), vec3(0.05, 0.09, 0.05), vec3(0.3, 0.3, 0.29),
	vec3(0.45, 0.06, 0.04), vec3(0.03, 0.1, 0.32), vec3(0.42, 0.3, 0.06),
	vec3(0.18, 0.11, 0.06), vec3(0.5, 0.5, 0.48), vec3(0.09, 0.02, 0.12)
);

varying vec3 v_col;
varying float v_spill;
varying float v_haze;
varying float v_rim_up;
varying float v_house;
varying float v_phone;

float hash11(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

vec3 vat_pos(vec2 cr, float frame) {
	vec3 q = texelFetch(vat, ivec2(int(cr.x), int(cr.y + frame)), 0).rgb;
	return pos_min + q * (pos_max - pos_min);
}

vec3 vat_nrm(vec2 cr, float frame) {
	return texelFetch(vat, ivec2(int(cr.x), int(cr.y + frames + frame)), 0).rgb * 2.0 - 1.0;
}

// Frame pair + mix for time `t` seconds into a clip. loop: wrap; else clamp.
vec3 clip_frames(vec3 clip, float t, bool loop) {
	float f = t / clip.z;
	if (loop) {
		f = mod(f, clip.y);
		float f0 = floor(f);
		return vec3(clip.x + f0, clip.x + mod(f0 + 1.0, clip.y), fract(f));
	}
	f = clamp(f, 0.0, clip.y - 1.0);
	float f0 = floor(f);
	return vec3(clip.x + f0, clip.x + min(f0 + 1.0, clip.y - 1.0), fract(f));
}

// An action: `in` clip, the `loop` clip for `hold` seconds, then `in` backwards.
// Frame pair + mix in xyz, weight over the idle in w.
vec4 action(vec3 in_clip, vec3 loop_clip, float lt, float hold) {
	float d_in = (in_clip.y - 1.0) * in_clip.z;
	float per = loop_clip.y * loop_clip.z;
	hold = max(per, ceil(hold / per) * per);
	float total = d_in * 2.0 + hold;
	if (lt <= 0.0 || lt >= total) {
		return vec4(0.0);
	}
	float w = smoothstep(0.0, 0.16, lt) * (1.0 - smoothstep(total - 0.16, total, lt));
	vec3 fr;
	if (lt < d_in) {
		fr = clip_frames(in_clip, lt, false);
	} else if (lt < d_in + hold) {
		fr = clip_frames(loop_clip, lt - d_in, true);
	} else {
		fr = clip_frames(in_clip, d_in - (lt - d_in - hold), false);
	}
	return vec4(fr, w);
}

void vertex() {
	vec2 cr = floor(UV);
	float zone = floor(UV2.x + 0.5);
	bool seated = INSTANCE_CUSTOM.x > 1.5;
	float phase = fract(INSTANCE_CUSTOM.x);
	float excit = INSTANCE_CUSTOM.y;
	float house = INSTANCE_CUSTOM.z;
	float seed = INSTANCE_CUSTOM.w;
	float rate = 0.88 + 0.24 * hash11(seed * 41.3);
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 local = (world_to_arena * vec4(origin, 1.0)).xyz;

	// Idle: always playing, own phase and rate.
	float ti = TIME * rate + phase * 40.0;
	vec3 idle_clip = seated ? clip_sit : clip_idle;
	vec3 fi = clip_frames(idle_clip, ti, true);
	vec3 p = mix(vat_pos(cr, fi.x), vat_pos(cr, fi.y), fi.z);
	vec3 n = mix(vat_nrm(cr, fi.x), vat_nrm(cr, fi.y), fi.z);

	vec3 raise_in = seated ? clip_sit_raise : clip_raise;
	vec3 raise_loop = seated ? clip_sit_cheer : clip_cheer;
	vec4 a = vec4(0.0);
	float arms_up = 0.0;
	// 1. The last big moment. A hit ripples out from where it happened; a verdict sweeps the
	// house from `react_pos` (the arena centre) faster and holds longer.
	float verdict = step(0.5, react_kind);
	float lt = react_age - distance(origin.xz, react_pos.xz) / mix(ripple_speed, 14.0, verdict)
		- phase * 0.35 - (1.0 - excit) * 0.25;
	float r1 = hash11(seed * 91.7 + 3.1);
	float r2 = hash11(seed * 53.3 + 7.7);
	if (react_kind > 1.5) {
		// Boo: most boo, some cover their faces, the seated stay put.
		if (!seated && r1 < 0.55 + 0.35 * react_strength) {
			a = action(clip_boo_in, clip_boo, lt, 1.6 + 2.0 * react_strength * excit);
		} else if (!seated && r2 < 0.5) {
			a = action(clip_flinch, vec3(clip_flinch.x + clip_flinch.y - 1.0, 1.0, clip_flinch.z), lt, 1.4);
		}
	} else {
		float keen = react_strength * (mix(0.4, 0.75, verdict) + 0.6 * excit);
		float hold = (1.0 + 2.2 * react_strength * excit) * mix(1.0, 1.8, verdict);
		if (r1 < keen) {
			a = action(raise_in, raise_loop, lt, hold);
			arms_up = a.w;
		} else if (!seated && r2 < 0.35 + 0.5 * react_strength) {
			a = action(clip_clap_in, clip_clap, lt - 0.2, hold * 0.9 + 0.3);
		}
	}
	// 2. Between moments, the house's level: a few people at a time clap or cheer in
	// eight-second slots of their own.
	if (a.w <= 0.0) {
		float slot_len = 8.0;
		float ts = TIME * rate + seed * slot_len;
		float slot = floor(ts / slot_len);
		float in_slot = mod(ts, slot_len) - hash11(slot + seed * 13.0) * 3.0;
		float e = excitement * (0.35 + 0.65 * excit);
		float r = hash11(slot * 7.1 + seed * 29.0);
		if (r < e * 0.5) {
			a = action(raise_in, raise_loop, in_slot, 1.5 + 2.0 * e);
			arms_up = a.w;
		} else if (!seated && r < 0.06 + e) {
			a = action(clip_clap_in, clip_clap, in_slot, 1.5 + 2.5 * e);
		}
	}
	// 3. A flinch (the arena biting) beats everything.
	float fl = flinch_age - phase * 0.2;
	if (!seated && fl > 0.0 && fl < 2.0 && hash11(seed * 17.9) < 0.3 + 0.5 * excit) {
		a = action(clip_flinch, vec3(clip_flinch.x + clip_flinch.y - 1.0, 1.0, clip_flinch.z), fl, 0.5);
		arms_up = 0.0;
	}
	if (a.w > 0.0) {
		vec3 pa = mix(vat_pos(cr, a.x), vat_pos(cr, a.y), a.z);
		vec3 na = mix(vat_nrm(cr, a.x), vat_nrm(cr, a.y), a.z);
		p = mix(p, pa, a.w);
		n = mix(n, na, a.w);
	}

	// Phones: only the ones filming, and only while their arms are up.
	v_phone = 0.0;
	if (zone > 6.5) {
		bool films = hash11(seed * 7.3 + 1.9) < phone_share;
		float show = films ? smoothstep(0.6, 0.95, arms_up) : 0.0;
		v_phone = show;
		if (show < 0.01) {
			p = vec3(0.0, -50.0, 0.0);
		}
	}

	// Heads and shoulders follow the fight: a twist about the spine that grows up the body.
	vec3 to_f = focus_pos - origin;
	float lx = dot(to_f, normalize(MODEL_MATRIX[0].xyz));
	float lz = dot(to_f, normalize(MODEL_MATRIX[2].xyz));
	float look = clamp(atan(lx, lz), -1.0, 1.0) * look_share;
	look += sin(TIME * 0.31 * rate + seed * 50.0) * 0.14;
	float h0 = seated ? 0.3 : 0.95;
	float ang = look * (0.3 * smoothstep(h0, h0 + 0.55, p.y) + 0.7 * smoothstep(h0 + 0.47, h0 + 0.67, p.y));
	float c = cos(ang);
	float s = sin(ang);
	p.xz = vec2(c * p.x + s * p.z, -s * p.x + c * p.z);
	n.xz = vec2(c * n.x + s * n.z, -s * n.x + c * n.z);

	VERTEX = p;
	NORMAL = normalize(n);

	// Colour: the baked albedo, clothes re-tinted per person.
	vec3 alb = pow(COLOR.rgb, vec3(2.2));
	float lum = dot(alb, vec3(0.299, 0.587, 0.114));
	float rc = hash11(seed * 7.77) < keep_share ? 0.0 : recolour;
	vec3 top = PALETTE[int(hash11(seed * 3.3) * 11.99)];
	vec3 acc = PALETTE[int(hash11(seed * 5.9) * 11.99)];
	float grey = max(lum, 0.02) / 0.08;
	if (zone > 0.5 && zone < 1.5) {
		alb = mix(alb, top * clamp(grey, 0.3, 2.0), rc);
	} else if (zone > 1.5 && zone < 2.5) {
		alb *= 0.6 + 0.8 * hash11(seed * 2.2);
	} else if ((zone > 2.5 && zone < 3.5) || (zone > 5.5 && zone < 6.5)) {
		alb = mix(alb, acc * clamp(grey, 0.3, 2.0), rc);
	}
	v_col = alb;
	v_house = house;
	float beyond = max(abs(local.x), abs(local.z)) - arena_half;
	v_spill = (1.0 - smoothstep(0.0, spill_depth, beyond)) * (1.0 - smoothstep(0.0, spill_height, local.y));
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	v_haze = smoothstep(haze_near, haze_far, length(cam - origin)) * haze_max;
	v_rim_up = smoothstep(h0 + 0.25, h0 + 0.75, p.y);
}

void fragment() {
	vec3 body = v_col;
	float lum = dot(body, vec3(0.299, 0.587, 0.114));
	body = max(mix(vec3(lum), body, saturation), vec3(0.0));
	body = mix(body, vec3(lum), desat_far * v_haze);
	// Deeper into the house, darker: the 3D rows hand over to the dark cards without a band.
	float dim = 1.0 - house_dim * v_house;
	ALBEDO = mix(body * body_light * person_light * dim, haze_color, v_haze);
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	// Rim from behind and above: grazing view angle, strongest on heads and shoulders.
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 up_v = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	float top = clamp(dot(NORMAL, up_v) * 0.6 + 0.5, 0.0, 1.0);
	float rim = fres * top * (0.4 + 0.6 * v_rim_up) * (1.0 - v_haze * 0.6);
	vec3 spill = body * spill_color * spill_strength * v_spill * dim;
	EMISSION = spill + rim_color * rim * rim_strength * (0.5 + 0.5 * (1.0 - v_spill)) * (1.0 - 0.4 * v_house)
		+ phone_color * v_phone * phone_glow * 0.35;
	if (debug_view == 1) { ALBEDO = vec3(0.0); EMISSION = v_col; }
	if (debug_view == 3) { ALBEDO = vec3(0.0); EMISSION = NORMAL * 0.5 + 0.5; }
}
