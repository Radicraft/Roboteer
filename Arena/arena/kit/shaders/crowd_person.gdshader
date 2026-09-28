// Venue kit 3D crowd person (wave C crowd, docs/wave-c-crowd-notes.md).
//
// One MultiMesh per MakeHuman person (Tools/blender/arena_kit/crowd_vat_human.py). The mesh
// is drawn from a VERTEX ANIMATION TEXTURE: for frame f, row person_row + 2f holds every
// vertex's position and the next row its normal. Clips (idle sway, clap, raise, cheer,
// flinch) are played per instance with its own phase and rate, and blended over the idle so
// nothing pops. Presentation only: TIME and uniforms the kit pushes, nothing from the fight.
//
// INSTANCE_CUSTOM: x = phase 0..1, y = excitability 0..1, z = rate 0.85..1.15, w = seed 0..1.
// (no instance colour: COLOR is the vertex's baked albedo; clothes tints come from `seed`)
// UV:              x = VAT column (vertex index), y = zone / 8 (skin, top, bottom, hat, hair,
//                  shoes, scarf).
// Vertex COLOR:    the baked albedo (sRGB).
shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_lambert_wrap, specular_schlick_ggx;

uniform sampler2D vat : filter_nearest, repeat_disable;
uniform float person_row = 0.0;
uniform vec2 vat_size = vec2(1660.0, 2336.0);
uniform vec3 pos_min = vec3(-0.95, -0.05, -0.95);
uniform vec3 pos_max = vec3(0.95, 2.45, 0.95);
uniform float fps = 12.0;
// clip table: start frame, frame count
uniform vec2 clip_idle = vec2(0.0, 40.0);
uniform vec2 clip_clap_in = vec2(40.0, 6.0);
uniform vec2 clip_clap = vec2(46.0, 6.0);
uniform vec2 clip_raise = vec2(52.0, 7.0);
uniform vec2 clip_cheer = vec2(59.0, 8.0);
uniform vec2 clip_flinch = vec2(67.0, 6.0);

// Reactions (the same uniforms as the cards).
uniform float excitement : hint_range(0.0, 1.0) = 0.0;
uniform float flinch : hint_range(0.0, 1.0) = 0.0;
uniform float flinch_age = 100.0;
uniform vec3 react_pos = vec3(0.0);
uniform float react_age = 100.0;
uniform float react_strength = 0.0;
uniform float ripple_speed = 9.0;
// Where the fight is: heads and shoulders follow it.
uniform vec3 focus_pos = vec3(0.0);
uniform float look_share = 1.0;

// Staging (card names kept so a venue's crowd_staging applies to both).
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
// Clothes palette (linear): mostly muted night colours, a few loud ones, a team colour.
const vec3 PALETTE[12] = vec3[](
	vec3(0.05, 0.05, 0.055), vec3(0.16, 0.16, 0.17), vec3(0.03, 0.05, 0.12),
	vec3(0.12, 0.03, 0.03), vec3(0.05, 0.09, 0.05), vec3(0.3, 0.3, 0.29),
	vec3(0.55, 0.05, 0.03), vec3(0.03, 0.12, 0.4), vec3(0.5, 0.35, 0.06),
	vec3(0.18, 0.11, 0.06), vec3(0.6, 0.6, 0.58), vec3(0.09, 0.02, 0.12)
);
uniform float keep_share = 0.3;
// Broadcast treatment: 1 = everyone a dark rim-lit shape (the mixed option's back rows).
uniform float silhouette : hint_range(0.0, 1.0) = 0.0;
uniform vec3 silhouette_color : source_color = vec3(0.012, 0.014, 0.02);

varying vec3 v_col;
varying vec3 v_raw;
varying float v_zone;
uniform int debug_view = 0;
varying float v_spill;
varying float v_haze;
varying float v_rim_up;

float hash11(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

vec3 vat_pos(float col, float frame) {
	float y = person_row + frame * 2.0 + 0.5;
	vec3 q = texelFetch(vat, ivec2(int(col), int(y)), 0).rgb;
	return pos_min + q * (pos_max - pos_min);
}

vec3 vat_nrm(float col, float frame) {
	float y = person_row + frame * 2.0 + 1.5;
	return texelFetch(vat, ivec2(int(col), int(y)), 0).rgb * 2.0 - 1.0;
}

// Frame pair + mix for time `t` seconds into a clip. loop: wrap; else clamp.
vec3 clip_frames(vec2 clip, float t, bool loop) {
	float f = t * fps;
	if (loop) {
		f = mod(f, clip.y);
		float f0 = floor(f);
		float f1 = mod(f0 + 1.0, clip.y);
		return vec3(clip.x + f0, clip.x + f1, fract(f));
	}
	f = clamp(f, 0.0, clip.y - 1.0);
	float f0 = floor(f);
	return vec3(clip.x + f0, clip.x + min(f0 + 1.0, clip.y - 1.0), fract(f));
}

// An action: `in` clip, then the `loop` clip for `hold` seconds, then `in` backwards.
// Returns frame pair + mix in xyz, and its weight over the idle in w.
vec4 action(vec2 in_clip, vec2 loop_clip, float lt, float hold) {
	float d_in = (in_clip.y - 1.0) / fps;
	float per = loop_clip.y / fps;
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
	float col = floor(UV.x);
	float zone = floor(UV.y * 8.0 + 0.5);
	float phase = INSTANCE_CUSTOM.x;
	float excit = INSTANCE_CUSTOM.y;
	float rate = INSTANCE_CUSTOM.z;
	float seed = INSTANCE_CUSTOM.w;
	vec3 origin = MODEL_MATRIX[3].xyz;

	// Idle: always playing, own phase and rate.
	float ti = TIME * rate + phase * 40.0;
	vec3 fi = clip_frames(clip_idle, ti, true);
	vec3 p = mix(vat_pos(col, fi.x), vat_pos(col, fi.y), fi.z);
	vec3 n = mix(vat_nrm(col, fi.x), vat_nrm(col, fi.y), fi.z);

	// 1. The ripple from the last big moment: the keen ones raise their arms, the rest clap.
	float lt = react_age - distance(origin.xz, react_pos.xz) / ripple_speed
		- phase * 0.35 - (1.0 - excit) * 0.25;
	float keen = react_strength * (0.4 + 0.6 * excit);
	vec4 a = vec4(0.0);
	if (hash11(seed * 91.7 + 3.1) < keen) {
		a = action(clip_raise, clip_cheer, lt, 1.0 + 2.2 * react_strength * excit);
	} else if (hash11(seed * 53.3 + 7.7) < 0.35 + 0.5 * react_strength) {
		a = action(clip_clap_in, clip_clap, lt - 0.2, 1.2 + 1.8 * excit);
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
			a = action(clip_raise, clip_cheer, in_slot, 1.5 + 2.0 * e);
		} else if (r < 0.06 + e) {
			a = action(clip_clap_in, clip_clap, in_slot, 1.5 + 2.5 * e);
		}
	}
	// 3. A flinch (the arena biting) beats everything.
	float fl = flinch_age - phase * 0.2;
	if (fl > 0.0 && fl < 2.0 && hash11(seed * 17.9) < 0.3 + 0.5 * excit) {
		a = action(clip_flinch, vec2(clip_flinch.x + clip_flinch.y - 1.0, 1.0), fl, 0.5);
	}
	if (a.w > 0.0) {
		vec3 pa = mix(vat_pos(col, a.x), vat_pos(col, a.y), a.z);
		vec3 na = mix(vat_nrm(col, a.x), vat_nrm(col, a.y), a.z);
		p = mix(p, pa, a.w);
		n = mix(n, na, a.w);
	}

	// Heads and shoulders follow the fight: a twist about the spine that grows up the body.
	// Local frame of this person (the basis carries a non-uniform scale: normalise).
	vec3 to_f = focus_pos - origin;
	float lx = dot(to_f, normalize(MODEL_MATRIX[0].xyz));
	float lz = dot(to_f, normalize(MODEL_MATRIX[2].xyz));
	float look = clamp(atan(lx, lz), -1.0, 1.0) * look_share;
	look += sin(TIME * 0.31 * rate + seed * 50.0) * 0.14;
	float ang = look * (0.3 * smoothstep(0.95, 1.5, p.y) + 0.7 * smoothstep(1.42, 1.62, p.y));
	float c = cos(ang);
	float s = sin(ang);
	p.xz = vec2(c * p.x + s * p.z, -s * p.x + c * p.z);
	n.xz = vec2(c * n.x + s * n.z, -s * n.x + c * n.z);

	VERTEX = p;
	NORMAL = normalize(n);

	// Colour: the baked albedo, clothes re-tinted per instance.
	vec3 alb = pow(COLOR.rgb, vec3(2.2));
	v_raw = alb;
	v_zone = zone;
	float lum = dot(alb, vec3(0.299, 0.587, 0.114));
	float rc = hash11(seed * 7.77) < keep_share ? 0.0 : recolour;
	vec3 top = PALETTE[int(hash11(seed * 3.3) * 11.99)];
	vec3 acc = PALETTE[int(hash11(seed * 5.9) * 11.99)];
	float grey = max(lum, 0.02) / 0.08;
	if (zone > 0.5 && zone < 1.5) {
		alb = mix(alb, top * clamp(grey, 0.3, 2.0), rc);
	} else if (zone > 1.5 && zone < 2.5) {
		alb *= 0.6 + 0.8 * hash11(seed * 2.2);
	} else if ((zone > 2.5 && zone < 3.5) || zone > 5.5) {
		alb = mix(alb, acc * clamp(grey, 0.3, 2.0), rc);
	}
	v_col = alb;
	float beyond = max(abs(origin.x), abs(origin.z)) - arena_half;
	v_spill = (1.0 - smoothstep(0.0, spill_depth, beyond)) * (1.0 - smoothstep(0.0, spill_height, origin.y));
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	v_haze = smoothstep(haze_near, haze_far, length(cam - origin)) * haze_max;
	v_rim_up = smoothstep(1.2, 1.7, p.y);
}

void fragment() {
	vec3 body = v_col;
	float lum = dot(body, vec3(0.299, 0.587, 0.114));
	body = max(mix(vec3(lum), body, saturation), vec3(0.0));
	body = mix(body, vec3(lum), desat_far * v_haze);
	vec3 alb = mix(body * body_light * person_light, silhouette_color, silhouette);
	ALBEDO = mix(alb, haze_color, v_haze);
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	// Rim from behind and above: grazing view angle, strongest on heads and shoulders.
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 up_v = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	float top = clamp(dot(NORMAL, up_v) * 0.6 + 0.5, 0.0, 1.0);
	float rim = fres * top * (0.4 + 0.6 * v_rim_up) * (1.0 - v_haze * 0.6);
	vec3 spill = body * spill_color * spill_strength * v_spill * (1.0 - silhouette * 0.85);
	EMISSION = spill + rim_color * rim * rim_strength * (0.5 + 0.5 * (1.0 - v_spill));
	if (debug_view == 1) { ALBEDO = vec3(0.0); EMISSION = v_raw; }
	if (debug_view == 2) { ALBEDO = vec3(0.0); EMISSION = vec3(abs(v_zone - 1.0) < 0.1 ? 1.0 : 0.0, abs(v_zone - 2.0) < 0.1 ? 1.0 : 0.0, v_zone > 2.5 ? v_zone / 6.0 : 0.0); }
	if (debug_view == 3) { ALBEDO = vec3(0.0); EMISSION = NORMAL * 0.5 + 0.5; }
	if (debug_view == 4) { ALBEDO = vec3(0.0); EMISSION = vec3(rim, float(FRONT_FACING), 0.0); }
}
