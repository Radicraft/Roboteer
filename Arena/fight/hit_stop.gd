class_name HitStop extends RefCounted
## The fight's tick clock HOLD (combat feel wave, docs/wave-a-combat-notes.md section 2).
##
## A hit-stop, a slow motion and a slow replay are all the same thing here: engine physics
## iterations in which the simulation is simply NOT TAKEN. The tick never changes length and
## never changes rate (both were measured to give a different fight, docs/aaa/combat-feel.md
## S4 and B1); a held iteration is one where the SceneTree is paused, PhysicsServer3D does not
## step, no bot, weapon or hazard runs, and the fight's own tick is skipped. So a fight with a
## thousand holds in it is tick for tick the fight with none, and only its pacing against the
## wall clock differs.
##
## `fight.gd` owns one of these and asks it once per engine physics iteration:
##
##     if not _hitstop.take_tick():     # this iteration is held
##         return
##
## Everything else calls the three requests. None of them is allowed to be asked from inside
## the simulation (they are presentation decisions, made in the `_process` drain), and a
## request can only ever DELAY ticks, never add or drop one.
##
## Every number is a dial in DIALS, so the feel can be tuned without reading the code.

const DIALS := {
	# Never hold longer than this for one blow. The owner's "Ratchet-strong" ceiling.
	"max_stop_ms": 120.0,
	# A second stop inside this window of the last one is dropped, so a flurry reads as a
	# flurry and not as a stutter.
	"min_gap_ms": 250.0,
	# Slow motion: take one tick in this many iterations (4 = quarter speed).
	"slowmo_every": 4,
}

## The engine iteration length the holds are counted in. The tick rate never changes, so a
## hold of N ms is N / (1000 / TICK_HZ) iterations.
const ITERATION_MS := 1000.0 / float(FightTypes.TICK_HZ)

var enabled: bool = true

var _hold_left: int = 0          # iterations still to hold for a stop
var _gap_left: int = 0           # iterations before another stop is allowed
var _slow_left: int = 0          # iterations of slow motion still to run
var _slow_every: int = 1         # take one tick in this many while slow
var _base_every: int = 1         # the replay speed: 1, 2 or 4
var _phase: int = 0              # iterations since the last tick taken while slowed

## For the tests and the notes.
var stops_taken: int = 0
var held_iterations: int = 0


## A blow wants the picture to stop for `ms`. Clamped to the ceiling; dropped inside the gap
## after the last stop, and while slow motion is already running (it is already slow).
## Returns true when it was taken.
func request_stop(ms: float) -> bool:
	if not enabled or ms <= 0.0:
		return false
	if _gap_left > 0 or _slow_left > 0:
		return false
	var capped := minf(ms, float(DIALS["max_stop_ms"]))
	var iterations := int(round(capped / ITERATION_MS))
	if iterations <= 0:
		return false
	_hold_left = maxi(_hold_left, iterations)
	_gap_left = iterations + int(round(float(DIALS["min_gap_ms"]) / ITERATION_MS))
	stops_taken += 1
	return true


## Run at 1 / `every` speed for `seconds` of wall time (a part coming off, the finish).
## A longer request extends a shorter one; it never shortens it.
func request_slowmo(seconds: float, every: int = -1) -> void:
	if not enabled or seconds <= 0.0:
		return
	var n := int(DIALS["slowmo_every"]) if every <= 0 else every
	_slow_every = maxi(_slow_every if _slow_left > 0 else 1, maxi(n, 1))
	_slow_left = maxi(_slow_left, int(round(seconds * 1000.0 / ITERATION_MS)))
	# A stop that is still holding lets go: the slow motion IS the beat now.
	_hold_left = 0


## The replay speed: 1.0, 0.5 or 0.25. Anything else is taken to the nearest of the three,
## because only those divide the iteration rate exactly.
func set_speed(speed: float) -> void:
	if speed <= 0.375:
		_base_every = 4
	elif speed <= 0.75:
		_base_every = 2
	else:
		_base_every = 1
	_phase = 0


func speed() -> float:
	return 1.0 / float(_base_every)


## Drop every hold (a seek, a new fight, the user pausing through one).
func clear() -> void:
	_hold_left = 0
	_gap_left = 0
	_slow_left = 0
	_slow_every = 1
	_phase = 0


func is_holding() -> bool:
	return _hold_left > 0


func is_slow() -> bool:
	return _slow_left > 0 or _base_every > 1


## Called ONCE per engine physics iteration, while the fight is live and not paused.
## Returns true when this iteration is a real tick.
func take_tick() -> bool:
	if _gap_left > 0:
		_gap_left -= 1
	if _hold_left > 0:
		_hold_left -= 1
		held_iterations += 1
		return false
	var every := _base_every
	if _slow_left > 0:
		_slow_left -= 1
		every = maxi(every, _slow_every)
		if _slow_left == 0:
			_slow_every = 1
	if every <= 1:
		_phase = 0
		return true
	_phase += 1
	if _phase >= every:
		_phase = 0
		return true
	held_iterations += 1
	return false
