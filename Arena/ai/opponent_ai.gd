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
##   - The bot's nose points along -Z of `bot.chassis.global_transform.basis`.
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

	# --- avoid: the spike patch is about to rise and we are standing on top of it
	var spike_centre: Vector3 = ctx.get("spike_centre", Vector3.ZERO)
	var spike_rise_in_s := float(ctx.get("spike_rise_in_s", 999.0))
	var from_spikes := _flat(my_position - spike_centre)
	if spike_rise_in_s <= SPIKE_AVOID_LEAD_S and from_spikes.length() <= SPIKE_AVOID_RANGE_M:
		_darting = false
		var away := from_spikes if from_spikes.length() > 0.0001 else forward
		return _input(_jittered(heading_from_world_dir(away)), false, false)

	# --- strike, decided before the movement so it can fire on the way in
	var fire := _should_fire(me, foe, range_m, to_foe_dir, forward, tick)
	if fire:
		_fire_ready_tick = tick + FIRE_COOLDOWN_TICKS
		_backoff_until_tick = tick + BACKOFF_MAX_TICKS
		_backoff_from_range = range_m
		_darting = false

	# --- back off: give ground after a shot rather than grinding the gas away
	if tick < _backoff_until_tick:
		if range_m >= _backoff_from_range + BACKOFF_M:
			_backoff_until_tick = -1
		else:
			return _input(_jittered(heading_from_world_dir(-to_foe_dir)), fire, false)

	return _input(_jittered(_manoeuvre(my_position, foe_position, _flat(_forward(foe)),
		range_m, to_foe_dir)), fire, false)


# ---------------------------------------------------------------- movement

## Hold the ring, circle to a side or rear angle, then dart in. Three plain rules, and
## a commitment flag so the dart is not re-decided every tick on the way in.
func _manoeuvre(my_position: Vector3, foe_position: Vector3, foe_forward: Vector3,
		range_m: float, to_foe_dir: Vector3) -> Vector2:
	var bearing := _flat(my_position - foe_position)
	var bearing_dir := bearing.normalized() if bearing.length() > 0.0001 else -to_foe_dir
	# 1.0 = dead in front of them, -1.0 = dead behind them.
	var exposure := foe_forward.dot(bearing_dir) if foe_forward.length() > 0.0001 else -1.0
	var good := exposure <= cos(deg_to_rad(GOOD_ANGLE_DEG))

	if _darting:
		if range_m > ABANDON_RANGE_M or exposure > cos(deg_to_rad(ABANDON_ANGLE_DEG)):
			_darting = false
		else:
			return heading_from_world_dir(to_foe_dir)

	if range_m > STANDOFF_M + STANDOFF_BAND_M:
		# Close on the ring, aiming at the flank we have chosen rather than at their nose.
		var target := foe_position + _flank_direction(foe_forward, bearing_dir) * STANDOFF_M
		return heading_from_world_dir(_flat(target - my_position))

	if good:
		_darting = true
		return heading_from_world_dir(to_foe_dir)

	# Circle: drive along the ring toward the flank, correcting the radius as we go.
	var tangent := bearing_dir.cross(Vector3.UP) * float(_flank_sign)
	var radius_error := range_m - STANDOFF_M
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

## Fire when the opponent's chassis is inside reach and inside the nose cone, or when the
## Bot says it is sitting on our wedge. `opponent_on_wedge()` and `flipper_ready()` are
## agent P's; both are optional and fall back to geometry and a local cooldown.
func _should_fire(me: Object, foe: Object, range_m: float, to_foe_dir: Vector3,
		forward: Vector3, tick: int) -> bool:
	if not _weapon_ready(me, tick):
		return false
	if me.has_method("opponent_on_wedge") and bool(me.call("opponent_on_wedge")):
		return true
	if range_m > STRIKE_REACH_M + STRIKE_SLACK_M:
		return false
	if forward.length() < 0.0001:
		return false
	return forward.dot(to_foe_dir) >= cos(deg_to_rad(STRIKE_ANGLE_DEG))


func _weapon_ready(me: Object, tick: int) -> bool:
	if tick < _fire_ready_tick:
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


func _forward(bot: Object) -> Vector3:
	var chassis: Object = bot.get("chassis")
	if chassis == null:
		return Vector3.FORWARD
	return -(chassis as Node3D).global_transform.basis.z.normalized()


func _speed(bot: Object) -> float:
	var chassis: Object = bot.get("chassis")
	if chassis is RigidBody3D:
		return (chassis as RigidBody3D).linear_velocity.length()
	return 0.0


func _is_inverted(bot: Object) -> bool:
	if bot.has_method("is_inverted"):
		return bool(bot.call("is_inverted"))
	return false
