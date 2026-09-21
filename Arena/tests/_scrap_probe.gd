extends SceneTree
## MEASUREMENT PROBE, not a test (the leading underscore keeps it out of the suite):
## what the career scrap ledger actually pays over a real three minute fight, per weapon.
##   Godot --headless --path Arena --script tests/_scrap_probe.gd
##
## Why it exists. `scrap_test.gd` proves the arithmetic; only a fight in the physics world
## can say whether `damage_full` of 200 pays 30 scrap or 190, and the owner cannot tune a
## dial he has no numbers for. Every row below is one 180 s fight between two AI machines
## in the Yard with the same weapon on both, driven exactly the way `ai_physics_test.gd`
## drives its fights (real arena, real bots, the same fixed driver order fight.gd uses).
##
## It prints, per weapon: the fraction of each machine's condition removed, the weapon hits
## counted the way the fight counts them (a fire that produced damage inside 0.35 s), the
## parts each machine lost, and the Series 1 scrap breakdown that follows from all of it.

const BOT_SCENE := "res://bot/bot.tscn"
const ARENA_SCENE := "res://arena/yard.tscn"
const OpponentAIScript := preload("res://ai/opponent_ai.gd")
const Rules := preload("res://fight/rules.gd")

## A full career round. Both dials can be overridden on the command line, because six
## 180 s fights is a quarter of an hour of wall clock and a comparison across weapons does
## not always need the whole round:
##   Godot --headless --path Arena --script tests/_scrap_probe.gd -- --seconds=60 --weapons=saw,axe
const DEFAULT_FIGHT_S := 180.0
const SEED := 20260917

var _fight_s := DEFAULT_FIGHT_S
var _fight_ticks := int(DEFAULT_FIGHT_S * 60.0)

## Series 1's scrap rules, from Shared/parts.json `progression.series[0].scrap`.
const SCRAP_RULES := {
	"base": 120, "damage_full": 200, "survivor": 60, "survivor_min": 0.7, "flawless": 100,
}

const WEAPONS := ["flipper", "horizontal_spinner", "vertical_spinner", "axe", "saw", "crusher"]

const FIXTURE_BOT := {
	"id": "bot", "name": "Probe", "controller": "ai",
	"chassis": "wedge", "drive": "4wd", "weapon": "flipper",
	"utility": ["srimech"],
	"armour": {
		"front": {"material": "steel", "thickness": 2},
		"sides": {"material": "steel", "thickness": 2},
		"rear": {"material": "steel", "thickness": 2},
		"top": {"material": "steel", "thickness": 2},
	},
	"damage": {
		"wheels": [1.0, 1.0, 1.0, 1.0], "weapon": 1.0,
		"armour": {"front": 1.0, "sides": 1.0, "rear": 1.0, "top": 1.0},
		"drive": 1.0, "core": 1.0,
	},
}

var _fired_at: Array = [-999, -999]
var _fire_counted: Array = [true, true]
var _hits: Array = [0, 0]
var _tick: int = 0


func _initialize() -> void:
	await _run()


func _run() -> void:
	var weapons := WEAPONS.duplicate()
	for arg_variant in OS.get_cmdline_user_args():
		var arg := str(arg_variant)
		if arg.begins_with("--seconds="):
			_fight_s = maxf(float(arg.substr(10)), 1.0)
		elif arg.begins_with("--weapons="):
			weapons = Array(arg.substr(10).split(","))
	_fight_ticks = int(_fight_s * 60.0)
	print("Roboteer scrap probe, Godot ", Engine.get_version_info()["string"])
	print("Yard, %d s, two AI machines, same weapon on both, seed %d" % [int(_fight_s), SEED])
	for weapon in weapons:
		await _fight(str(weapon))
	quit(0)


func _fight(weapon: String) -> void:
	var fight := Node3D.new()
	fight.name = "Fight"
	root.add_child(fight)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var arena: Node3D = (load(ARENA_SCENE) as PackedScene).instantiate()
	arena.name = "Arena"
	fight.add_child(arena)
	arena.call("setup", rng)

	var bots: Array = []
	for i in 2:
		var bot: Bot = (load(BOT_SCENE) as PackedScene).instantiate()
		bot.name = "Bot%d" % i
		fight.add_child(bot)
		var at: Vector3 = arena.call("spawn_position", i)
		var facing: Vector3 = arena.call("spawn_facing", i)
		bot.place_at(at, facing)
		var config := FIXTURE_BOT.duplicate(true)
		config["id"] = "bot-%d" % i
		config["weapon"] = weapon
		bot.setup(config, i, rng)
		bot.place_at(at, facing)
		bots.append(bot)

	_fired_at = [-999, -999]
	_fire_counted = [true, true]
	_hits = [0, 0]
	(bots[0] as Bot).weapon_fired.connect(_on_fired.bind(0))
	(bots[1] as Bot).weapon_fired.connect(_on_fired.bind(1))

	for _i in range(30):
		for bot_variant in bots:
			(bot_variant as Bot).apply_input(FightTypes.empty_input())
		await physics_frame

	var start: Array = [
		(bots[0] as Bot).condition().duplicate(true),
		(bots[1] as Bot).condition().duplicate(true),
	]
	var left: Array = [Rules.condition_total(start[0]), Rules.condition_total(start[1])]
	var drivers: Array = [
		OpponentAIScript.new(rng, OpponentAIScript.MODE_NORMAL, "regional",
			OpponentAIScript.TEMPERAMENT_BRAWLER),
		OpponentAIScript.new(rng, OpponentAIScript.MODE_NORMAL, "regional",
			OpponentAIScript.TEMPERAMENT_BRAWLER),
	]
	var half: float = arena.call("arena_half_extent")

	for tick in _fight_ticks:
		_tick = tick
		var ctx := {
			"tick": tick,
			"spike_centre": arena.call("spike_patch_centre"),
			"spike_rise_in_s": float(arena.call("seconds_to_spike_rise")),
			"arena_half_extent": half,
			"phase": FightTypes.PHASE_OPEN if float(tick) / 60.0 < FightTypes.ENDGAME_AT_S else FightTypes.PHASE_ENDGAME,
			"time_left_s": _fight_s - float(tick) / 60.0,
		}
		var helpers: Variant = arena.call("hazard_helpers")
		if helpers is Dictionary:
			ctx["hazard"] = helpers
			ctx["hazards"] = (helpers as Dictionary).get("danger_positions", [])
		var inputs: Array = [
			drivers[0].think(bots[0], bots[1], ctx),
			drivers[1].think(bots[1], bots[0], ctx),
		]
		(bots[0] as Bot).apply_input(inputs[0])
		(bots[1] as Bot).apply_input(inputs[1])
		await physics_frame

		# The fight's own hit rule, applied to condition rather than to damage events: a
		# fire that produced damage within WEAPON_HIT_WINDOW_S made contact, counted once.
		for i in 2:
			var foe := 1 - i
			var now := Rules.condition_total((bots[foe] as Bot).condition())
			if now < left[foe] - 0.0001:
				var since := float(tick - int(_fired_at[i])) / 60.0
				if not bool(_fire_counted[i]) and since <= Rules.WEAPON_HIT_WINDOW_S:
					_fire_counted[i] = true
					_hits[i] += 1
			left[foe] = now

	print("")
	print("  %s" % weapon.to_upper())
	for i in 2:
		var now: Dictionary = (bots[i] as Bot).condition()
		var foe := 1 - i
		var fraction := Rules.damage_fraction(start[foe], (bots[foe] as Bot).condition())
		var lines := Rules.scrap_breakdown(SCRAP_RULES, start[i], now,
			start[foe], (bots[foe] as Bot).condition(), i == 0)
		var lost: Array = []
		for row_variant in Rules.parts_lost(now, (bots[i] as Bot).damage.wheel_keys,
				(bots[i] as Bot).weapon_fault()):
			lost.append("%s %s" % [str((row_variant as Dictionary)["label"]),
				str((row_variant as Dictionary)["state"])])
		print("    bot-%d: removed %.3f of the other machine, %d hits landed, own condition %.2f of %.2f"
			% [i, fraction, int(_hits[i]), Rules.condition_total(now),
				Rules.condition_total(start[i])])
		print("           parts lost: %s" % ("none" if lost.is_empty() else ", ".join(lost)))
		print("           scrap (as if it won): base %d, damage %d, survivor %d, flawless %d, total %d"
			% [int(lines["base"]), int(lines["damage"]), int(lines["survivor"]),
				int(lines["flawless"]), int(lines["total"])])

	root.remove_child(fight)
	fight.queue_free()
	await physics_frame
	await physics_frame


func _on_fired(index: int) -> void:
	_fired_at[index] = _tick
	_fire_counted[index] = false
