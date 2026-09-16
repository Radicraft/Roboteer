class_name FightFx extends Node3D
## Everything the fight FEELS like: bolt showers, collect pitch ramp, impact sounds,
## sparks, dust, drive hum, haptics. docs/stage3-spec.md §11, brief-v3.md §6.
##
## HARD RULE (spec §7): this node is presentation. Everything runs in _process, it
## never touches physics state, and nothing it does can feed back into the fight.
## It is safe to delete the whole FX subtree and still get the same result JSON.
##
## The fight orchestrator (R) instantiates res://fx/fx.tscn under Fight, calls
## bind(), then calls the on_* methods from its own signal handlers.
##
##     var fx: FightFx = preload("res://fx/fx.tscn").instantiate()
##     add_child(fx)
##     fx.bind(hud, func(bot_id: String) -> Vector3: return _bots[bot_id].chassis.global_position)
##     fx.on_scrap_awarded("player-1", 30, hit_position)
##
## Presentation clock: _now advances by the frame delta (or fixed_delta_override when
## a test drives it), and every timing in the FX tree reads that clock rather than
## Time.get_ticks_msec(), so the headless test can step four seconds in 240 frames.

## One bolt landed and its share of the scrap was handed to the HUD.
signal bolts_landed(bot_id: String, amount: int)

const IMPACT_HEAVY_SEVERITY := 0.3     # spec §11: below this an impact is "light"
## The one shot voice pool moved into AudioMix (AudioMix.VOICES_2D / VOICES_3D), along
## with the polyphony caps that a plain round robin pool could not express.
const MOTOR_VOLUME_QUIET_DB := -34.0
const MOTOR_VOLUME_LOUD_DB := -11.0
const MOTOR_PITCH_IDLE := 0.72
const MOTOR_PITCH_FULL := 1.45
const MOTOR_SMOOTH := 6.0              # per second, how fast hum follows throttle

## Camera kick per damage event, mapped from severity. The floor is there so even a
## scrape moves the frame a little; the span keeps a maximum hit inside one unit of
## trauma so a pile-up cannot shake the camera off the arena. See impact_shake.gd.
const SHAKE_MIN := 0.10
const SHAKE_SPAN := 0.80

## Weapons whose sound is a loop rather than a bang, by WeaponBase.kind.
const WEAPON_LOOPS := {
	"spinner": "spin_up_loop",
	"drum": "spin_up_loop",
	"fbs": "spin_up_loop",
	"saw": "saw_cut_loop",
	"flame": "flame_loop",
}
## A spinner at zero readiness is an octave low and 16 dB down; at full speed it is
## an octave up and at its written level. One file covers the whole rev.
const SPIN_PITCH_MIN := 0.55
const SPIN_PITCH_MAX := 2.10
const SPIN_QUIET_DB := -16.0
## A hazard that nobody is touching is still running, just further away.
const HAZARD_IDLE_DB := -9.0

## The sound catalogue lives in AudioMix now, because the mixer is what needs to know
## the levels, the caps, the buses and the variants alongside the paths. This alias is
## kept because it is the public name other code (and fx_test) already uses.
const SOUNDS := AudioMix.SOUNDS

## Test seam. > 0 makes _process step by exactly this many seconds per frame so a
## headless test can simulate real time without waiting for it.
var fixed_delta_override: float = 0.0

@onready var _bolts: BoltShower = $BoltShower
@onready var _collect: CollectAudio = $CollectAudio

var _haptics := FightHaptics.new()
var _particles: FightParticles = null
var _shake: ImpactShake = null
var _now: float = 0.0

var _hud: Object = null
var _get_bot_position: Callable = Callable()

var _mix: AudioMix = null
## Wave F (agent F2): the movement layer. It finds the machines itself and reads their
## drive state every presentation frame, so unlike `set_motor_state` below it cannot be
## left unwired — which is exactly what happened to `set_motor_state` for six stages.
var _machines: MachineAudio = null

## bot_id -> the mixer loop key for its drive hum, plus its current/target state.
var _motors: Dictionary = {}

## bot_id -> {"kind": String, "key": String} for a weapon whose sound is a LOOP
## (spinners, the saw, the flamethrower). One-shot weapons never appear here.
var _weapon_loops: Dictionary = {}

## hazard kind -> mixer loop key, for the hazards that hum rather than bang.
var _hazard_loops: Dictionary = {}

## bot_id -> Array of {"amount": int, "bolts": int}. Bolts carry scrap that was ALREADY
## awarded by the rules, so the ledger guarantees the HUD is bumped by exactly the
## amount that was awarded, whether the shower spawned 30 bolts or 12 fat ones.
var _ledger: Dictionary = {}

## Awards waiting for the damage event that earned them. See on_scrap_awarded.
## Entries are {"bot_id": String, "amount": int, "position": Vector3}.
var _pending_awards: Array = []


func _ready() -> void:
	_mix = AudioMix.new()
	_mix.name = "AudioMix"
	add_child(_mix)
	_machines = MachineAudio.new()
	_machines.name = "MachineAudio"
	add_child(_machines)
	_machines.bind(_mix)
	_particles = FightParticles.new()
	_particles.name = "Particles"
	add_child(_particles)
	# The camera rig finds this by group, so the FX tree stays deletable: with no
	# FX node the lookup returns null and the camera behaves exactly as before.
	_shake = ImpactShake.new()
	_shake.name = "ImpactShake"
	add_child(_shake)
	_collect.bind_haptics(_haptics)
	_bolts.collected.connect(_on_bolt_collected)


func _process(delta: float) -> void:
	var d := fixed_delta_override if fixed_delta_override > 0.0 else delta
	if d <= 0.0:
		return
	_now += d
	# Any award whose damage event never arrived is shown now rather than held: the
	# hazard credit path rewrites the attacker, a paused drain can swallow an event,
	# and earned scrap is never allowed to wait more than a frame.
	_flush_awards()
	_bolts.step(d)
	_collect.step(_now)
	if _particles != null:
		_particles.step(d)
	if _shake != null:
		_shake.step(d)
	if _machines != null:
		_machines.step(d)
	_step_motors(d)


## --- public API, called by the fight orchestrator ---------------------------

## hud is C's HUD node (anything exposing bump(amount: int)); get_bot_position takes
## a bot_id String and returns that bot's live chassis position in world space.
func bind(hud: Object, get_bot_position: Callable) -> void:
	_hud = hud
	_get_bot_position = get_bot_position


## The rules awarded `amount` scrap to bot_id for a hit at `position`. Spray that many
## bolts; each one bumps the HUD by its share as it lands, so the counter climbs in a
## stream rather than jumping. Nothing here decides the scrap, it only shows it.
##
## Wave F (agent F3): the award now waits for its damage event before it is shown. A
## shower is made of torn plate, shards and fasteners chosen from the SEVERITY of the
## hit and the MATERIAL of the face that was hit, and the award message carries
## neither. `fight.gd` emits `scrap_awarded` inside the physics tick and drains
## `damage_event` to us later in the same frame, so the award always arrives first and
## bare. Rather than reach into the fight for the context, the award is queued here
## until its own event turns up (they carry the same `position`, so the match is
## exact), and anything still queued when the next presentation step runs is spawned
## anyway with the severity recovered from the amount. The wait is at most one frame,
## which is inside the 25 to 475 ms scatter delay and invisible.
##
## Scrap cannot be lost by this: an entry only ever leaves the queue by being spawned
## or banked, and both paths bump the HUD by the full amount.
func on_scrap_awarded(bot_id: String, amount: int, position: Vector3) -> void:
	if amount <= 0:
		return
	_pending_awards.append({"bot_id": bot_id, "amount": amount, "position": position})


## P's damage_event payload (spec §6). Sparks sized by severity, an impact sound, a
## dust puff and a part sound when something came off, and the matching haptic.
func on_damage_event(info: Dictionary) -> void:
	var at := _as_vector3(info.get("position", Vector3.ZERO))
	var severity := float(info.get("severity", 0.0))
	var detached := bool(info.get("detached", false))
	var part := str(info.get("part", ""))
	var heavy := severity >= IMPACT_HEAVY_SEVERITY

	if _particles != null:
		_particles.burst_sparks(at, severity)
	if _shake != null:
		_shake.kick(SHAKE_MIN + SHAKE_SPAN * clampf(severity, 0.0, 1.0))
	_play("impact_heavy" if heavy else "impact_light", _jitter(0.92, 1.08), 0.0, at)
	_haptics.send("impact_heavy" if heavy else "impact_light", _now)

	if detached:
		# A detach is a bigger moment than a hit: a hot white core at the tear, the
		# grey dust that says structural loss rather than scrap, and torn chips.
		if _particles != null:
			_particles.burst_detach(at, severity)
		_play("wheel_off" if part.begins_with("wheel") else "panel_off",
			_jitter(0.94, 1.06), 0.0, at)

	# Hand this hit to the award that is waiting for it, so the shower knows what it
	# is made of (agent F3, see on_scrap_awarded).
	_spawn_award_for(info, at)


## A weapon fired. `kind` is WeaponBase.kind ("flipper", "axe", "ram", "crusher", ...);
## it defaults to the flipper so the Stage 3 call site is unchanged.
func on_weapon_fired(bot_id: String, kind: String = "flipper") -> void:
	var at: Variant = _bot_position(bot_id)
	match kind:
		"axe":
			# An axe is two sounds, not one: the arm moving, then the head landing.
			# The hit is fired by the damage event, so only the swing belongs here.
			_play("axe_swing", _jitter(0.94, 1.06), 0.0, at)
		"ram":
			_play("ram_hit", _jitter(0.94, 1.06), 0.0, at)
		"crusher":
			_play("crusher_clamp", _jitter(0.97, 1.03), 0.0, at)
		_:
			_play("flipper_fire", _jitter(0.97, 1.03), 0.0, at)
	_haptics.send("flip", _now)


## A weapon that SOUNDS while it runs rather than banging once: a spinner spinning up,
## a saw in a cut, a flamethrower burning. Call it whenever the state changes; calling
## it every frame is fine and is in fact how `readiness` is meant to be fed, because
## the loop is pitched rather than restarted.
##
##   fx.on_weapon_state("player-1", "spinner", true, weapon.readiness())
##
## `readiness` is WeaponBase.readiness(), 0 to 1. For a spinner it is the spin
## fraction, and it drives pitch across SPIN_PITCH_MIN..MAX, which is why there is one
## `spin_up_loop.wav` rather than a spin-up sample and a spinning sample: a sample pair
## has a seam at the handover and this does not.
func on_weapon_state(bot_id: String, kind: String, active: bool,
		readiness: float = 1.0) -> void:
	if _mix == null:
		return
	var sound: String = str(WEAPON_LOOPS.get(kind, ""))
	if sound == "":
		return
	var key := "weapon:" + bot_id
	var running: Dictionary = _weapon_loops.get(bot_id, {})
	if not active:
		if not running.is_empty():
			_mix.stop_loop(key)
			_weapon_loops.erase(bot_id)
		return
	var r := clampf(readiness, 0.0, 1.0)
	var pitch := 1.0
	var db := 0.0
	if kind == "spinner" or kind == "drum" or kind == "fbs":
		pitch = lerpf(SPIN_PITCH_MIN, SPIN_PITCH_MAX, r)
		db = lerpf(SPIN_QUIET_DB, 0.0, r)
	if running.is_empty() or str(running.get("kind", "")) != kind:
		if not running.is_empty():
			_mix.stop_loop(key)
		_mix.start_loop(key, sound, _bot_position(bot_id), db, pitch)
		_weapon_loops[bot_id] = {"kind": kind, "key": key}
		return
	_mix.set_loop(key, pitch, db, _bot_position(bot_id))


## The arena's `hazard_fx(kind, active, position)` signal (ArenaBase). R connects it:
##
##   arena.hazard_fx.connect(fx.on_hazard_fx)
##
## Spikes keep their own entry point (`on_spikes`) because they also drive particles.
func on_hazard_fx(kind: String, active: bool, position: Vector3) -> void:
	if _mix == null:
		return
	match kind:
		"spikes":
			on_spikes(active, position)
		"grinder", "disc":
			# A grinder is always turning; `active` means a bot is ON it, so the
			# loop stays up and only the level moves. Starting it on contact would
			# make a hazard that is silent until it hurts you, which is a lie the
			# player cannot learn from.
			var sound: String = "grinder_loop" if kind == "grinder" else "disc_spin_loop"
			var key := "hazard:" + kind
			if not _mix.has_loop(key):
				_mix.start_loop(key, sound, position, HAZARD_IDLE_DB)
				_hazard_loops[kind] = key
			else:
				_mix.set_loop(key, 1.0, 0.0 if active else HAZARD_IDLE_DB, position)
		"flame":
			var fkey := "hazard:flame"
			if active:
				if not _mix.has_loop(fkey):
					_play("flame_jet", _jitter(0.96, 1.04), 0.0, position)
					_mix.start_loop(fkey, "flame_loop", position)
					_hazard_loops["flame"] = fkey
				else:
					_mix.set_loop(fkey, 1.0, 0.0, position)
			else:
				_mix.stop_loop(fkey)
				_hazard_loops.erase("flame")
		"pit":
			if active:
				_play("pit_open", _jitter(0.98, 1.02), 0.0, null)
		"ram":
			if active:
				_play("ram_crush", _jitter(0.96, 1.04), 0.0, position)
		_:
			pass


## The arena hall. R turns it on when the fight world is built and off at teardown.
func set_ambience(on: bool) -> void:
	if _mix == null:
		return
	if on:
		_mix.start_loop("ambience", "crowd_ambience_loop")
	else:
		_mix.stop_loop("ambience")


## The `settings` message's volume, 0..1 linear. Agent R's fight.gd writes bus 0
## directly and that still works; this is the same operation behind one name, so the
## shell has something to call that does not assume the bus index.
func set_master_volume(linear: float) -> void:
	if _mix != null:
		_mix.set_master_volume(linear)


## One second of the knockout count. seconds_left counts down to zero; the tick
## tightens as it runs out so the count feels like it is closing in.
func on_ko_tick(seconds_left: int) -> void:
	var elapsed := clampi(int(FightTypes.KO_COUNT_S) - seconds_left, 0, 10)
	_play("ko_tick", 1.0 + float(elapsed) * 0.035)  # ~3.5 % per second, about 0.6 of a semitone
	_haptics.send("ko_tick", _now)
	# Wave F: the crowd gets up as the count starts, and the mixer's own gap keeps it to
	# one roar per count rather than one per tick. The tick itself ducks it (AudioMix.DUCKS),
	# so the roar is under the count and never over it.
	if _mix != null:
		_mix.crowd_reaction(AudioMix.SWELL_KO)


## step 3, 2, 1 then 0 for FIGHT. The bell is kept for the result (spec §11).
func on_countdown(step: int) -> void:
	_play("countdown_tick", 1.0 if step > 0 else 1.5)


func on_bell() -> void:
	_play("bell")
	_haptics.send("bell", _now)


## throttle is 0..1. The hum pitch and level follow it; the loop never restarts, so
## there is no click when a bot goes on and off the throttle.
##
## SUPERSEDED by `MachineAudio` (wave F). Nothing in the game has ever called this — the
## only callers in the repo are `fx_test.gd` — which is why there were no movement
## sounds at all until wave F. It is kept because it is part of the Stage 3 contract and
## an external caller may still use it; a bot driven through here gets `motor_loop` on
## the key "motor:<id>", which is a different key from MachineAudio's "machine:whine:<id>",
## so the two would stack rather than fight. Prefer MachineAudio.
func set_motor_state(bot_id: String, throttle: float) -> void:
	var t := clampf(absf(throttle), 0.0, 1.0)
	if not _motors.has(bot_id):
		_motors[bot_id] = _make_motor(bot_id)
	var motor: Dictionary = _motors[bot_id]
	motor["target"] = t


func on_spikes(risen: bool, position: Vector3) -> void:
	if risen:
		_play("spikes", 1.0, 0.0, position)
	if _particles != null:
		_particles.set_spike_sparks(risen, position)


func set_haptics_enabled(on: bool) -> void:
	_haptics.enabled = on


## Silence every voice, including the drive hums. R should call this when the fight
## is torn down; without it a still mixing playback outlives the node.
func stop_all_audio() -> void:
	if _machines != null:
		_machines.stop_all()
	if _mix != null:
		_mix.stop_all()
	_motors.clear()
	_weapon_loops.clear()
	_hazard_loops.clear()
	_collect.stop_all()


## --- introspection for Arena/tests/fx_test.gd -------------------------------

func bolt_shower() -> BoltShower:
	return _bolts


func collect_audio() -> CollectAudio:
	return _collect


func haptics() -> FightHaptics:
	return _haptics


func particles() -> FightParticles:
	return _particles


## The camera kick source. C's rig finds it by group (ImpactShake.GROUP) rather than
## through this, so the rig never has to know the FX tree exists; this accessor is
## for the test and for anything already holding the FightFx.
func impact_shake() -> ImpactShake:
	return _shake


func audio_mix() -> AudioMix:
	return _mix


func machine_audio() -> MachineAudio:
	return _machines


func now() -> float:
	return _now


## --- internals --------------------------------------------------------------

## Give the hit to the award it earned. Matched on `position`, which is the same
## Vector3 in both messages because `fight.gd` passes the damage event's own value
## straight into `scrap_awarded`. First match wins, and the queue is in the order the
## hits happened, so two hits at the same spot in one frame still pair up in order.
func _spawn_award_for(info: Dictionary, at: Vector3) -> void:
	for i in _pending_awards.size():
		var entry: Dictionary = _pending_awards[i]
		if (entry["position"] as Vector3).is_equal_approx(at):
			_pending_awards.remove_at(i)
			_spawn_award(entry, info)
			return


## Show everything still waiting, with no hit to describe it. The shower falls back to
## the severity recovered from the amount (BoltShower.severity_from_award).
func _flush_awards() -> void:
	if _pending_awards.is_empty():
		return
	var queued: Array = _pending_awards
	_pending_awards = []
	for entry_variant in queued:
		_spawn_award(entry_variant as Dictionary, {})


## The old body of on_scrap_awarded, unchanged except that the shower is now told what
## the hit was. The ledger is what guarantees the HUD ends up bumped by exactly the
## scrap that was awarded, however many pieces the pool could spare.
func _spawn_award(entry: Dictionary, hit: Dictionary) -> void:
	var bot_id := str(entry["bot_id"])
	var amount: int = int(entry["amount"])
	var position: Vector3 = entry["position"]
	var spawned := _bolts.spawn(position, amount, bot_id, _get_bot_position, hit)
	if spawned <= 0:
		# The pool is completely full. Never drop earned scrap: bank it silently.
		_bump_hud(amount)
		bolts_landed.emit(bot_id, amount)
		return
	var q: Array = _ledger.get(bot_id, [])
	q.append({"amount": amount, "bolts": spawned})
	_ledger[bot_id] = q


func _on_bolt_collected(bot_id: String) -> void:
	var amount := _take_from_ledger(bot_id)
	_collect.play_collect(_now)
	if amount > 0:
		_bump_hud(amount)
	bolts_landed.emit(bot_id, amount)


## Hand out this bolt's share of the shower it belongs to. Shares are ceilinged so
## the last bolts can be worth nothing rather than the total overshooting; the sum
## over a shower is exactly the amount that was awarded.
func _take_from_ledger(bot_id: String) -> int:
	var q: Array = _ledger.get(bot_id, [])
	if q.is_empty():
		return 0
	var entry: Dictionary = q[0]
	var bolts: int = entry["bolts"]
	var amount: int = entry["amount"]
	var share := 0
	if bolts > 0 and amount > 0:
		share = int(ceil(float(amount) / float(bolts)))
	entry["bolts"] = bolts - 1
	entry["amount"] = amount - share
	if entry["bolts"] <= 0:
		q.pop_front()
		if q.is_empty():
			_ledger.erase(bot_id)
	return share


func _bump_hud(amount: int) -> void:
	if _hud != null and is_instance_valid(_hud) and _hud.has_method("bump"):
		_hud.call("bump", amount)


## Every one shot in the fight goes through here and therefore through AudioMix: the
## per sound level trim, the polyphony cap, the variant rotation and the 3D placement
## all live there. `at` is a Vector3 in world space, or null for a sound that belongs
## to the arena rather than to a place in it.
func _play(key: String, pitch: float = 1.0, volume_db: float = 0.0,
		at: Variant = null) -> void:
	if _mix == null:
		return
	_mix.play(key, at, volume_db, pitch)


func _make_motor(bot_id: String) -> Dictionary:
	var key := "motor:" + bot_id
	if _mix != null:
		_mix.start_loop(key, "motor_loop", _bot_position(bot_id),
			MOTOR_VOLUME_QUIET_DB, MOTOR_PITCH_IDLE)
	return {"key": key, "level": 0.0, "target": 0.0}


## The hum follows the throttle in pitch and level, and the LOOP NEVER RESTARTS, which
## is why going on and off the throttle makes no click. The voice also follows the bot
## around the arena, so on a stereo device the two drives separate.
func _step_motors(delta: float) -> void:
	if _mix == null:
		return
	var k := clampf(delta * MOTOR_SMOOTH, 0.0, 1.0)
	for bot_id in _motors:
		var motor: Dictionary = _motors[bot_id]
		var level: float = lerpf(motor["level"], motor["target"], k)
		motor["level"] = level
		_mix.set_loop(str(motor["key"]),
			lerpf(MOTOR_PITCH_IDLE, MOTOR_PITCH_FULL, level),
			lerpf(MOTOR_VOLUME_QUIET_DB, MOTOR_VOLUME_LOUD_DB, level),
			_bot_position(bot_id))


## A presentation-only random, never the fight's seeded rng: pitch jitter must not be
## able to move the fight's random sequence. AudioMix owns the generator.
func _jitter(lo: float, hi: float) -> float:
	if _mix == null:
		return 1.0
	return _mix.jitter(lo, hi)


## Where a bot is, for placing its voice, or null if nothing has bound a getter (which
## is the case in the headless test). Never fails: a missing position means the sound
## plays without a place rather than not at all.
func _bot_position(bot_id: String) -> Variant:
	if not _get_bot_position.is_valid():
		return null
	var v: Variant = _get_bot_position.call(bot_id)
	return v if v is Vector3 else null


## damage_event.position survives a JSON round trip as an Array, so accept both.
static func _as_vector3(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	if v is Array and (v as Array).size() >= 3:
		var a: Array = v
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO
