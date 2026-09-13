extends SceneTree
## Headless determinism test (docs/stage3-spec.md §7).
##   Godot --headless --path Arena --script tests/determinism_test.gd
##
## Runs the real fight scene THREE times from the same seed, through the shipping path:
## one Fight node, re-armed with a new fight_config for each fight, exactly as the Swift
## shell does it. Each run is fed the same scripted input list through the replay recorder
## and every chassis transform, every condition() dictionary, the scrap tallies and the
## recorded replay rows must match at tick TARGET_TICK.
##
## Three runs and not two on purpose: the bugs this catches are all "the first fight in a
## process is different", so two runs can agree by accident where three cannot.
##
## The AI's input is deliberately NOT in the script: it is regenerated from the shared
## seed, so this also proves the AI consumes the RNG at the same cadence both times.
##
## If agent P's bot scene is absent there is nothing to simulate: prints SKIP, exits 0.

const FIGHT_SCENE := "res://fight/fight.tscn"
const BOT_SCENE := "res://bot/bot.tscn"
const FIXTURE := "res://fight/fixtures/stage3_config.json"

const RUNS := 3
const TARGET_TICK := 1800
## Divergence in a deterministic run is exactly zero; a nondeterministic one drifts by
## metres in half a minute. This tolerance only forgives the printf of a float.
const EPSILON := 1.0e-4
## Frames to allow per run before calling it hung. The countdown is 180 ticks.
const FRAME_BUDGET := 12000

var _failures := 0
var _checks := 0

var _fight: Node = null


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame

	if not ResourceLoader.exists(BOT_SCENE):
		print("SKIP  determinism: %s is absent, nothing to simulate" % BOT_SCENE)
		quit(0)
		return
	if not ResourceLoader.exists(FIGHT_SCENE):
		print("SKIP  determinism: %s is absent" % FIGHT_SCENE)
		quit(0)
		return

	var config := _fixture()
	if config.is_empty():
		_check(false, "the desktop QA fixture loads")
		_finish()
		return
	_check(true, "the desktop QA fixture loads")

	var script := _scripted_inputs()
	_check(script.size() == TARGET_TICK, "the scripted input list covers %d ticks" % TARGET_TICK)

	var runs: Array = []
	for i in RUNS:
		runs.append(await _simulate(config, script))
	_check(_fight != null, "all %d fights ran on ONE Fight node, re-armed between them" % RUNS)

	var empty := false
	for run in runs:
		if (run as Dictionary).is_empty():
			empty = true
	if empty:
		_check(false, "every run produced a snapshot")
		_finish()
		return
	_check(true, "every run produced a snapshot")

	var first: Dictionary = runs[0]
	for r in range(1, RUNS):
		var other: Dictionary = runs[r]
		var tag := "fight %d against fight 1" % (r + 1)

		_check(int(first["tick"]) == int(other["tick"]),
			"%s stopped on the same tick (%d and %d)" % [tag, int(first["tick"]), int(other["tick"])])
		_check(str(first["state"]) == str(other["state"]),
			"%s is in the same state (%s and %s)" % [tag, str(first["state"]), str(other["state"])])

		for i in 2:
			var a: Transform3D = (first["transforms"] as Array)[i]
			var b: Transform3D = (other["transforms"] as Array)[i]
			var drift := (a.origin - b.origin).length()
			_check(drift <= EPSILON,
				"%s: bot %d chassis position matches at tick %d (drift %0.9f m)"
					% [tag, i, int(first["tick"]), drift])
			var basis_drift := 0.0
			for axis in 3:
				basis_drift = maxf(basis_drift, (a.basis[axis] - b.basis[axis]).length())
			_check(basis_drift <= EPSILON,
				"%s: bot %d chassis orientation matches (drift %0.9f)" % [tag, i, basis_drift])
			_check(_conditions_match((first["conditions"] as Array)[i], (other["conditions"] as Array)[i]),
				"%s: bot %d condition() matches" % [tag, i])

		_check(first["scrap"] == other["scrap"],
			"%s: the scrap tallies match (%s and %s)" % [tag, str(first["scrap"]), str(other["scrap"])])
		_check(first["replay"] == other["replay"], "%s: the same replay rows were recorded" % tag)
		_check(str(first["outcome"]) == str(other["outcome"]),
			"%s: the same outcome (%s)" % [tag, str(first["outcome"])])
		_check(int(first["damage_events"]) == int(other["damage_events"]),
			"%s: the same number of damage events (%d and %d)"
				% [tag, int(first["damage_events"]), int(other["damage_events"])])

	if int(first["tick"]) < TARGET_TICK:
		print("NOTE  the fight resolved at tick %d, before tick %d; every run is compared there"
			% [int(first["tick"]), TARGET_TICK])

	_finish()


## One fight, through the shipping re-arm path: the same Fight node receives a new
## configuration and builds itself a brand new World3D for it (fight.gd `_build_world`).
## The Swift shell does exactly this on every tap of "Fight", on one never restarted
## Godot process, so this is the path a replay has to reproduce.
func _simulate(config: Dictionary, script: Array) -> Dictionary:
	if _fight == null:
		_fight = (load(FIGHT_SCENE) as PackedScene).instantiate()
		root.add_child(_fight)
		await process_frame
	var fight: Node = _fight

	fight.call("start_fight", config.duplicate(true), script)
	var damage_events := [0]
	for bot in (fight.get("_bots") as Array):
		if bot != null:
			bot.connect("damage_event", func(_info: Dictionary) -> void:
				damage_events[0] += 1)

	var frames := 0
	while frames < FRAME_BUDGET:
		if int(fight.get("_tick")) >= TARGET_TICK:
			break
		if int(fight.get("state")) == 3:      # State.RESULT
			break
		await process_frame
		frames += 1

	var snapshot := {
		"tick": int(fight.get("_tick")),
		"state": str(fight.call("_state_name", int(fight.get("state")))),
		"transforms": [Transform3D(), Transform3D()],
		"conditions": [{}, {}],
		"scrap": (fight.get("_scrap") as Array).duplicate(),
		"replay": [],
		"outcome": str(fight.get("_hud_banner")),
		"damage_events": damage_events[0],
	}
	var bots: Array = fight.get("_bots") as Array
	for i in 2:
		var bot: Node = bots[i]
		if bot == null:
			continue
		var chassis: Node3D = bot.get("chassis") as Node3D
		if chassis != null and chassis.is_inside_tree():
			(snapshot["transforms"] as Array)[i] = chassis.global_transform
		if bot.has_method("condition"):
			(snapshot["conditions"] as Array)[i] = (bot.call("condition") as Dictionary).duplicate(true)
	var recorder: Object = fight.get("_recorder")
	if recorder != null:
		snapshot["replay"] = (recorder.call("to_inputs") as Array).duplicate(true)
	return snapshot


## A fixed script that keeps the player driving and firing, so the run exercises the
## drive, the flipper and the collisions rather than two bots sitting still.
func _scripted_inputs() -> Array:
	var rows: Array = []
	for tick in range(1, TARGET_TICK + 1):
		var angle := float(tick) * 0.013
		var heading := Vector2(cos(angle), sin(angle))
		var fire := 1 if tick % 150 == 0 else 0
		var secondary := 1 if tick % 400 == 0 else 0
		rows.append([tick, snappedf(heading.x, 0.0001), snappedf(heading.y, 0.0001), fire, secondary])
	return rows


func _fixture() -> Dictionary:
	if not FileAccess.file_exists(FIXTURE):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	return parsed as Dictionary if parsed is Dictionary else {}


func _conditions_match(a: Dictionary, b: Dictionary) -> bool:
	if a.keys().size() != b.keys().size():
		return false
	for key in a.keys():
		if not b.has(key):
			return false
		var va: Variant = a[key]
		var vb: Variant = b[key]
		if va is Dictionary and vb is Dictionary:
			if not _conditions_match(va as Dictionary, vb as Dictionary):
				return false
		elif va is Array and vb is Array:
			var aa: Array = va as Array
			var ab: Array = vb as Array
			if aa.size() != ab.size():
				return false
			for i in aa.size():
				if absf(float(aa[i]) - float(ab[i])) > EPSILON:
					return false
		elif absf(float(va) - float(vb)) > EPSILON:
			return false
	return true


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS  ", label)
	else:
		_failures += 1
		printerr("FAIL  ", label)
		print("FAIL  ", label)


func _finish() -> void:
	print("")
	if _failures == 0:
		print("PASS  determinism: %d checks, 0 failures" % _checks)
		quit(0)
	else:
		print("FAIL  determinism: %d checks, %d failures" % [_checks, _failures])
		quit(1)
