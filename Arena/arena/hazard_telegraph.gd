class_name HazardTelegraph extends Node3D
## Wave A: ONE hazard warning language for every hazard in every arena
## (docs/wave-a-hazards-notes.md, owner decision 2026-09-24).
##
## The arena builds one of these as its child "HazardTelegraph". Every frame it reads
## the arena's `hazard_schedule()` (read-only: seconds to each hazard's next activation,
## derived from the same tick clock the hazard runs on) and paints the same four stages
## on every hazard, whatever it is:
##
##   IDLE     a dim amber outline on the floor round the hazard's footprint. You can
##            always see where the danger is.
##   ARMED    (only the Crush and the Drop Zone, whose own warnings were already longer:
##            2 s and 3 s) a slow 2 Hz amber pulse, fill empty.
##   WARNING  the last WARN_LEAD_S (1.25 s) before it acts, identical everywhere: the
##            outline pulses from 3 Hz up to 10 Hz, amber goes to red, hazard stripes
##            light inside the footprint and a wash fills it from the edge inward so it
##            is full on the frame the hazard acts. A light over the zone pulses with it,
##            the hazard's own lamps (nozzle bezel, spike bezel, ram lamp, pit strip) run
##            the same rhythm, and the hazard's OWN wind-up sound starts (spikes charge,
##            gas igniter, hydraulic whine, klaxon). The rhythm is shared; the sound and
##            the props are each arena's.
##   ACTIVE   solid red, a flash, and the hit: camera kick scaled by hazard, a haptic if
##            the player's machine is close enough for it to be theirs.
##   AFTER    fades back to IDLE over 0.5 s.
##
## Always-on hazards (grinders, turntables) have no clock, so they speak the same
## colours by PROXIMITY instead: the ring warms and pulses faster as any machine closes
## in, and goes red on contact.
##
## DETERMINISM. Everything here runs in `_process` on the presentation clock, reads the
## arena and the bots, and writes only to its own meshes, lights and materials and to the
## FX node's audio, shake and haptics. It never touches a physics body, never calls the
## fight's RNG and adds no collision. `hazard_determinism_test.gd` proves it: the six
## arenas hash bit-identical to the pre-wave-A goldens with this on, and the Coliseum
## hashes the same with it off.

## Switch for the determinism proof (and for anyone bisecting a visual problem). A
## telegraph built while this is false does nothing at all and hides itself.
static var enabled := true

const COL_IDLE := Color(0.95, 0.56, 0.10)
const COL_WARN := Color(1.0, 0.50, 0.06)
const COL_HOT := Color(1.0, 0.10, 0.04)
const IDLE_INTENSITY := 0.16
const ARMED_HZ := 2.0
const WARN_HZ_FAR := 3.0
const WARN_HZ_NEAR := 10.0
const FLASH_S := 0.18
const AFTER_S := 0.5
## Proximity band for the always-on hazards, metres beyond the footprint's edge.
const NEAR_M := 1.2
## The player's machine within this of a hazard's footprint edge feels it in the hand.
const HAPTIC_NEAR_M := 1.5
const DECAL_Y := 0.009
const LIGHT_HEIGHT := 0.9
const LIGHT_ENERGY := 2.4

const SHADER_CODE := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 colour = vec3(1.0, 0.55, 0.1);
uniform float intensity = 0.2;
uniform float fill = 0.0;
uniform float stripes = 0.0;
uniform float stripe_phase = 0.0;
// 0 rect (half_size = half extents), 1 disc (half_size.x = radius),
// 2 ring (half_size.x = outer radius, half_size.y = inner radius).
uniform float shape = 0.0;
uniform vec2 half_size = vec2(1.0, 1.0);

varying vec2 local_xz;

void vertex() {
	local_xz = VERTEX.xz;
}

void fragment() {
	vec2 p = local_xz;
	float d;
	float depth;
	if (shape < 0.5) {
		vec2 q = half_size - abs(p);
		d = min(q.x, q.y);
		depth = min(half_size.x, half_size.y);
	} else if (shape < 1.5) {
		d = half_size.x - length(p);
		depth = half_size.x;
	} else {
		float r = length(p);
		d = min(half_size.x - r, r - half_size.y);
		depth = (half_size.x - half_size.y) * 0.5;
	}
	// A crisp lit edge just inside the footprint, a soft glow spilling out of it.
	float edge = exp(-abs(d - 0.045) / 0.03);
	float glow = d < 0.0 ? exp(d / 0.10) * 0.45 : 0.0;
	float inside = step(0.0, d);
	// Hazard stripes, diagonal, marching toward the edge.
	float band = step(0.5, fract((p.x + p.y) / 0.36 + stripe_phase));
	float s = inside * band * stripes * 0.30;
	// The wash fills from the edge inward and is full when fill reaches 1.
	float wash = inside * step(d, fill * depth + 0.001) * fill * 0.32;
	ALBEDO = colour * intensity * (edge + glow + s + wash);
}
"""

static var _shader: Shader = null

var _arena: Node = null
var _t := 0.0
## id -> {"mesh", "mat", "phase", "was_active", "since", "light"}
var _views: Dictionary = {}
## group -> OmniLight3D
var _lights: Dictionary = {}
## group -> true once its wind-up has played this cycle
var _armed: Dictionary = {}
## group -> true while active (so a strike fires once per group per activation)
var _striking: Dictionary = {}
var _built := false


func _ready() -> void:
	_arena = get_parent()
	if not enabled:
		visible = false
		set_process(false)
		return
	# One frame late on purpose: the arena's _ready has built its hazards by then and
	# fight.gd has put the world round it, so the bots and the FX node can be found.
	set_process(true)


func _process(delta: float) -> void:
	if not enabled or _arena == null or not is_instance_valid(_arena):
		return
	if not _arena.has_method("hazard_schedule"):
		return
	_t += delta
	var schedule: Array = _arena.call("hazard_schedule")
	if not _built:
		_build_views(schedule)
		_built = true
	var group_level: Dictionary = {}
	var group_pos: Dictionary = {}
	var group_warned: Dictionary = {}
	for entry_variant in schedule:
		var e: Dictionary = entry_variant
		var id := str(e["id"])
		if not _views.has(id):
			_views[id] = _make_view(e)
		var v: Dictionary = _views[id]
		var look := _stage(e, v, delta)
		_paint(v, e, look)
		var group := str(e.get("group", id))
		if bool(e.get("always_on", false)):
			_strike_on_edge(e, group, bool(e.get("contact", false)))
			continue
		group_level[group] = maxf(float(group_level.get(group, 0.0)), float(look["light"]))
		group_pos[group] = e.get("light_at", e["position"])
		_strike_on_edge(e, group, bool(e["active"]))
		# The wind-up: once per group, the frame the clock crosses the lead.
		var in_s := float(e["in_s"])
		if bool(e["active"]) or in_s > ArenaBase.WARN_LEAD_S:
			_armed[group] = false
		elif not bool(_armed.get(group, false)) and not group_warned.has(group):
			_armed[group] = true
			group_warned[group] = true
			_fx_call("on_hazard_warning", [str(e["kind"]), e.get("sound_at", e["position"])])
	for group in group_level.keys():
		var light := _light_for(str(group), group_pos[group])
		var level: float = group_level[group]
		light.visible = level > 0.02
		light.light_energy = LIGHT_ENERGY * level
		light.light_color = COL_WARN.lerp(COL_HOT, clampf(level, 0.0, 1.0))


# ---------------------------------------------------------------------------
# The four stages
# ---------------------------------------------------------------------------
## Returns {"colour", "intensity", "fill", "stripes", "lamp", "light"} for this frame.
func _stage(e: Dictionary, v: Dictionary, delta: float) -> Dictionary:
	var active := bool(e["active"])
	var in_s := float(e["in_s"])
	var warn_s := float(e.get("warn_s", ArenaBase.WARN_LEAD_S))
	var lead := ArenaBase.WARN_LEAD_S
	if active != bool(v["was_active"]):
		v["was_active"] = active
		v["since"] = 0.0
	v["since"] = float(v["since"]) + delta
	var since := float(v["since"])

	if bool(e.get("always_on", false)):
		return _proximity_stage(e, v, delta)

	if active:
		var flash := 1.0 - clampf(since / FLASH_S, 0.0, 1.0)
		return {"colour": COL_HOT, "intensity": 1.1 + 1.4 * flash, "fill": 1.0,
			"stripes": 1.0, "lamp": 1.0, "light": 0.75 + 0.25 * flash}

	# Just finished: fade back to idle.
	if since < AFTER_S and float(v.get("ever_active", 0.0)) > 0.0:
		var k := 1.0 - since / AFTER_S
		return {"colour": COL_HOT.lerp(COL_IDLE, 1.0 - k), "intensity":
			lerpf(IDLE_INTENSITY, 1.1, k), "fill": k, "stripes": k, "lamp": k * 0.6,
			"light": k * 0.5}

	if in_s <= warn_s and in_s > 0.0:
		var hz := ARMED_HZ
		var p := 1.0
		if in_s <= lead:
			p = in_s / lead                               # 1 at the lead, 0 at the hit
			hz = lerpf(WARN_HZ_NEAR, WARN_HZ_FAR, p)
		v["phase"] = fmod(float(v["phase"]) + hz * delta, 1.0)
		var pulse := 0.5 + 0.5 * cos(TAU * float(v["phase"]))
		var heat := 1.0 - p
		var level := lerpf(0.35, 1.0, heat) * (0.35 + 0.65 * pulse)
		return {"colour": COL_WARN.lerp(COL_HOT, heat), "intensity": lerpf(0.6, 1.5, heat)
			* (0.6 + 0.4 * pulse), "fill": heat, "stripes": heat, "lamp": level,
			"light": level if in_s <= lead else level * 0.5}

	return {"colour": COL_IDLE, "intensity": IDLE_INTENSITY, "fill": 0.0, "stripes": 0.0,
		"lamp": 0.08, "light": 0.0}


## Grinders and turntables: the nearest machine is the clock.
func _proximity_stage(e: Dictionary, v: Dictionary, delta: float) -> Dictionary:
	var harmless := str(e["kind"]) == "turntable"
	var contact := bool(e.get("contact", false))
	var gap := _nearest_bot_gap(e)
	var near := 1.0 - clampf(gap / NEAR_M, 0.0, 1.0)
	if harmless:
		# Turntables do no damage; they only get the idle outline and a slow chase.
		v["phase"] = fmod(float(v["phase"]) + 0.6 * delta, 1.0)
		return {"colour": COL_IDLE, "intensity": IDLE_INTENSITY * 1.4, "fill": 0.0,
			"stripes": 0.0, "lamp": 0.25 + 0.15 * sin(TAU * float(v["phase"])), "light": 0.0}
	if contact:
		v["phase"] = fmod(float(v["phase"]) + WARN_HZ_NEAR * delta, 1.0)
		var pulse := 0.5 + 0.5 * cos(TAU * float(v["phase"]))
		return {"colour": COL_HOT, "intensity": 1.2 + 0.5 * pulse, "fill": 1.0,
			"stripes": 1.0, "lamp": 1.0, "light": 0.0}
	var hz := lerpf(ARMED_HZ, WARN_HZ_NEAR, near)
	v["phase"] = fmod(float(v["phase"]) + hz * delta, 1.0)
	var pulse := 0.5 + 0.5 * cos(TAU * float(v["phase"]))
	var base := lerpf(0.30, 1.2, near)
	return {"colour": COL_IDLE.lerp(COL_HOT, near * 0.8),
		"intensity": base * lerpf(1.0, 0.45 + 0.55 * pulse, near), "fill": near * 0.6,
		"stripes": near, "lamp": 0.3 + 0.7 * near, "light": 0.0}


func _paint(v: Dictionary, e: Dictionary, look: Dictionary) -> void:
	if bool(e["active"]) or bool(e.get("contact", false)):
		v["ever_active"] = 1.0
	var mat := v["mat"] as ShaderMaterial
	var colour: Color = look["colour"]
	if mat != null:
		mat.set_shader_parameter("colour", Vector3(colour.r, colour.g, colour.b))
		mat.set_shader_parameter("intensity", float(look["intensity"]))
		mat.set_shader_parameter("fill", float(look["fill"]))
		mat.set_shader_parameter("stripes", float(look["stripes"]))
		mat.set_shader_parameter("stripe_phase", fmod(_t * 0.8, 1.0))
	# The hazard's own lamps run the same rhythm in the same colours.
	var lamp_level := float(look["lamp"])
	for lamp_variant in e.get("lamps", []):
		var lamp := lamp_variant as StandardMaterial3D
		if lamp == null:
			continue
		lamp.emission = colour
		lamp.emission_energy_multiplier = 0.25 + 3.5 * lamp_level


# ---------------------------------------------------------------------------
# The hit: camera and hand, once per group per activation
# ---------------------------------------------------------------------------
func _strike_on_edge(e: Dictionary, group: String, on: bool) -> void:
	var was := bool(_striking.get(group, false))
	if on == was:
		return
	_striking[group] = on
	if not on:
		return
	var near := _player_gap(e) <= HAPTIC_NEAR_M
	_fx_call("on_hazard_strike", [str(e["kind"]), e["position"], near])


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
func _build_views(schedule: Array) -> void:
	for entry_variant in schedule:
		var e: Dictionary = entry_variant
		var id := str(e["id"])
		if not _views.has(id):
			_views[id] = _make_view(e)


func _make_view(e: Dictionary) -> Dictionary:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	var shape := str(e.get("shape", "rect"))
	var size: Vector2 = e.get("size", Vector2.ONE)
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	var half := size * 0.5
	var shape_id := 0.0
	match shape:
		"disc":
			shape_id = 1.0
			half = Vector2(size.x * 0.5, 0.0)
		"ring":
			shape_id = 2.0
			half = Vector2(size.x * 0.5, size.y * 0.5)       # outer, inner radius
	mat.set_shader_parameter("shape", shape_id)
	mat.set_shader_parameter("half_size", half)
	mat.set_shader_parameter("intensity", IDLE_INTENSITY)
	var plane := PlaneMesh.new()
	var extent := Vector2(size.x, size.x) if shape != "rect" else size
	# Room for the outer glow.
	plane.size = extent + Vector2(0.5, 0.5)
	var mi := MeshInstance3D.new()
	mi.name = "Warn_" + str(e["id"])
	mi.mesh = plane
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pos: Vector3 = e["position"]
	mi.position = Vector3(pos.x, float(e.get("decal_y", DECAL_Y)), pos.z)
	mi.rotation = Vector3(0.0, float(e.get("yaw", 0.0)), 0.0)
	add_child(mi)
	return {"mesh": mi, "mat": mat, "phase": 0.0, "was_active": false, "since": 99.0,
		"ever_active": 0.0}


func _light_for(group: String, at: Vector3) -> OmniLight3D:
	if _lights.has(group):
		return _lights[group]
	var light := OmniLight3D.new()
	light.name = "WarnLight_" + group
	light.shadow_enabled = false
	light.omni_range = 3.2
	light.omni_attenuation = 1.4
	light.light_color = COL_WARN
	light.light_energy = 0.0
	light.visible = false
	light.position = Vector3(at.x, LIGHT_HEIGHT, at.z)
	add_child(light)
	_lights[group] = light
	return light


# ---------------------------------------------------------------------------
# What is round us: read-only
# ---------------------------------------------------------------------------
func _fx_call(method: String, args: Array) -> void:
	var world := _arena.get_parent() if _arena != null else null
	if world == null:
		return
	var fx := world.get_node_or_null("FX")
	if fx != null and fx.has_method(method):
		fx.callv(method, args)


func _bots() -> Array:
	var world := _arena.get_parent() if _arena != null else null
	if world == null:
		return []
	var holder := world.get_node_or_null("Bots")
	return holder.get_children() if holder != null else []


func _chassis_of(bot: Node) -> Node3D:
	if bot == null or not is_instance_valid(bot):
		return null
	var chassis: Variant = bot.get("chassis")
	if chassis is Node3D and is_instance_valid(chassis) and (chassis as Node3D).is_inside_tree():
		return chassis as Node3D
	return null


## Distance from a point to the footprint's edge (0 inside it).
func _gap_to(e: Dictionary, at: Vector3) -> float:
	var pos: Vector3 = e["position"]
	var size: Vector2 = e.get("size", Vector2.ONE)
	var d := Vector2(at.x - pos.x, at.z - pos.z)
	if str(e.get("shape", "rect")) == "rect":
		var yaw := float(e.get("yaw", 0.0))
		d = d.rotated(yaw)
		var q := Vector2(absf(d.x), absf(d.y)) - size * 0.5
		return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()
	return maxf(d.length() - size.x * 0.5, 0.0)


func _nearest_bot_gap(e: Dictionary) -> float:
	var best := 999.0
	for bot in _bots():
		var chassis := _chassis_of(bot)
		if chassis != null:
			best = minf(best, _gap_to(e, chassis.global_position))
	return best


func _player_gap(e: Dictionary) -> float:
	for bot in _bots():
		if int(bot.get("team")) != 0:
			continue
		var chassis := _chassis_of(bot)
		if chassis != null:
			return _gap_to(e, chassis.global_position)
	return 999.0
