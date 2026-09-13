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
const SFX_VOICES := 10
const MOTOR_VOLUME_QUIET_DB := -34.0
const MOTOR_VOLUME_LOUD_DB := -11.0
const MOTOR_PITCH_IDLE := 0.72
const MOTOR_PITCH_FULL := 1.45
const MOTOR_SMOOTH := 6.0              # per second, how fast hum follows throttle

const SOUNDS := {
	"bolt_collect": "res://audio/bolt_collect.wav",
	"impact_light": "res://audio/impact_light.wav",
	"impact_heavy": "res://audio/impact_heavy.wav",
	"flipper_fire": "res://audio/flipper_fire.wav",
	"wheel_off": "res://audio/wheel_off.wav",
	"panel_off": "res://audio/panel_off.wav",
	"motor_loop": "res://audio/motor_loop.wav",
	"countdown_tick": "res://audio/countdown_tick.wav",
	"bell": "res://audio/bell.wav",
	"ko_tick": "res://audio/ko_tick.wav",
	"spikes": "res://audio/spikes.wav",
}

## Test seam. > 0 makes _process step by exactly this many seconds per frame so a
## headless test can simulate real time without waiting for it.
var fixed_delta_override: float = 0.0

@onready var _bolts: BoltShower = $BoltShower
@onready var _collect: CollectAudio = $CollectAudio

var _haptics := FightHaptics.new()
var _particles: FightParticles = null
var _now: float = 0.0

var _hud: Object = null
var _get_bot_position: Callable = Callable()

var _streams: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0

## bot_id -> AudioStreamPlayer running motor_loop.wav, plus its current/target state.
var _motors: Dictionary = {}

## bot_id -> Array of {"amount": int, "bolts": int}. Bolts carry scrap that was ALREADY
## awarded by the rules, so the ledger guarantees the HUD is bumped by exactly the
## amount that was awarded, whether the shower spawned 30 bolts or 12 fat ones.
var _ledger: Dictionary = {}


func _ready() -> void:
	for key in SOUNDS:
		var s: AudioStream = load(SOUNDS[key]) as AudioStream
		if s == null:
			push_warning("FightFx: missing sound " + str(SOUNDS[key]))
			continue
		_streams[key] = s
	for i in SFX_VOICES:
		var p := AudioStreamPlayer.new()
		p.name = "Sfx%d" % i
		add_child(p)
		_voices.append(p)
	_particles = FightParticles.new()
	_particles.name = "Particles"
	add_child(_particles)
	_collect.bind_haptics(_haptics)
	_bolts.collected.connect(_on_bolt_collected)


func _process(delta: float) -> void:
	var d := fixed_delta_override if fixed_delta_override > 0.0 else delta
	if d <= 0.0:
		return
	_now += d
	_bolts.step(d)
	_collect.step(_now)
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
func on_scrap_awarded(bot_id: String, amount: int, position: Vector3) -> void:
	if amount <= 0:
		return
	var spawned := _bolts.spawn(position, amount, bot_id, _get_bot_position)
	if spawned <= 0:
		# The pool is completely full. Never drop earned scrap: bank it silently.
		_bump_hud(amount)
		bolts_landed.emit(bot_id, amount)
		return
	var q: Array = _ledger.get(bot_id, [])
	q.append({"amount": amount, "bolts": spawned})
	_ledger[bot_id] = q


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
	_play("impact_heavy" if heavy else "impact_light", randf_range(0.92, 1.08))
	_haptics.send("impact_heavy" if heavy else "impact_light", _now)

	if detached:
		if _particles != null:
			_particles.puff_dust(at)
		_play("wheel_off" if part.begins_with("wheel") else "panel_off", randf_range(0.94, 1.06))


func on_weapon_fired(bot_id: String) -> void:
	var _unused := bot_id   # one weapon in Stage 3; the id is here for per bot voices later
	_play("flipper_fire", randf_range(0.97, 1.03))
	_haptics.send("flip", _now)


## One second of the knockout count. seconds_left counts down to zero; the tick
## tightens as it runs out so the count feels like it is closing in.
func on_ko_tick(seconds_left: int) -> void:
	var elapsed := clampi(int(FightTypes.KO_COUNT_S) - seconds_left, 0, 10)
	_play("ko_tick", 1.0 + float(elapsed) * 0.035)
	_haptics.send("ko_tick", _now)


## step 3, 2, 1 then 0 for FIGHT. The bell is kept for the result (spec §11).
func on_countdown(step: int) -> void:
	_play("countdown_tick", 1.0 if step > 0 else 1.5)


func on_bell() -> void:
	_play("bell")
	_haptics.send("bell", _now)


## throttle is 0..1. The hum pitch and level follow it; the loop never restarts, so
## there is no click when a bot goes on and off the throttle.
func set_motor_state(bot_id: String, throttle: float) -> void:
	var t := clampf(absf(throttle), 0.0, 1.0)
	if not _motors.has(bot_id):
		_motors[bot_id] = _make_motor(bot_id)
	var motor: Dictionary = _motors[bot_id]
	motor["target"] = t


func on_spikes(risen: bool, position: Vector3) -> void:
	if risen:
		_play("spikes")
	if _particles != null:
		_particles.set_spike_sparks(risen, position)


func set_haptics_enabled(on: bool) -> void:
	_haptics.enabled = on


## Silence every voice, including the drive hums. R should call this when the fight
## is torn down; without it a still mixing playback outlives the node.
func stop_all_audio() -> void:
	for p in _voices:
		p.stop()
	for bot_id in _motors:
		var motor: Dictionary = _motors[bot_id]
		var player: AudioStreamPlayer = motor["player"]
		player.stop()
	_collect.stop_all()


## --- introspection for Arena/tests/fx_test.gd -------------------------------

func bolt_shower() -> BoltShower:
	return _bolts


func collect_audio() -> CollectAudio:
	return _collect


func haptics() -> FightHaptics:
	return _haptics


func now() -> float:
	return _now


## --- internals --------------------------------------------------------------

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


func _play(key: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if not _streams.has(key):
		return
	var p := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % SFX_VOICES
	p.stream = _streams[key]
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.play()


func _make_motor(bot_id: String) -> Dictionary:
	var p := AudioStreamPlayer.new()
	p.name = "Motor_" + bot_id
	p.stream = _streams.get("motor_loop", null)
	p.volume_db = MOTOR_VOLUME_QUIET_DB
	p.pitch_scale = MOTOR_PITCH_IDLE
	add_child(p)
	if p.stream != null:
		p.play()
	return {"player": p, "level": 0.0, "target": 0.0}


func _step_motors(delta: float) -> void:
	var k := clampf(delta * MOTOR_SMOOTH, 0.0, 1.0)
	for bot_id in _motors:
		var motor: Dictionary = _motors[bot_id]
		var level: float = lerpf(motor["level"], motor["target"], k)
		motor["level"] = level
		var p: AudioStreamPlayer = motor["player"]
		p.pitch_scale = lerpf(MOTOR_PITCH_IDLE, MOTOR_PITCH_FULL, level)
		p.volume_db = lerpf(MOTOR_VOLUME_QUIET_DB, MOTOR_VOLUME_LOUD_DB, level)


## damage_event.position survives a JSON round trip as an Array, so accept both.
static func _as_vector3(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	if v is Array and (v as Array).size() >= 3:
		var a: Array = v
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO
