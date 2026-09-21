class_name MachineAudio extends Node
## What every machine on the floor SOUNDS like while it moves (wave F, agent F2).
##
## The owner played the wave G build on his iPhone and said: "I can't hear the crowd
## properly, there are no movement noises". The second half was literally true. The FX
## layer has had `FightFx.set_motor_state()` since Stage 3 and **nothing has ever called
## it**: grep the repo and the only callers are `fx_test.gd`. So two machines have been
## driving around a steel shed in silence for six stages.
##
## This node is the fix, and it is deliberately not a call the orchestrator has to
## remember to make. It finds the machines itself and reads their drive state every
## presentation frame, so it cannot fall out of the wiring again.
##
## FIVE SOUNDS PER MACHINE, each from a different physical cause:
##
##   whine   the motor and gearbox, pitched and levelled by throttle and road speed
##   roll    the surface: rubber on steel, track links, or an omni's rollers
##   skid    scrub, when the machine is going somewhere its wheels are not pointing
##   scrape  the chassis dragging on the boards (or on its back)
##   thud    a one shot when it lands after a flip or a throw
##
## HARD RULE (spec §7): this is presentation. It only ever READS the bots — velocities,
## the last input, the drive's catalogue numbers — and it runs in `_process`, outside the
## physics tick. Delete the FX subtree and the fight's result JSON is identical. Nothing
## here draws from the fight's rng; the pitch jitter comes from `AudioMix.jitter()`.
##
##     var machines := MachineAudio.new()
##     add_child(machines)
##     machines.bind(audio_mix)          # then nothing: it finds the bots itself
##
## WHAT A MACHINE HAS TO LOOK LIKE. Everything is read defensively, so a test double
## works and a half-built bot cannot crash the mixer:
##
##     bot_id        String
##     chassis       RigidBody3D (linear_velocity, angular_velocity, global_basis,
##                   global_position, get_colliding_bodies())
##     drive_module  id: String, top_speed(), turn_rate(), track_half(), power_scale()
##     is_inverted() bool
##     _last_input   Dictionary, optional: {"heading": Vector2, "turn": float}

## Where the bots live in the fight world (`Arena/fight/fight_world.tscn`). Looked up
## from this node's own FX parent, so nothing has to hand them over.
const BOTS_HOLDER := "Bots"

## Per drive, from Arena/data/parts.json. The five drives really do sound different and
## the difference is not a filter setting: a 2WD is a fast, light, high-revving thing, a
## six wheeler is geared down and heavy, TRACKS ARE A CLATTER (their roll is an impulse
## train at the link rate, not a tyre), and an omni is a patter of little hard rollers
## that buzzes when it strafes.
##
##   whine_pitch  pitch at a standstill -> pitch at top speed
##   whine_db     relative dB at a standstill -> relative dB at full effort
##   roll         the SOUNDS name for this drive's contact with the floor
##   roll_pitch   pitch at a crawl -> pitch at top speed
##   roll_db      relative dB at a crawl -> relative dB at top speed
##   skid_gain    how readily this drive breaks traction, from its catalogue `traction`
##   scrape_db    relative dB of a chassis drag, at speed
const DRIVES := {
	# Light, fast, only two driven wheels: revs high, breaks traction easily.
	"2wd": {
		"whine_pitch": [1.10, 2.00], "whine_db": [-20.0, 0.0],
		"roll": "roll_wheel_loop", "roll_pitch": [0.85, 1.60], "roll_db": [-26.0, 0.0],
		"skid_gain": 1.25, "scrape_db": -2.0,
	},
	# The default. Everything above is measured against this one.
	"4wd": {
		"whine_pitch": [1.00, 1.80], "whine_db": [-20.0, 0.0],
		"roll": "roll_wheel_loop", "roll_pitch": [0.80, 1.45], "roll_db": [-26.0, 0.0],
		"skid_gain": 1.00, "scrape_db": 0.0,
	},
	# Geared down and heavy: lower, louder, and it does not let go of the floor.
	"6wd": {
		"whine_pitch": [0.88, 1.52], "whine_db": [-18.0, 1.5],
		"roll": "roll_wheel_loop", "roll_pitch": [0.72, 1.25], "roll_db": [-24.0, 2.0],
		"skid_gain": 0.80, "scrape_db": 1.0,
	},
	# Tracks. The lowest whine in the game and the loudest contact: every link slaps.
	"tracks": {
		"whine_pitch": [0.80, 1.34], "whine_db": [-18.0, 0.0],
		"roll": "track_clatter_loop", "roll_pitch": [0.70, 1.30], "roll_db": [-20.0, 3.0],
		# Skid steering IS scrubbing: a tracked machine turning is grinding two belts
		# across the floor, and traction 1.8 means it never breaks away sideways.
		"skid_gain": 0.70, "scrape_db": 1.5,
	},
	# WAVE P (agent F), the three rows docs/wave-p-d2-notes.md section 6 asked for.
	# All three fell back to the 4WD row, which meant a walker that sounded like a car.
	#
	# Two optional keys arrive with them, both read with a default so every row above
	# is untouched: `whine` names the motor loop (these machines do not all have an
	# electric motor), and `whine_throttle` is how much of the whine's PITCH is the
	# throttle rather than the road speed.
	#
	# HYDRAULIC LEGS. There is no motor and there is no roll: the pump runs at its own
	# speed whatever the machine is doing (so the pitch span is nearly flat), and the
	# contact with the floor is a FOOTFALL, which is a one shot at the stride rate and
	# is played by `fx/weapon_fx.gd`, not a loop. An empty `roll` name is a sound
	# AudioMix does not have, which it answers with silence and no voice at all.
	"legs": {
		"whine": "leg_servo_loop",
		"whine_pitch": [0.72, 1.20], "whine_db": [-16.0, 0.0],
		"roll": "", "roll_pitch": [1.0, 1.0], "roll_db": [-60.0, -60.0],
		# Planted. A walker at traction 1.6 does not lose the back end; what it does
		# instead is pivot, and the pivot floor in `_skid_amount` still reaches it.
		"skid_gain": 0.55, "scrape_db": 1.5,
	},
	# HOVER. The one drive whose whine is not the road speed: a fan answers the
	# THROTTLE, more or less instantly, and a hover sliding sideways at 4 m/s with the
	# stick centred is nearly silent, which is exactly right. The skirt is its contact
	# with the floor and the only contact sound in the game with no impulses in it.
	"hover": {
		"whine": "hover_fan_loop",
		"whine_pitch": [0.95, 2.00], "whine_db": [-17.0, 0.5],
		"whine_throttle": 0.85,
		"roll": "hover_skirt_loop", "roll_pitch": [0.90, 1.35], "roll_db": [-22.0, 0.0],
		# Traction 0.35, the lowest in the catalogue: it drifts through everything.
		"skid_gain": 1.45, "scrape_db": -3.0,
	},
	# ADAPTIVE TRACKS. A segmented belt on a compliant carrier: more than twice the
	# link rate of the plain track and every slap smaller, which is the audible half
	# of "track grip with a 4WD's steering and nothing to tear off".
	"adaptive_tracks": {
		"whine_pitch": [0.84, 1.42], "whine_db": [-18.0, 0.0],
		"roll": "adaptive_track_loop", "roll_pitch": [0.75, 1.40], "roll_db": [-21.0, 2.0],
		"skid_gain": 0.75, "scrape_db": 1.2,
	},
	# Omni: high, busy and dry, and the only drive whose sideways motion is not a skid.
	"omni": {
		"whine_pitch": [1.25, 2.10], "whine_db": [-20.0, -1.0],
		"roll": "roll_omni_loop", "roll_pitch": [0.95, 1.70], "roll_db": [-26.0, 0.0],
		"skid_gain": 0.85, "scrape_db": -1.0,
	},
}
const DRIVE_DEFAULT := "4wd"

## How many machines get a movement layer at all. A Rumble is three; the fourth slot is
## there so an enforcer or a house bot cannot silently push a player's machine out of the
## mix. Past this, the machines already sounding keep their voices.
const MAX_MACHINES := 4
## Skid and scrape voices across the WHOLE arena. Three machines can all be sliding at
## once and three skids on top of each other is not three times the information; the
## quietest one is refused a voice rather than stealing somebody else's.
const MAX_TRANSIENT_LOOPS := 4

## How fast a level follows what the machine is doing, in "fraction closed per second".
## The whine is slower than the contact sounds because a motor has inertia and a tyre
## does not; a skid has to arrive almost instantly or it lands after the slide.
const SMOOTH_WHINE := 7.0
## How much of the whine's PITCH is the throttle rather than the road speed. Wheels spin
## up when they lose the floor, so it is not zero; a machine shoving another one at full
## throttle and half a metre a second has to bog down, so it is not one either.
const WHINE_FROM_THROTTLE := 0.45
const SMOOTH_ROLL := 10.0
const SMOOTH_SKID_UP := 22.0
const SMOOTH_SKID_DOWN := 7.0

## A loop that has been silent this long is freed, so a fight that never skids again is
## not carrying four dead voices.
const TRANSIENT_OFF := 0.06         # level below which a transient counts as silent
const TRANSIENT_HOLD_S := 0.45

## THE SKID. Two independent causes, and the loudest one wins:
##
## 1. SLIP the machine is actually doing: the sideways component of its velocity (a
##    wheel cannot move sideways, so any of it is scrub) plus the scrub the two sides
##    must do to yaw at all, which is the yaw rate times half the track width.
## 2. SLIP the driver is ASKING FOR: the heading is that far off the nose, at that much
##    throttle. This is "the heading changes faster than the drive can follow" — it
##    fires on the frame the stick goes over, before the physics has caught up.
## MEASURED, not guessed (Arena/tests/_f2_movement_probe.gd, flipper vs flipper, 25 s).
## The first build floored at 0.55 m/s and the skid was audible on 60 % of frames,
## because skid steering is ALWAYS scrubbing a little: a 4WD cannot change direction
## without it. At 0.90 the loop is what it is meant to be, the moment the machine loses
## the back end, and an ordinary turn is under it.
const SKID_FLOOR_MS := 0.90         # m/s of scrub below which nothing is happening
const SKID_SPAN_MS := 2.10          # m/s of scrub that is a full skid
const SKID_SCRUB_GAIN := 1.0        # yaw scrub, as a fraction of yaw_rate * track_half
const SKID_DEMAND_FLOOR := 0.35     # commanded heading error, as a fraction of 90 deg
const SKID_PITCH := [0.90, 1.12]    # pitch across the skid's range

## A pivot on the spot is a skid by definition: both sides are scrubbing and the machine
## is going nowhere. It is floored here so a spin always makes the noise a spin makes.
const SPIN_YAW_RATE := 1.6          # rad/s of yaw with no translation
const SPIN_SKID_FLOOR := 0.45

## THE SCRAPE. A chassis touching arena geometry is a wall or the floor: the hull sits
## `clearance_front` (0.04 m) above the deck when the machine is level, so it only ever
## touches the boards, or the floor when the machine is on its back or dragging a wedge
## lip. All three are a steel drag and all three want the same sound; only the level
## differs, by how fast it is going.
## WALL, OR THE FLOOR, AND WHY IT HAS TO BE TOLD APART. The first build called any
## chassis contact with arena geometry a scrape, on the reasoning that the hull rides
## `clearance_front` (0.04 m) above the deck. Measured in a real fight, that ran the
## scrape on 55 % of frames at near full level: a wedge is SUPPOSED to drag its front
## lip along the floor, and a pyramid and a long-low do too. A constant grind is worse
## than no grind.
##
## Arenas are built by `ArenaBase`, which puts floor slabs at y = -FLOOR_THICKNESS/2
## (below zero) and every wall at y = wall_height / 2 (well above it). So a colliding
## body whose own origin is above the wheels is upright geometry — a wall, a pillar, a
## house bot's cage — and anything at or under the deck is the floor.
##
## The floor is still a scrape in the one case where it should be: on its back, where
## the whole hull is dragging rather than a designed lip.
const WALL_MIN_Y := 0.15
const SCRAPE_MIN_MS := 0.35
const SCRAPE_SPAN_MS := 2.40
const SCRAPE_INVERTED_DB := 2.0     # on its back it is the whole hull, not an edge
const SCRAPE_PITCH := [0.88, 1.10]

## THE LANDING. Airborne means no wheel is touching and the hull is clear of the deck.
## A machine has to have been off the floor for this long before landing is an event:
## below it, a wheel bouncing over a seam would fire a thud every second.
const AIR_MIN_S := 0.20
const AIR_CLEARANCE_M := 0.055
## Falling this fast at the moment of contact is the quietest landing worth a sound, and
## this fast is a full one. A flipper throw arrives at about 4 m/s.
const LAND_MIN_MS := 1.40
const LAND_FULL_MS := 4.50
const LAND_DB := [-11.0, 0.0]
const LAND_PITCH := [1.10, 0.90]    # a harder landing is a LOWER, bigger sound
const LAND_COOLDOWN_S := 0.35

## Nothing sounds for this long after a machine is first seen. Bots are placed a few
## centimetres above the deck and settle onto it, and a thud on the countdown is a bug
## the player would read as the fight having already started.
const SETTLE_S := 1.20

## How often the world is re-scanned for machines, in seconds. A fight spawns its bots
## once and an enforcer arrives later, so this only has to be faster than a player can
## notice; it is not a per frame walk of the tree.
const RESCAN_S := 0.50

var _mix: AudioMix = null
var _machines: Array = []                  ## the bots, found or bound
var _bound := false                        ## true when bind_bots() was used explicitly
var _state: Dictionary = {}                ## bot_id -> the per machine bookkeeping
var _now: float = 0.0
var _next_scan: float = -1.0
var _enabled := true


## `mix` is the audio director. Without one this node does nothing at all, which is the
## correct behaviour for a scene that has no FX subtree.
func bind(mix: AudioMix) -> void:
	_mix = mix


## Hand the machines over explicitly instead of letting this node find them. The test
## uses it; the game does not need to.
func bind_bots(bots: Array) -> void:
	_machines = bots.duplicate()
	_bound = true


func set_enabled(on: bool) -> void:
	if _enabled == on:
		return
	_enabled = on
	if not on:
		stop_all()


## `FightFx` drives this node from its own `_process`, and this node deliberately has no
## `_process` of its own: two clocks would step it twice a frame, which would halve every
## smoothing constant in here and double the skid's attack. It also means the whole
## movement layer honours `FightFx.fixed_delta_override`, so a headless test can simulate
## four seconds in 240 frames exactly as the rest of the FX tree does.
func _ready() -> void:
	set_process(false)


## One presentation frame.
func step(delta: float) -> void:
	if _mix == null or not _enabled or delta <= 0.0:
		return
	_now += delta
	if not _bound and _now >= _next_scan:
		_next_scan = _now + RESCAN_S
		_scan()
	_drop_dead()
	var live := 0
	for machine in _machines:
		if live >= MAX_MACHINES:
			break
		# A machine can be FREED between two scans — eliminated, or the world torn down —
		# and `_machines` is only rebuilt every RESCAN_S. A freed object cannot even be
		# PASSED to a typed parameter (GDScript checks the argument's class before the
		# body runs, so a guard inside `_step_machine` is too late and throws "the
		# Object-derived class of argument 1 (previously freed)"), so the check has to
		# happen here, at the call site.
		if machine == null or not is_instance_valid(machine):
			continue
		if _step_machine(machine, delta):
			live += 1


## Silence and free everything this node owns. `FightFx.stop_all_audio()` calls it.
func stop_all() -> void:
	if _mix != null:
		for id in _state.keys():
			_stop_machine(str(id))
	_state.clear()
	if not _bound:
		_machines.clear()
	_next_scan = -1.0


# ---------------------------------------------------------------- introspection

## Every loop key this node currently owns, for the test and for tuning.
func loop_keys() -> Array:
	var out: Array = []
	for id in _state.keys():
		var st: Dictionary = _state[id]
		for role in ["whine", "roll", "skid", "scrape"]:
			if bool(st.get(role + "_on", false)):
				out.append(_key(str(id), role))
	return out


func machine_count() -> int:
	return _machines.size()


## The last frame's readings for one machine: throttle, speed_norm, skid, scrape, air.
## The test asserts against this rather than against how it sounds.
func state_of(bot_id: String) -> Dictionary:
	return (_state.get(bot_id, {}) as Dictionary).duplicate()


# ---------------------------------------------------------------- finding them

## Walk the fight world for machines. `MachineAudio` is a child of `FightFx`, which
## `fight.gd` swaps into the World under the name "FX", and the bots live beside it under
## "Bots" — so the lookup is two `get_parent()`s and a name, with a full walk as the
## fallback for any scene that arranges itself differently (the test arena does).
func _scan() -> void:
	var found: Array = []
	var fx := get_parent()
	var world: Node = fx.get_parent() if fx != null else null
	if world != null:
		var holder := world.get_node_or_null(BOTS_HOLDER)
		if holder != null:
			for child in holder.get_children():
				if _is_machine(child):
					found.append(child)
		if found.is_empty():
			_collect(world, found, 0)
	_machines = found


func _collect(node: Node, out: Array, depth: int) -> void:
	if depth > 3 or out.size() >= MAX_MACHINES:
		return
	for child in node.get_children():
		if _is_machine(child):
			out.append(child)
		else:
			_collect(child, out, depth + 1)


static func _is_machine(node: Variant) -> bool:
	if node == null or not is_instance_valid(node) or not (node is Node):
		return false
	# Duck typed on purpose: the test's double is not a `Bot` and must still work.
	return node.get("chassis") is RigidBody3D and node.get("drive_module") != null


## A machine that has gone (eliminated, or the world torn down) takes its voices with it.
func _drop_dead() -> void:
	for id in _state.keys():
		var st: Dictionary = _state[id]
		# Variant, not Object: ASSIGNING a freed instance to a typed variable throws
		# "Trying to assign invalid previously freed instance" before `is_instance_valid`
		# ever gets a chance to answer.
		var machine: Variant = st.get("bot", null)
		if machine == null or not is_instance_valid(machine) \
				or not (machine as Node).is_inside_tree():
			_stop_machine(str(id))
			_state.erase(id)


# ---------------------------------------------------------------- one machine

## Returns true when this machine got a movement layer this frame.
func _step_machine(machine: Variant, delta: float) -> bool:
	if machine == null or not is_instance_valid(machine):
		return false
	var chassis: RigidBody3D = machine.get("chassis") as RigidBody3D
	if chassis == null or not chassis.is_inside_tree():
		return false
	var bot_id := str(machine.get("bot_id"))
	if bot_id.is_empty():
		bot_id = (machine as Node).name
	var st: Dictionary = _state.get(bot_id, {})
	if st.is_empty():
		st = _new_state(machine)
		_state[bot_id] = st
	st["bot"] = machine
	st["age"] = float(st.get("age", 0.0)) + delta

	var drive: Variant = machine.get("drive_module")
	var tuning: Dictionary = DRIVES.get(_drive_id(drive), DRIVES[DRIVE_DEFAULT])
	var at := chassis.global_position

	# --- what the machine is doing -------------------------------------------
	var v := chassis.linear_velocity
	var speed: float = Vector2(v.x, v.z).length()
	var top := maxf(_call_float(drive, "top_speed", 3.5), 0.5)
	var speed_norm := clampf(speed / top, 0.0, 1.4)
	var throttle := _throttle(machine)
	# A dead drive makes no noise: lose every wheel and the machine is a box on a floor.
	var power := clampf(_call_float(drive, "power_scale", 1.0), 0.0, 1.0)
	var frozen := bool(machine.get("_frozen")) if machine.get("_frozen") != null else false
	if frozen:
		throttle = 0.0
	var effort := clampf(maxf(throttle * power, speed_norm * 0.8), 0.0, 1.0)

	st["throttle"] = throttle
	st["speed"] = speed
	st["speed_norm"] = speed_norm
	st["effort"] = effort

	# --- the whine and the roll ----------------------------------------------
	#
	# PITCH AND LEVEL COME FROM DIFFERENT THINGS, which is the difference between a
	# machine and a sound effect. Pitch is the shaft turning, so it follows ROAD SPEED;
	# level is the current being drawn, so it follows THROTTLE. A machine flat out
	# against the boards is therefore loud and LOW — it bogs down, the way a real one
	# does — where a single throttle-driven parameter would have it screaming at full
	# revs while going nowhere. The throttle still gets a share of the pitch, because
	# wheels really do spin up when they let go of the floor.
	# Wave P: the share is per drive now, because a fan is not a gearbox. Every row
	# written before wave P leaves the key out and gets WHINE_FROM_THROTTLE exactly.
	var from_throttle := float(tuning.get("whine_throttle", WHINE_FROM_THROTTLE))
	var rev := clampf(from_throttle * throttle
		+ (1.0 - from_throttle) * clampf(speed_norm, 0.0, 1.0), 0.0, 1.0)
	var k_whine := clampf(delta * SMOOTH_WHINE, 0.0, 1.0)
	var whine_level: float = lerpf(float(st["whine_level"]), effort, k_whine)
	st["whine_level"] = whine_level
	var whine_rev: float = lerpf(float(st["whine_rev"]), rev, k_whine)
	st["whine_rev"] = whine_rev
	var roll_target := clampf(speed_norm, 0.0, 1.0) * (0.35 + 0.65 * power)
	var roll_level: float = lerpf(float(st["roll_level"]), roll_target,
		clampf(delta * SMOOTH_ROLL, 0.0, 1.0))
	st["roll_level"] = roll_level

	# Wave P: the motor loop is per drive (the walker has a hydraulic pack, the hover
	# has an impeller). Absent means the electric motor every wheeled drive has.
	_drive_loop(bot_id, st, "whine", str(tuning.get("whine", "drive_whine_loop")), at,
		_span(tuning["whine_pitch"], whine_rev), _span(tuning["whine_db"], whine_level))
	# A machine on its back is not rolling on anything; the roll gives way to the scrape.
	var inverted := bool(machine.call("is_inverted")) if machine.has_method("is_inverted") else false
	st["inverted"] = inverted
	var roll_db: float = _span(tuning["roll_db"], roll_level) + (-9.0 if inverted else 0.0)
	_drive_loop(bot_id, st, "roll", str(tuning["roll"]), at,
		_span(tuning["roll_pitch"], roll_level), roll_db)

	# --- the skid -------------------------------------------------------------
	var skid := _skid_amount(machine, chassis, drive, tuning, throttle, speed, v)
	st["skid_raw"] = skid
	var k_skid := clampf(delta * (SMOOTH_SKID_UP if skid > float(st["skid_level"])
		else SMOOTH_SKID_DOWN), 0.0, 1.0)
	var skid_level: float = lerpf(float(st["skid_level"]), skid * power, k_skid)
	st["skid_level"] = skid_level
	_transient(bot_id, st, "skid", "skid_loop", at, skid_level,
		_span(SKID_PITCH, skid_level), linear_to_db(maxf(skid_level, 0.0001)), delta)

	# --- the scrape -----------------------------------------------------------
	var scrape := _scrape_amount(chassis, speed, inverted)
	st["scrape_raw"] = scrape
	var scrape_level: float = lerpf(float(st["scrape_level"]), scrape,
		clampf(delta * SMOOTH_ROLL, 0.0, 1.0))
	st["scrape_level"] = scrape_level
	var scrape_db: float = float(tuning["scrape_db"]) \
		+ linear_to_db(maxf(scrape_level, 0.0001)) * 0.8 \
		+ (SCRAPE_INVERTED_DB if inverted else 0.0)
	_transient(bot_id, st, "scrape", "scrape_loop", at, scrape_level,
		_span(SCRAPE_PITCH, scrape_level), scrape_db, delta)

	# --- the landing ----------------------------------------------------------
	_step_landing(machine, chassis, st, at, delta)
	return true


func _new_state(machine: Variant) -> Dictionary:
	return {
		"bot": machine, "age": 0.0,
		"whine_level": 0.0, "whine_rev": 0.0,
		"roll_level": 0.0, "skid_level": 0.0, "scrape_level": 0.0,
		"whine_on": false, "roll_on": false, "skid_on": false, "scrape_on": false,
		"skid_quiet": 0.0, "scrape_quiet": 0.0,
		"airborne": false, "air_s": 0.0, "fall": 0.0, "land_at": -100.0,
	}


# ---------------------------------------------------------------- the readings

## Commanded effort, 0..1. `heading` is the stick and `turn` is the twin-stick scheme's
## pure pivot; a machine spinning on the spot is at full throttle and zero road speed,
## which is exactly the case a speed-derived throttle would call idle.
static func _throttle(machine: Variant) -> float:
	var last: Variant = machine.get("_last_input")
	if not (last is Dictionary):
		return 0.0
	var inp: Dictionary = last
	var heading: Variant = inp.get("heading", Vector2.ZERO)
	var h := 0.0
	if heading is Vector2:
		h = (heading as Vector2).length()
	var turn := absf(float(inp.get("turn", 0.0)))
	return clampf(maxf(h, turn), 0.0, 1.0)


## How hard this machine is scrubbing, 0..1. See SKID_FLOOR_MS for the two causes.
func _skid_amount(machine: Variant, chassis: RigidBody3D, drive: Variant,
		tuning: Dictionary, throttle: float, speed: float, v: Vector3) -> float:
	var gain := float(tuning["skid_gain"])

	# 1. The slip it is doing. Sideways velocity is scrub for every drive except the
	# omni, whose whole reason to exist is that its rollers go sideways on purpose.
	var side := chassis.global_basis.z
	side.y = 0.0
	side = side.normalized() if side.length_squared() > 1e-6 else Vector3.BACK
	var lateral := 0.0
	if not bool(_call_bool(drive, "strafes", false)):
		lateral = absf(v.dot(side))
	var yaw := absf(chassis.angular_velocity.y)
	var half := maxf(_call_float(drive, "track_half", 0.18), 0.05)
	var scrub := lateral + yaw * half * SKID_SCRUB_GAIN
	var measured := clampf((scrub - SKID_FLOOR_MS) / SKID_SPAN_MS, 0.0, 1.0)

	# 2. The slip it is being asked for: the stick that far off the nose, at that much
	# throttle. This fires on the frame the stick goes over, ahead of the physics.
	var demand := 0.0
	var last: Variant = machine.get("_last_input")
	if throttle > 0.05 and last is Dictionary:
		var heading: Variant = (last as Dictionary).get("heading", Vector2.ZERO)
		if heading is Vector2 and (heading as Vector2).length() > 0.05:
			var want := Vector3((heading as Vector2).x, 0.0, (heading as Vector2).y).normalized()
			var fwd := chassis.global_basis.x
			fwd.y = 0.0
			fwd = fwd.normalized() if fwd.length_squared() > 1e-6 else Vector3.RIGHT
			var err := absf(wrapf(atan2(-want.z, want.x) - atan2(-fwd.z, fwd.x), -PI, PI))
			# Past 135 degrees the drive reverses toward the stick instead of spinning
			# (DriveBase.REVERSE_ANGLE), so that is a manoeuvre and not a scrub.
			if err > DriveBase.REVERSE_ANGLE:
				err = PI - err
			var frac := clampf(err / (PI * 0.5), 0.0, 1.0)
			# Only the part of the error the machine is actually moving into counts:
			# turning on the spot from a standstill is a spin, handled below.
			demand = clampf((frac - SKID_DEMAND_FLOOR) / (1.0 - SKID_DEMAND_FLOOR), 0.0, 1.0) \
				* throttle * clampf(speed / 1.2, 0.25, 1.0)

	# 3. A pivot: yawing hard while going nowhere. Both sides are scrubbing.
	var spin := 0.0
	if yaw > SPIN_YAW_RATE and speed < 0.8:
		spin = SPIN_SKID_FLOOR * clampf(yaw / (SPIN_YAW_RATE * 2.0), 0.0, 1.0)

	return clampf(maxf(maxf(measured, demand), spin) * gain, 0.0, 1.0)


## How hard the hull is dragging on something that is not a machine, 0..1.
##
## The hull rides `clearance_front` (0.04 m) above the deck when the machine is level, so
## a chassis contact with arena geometry is the boards, a wedge lip on the floor, or the
## machine on its back. `get_colliding_bodies()` is read only and needs no space query:
## `Bot.register_part` already turns contact monitoring on for every body it owns.
static func _scrape_amount(chassis: RigidBody3D, speed: float, inverted: bool) -> float:
	if speed < SCRAPE_MIN_MS or not chassis.contact_monitor:
		return 0.0
	var touching := false
	for body in chassis.get_colliding_bodies():
		# Another machine's parts are an IMPACT, and the damage event already sounds
		# for those. Only arena geometry is a scrape.
		if body is BotPart:
			continue
		if not inverted and (body as Node3D).global_position.y < WALL_MIN_Y:
			continue                     # the floor, under a lip that is meant to touch it
		touching = true
		break
	if not touching:
		return 0.0
	return clampf((speed - SCRAPE_MIN_MS) / SCRAPE_SPAN_MS, 0.0, 1.0)


## The airborne edge and the thud. A flip, a throw off a flipper, a ramp: all the same
## fact, which is that nothing was touching the floor and then something was.
func _step_landing(machine: Variant, chassis: RigidBody3D, st: Dictionary,
		at: Vector3, delta: float) -> void:
	var clear := chassis.global_position.y > _ride_height(machine) + AIR_CLEARANCE_M
	var wheels_down := false
	if machine.has_method("wheel_contacts"):
		for touching in (machine.call("wheel_contacts") as Array):
			if bool(touching):
				wheels_down = true
				break
	var airborne: bool = clear and not wheels_down
	var was: bool = bool(st["airborne"])
	var fall: float = maxf(float(st["fall"]), -chassis.linear_velocity.y)

	if airborne:
		st["air_s"] = float(st["air_s"]) + delta
		st["fall"] = fall
		st["airborne"] = true
		return

	st["airborne"] = false
	var air: float = float(st["air_s"])
	st["air_s"] = 0.0
	st["fall"] = 0.0
	if not was or air < AIR_MIN_S:
		return
	if float(st["age"]) < SETTLE_S or _now - float(st["land_at"]) < LAND_COOLDOWN_S:
		return
	if fall < LAND_MIN_MS:
		return
	st["land_at"] = _now
	var hard := clampf((fall - LAND_MIN_MS) / (LAND_FULL_MS - LAND_MIN_MS), 0.0, 1.0)
	st["last_land"] = fall
	_mix.play("chassis_thud", at, _span(LAND_DB, hard),
		_span(LAND_PITCH, hard) + _mix.jitter(-0.03, 0.03))


static func _ride_height(machine: Variant) -> float:
	if machine.has_method("ride_height"):
		return maxf(float(machine.call("ride_height")), 0.02)
	return 0.11


# ---------------------------------------------------------------- the voices

## The always-on pair. The loop is started once and then only ever re-pointed, which is
## the whole reason going on and off the throttle makes no click (AudioMix.set_loop).
func _drive_loop(bot_id: String, st: Dictionary, role: String, sound: String,
		at: Vector3, pitch: float, db: float) -> void:
	var key := _key(bot_id, role)
	if not bool(st.get(role + "_on", false)):
		if _mix.start_loop(key, sound, at, db, pitch) == null:
			return
		st[role + "_on"] = true
		return
	_mix.set_loop(key, pitch, db, at)


## The on-demand pair. Started when there is something to hear, freed once it has been
## silent for TRANSIENT_HOLD_S, and refused a voice when the arena is already carrying
## MAX_TRANSIENT_LOOPS of them.
func _transient(bot_id: String, st: Dictionary, role: String, sound: String,
		at: Vector3, level: float, pitch: float, db: float, delta: float) -> void:
	var key := _key(bot_id, role)
	var on: bool = bool(st.get(role + "_on", false))
	if level > TRANSIENT_OFF:
		st[role + "_quiet"] = 0.0
		if not on:
			if _transient_count() >= MAX_TRANSIENT_LOOPS:
				return
			if _mix.start_loop(key, sound, at, db, pitch) == null:
				return
			st[role + "_on"] = true
			return
		_mix.set_loop(key, pitch, db, at)
		return
	if not on:
		return
	# Silent: hold the voice briefly (a skid that stutters must not restart, which is a
	# click per stutter), then let it go.
	st[role + "_quiet"] = float(st.get(role + "_quiet", 0.0)) + delta
	if float(st[role + "_quiet"]) < TRANSIENT_HOLD_S:
		_mix.set_loop(key, pitch, -60.0, at)
		return
	_mix.stop_loop(key)
	st[role + "_on"] = false


func _transient_count() -> int:
	var n := 0
	for id in _state.keys():
		var st: Dictionary = _state[id]
		if bool(st.get("skid_on", false)):
			n += 1
		if bool(st.get("scrape_on", false)):
			n += 1
	return n


func _stop_machine(bot_id: String) -> void:
	var st: Dictionary = _state.get(bot_id, {})
	for role in ["whine", "roll", "skid", "scrape"]:
		if bool(st.get(role + "_on", false)):
			_mix.stop_loop(_key(bot_id, role))
			st[role + "_on"] = false


static func _key(bot_id: String, role: String) -> String:
	return "machine:" + role + ":" + bot_id


# ---------------------------------------------------------------- small helpers

static func _span(pair: Variant, t: float) -> float:
	var a: Array = pair
	return lerpf(float(a[0]), float(a[1]), clampf(t, 0.0, 1.0))


static func _drive_id(drive: Variant) -> String:
	if drive == null:
		return DRIVE_DEFAULT
	var id := str(drive.get("id"))
	return id if DRIVES.has(id) else DRIVE_DEFAULT


## Everything about a machine is read through these two, so a bot that is half built, a
## drive with no wheels left or a test double cannot take the mixer down with it.
static func _call_float(obj: Variant, method: String, fallback: float) -> float:
	if obj == null or not is_instance_valid(obj) or not obj.has_method(method):
		return fallback
	var v: Variant = obj.call(method)
	return float(v) if (v is float or v is int) else fallback


static func _call_bool(obj: Variant, method: String, fallback: bool) -> bool:
	if obj == null or not is_instance_valid(obj) or not obj.has_method(method):
		return fallback
	var v: Variant = obj.call(method)
	return bool(v) if v is bool else fallback
