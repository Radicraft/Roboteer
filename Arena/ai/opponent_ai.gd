extends RefCounted
class_name OpponentAI
## A bot driver (docs/stage3-spec.md §9). Produces one BotInput dictionary per physics
## tick from the shared RandomNumberGenerator.
##
## fight.gd builds one of these for the opponent always, and a second one for the player
## bot when `debug.player_ai` is set (QA now, the async ladder's ghost builds later).
##
## Deterministic by construction:
##   1. It draws from the rng at a FIXED cadence (once every JITTER_TICKS ticks, always,
##      in every mode) before any branching, so no decision can change how many numbers it
##      consumes.
##   2. It reads only positions, velocities and the bots' public API, never the clock,
##      never Engine.get_frames_drawn, never a second rng.
##
## Frame conventions it assumes about the Bot API (see docs/stage3-rules-notes.md):
##   - `bot.chassis` is a Node3D-or-better whose `global_position` is the bot position.
##   - The bot's nose points along **+X** of `bot.chassis.global_transform.basis`. That is
##     not Godot's usual forward, it is the convention `Bot._drive` and `Bot.place_at`
##     actually use (`fwd = chassis.global_basis.x`), and the AI has to agree with the
##     drive or its aim is ninety degrees out.
##   - An input heading of Vector2(x, y) asks for world direction Vector3(x, 0, y).
##     heading_from_world_dir() is the single place that mapping lives.

const MODE_NORMAL := "normal"
const MODE_IDLE := "idle"
const MODE_CHARGE := "charge"
## Not a behaviour: "off" means no driver at all. `debug.player_ai` defaults to it, and
## fight.gd builds no OpponentAI for a bot whose driver is off.
const MODE_OFF := "off"

# --- the fight, at arm's length ------------------------------------------------------
## Ring the bot holds while it looks for an angle. Far enough out to turn freely, close
## enough to dart in before the opponent can square up.
const STANDOFF_M := 1.4
const STANDOFF_BAND_M := 0.35       # how sloppily the ring is held while circling
## An approach angle is good when the bot is more than this far off the opponent's nose.
## 50 degrees puts it on a front corner at worst, and on the side or rear at best.
const GOOD_ANGLE_DEG := 50.0
## Once committed to a dart, keep going until this angle is lost, so it does not dither
## on the way in.
const ABANDON_ANGLE_DEG := 78.0
const ABANDON_RANGE_M := 2.2

# --- the strike ----------------------------------------------------------------------
## Chassis centre to chassis centre reach. The bots are 0.9 m long, so 0.9 is nose on
## nose; the slack lets the flipper start its sweep as the wedge bites rather than after.
##
## This is deliberately NOT the old "front edge within 0.45 m of their chassis" test.
## That test inverts in a clinch: at 0.3 m apart the front edge is already PAST the
## opponent's centre, the vector from edge to chassis points backwards, and the facing
## check fails exactly when the bots are locked together. Measured: 2322 ticks inside 1 m
## over 45 seconds and not one shot fired.
const STRIKE_REACH_M := 0.9
const STRIKE_SLACK_M := 0.2
const STRIKE_ANGLE_DEG := 45.0
const CHARGE_FIRE_RANGE_M := 0.9
## After firing, give ground so a whole tank of gas is not dumped into one clinch.
const BACKOFF_M := 0.6
const BACKOFF_MAX_TICKS := 45       # 0.75 s, a hard stop in case the retreat is blocked
const FIRE_COOLDOWN_TICKS := 48     # 0.8 s, just over FightTypes.FLIPPER_COOLDOWN_S

# --- housekeeping --------------------------------------------------------------------
const FRONT_EDGE_M := 0.45          # nose offset from the chassis centre
const JITTER_TICKS := 30            # 0.5 s at 60 Hz
const JITTER_MAX := 0.15
const RECOVER_STILL_SPEED := 0.35   # m/s: "nearly still" before pressing the srimech
const RECOVER_RETRY_TICKS := 90
const RECOVER_GIVE_UP_PRESSES := 2
const REVERSE_TICKS := 45
const SPIKE_AVOID_LEAD_S := 1.0
const SPIKE_AVOID_RANGE_M := 1.2

# --- weapon kinds (docs/stage4-spec.md §6) -------------------------------------------
## `WeaponBase.kind`, straight out of the catalogue. Everything the AI does differently
## per weapon is in PROFILES and nowhere else, so a new weapon needs one row, not a branch.
##   standoff    ring radius it holds while it looks for an angle, metres
##   engage      fire range as a multiple of the weapon's own reach, plus ENGAGE_SLACK_M
##   flank       needs a side or rear angle before it commits, or charges straight in
##   spin_up     will not engage below READY_ENGAGE readiness, disengages below READY_DROP
##   hold        the weapon wants to be held on (saws, flame, spinners) rather than tapped
##   latch       stays in the clinch instead of giving ground after a hit
##   orbit       circles at the standoff while engaged, rather than closing
const PROFILES := {
	"flipper": {"standoff": 1.15, "engage": 1.0, "flank": true, "spin_up": false,
		"hold": false, "latch": false, "orbit": false},
	"lifter": {"standoff": 1.05, "engage": 1.0, "flank": true, "spin_up": false,
		"hold": true, "latch": true, "orbit": false},
	"drum": {"standoff": 1.4, "engage": 1.0, "flank": true, "spin_up": true,
		"hold": true, "latch": false, "orbit": false},
	"spinner": {"standoff": 1.7, "engage": 1.1, "flank": true, "spin_up": true,
		"hold": true, "latch": false, "orbit": false},
	"fbs": {"standoff": 1.3, "engage": 1.2, "flank": false, "spin_up": true,
		"hold": true, "latch": false, "orbit": true},
	"saw": {"standoff": 1.0, "engage": 0.9, "flank": false, "spin_up": true,
		"hold": true, "latch": true, "orbit": false},
	"crusher": {"standoff": 1.0, "engage": 0.9, "flank": false, "spin_up": false,
		"hold": true, "latch": true, "orbit": false},
	"axe": {"standoff": 1.1, "engage": 0.7, "flank": false, "spin_up": false,
		"hold": false, "latch": false, "orbit": false},
	"ram": {"standoff": 0.0, "engage": 0.0, "flank": false, "spin_up": false,
		"hold": false, "latch": true, "orbit": false},
	"flame": {"standoff": 0.0, "engage": 1.0, "flank": false, "spin_up": false,
		"hold": true, "latch": false, "orbit": true},
}
const DEFAULT_KIND := "flipper"
const DEFAULT_REACH := 0.45         # the Stage 3 flipper
## Fire range is the weapon's reach times the profile's engage, plus this, measured
## chassis centre to chassis centre. The bots are 0.9 m long, so a 0.45 m reach weapon
## still has to fire from about a metre out.
const ENGAGE_SLACK_M := 0.65
const READY_ENGAGE := 0.85          # spun up enough to be worth closing with
const READY_DROP := 0.45            # spun down enough to be worth backing off to re-spin
## A weapon with no reach of its own (a ram) fights at contact.
const CONTACT_M := 0.95
## Circle for at most this long before going in anyway.
##
## The flank gate is a preference, not a requirement. Against an opponent that keeps its
## nose on you (a faster bot, or another AI doing the same thing) the angle may simply
## never come good, and a bot that waits forever for a perfect entry never fights at all:
## measured at 202 ticks of 2900 spent inside 1 m. Two seconds of looking, then commit.
const COMMIT_AFTER_TICKS := 120

var mode: String = MODE_NORMAL

var _rng: RandomNumberGenerator = null
var _jitter: Vector2 = Vector2.ZERO
var _fire_ready_tick: int = 0
var _failed_flips: int = 0
var _secondary_ready_tick: int = 0
var _reverse_until_tick: int = -1
var _was_inverted: bool = false
## +1 or -1: which way round the opponent this bot is working. Held until the other side
## is clearly better, so it does not oscillate across the opponent's nose.
var _flank_sign: int = 1
var _darting: bool = false
var _backoff_until_tick: int = -1
var _backoff_from_range: float = 0.0
## The tick circling started, or -1 when it is not circling.
var _circling_since_tick: int = -1


func _init(rng: RandomNumberGenerator, ai_mode: String = MODE_NORMAL) -> void:
	_rng = rng
	mode = ai_mode if ai_mode in [MODE_NORMAL, MODE_IDLE, MODE_CHARGE] else MODE_NORMAL


## Map a world direction to the stick heading both bots consume.
static func heading_from_world_dir(direction: Vector3) -> Vector2:
	var flat := Vector2(direction.x, direction.z)
	if flat.length() < 0.0001:
		return Vector2.ZERO
	return flat.normalized()


## One tick of thought.
##   me, foe: Bot instances (or duck-typed fakes exposing chassis / is_inverted()).
##   ctx: {"tick": int, "spike_rise_in_s": float, "spike_centre": Vector3}
func think(me: Object, foe: Object, ctx: Dictionary) -> Dictionary:
	var tick := int(ctx.get("tick", 0))

	# The rng is drawn at a fixed cadence in EVERY mode, before any branching, so the
	# number of draws over a fight depends only on the tick count.
	if tick % JITTER_TICKS == 0:
		_jitter = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * JITTER_MAX

	if me == null or foe == null or mode == MODE_IDLE:
		return FightTypes.empty_input()

	var my_position := _position(me)
	var foe_position := _position(foe)
	var forward := _flat(_forward(me))

	if mode == MODE_CHARGE:
		return _charge(my_position, foe_position, forward, tick)

	# --- recover: inverted bots do nothing else until they are back on their wheels
	var inverted := _is_inverted(me)
	if not inverted:
		_failed_flips = 0
		_reverse_until_tick = -1
	elif not _was_inverted:
		_failed_flips = 0
	_was_inverted = inverted
	if inverted:
		_darting = false
		return _recover(me, forward, tick)

	var to_foe := _flat(foe_position - my_position)
	var range_m := to_foe.length()
	var to_foe_dir := to_foe.normalized() if range_m > 0.0001 else forward

	var profile := _profile(me)
	var reach := _weapon_reach(me)
	var ready := _weapon_readiness(me)
	var engage_m := maxf(reach * float(profile["engage"]) + ENGAGE_SLACK_M, CONTACT_M) \
		if float(profile["engage"]) > 0.0 else CONTACT_M
	var standoff := float(profile["standoff"])
	if standoff <= 0.0:
		# A flame keeps its own reach; a ram has no standoff at all and just charges.
		standoff = maxf(reach * 0.9, CONTACT_M) if float(profile["engage"]) > 0.0 else 0.0

	# --- avoid: the spike patch is about to rise and we are standing on top of it
	var spike_centre: Vector3 = ctx.get("spike_centre", Vector3.ZERO)
	var spike_rise_in_s := float(ctx.get("spike_rise_in_s", 999.0))
	var from_spikes := _flat(my_position - spike_centre)
	if spike_rise_in_s <= SPIKE_AVOID_LEAD_S and from_spikes.length() <= SPIKE_AVOID_RANGE_M:
		_darting = false
		var away := from_spikes if from_spikes.length() > 0.0001 else forward
		return _input(_jittered(heading_from_world_dir(away)), false, false)

	# --- strike, decided before the movement so it can fire on the way in
	var fire := _should_fire(me, profile, range_m, engage_m, ready, to_foe_dir, forward, tick)
	if fire and not bool(profile["hold"]):
		# A one shot weapon taps and gives ground; a held one stays on the target.
		_fire_ready_tick = tick + FIRE_COOLDOWN_TICKS
		if not bool(profile["latch"]):
			_backoff_until_tick = tick + BACKOFF_MAX_TICKS
			_backoff_from_range = range_m
			_darting = false

	# --- disengage to re-spin: a spun down bar is a handle, not a weapon
	if bool(profile["spin_up"]) and ready < READY_DROP and range_m < standoff:
		_darting = false
		return _input(_jittered(heading_from_world_dir(-to_foe_dir)), fire, false)

	# --- back off: give ground after a shot rather than grinding the gas away
	if tick < _backoff_until_tick:
		if range_m >= _backoff_from_range + BACKOFF_M:
			_backoff_until_tick = -1
		else:
			return _input(_jittered(heading_from_world_dir(-to_foe_dir)), fire, false)

	return _input(_jittered(_manoeuvre(my_position, foe_position, _flat(_forward(foe)),
		range_m, to_foe_dir, profile, standoff, engage_m, ready, tick)), fire, false)


# ---------------------------------------------------------------- movement

## Hold the ring, circle to a side or rear angle, then dart in, and a commitment flag so
## the dart is not re-decided every tick on the way in.
##
## The profile changes three things and nothing else: whether an angle is required before
## committing (`flank`), whether the bot orbits at the ring instead of closing (`orbit`,
## the full body spinner and the flame), and whether it waits to be spun up (`spin_up`).
func _manoeuvre(my_position: Vector3, foe_position: Vector3, foe_forward: Vector3,
		range_m: float, to_foe_dir: Vector3, profile: Dictionary, standoff: float,
		engage_m: float, ready: float, tick: int) -> Vector2:
	var bearing := _flat(my_position - foe_position)
	var bearing_dir := bearing.normalized() if bearing.length() > 0.0001 else -to_foe_dir
	# 1.0 = dead in front of them, -1.0 = dead behind them.
	var exposure := foe_forward.dot(bearing_dir) if foe_forward.length() > 0.0001 else -1.0
	var angle_ok := (not bool(profile["flank"])) or exposure <= cos(deg_to_rad(GOOD_ANGLE_DEG))
	var spun_ok := (not bool(profile["spin_up"])) or ready >= READY_ENGAGE

	# A latching weapon that is already on the target simply stays there.
	if bool(profile["latch"]) and range_m <= engage_m:
		_circling_since_tick = -1
		return heading_from_world_dir(to_foe_dir)

	if _darting:
		if range_m > ABANDON_RANGE_M or (bool(profile["flank"]) \
				and exposure > cos(deg_to_rad(ABANDON_ANGLE_DEG))):
			_darting = false
		else:
			_circling_since_tick = -1
			return heading_from_world_dir(to_foe_dir)

	# Orbiters (full body spinner, flame) never close past their working distance: their
	# weapon reaches out, so closing only gives the opponent a wedge under them.
	if bool(profile["orbit"]) and range_m <= standoff + STANDOFF_BAND_M:
		return _circle(bearing_dir, to_foe_dir, range_m, standoff)

	if standoff <= 0.0:
		# A ram has no ring: it lines up and charges.
		_circling_since_tick = -1
		return heading_from_world_dir(to_foe_dir)

	if range_m > standoff + STANDOFF_BAND_M:
		_circling_since_tick = -1
		var target := foe_position + _flank_direction(foe_forward, bearing_dir) * standoff
		return heading_from_world_dir(_flat(target - my_position))

	# Out of patience: a flank is worth waiting two seconds for and no longer. Spinning up
	# is not negotiable, though, because a cold bar is a handle.
	if _circling_since_tick >= 0 and tick - _circling_since_tick >= COMMIT_AFTER_TICKS:
		angle_ok = true

	if angle_ok and spun_ok:
		_darting = true
		_circling_since_tick = -1
		return heading_from_world_dir(to_foe_dir)

	if _circling_since_tick < 0:
		_circling_since_tick = tick
	return _circle(bearing_dir, to_foe_dir, range_m, standoff)


## Drive along the ring toward the chosen flank, correcting the radius as it goes.
func _circle(bearing_dir: Vector3, to_foe_dir: Vector3, range_m: float, standoff: float) -> Vector2:
	var tangent := bearing_dir.cross(Vector3.UP) * float(_flank_sign)
	var radius_error := range_m - standoff
	var correction := to_foe_dir * clampf(radius_error, -0.6, 0.6)
	return heading_from_world_dir(tangent + correction)


## Which side of the opponent to work, as a world direction from their chassis. The sign
## is held until the other side is clearly better, so the bot commits to a lap instead of
## flip-flopping across the opponent's nose.
func _flank_direction(foe_forward: Vector3, bearing_dir: Vector3) -> Vector3:
	if foe_forward.length() < 0.0001:
		return bearing_dir
	var right := foe_forward.cross(Vector3.UP).normalized()
	var side := 1 if bearing_dir.dot(right) >= 0.0 else -1
	# Only change sides when we are well past the midline, never on a knife edge.
	if side != _flank_sign and absf(bearing_dir.dot(right)) > 0.35:
		_flank_sign = side
	# Aim a little behind the opponent's shoulder: that is the angle worth having.
	return (right * float(_flank_sign) * 0.8 - foe_forward * 0.6).normalized()


# ---------------------------------------------------------------- the strike

## Fire when the opponent's chassis is inside this weapon's engage range and inside the
## nose cone, or when the Bot says the opponent is already sitting on our wedge.
##
## This is deliberately NOT the Stage 3 "front edge within 0.45 m of their chassis" test.
## That test inverts in a clinch: at 0.3 m apart the front edge is already PAST the
## opponent's centre, the vector from edge to chassis points backwards, and the facing
## check fails exactly when the bots are locked together. Measured: 2322 ticks inside 1 m
## over 45 seconds and not one shot fired.
func _should_fire(me: Object, profile: Dictionary, range_m: float, engage_m: float,
		ready: float, to_foe_dir: Vector3, forward: Vector3, tick: int) -> bool:
	if float(profile["engage"]) <= 0.0:
		return false            # a ram has nothing to fire
	if not _weapon_ready(me, tick, profile):
		return false

	# A weapon that spins up only gains readiness WHILE IT IS HELD, so holding it is not a
	# decision about the opponent at all: it is what makes it a weapon. Gating the press on
	# readiness is a deadlock, and it was one (agent W1, 2026-09-13): `ready` never rose,
	# so the bar never spun, so a spinner in AI hands removed nothing while the same weapon
	# held down by a test took 0.81 condition off in four seconds. Spinners, drums, the
	# full body spinner and the saw now spin from the bell and keep spinning.
	#
	# READY_ENGAGE and READY_DROP still gate the MOVEMENT (see _manoeuvre and the
	# disengage in think): a cold bar is a handle, so the bot does not close with one, and
	# backs off to re-spin if it drops. They must never gate the press.
	if bool(profile["hold"]) and bool(profile["spin_up"]):
		return true

	if me.has_method("opponent_on_wedge") and bool(me.call("opponent_on_wedge")):
		return true
	if range_m > engage_m:
		return false
	if forward.length() < 0.0001:
		return false
	return forward.dot(to_foe_dir) >= cos(deg_to_rad(STRIKE_ANGLE_DEG))


func _weapon_ready(me: Object, tick: int, profile: Dictionary) -> bool:
	# A held weapon has no tap cooldown: the cooldown exists so a flipper does not empty
	# its gas into one clinch, and a saw has nothing to empty.
	if not bool(profile["hold"]) and tick < _fire_ready_tick:
		return false
	var gas: Variant = me.get("gas_charges")
	if gas != null and int(gas) <= 0:
		return false
	if me.has_method("flipper_ready"):
		return bool(me.call("flipper_ready"))
	if me.has_method("weapon_jammed") and bool(me.call("weapon_jammed")):
		return false
	return true


# ---------------------------------------------------------------- other modes

func _charge(my_position: Vector3, foe_position: Vector3, forward: Vector3, tick: int) -> Dictionary:
	var to_foe := _flat(foe_position - my_position)
	var fire := false
	if tick >= _fire_ready_tick and to_foe.length() <= CHARGE_FIRE_RANGE_M:
		fire = true
		_fire_ready_tick = tick + FIRE_COOLDOWN_TICKS
	var direction := to_foe if to_foe.length() > 0.0001 else forward
	return _input(heading_from_world_dir(direction), fire, false)


func _recover(me: Object, forward: Vector3, tick: int) -> Dictionary:
	# After two failed srimech presses, drive in reverse to rock off whatever is holding us.
	if tick < _reverse_until_tick:
		return _input(heading_from_world_dir(-forward), false, false)
	if _failed_flips >= RECOVER_GIVE_UP_PRESSES:
		_reverse_until_tick = tick + REVERSE_TICKS
		_failed_flips = 0
		return _input(heading_from_world_dir(-forward), false, false)
	# Press the srimech only once the bot is nearly still: firing mid tumble wastes it.
	if _speed(me) <= RECOVER_STILL_SPEED and tick >= _secondary_ready_tick:
		_secondary_ready_tick = tick + RECOVER_RETRY_TICKS
		_failed_flips += 1
		return _input(Vector2.ZERO, false, true)
	return FightTypes.empty_input()


# ---------------------------------------------------------------- helpers

static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _jittered(heading: Vector2) -> Vector2:
	if heading.length() < 0.0001:
		return heading
	var out := heading + _jitter
	if out.length() > 1.0:
		out = out.normalized()
	return out


func _input(heading: Vector2, fire: bool, secondary: bool) -> Dictionary:
	return {"heading": heading, "fire": fire, "secondary": secondary}


func _position(bot: Object) -> Vector3:
	var chassis: Object = bot.get("chassis")
	if chassis == null:
		return Vector3.ZERO
	return (chassis as Node3D).global_position


## The nose direction. `Bot._drive` steers by `chassis.global_basis.x`, so that is the
## nose, and `Bot.place_at` yaws the same way. Measured 2026-09-13: a bot placed facing
## +X has basis.x = (1,0,0) and -basis.z = (0,0,-1).
func _forward(bot: Object) -> Vector3:
	var chassis: Object = bot.get("chassis")
	if chassis == null:
		return Vector3.RIGHT
	return (chassis as Node3D).global_transform.basis.x.normalized()


func _speed(bot: Object) -> float:
	var chassis: Object = bot.get("chassis")
	if chassis is RigidBody3D:
		return (chassis as RigidBody3D).linear_velocity.length()
	return 0.0


# --- what weapon is this? -------------------------------------------------------------
## Everything here is duck typed through `has_method` / `get`, with the Stage 3 flipper as
## the fallback, so the AI works against P2's Bot before and after `weapon_readiness()`
## lands and against W1/W2's weapons before and after they do.

func _profile(bot: Object) -> Dictionary:
	var kind := _weapon_kind(bot)
	return PROFILES.get(kind, PROFILES[DEFAULT_KIND]) as Dictionary


func _weapon_kind(bot: Object) -> String:
	if bot.has_method("weapon_kind"):
		return str(bot.call("weapon_kind"))
	var weapon: Variant = bot.get("weapon")
	if weapon is Object and (weapon as Object).get("kind") != null:
		var kind := str((weapon as Object).get("kind"))
		if kind != "":
			return kind
	return DEFAULT_KIND


func _weapon_reach(bot: Object) -> float:
	for method in ["weapon_reach", "reach"]:
		if bot.has_method(method):
			var value := float(bot.call(method))
			if value > 0.0:
				return value
	var weapon: Variant = bot.get("weapon")
	if weapon is Object and (weapon as Object).has_method("reach"):
		var value := float((weapon as Object).call("reach"))
		if value > 0.0:
			return value
	return DEFAULT_REACH


## 0 to 1. A weapon with no idea of readiness is always ready, which is the Stage 3
## flipper's behaviour and the right default for anything that does not spin up.
func _weapon_readiness(bot: Object) -> float:
	if bot.has_method("weapon_readiness"):
		return clampf(float(bot.call("weapon_readiness")), 0.0, 1.0)
	var weapon: Variant = bot.get("weapon")
	if weapon is Object and (weapon as Object).has_method("readiness"):
		return clampf(float((weapon as Object).call("readiness")), 0.0, 1.0)
	return 1.0


func _is_inverted(bot: Object) -> bool:
	if bot.has_method("is_inverted"):
		return bool(bot.call("is_inverted"))
	return false
