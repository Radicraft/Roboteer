class_name ImpactShake extends Node
## THE ONE CAMERA SHAKE BUDGET (combat feel wave; the API is agreed in
## docs/wave-a-contracts.md section 3). Every camera shake in a fight goes through here:
## the combat hits (FightFx, by feel tier), the arena hazards (FightFx.on_hazard_strike, the
## hazards engineer's), landings and anything added later. Nothing else may move the fight
## camera for effect.
##
## So this is a SOURCE, not an effect: it keeps the state and offers the camera rig four
## numbers per frame, and the rig decides how to apply them. If the FX tree is deleted, the
## group lookup finds nothing and the rig runs exactly as it does without it, which keeps the
## "deleting Arena/fx changes nothing" rule true.
##
##   offset()        camera-local translation, metres (the trauma noise)
##   rotation()      camera-local rotation, radians (x pitch, y yaw, z roll): the trauma
##                   noise's rotational part plus the directional kick, which springs back
##   zoom_punch()    0..1 of a quick push in along the view (the rig turns it into metres)
##
## Trauma model (Squirrel Eiserloh's): trauma is ADDED, decays linearly, and the shake is
## trauma SQUARED, so two light hits barely register and one heavy hit is unmistakable.
##
## THE BUDGET. One trauma value, clamped to 1, shared by every source; and each SOURCE can
## only raise it as far as its own ceiling (SOURCE_CEILING). A hazard clinch (a grinder under
## both machines) can therefore never pin the camera at full shake, a saw in the cut cannot
## either, and a real blow still reaches the top. `kick(strength)`, the old call, is the
## "hit" source and keeps working unchanged.

## Group the camera rig looks this up by, so neither node has to know the other.
const GROUP := "roboteer_impact_shake"

## Metres of camera travel at full trauma. The fight camera sits 3 to 6 m out, so 7 cm is a
## firm shove and not an earthquake.
const MAX_OFFSET := 0.07
## Degrees of noise roll/pitch at full trauma (the rotational half of the shake: a camera
## that only translates reads as a wobble, one that also rolls reads as a blow).
const MAX_NOISE_DEG := 1.1
## Trauma per second shed. A single heavy kick is visibly over in about 0.4 s.
const DECAY_PER_S := 2.6
## Three incommensurate frequencies per axis, so the motion never repeats.
const FREQ := [27.0, 19.0, 13.0]
const AXIS_PHASE := [0.0, 2.1, 4.2]

## How far each source may raise the SHARED trauma. A source's kick adds normally below its
## ceiling and is clipped at it; it never pulls trauma down.
const SOURCE_CEILING := {
	"hit": 1.0,
	"hazard": 0.7,
	"landing": 0.5,
	"continuous": 0.3,
}

## The directional kick: a damped spring back to rest. Stiffness and damping in 1/s, chosen
## so a kick peaks in about 40 ms and is home in about 250 ms with one small overshoot.
const KICK_STIFFNESS := 180.0
const KICK_DAMPING := 18.0
const KICK_MAX_DEG := 2.5
## The zoom punch: in fast, out slow.
const PUNCH_IN_S := 0.06
const PUNCH_OUT_S := 0.25

var trauma: float = 0.0
var _t: float = 0.0
var _seed: float = 0.0
var _offset := Vector3.ZERO
var _noise_rot := Vector3.ZERO
## Spring state for the directional kick, radians and radians per second.
var _kick := Vector3.ZERO
var _kick_vel := Vector3.ZERO
var _punch_peak: float = 0.0
var _punch_t: float = -1.0


func _ready() -> void:
	add_to_group(GROUP)
	_seed = randf() * 100.0
	set_process(false)   # FightFx steps us on its presentation clock


## THE API. Add `amount` (0..1) of trauma from `source` ("hit", "hazard", "landing",
## "continuous"; an unknown source is treated as "hit").
func add_trauma(amount: float, source: String = "hit") -> void:
	var ceiling := float(SOURCE_CEILING.get(source, 1.0))
	var a := clampf(amount, 0.0, 1.0)
	if trauma >= ceiling:
		return
	trauma = minf(trauma + a, ceiling)


## The old call: a "hit" kick. Kept because the hazard path and fx_test use it.
func kick(strength: float) -> void:
	add_trauma(strength, "hit")


## A directional, rotational kick. `screen_dir` is the way the blow pushes the PICTURE, in
## screen space (+x right, +y down); the camera pitches and yaws the opposite way so the
## frame jolts with the blow, and rolls by `roll` of the kick. `degrees` is the size.
func kick_direction(screen_dir: Vector2, degrees: float, roll: float = 0.5) -> void:
	if degrees <= 0.0:
		return
	var d := screen_dir.normalized() if screen_dir.length_squared() > 1e-6 else Vector2.DOWN
	var mag := deg_to_rad(minf(degrees, KICK_MAX_DEG))
	# Impulse into the spring: pitch from the vertical part, yaw from the horizontal, roll
	# with the horizontal so a blow from the left tips the horizon.
	_kick_vel += Vector3(d.y * mag, -d.x * mag, -d.x * mag * roll) * KICK_STIFFNESS * 0.12


## A quick push in along the view, `amount` 0..1 (the rig turns 1 into a tenth of its
## distance). A bigger punch replaces a smaller one; a smaller one is ignored.
func punch_zoom(amount: float) -> void:
	var a := clampf(amount, 0.0, 1.0)
	if _punch_t >= 0.0 and a <= _current_punch():
		return
	_punch_peak = a
	_punch_t = 0.0


## Advance the shake. FightFx passes its presentation delta, so a headless test can step this
## at a fixed rate like the rest of Arena/fx.
func step(delta: float) -> void:
	if delta <= 0.0:
		return
	_t += delta
	_step_kick(delta)
	if _punch_t >= 0.0:
		_punch_t += delta
		if _punch_t >= PUNCH_IN_S + PUNCH_OUT_S:
			_punch_t = -1.0
	if trauma <= 0.0:
		_offset = Vector3.ZERO
		_noise_rot = Vector3.ZERO
		return
	trauma = maxf(0.0, trauma - DECAY_PER_S * delta)
	var shake := trauma * trauma
	var amp := MAX_OFFSET * shake
	# limit_length, not three independent axes: MAX_OFFSET is a TRAVEL bound.
	_offset = Vector3(
		_wave(0),
		_wave(1),
		_wave(2) * 0.35          # less push in and out: it reads as a zoom wobble
	).limit_length(1.0) * amp
	var rot := deg_to_rad(MAX_NOISE_DEG) * shake
	_noise_rot = Vector3(_wave(1) * rot * 0.6, 0.0, _wave(2) * rot)


func _step_kick(delta: float) -> void:
	if _kick == Vector3.ZERO and _kick_vel == Vector3.ZERO:
		return
	# Semi-implicit Euler in small slices, stable at any frame rate.
	var left := delta
	while left > 0.0:
		var h := minf(left, 1.0 / 240.0)
		left -= h
		var accel := -_kick * KICK_STIFFNESS - _kick_vel * KICK_DAMPING
		_kick_vel += accel * h
		_kick += _kick_vel * h
	var cap := deg_to_rad(KICK_MAX_DEG)
	_kick = Vector3(clampf(_kick.x, -cap, cap), clampf(_kick.y, -cap, cap), clampf(_kick.z, -cap, cap))
	if _kick.length() < 1e-5 and _kick_vel.length() < 1e-4:
		_kick = Vector3.ZERO
		_kick_vel = Vector3.ZERO


## The camera space offset for this frame. Cached; safe to call every frame.
func offset() -> Vector3:
	return _offset


## The camera space rotation for this frame, radians (x pitch, y yaw, z roll).
func rotation() -> Vector3:
	return _noise_rot + _kick


## 0..1 of the zoom punch this frame.
func zoom_punch() -> float:
	return _current_punch()


func _current_punch() -> float:
	if _punch_t < 0.0:
		return 0.0
	if _punch_t < PUNCH_IN_S:
		return _punch_peak * (_punch_t / PUNCH_IN_S)
	var k := clampf((_punch_t - PUNCH_IN_S) / PUNCH_OUT_S, 0.0, 1.0)
	return _punch_peak * (1.0 - k * k * (3.0 - 2.0 * k))


func reset() -> void:
	trauma = 0.0
	_offset = Vector3.ZERO
	_noise_rot = Vector3.ZERO
	_kick = Vector3.ZERO
	_kick_vel = Vector3.ZERO
	_punch_t = -1.0
	_punch_peak = 0.0


func _wave(axis: int) -> float:
	var f: float = FREQ[axis]
	var p: float = AXIS_PHASE[axis] + _seed
	return sin((_t * f + p) * TAU) * 0.72 + sin((_t * f * 0.37 + p * 1.7) * TAU) * 0.28
