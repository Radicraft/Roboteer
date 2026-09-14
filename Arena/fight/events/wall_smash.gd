extends "res://fight/events/event_rules.gd"
## WALL SMASH (side event 5, docs/stage6-spec.md §1, brief §10).
##
## Break through five brick walls inside ninety seconds. Score is time: the event ends the
## moment the fifth wall goes, and the clock it went on is the number the shell records.
## Cleared means all five.
##
## It is the one event where the BUILD is the whole answer, so the scoring deliberately
## rewards nothing else: no style, no route, no damage tally. A 100 kg ram on 6wd will beat
## a nimble flipper here and that is correct, because every other event punishes that build
## and the side events between them should want five different machines out of the garage.
##
## There is no opponent; the spare machine is parked and frozen behind the finish bar, for
## the same reason as the Gauntlet (`fight.gd` always builds two).
##
## Determinism: the arena pops the joints its bricks flagged inside the step, and emits one
## `wall_broken` per wall. Nothing here draws from the rng.

const ARENA_SCENE := "res://arena/events/wall_smash.tscn"
const WALLS := 5
## The clock a run has to beat to count as cleared quickly, for the shell's "best time".
## Not a gate: `cleared` is all five walls, whenever they fall.
const PAR_S := 45.0
## Score is a time, turned into a number that goes UP for a better run so one "best score"
## column in the shell works for all five events.
const SCORE_PER_SECOND := 100.0

var _duration := FightTypes.FIGHT_DURATION_S
var _broken := 0
var _wall_times: Array[float] = []
var _finish_time := -1.0
var _connected := false
var _armed := false


func setup(owner_fight: Node, event_config: Dictionary) -> void:
	super(owner_fight, event_config)
	var rules: Dictionary = event_config.get("rules", {}) as Dictionary
	_duration = float(rules.get("duration_s", FightTypes.FIGHT_DURATION_S))
	_broken = 0
	_wall_times = []
	_finish_time = -1.0
	_armed = false


func arena_scene_path() -> String:
	return ARENA_SCENE


func physics_tick(delta: float) -> void:
	super(delta)
	if not _armed:
		_arm()
	if not _connected:
		_connect_run()
	# Polled as well as signalled. The signal is the timestamp (it fires on the tick the
	# wall went), the poll is the truth: an event started before the arena finished
	# building would otherwise miss a wall and never clear.
	var run := arena()
	if run != null and run.has_method("walls_broken"):
		var now := int(run.call("walls_broken"))
		while _broken < now:
			_broken += 1
			_wall_times.append(time_s)
	if _broken >= WALLS and _finish_time < 0.0:
		_finish_time = time_s


func is_over() -> bool:
	return _broken >= WALLS or time_s >= _duration


func result() -> Dictionary:
	var run_time := _finish_time if _finish_time >= 0.0 else _duration
	var cleared := _broken >= WALLS
	var score := int(maxf(0.0, round((_duration - run_time) * SCORE_PER_SECOND))) if cleared else 0
	return {
		"score": score,
		"cleared": cleared,
		"time_s": run_time,
		"walls_broken": _broken,
		"details": {
			"time_s": run_time,
			"walls_broken": _broken,
			"walls": WALLS,
			"wall_times": _wall_times.duplicate(),
			"par_s": PAR_S,
		},
	}


func hud_lines() -> Array[String]:
	var lines: Array[String] = [
		"WALLS %d OF %d" % [_broken, WALLS],
		clock(_duration - time_s),
	]
	if _finish_time >= 0.0:
		lines.append("THROUGH IN %0.1f s" % _finish_time)
	return lines


# --------------------------------------------------------------------------------------

func _connect_run() -> void:
	var run := arena()
	if run == null or not run.has_signal("wall_broken"):
		return
	if not run.is_connected("wall_broken", _on_wall_broken):
		run.connect("wall_broken", _on_wall_broken)
	_connected = true


func _on_wall_broken(_index: int, _at: Vector3) -> void:
	# The count itself is polled in `physics_tick`, so this only has to exist for the FX
	# and for anything that wants the moment rather than the tally.
	pass


## Everything that needs the ARENA or the MACHINES happens here, on the first tick, not in
## `setup`. `fight.gd` builds the event before it builds the world (`_load_event` runs from
## `start_fight` ahead of `_build_world` and `_spawn_bots`), so at `setup` time `arena()` is
## still the last fight's arena and `bots()` is still the last fight's machines. Reading
## either one there is reading the wrong world. `setup` is for the configuration; this is
## for the fight.
func _arm() -> void:
	_armed = true
	_connect_run()
	var list := bots()
	if list.size() < 2 or list[1] == null:
		return
	var spare: Node = list[1]
	var run := arena()
	if run != null and run.has_method("spawn_position") and spare.has_method("place_at"):
		spare.call("place_at", run.call("spawn_position", 1) as Vector3,
			run.call("spawn_facing", 1) as Vector3)
	if spare.has_method("freeze"):
		spare.call("freeze")
