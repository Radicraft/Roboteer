extends "res://fight/events/event_rules.gd"
## PINBALL (side event 3, docs/stage6-spec.md §1, brief §10).
##
## Sixty seconds on the table. A bumper is 100, the ramp is 500, a drop target is 250 and
## comes back up five seconds later. There is nothing to break and nothing to survive, so
## the only number is the score and the only skill is the drive.
##
## Why the ramp is worth five bumpers: a bumper happens TO you and the ramp is something
## you have to aim at, line up and climb, and the table should pay for intent. Targets sit
## between the two, and their five second reset is what makes the table a route rather
## than a place to stand: hit both, go and do something else, come back.
##
## `cleared` is the first blueprint gate, not a win: the table cannot be lost, so clearing
## it is beating the par below. Par is set at a run that takes both targets twice, the
## ramp three times and a bumper every four seconds, which is a competent sixty seconds
## and not a perfect one.
##
## Determinism: the table reports what was struck from inside its own physics tick, this
## adds up integers, and neither draws from the rng at all.

const ARENA_SCENE := "res://arena/events/pinball.tscn"
const DURATION_S := 60.0
const BUMPER_SCORE := 100
const RAMP_SCORE := 500
const TARGET_SCORE := 250
## Both targets twice (1000), the ramp three times (1500) and fifteen bumpers (1500).
const PAR_SCORE := 4000

var _duration := DURATION_S
var _score := 0
var _bumper_hits := 0
var _ramp_runs := 0
var _target_hits := 0
var _armed := false
var _connected := false


func setup(owner_fight: Node, event_config: Dictionary) -> void:
	super(owner_fight, event_config)
	var rules: Dictionary = event_config.get("rules", {}) as Dictionary
	_duration = float(rules.get("duration_s", DURATION_S))
	_score = 0
	_bumper_hits = 0
	_ramp_runs = 0
	_target_hits = 0
	_armed = false


func arena_scene_path() -> String:
	return ARENA_SCENE


func physics_tick(delta: float) -> void:
	super(delta)
	if not _armed:
		_arm()
	# Re-tried every tick until it takes: a table that is not connected scores nothing at
	# all and looks like a table with the power off.
	if not _connected:
		_connect_table()


func is_over() -> bool:
	return time_s >= _duration


func result() -> Dictionary:
	return {
		"score": _score,
		"cleared": _score >= PAR_SCORE,
		"details": {
			"bumpers": _bumper_hits,
			"ramps": _ramp_runs,
			"targets": _target_hits,
			"par": PAR_SCORE,
		},
	}


func hud_lines() -> Array[String]:
	var table := arena()
	var down := int(table.call("targets_down")) if table != null \
		and table.has_method("targets_down") else 0
	var total := int(table.call("target_count")) if table != null \
		and table.has_method("target_count") else 2
	return [
		"SCORE %d" % _score,
		"TARGETS %d OF %d" % [down, total],
		clock(_duration - time_s),
	]


# --------------------------------------------------------------------------------------

func _connect_table() -> void:
	var table := arena()
	if table == null or not table.has_signal("bumper_hit"):
		return
	if not table.is_connected("bumper_hit", _on_bumper):
		table.connect("bumper_hit", _on_bumper)
	if not table.is_connected("ramp_crossed", _on_ramp):
		table.connect("ramp_crossed", _on_ramp)
	if not table.is_connected("target_dropped", _on_target):
		table.connect("target_dropped", _on_target)
	_connected = true


func _on_bumper(_index: int, _at: Vector3) -> void:
	_bumper_hits += 1
	_score += BUMPER_SCORE


func _on_ramp() -> void:
	_ramp_runs += 1
	_score += RAMP_SCORE


func _on_target(_index: int) -> void:
	_target_hits += 1
	_score += TARGET_SCORE


## Everything that needs the ARENA or the MACHINES happens here, on the first tick, not in
## `setup`. `fight.gd` builds the event before it builds the world (`_load_event` runs from
## `start_fight` ahead of `_build_world` and `_spawn_bots`), so at `setup` time `arena()` is
## still the last fight's arena and `bots()` is still the last fight's machines. Reading
## either one there is reading the wrong world. `setup` is for the configuration; this is
## for the fight.
##
## No opponent on a pinball table either. Same reasoning as the Gauntlet: the fight always
## builds two machines, so the spare gets the bay by the plunger and is frozen there.
func _arm() -> void:
	_armed = true
	_connect_table()
	var list := bots()
	if list.size() < 2 or list[1] == null:
		return
	var spare: Node = list[1]
	var table := arena()
	if table != null and table.has_method("spawn_position") and spare.has_method("place_at"):
		spare.call("place_at", table.call("spawn_position", 1) as Vector3,
			table.call("spawn_facing", 1) as Vector3)
	if spare.has_method("freeze"):
		spare.call("freeze")
