extends "res://fight/events/event_rules.gd"
## GAUNTLET (side event 2, docs/stage6-spec.md §1, brief §10 "traverse a hazard run
## against the clock").
##
## Reach the pad at the far end of the 24 m run inside ninety seconds. Scored on the time
## it took and the condition it cost; cleared by getting there at all. Twenty seconds in,
## BANDSAW comes through the gate behind you, which is brief §8's bosses doing the job the
## brief gives them ("they appear in gauntlet events"): it is not a competitor, it takes no
## scrap and scores nothing, it is a deadline with a saw on it.
##
## There is no opponent, but `fight.gd` always builds two machines, so the second one is
## put in the bay behind the finish pad and FROZEN at setup. Freezing rather than deleting:
## the fight's tallies, the HUD, the camera and the result builder all index two bots, and
## a null in that list is a crash waiting for whichever of them is read first.
##
## Determinism: the chaser enters on a FIXED tick, is built from the shared rng at that
## tick, and is driven by `BossAI`, which draws on the same fixed cadence as any other
## driver. Nothing else here draws at all.

const ARENA_SCENE := "res://arena/events/gauntlet.tscn"
const BOT_SCENE := "res://bot/bot.tscn"
const BossAIScript := preload("res://ai/boss_ai.gd")
const Rules := preload("res://fight/rules.gd")

## Brief §10 and the spec: the chaser enters twenty seconds in, from the start end.
const CHASER_ENTER_S := 20.0
const CHASER_BOSS := "bandsaw"
const CHASER_ID := "chaser-1"
## Scored so that a fast clean run beats a fast scruffy one. One second of clock is worth
## a hundred, one condition point is worth two hundred and fifty, and the floor is zero:
## a run that took every second and lost half the machine still scores, it just scores 0.
const SCORE_PER_SECOND := 100.0
const SCORE_PER_CONDITION := 250.0

var _duration := FightTypes.FIGHT_DURATION_S
var _tick := 0
var _finished := false
var _finish_time := -1.0
var _start_condition: Dictionary = {}
var _chaser: Node = null
var _chaser_ai: OpponentAI = null
var _chaser_entered := false
var _armed := false


func setup(owner_fight: Node, event_config: Dictionary) -> void:
	super(owner_fight, event_config)
	var rules: Dictionary = event_config.get("rules", {}) as Dictionary
	_duration = float(rules.get("duration_s", FightTypes.FIGHT_DURATION_S))
	_tick = 0
	_finished = false
	_finish_time = -1.0
	_chaser = null
	_chaser_ai = null
	_chaser_entered = false
	_start_condition = {}
	_armed = false


func arena_scene_path() -> String:
	return ARENA_SCENE


func physics_tick(delta: float) -> void:
	super(delta)
	if not _armed:
		_arm()
	_tick += 1
	if not _finished and _reached_pad():
		_finished = true
		_finish_time = time_s
	if not _chaser_entered and not _finished and time_s >= CHASER_ENTER_S:
		_send_in_chaser()
	_drive_chaser()


func is_over() -> bool:
	return _finished or time_s >= _duration


func result() -> Dictionary:
	var taken := _damage_taken()
	var run_time := _finish_time if _finished else _duration
	var score := 0
	if _finished:
		score = int(maxf(0.0,
			round((_duration - run_time) * SCORE_PER_SECOND - taken * SCORE_PER_CONDITION)))
	return {
		"score": score,
		"cleared": _finished,
		"time_s": run_time,
		"damage": taken,
		"details": {
			"time_s": run_time,
			"damage": taken,
			"chaser_entered": _chaser_entered,
			"chaser": CHASER_BOSS,
		},
	}


func hud_lines() -> Array[String]:
	var lines: Array[String] = []
	if _finished:
		lines.append("PAD REACHED %0.1f s" % _finish_time)
	else:
		lines.append("REACH THE PAD")
		lines.append(clock(_duration - time_s))
		if _chaser_entered:
			lines.append("BANDSAW IS BEHIND YOU")
		else:
			lines.append("BANDSAW IN %d" % int(ceil(maxf(0.0, CHASER_ENTER_S - time_s))))
	return lines


# --------------------------------------------------------------------------------------

func _reached_pad() -> bool:
	var player := player_bot()
	if player == null:
		return false
	var run := arena()
	if run != null and run.has_method("bot_on_pad") and bool(run.call("bot_on_pad", player)):
		return true
	if run != null and run.has_method("on_finish_pad"):
		return bool(run.call("on_finish_pad", bot_position(player)))
	return bot_position(player).x >= 9.8


func _damage_taken() -> float:
	var player := player_bot()
	if player == null or not player.has_method("condition") or _start_condition.is_empty():
		return 0.0
	return Rules.condition_removed(_start_condition, player.call("condition") as Dictionary)


## Everything that needs the ARENA or the MACHINES happens here, on the first tick, not in
## `setup`. `fight.gd` builds the event before it builds the world (`_load_event` runs from
## `start_fight` ahead of `_build_world` and `_spawn_bots`), so at `setup` time `arena()` is
## still the last fight's arena and `bots()` is still the last fight's machines. Reading
## either one there is reading the wrong world. `setup` is for the configuration; this is
## for the fight.
func _arm() -> void:
	_armed = true
	var player := player_bot()
	if player != null and player.has_method("condition"):
		_start_condition = player.call("condition") as Dictionary
	# The spare machine, parked and frozen in the bay behind the pad.
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


func _send_in_chaser() -> void:
	_chaser_entered = true
	var player := player_bot()
	if player == null or not player.is_inside_tree():
		return
	var holder := player.get_parent()
	var packed := load(BOT_SCENE) as PackedScene
	if holder == null or packed == null:
		return
	var run := arena()
	var gate := Vector3(-11.7, 0.25, 0.0)
	var facing := Vector3.RIGHT
	if run != null and run.has_method("chaser_gate"):
		gate = run.call("chaser_gate") as Vector3
		facing = run.call("chaser_facing") as Vector3
	var bot: Node = packed.instantiate()
	bot.name = "Chaser"
	holder.add_child(bot)
	if bot.has_method("setup"):
		bot.call("setup", BossAIScript.build_for(CHASER_BOSS, CHASER_ID), 1, rng())
	if bot.has_method("place_at"):
		bot.call("place_at", gate, facing)
	_chaser = bot
	_chaser_ai = BossAIScript.new(rng(), CHASER_BOSS)
	_chaser_ai.gate = gate


func _drive_chaser() -> void:
	if _chaser == null or not is_instance_valid(_chaser) or _chaser_ai == null:
		return
	var player := player_bot()
	if player == null:
		return
	if not _chaser.has_method("apply_input"):
		return
	_chaser.call("apply_input", _chaser_ai.think(_chaser, player, _chaser_context()))


func _chaser_context() -> Dictionary:
	var run := arena()
	var helpers: Dictionary = {}
	if run != null and run.has_method("hazard_helpers"):
		helpers = run.call("hazard_helpers") as Dictionary
	return {
		"tick": _tick,
		"spike_centre": run.call("spike_patch_centre") if run != null \
			and run.has_method("spike_patch_centre") else Vector3.ZERO,
		"spike_rise_in_s": float(helpers.get("next_danger_in_s", 999.0)),
		"hazard": helpers,
		"hazards": helpers.get("danger_positions", []),
	}
