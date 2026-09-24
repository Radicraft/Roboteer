extends SceneTree
## Hit-stop, slow motion and the slow replay speeds change NOTHING in the fight (combat feel
## wave, docs/wave-a-combat-notes.md section 2).
##   Godot --headless --path Arena --script tests/hitstop_test.gd
##
## Every one of them is the same mechanism (fight/hit_stop.gd): engine iterations in which the
## simulation is not taken. The claim is that the fight is tick for tick the same fight, so
## this runs ONE fixture fight several ways and compares a hash of every damage event (the
## fight tick it landed on, victim, part, severity to six decimals, detached) and both chassis
## transforms at the last tick:
##
##   A  hit-stop off                                   the reference
##   B  hit-stop on through the real FX tiers, PLUS a forced 120 ms stop on every damage
##      event and a slow motion on every part that comes off (far more holding than a
##      player ever sees)
##   C  the same fight as a replay at 0.25x            (docs/aaa/combat-feel.md B1)
##   D  the same fight as a replay at 0.5x
##   E  the same fight as a replay SEEKED to mid fight, then run on at 1x
##
## A spinner against the house flipper, the player holding the weapon, so the fight has
## blows, a spread of feel tiers and (usually) a part coming off.

const FIGHT_SCENE := "res://fight/fight.tscn"
const BOT_SCENE := "res://bot/bot.tscn"
const FIXTURE := "res://fight/fixtures/stage3_config.json"

const TARGET_TICK := 1200
const SEEK_TICK := 600
const EPSILON := 1.0e-4
const FRAME_BUDGET := 40000

var _failures := 0
var _checks := 0
var _fight: Node = null


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	if not ResourceLoader.exists(BOT_SCENE) or not ResourceLoader.exists(FIGHT_SCENE):
		print("SKIP  hitstop: the fight or bot scene is absent")
		quit(0)
		return
	var config := _config()
	if config.is_empty():
		_check(false, "the fixture loads")
		_finish()
		return
	var script := _scripted_inputs()

	var a := await _simulate(config, script, {"hitstop": false})
	var b := await _simulate(config, script, {"hitstop": true, "force": true})
	var c := await _simulate(config, script, {"hitstop": true, "replay": true, "speed": 0.25})
	var d := await _simulate(config, script, {"hitstop": true, "replay": true, "speed": 0.5})
	var e := await _simulate(config, script, {"hitstop": true, "replay": true, "seek": SEEK_TICK})

	_check(int(a["events"]) > 0, "the reference fight has damage events to compare (%d)" % int(a["events"]))
	_check(int(b["stops"]) > 0, "the hit-stop run really held the clock (%d stops, %d held iterations)"
		% [int(b["stops"]), int(b["held"])])
	_check(int(c["held"]) > 0, "the 0.25x replay really held iterations (%d)" % int(c["held"]))
	print("NOTE  reference: %d events, hash %s, ended tick %d (%s)"
		% [int(a["events"]), str(a["hash"]), int(a["tick"]), str(a["state"])])
	for pair in [[b, "hit-stop on (FX tiers + a forced stop on every event)"],
			[c, "the replay at 0.25x"], [d, "the replay at 0.5x"],
			[e, "the replay seeked to tick %d" % SEEK_TICK]]:
		var other: Dictionary = pair[0]
		var tag: String = pair[1]
		_check(int(other["tick"]) == int(a["tick"]),
			"%s stops on the same tick (%d and %d)" % [tag, int(a["tick"]), int(other["tick"])])
		_check(str(other["hash"]) == str(a["hash"]),
			"%s: identical damage event hash (%s, %d events)" % [tag, str(other["hash"]), int(other["events"])])
		for i in 2:
			var ta: Transform3D = (a["transforms"] as Array)[i]
			var tb: Transform3D = (other["transforms"] as Array)[i]
			var drift := (ta.origin - tb.origin).length()
			_check(drift <= EPSILON, "%s: bot %d ends where it did (drift %.9f m)" % [tag, i, drift])
	_check(is_equal_approx(Engine.time_scale, 1.0), "nothing left the engine clock scaled")
	_finish()


func _simulate(config: Dictionary, script: Array, opts: Dictionary) -> Dictionary:
	if _fight == null:
		_fight = (load(FIGHT_SCENE) as PackedScene).instantiate()
		root.add_child(_fight)
		await process_frame
	var fight: Node = _fight
	var hs: HitStop = fight.call("hit_stop")
	var replay := bool(opts.get("replay", false))
	if replay:
		var replay_config := config.duplicate(true)
		replay_config["replay"] = {"seed": config.get("seed", 0), "tick_hz": 60, "inputs": script}
		fight.call("start_fight", replay_config)
		if opts.has("speed"):
			fight.call("replay_control", {"action": "speed", "value": float(opts["speed"])})
		if opts.has("seek"):
			fight.call("replay_control", {"action": "seek", "value": int(opts["seek"])})
	else:
		fight.call("start_fight", config.duplicate(true), script)
	hs.enabled = bool(opts.get("hitstop", true))
	fight.call("halt_at_tick", TARGET_TICK)
	var stops_at_start := hs.stops_taken
	var held_at_start := hs.held_iterations
	var events: Array = []
	var force := bool(opts.get("force", false))
	for bot in (fight.get("_bots") as Array):
		if bot == null:
			continue
		bot.connect("damage_event", func(info: Dictionary) -> void:
			events.append("%d|%s|%s|%.6f|%s" % [int(fight.get("_tick")), str(info.get("victim")),
				str(info.get("part")), float(info.get("severity")), str(bool(info.get("detached")))])
			if force:
				hs.request_stop(120.0)
				if bool(info.get("detached", false)):
					hs.request_slowmo(0.4))
	var frames := 0
	while frames < FRAME_BUDGET:
		if int(fight.get("_tick")) >= TARGET_TICK or int(fight.get("state")) == 3:
			await process_frame      # let a pending hold drain, then snapshot on the tick
			break
		await process_frame
		frames += 1
	var snap := {
		"tick": int(fight.get("_tick")),
		"state": str(fight.call("_state_name", int(fight.get("state")))),
		"events": events.size(),
		"hash": "|".join(events).md5_text(),
		"stops": hs.stops_taken - stops_at_start,
		"held": hs.held_iterations - held_at_start,
		"transforms": [Transform3D(), Transform3D()],
	}
	var bots: Array = fight.get("_bots") as Array
	for i in 2:
		if bots[i] != null and bots[i].get("chassis") != null:
			(snap["transforms"] as Array)[i] = (bots[i].get("chassis") as Node3D).global_transform
	# Leave the node clean for the next run: any hold still pending is dropped by start_fight.
	fight.call("halt_at_tick", -1)
	if replay:
		fight.call("replay_control", {"action": "speed", "value": 1.0})
	return snap


func _config() -> Dictionary:
	if not FileAccess.file_exists(FIXTURE):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	if not parsed is Dictionary:
		return {}
	var config: Dictionary = parsed
	var player: Dictionary = (config["bots"] as Array)[0]
	player["chassis"] = "box"
	player["weapon"] = "vertical_spinner"
	config["rules"] = {"duration_s": 90, "ko_count_s": 10, "mode": "fight"}
	return config


## Drive at the middle of the arena in a slow spiral with the spinner held, so the house AI
## (a flipper) comes to it and the drum bites.
func _scripted_inputs() -> Array:
	var rows: Array = []
	for tick in range(1, TARGET_TICK + 1):
		var angle := float(tick) * 0.011
		var r := 0.55 + 0.35 * sin(float(tick) * 0.005)
		rows.append([tick, snappedf(cos(angle) * r, 0.0001), snappedf(sin(angle) * r, 0.0001), 1, 0])
	return rows


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
		print("PASS  hitstop: %d checks, 0 failures" % _checks)
		quit(0)
	else:
		print("FAIL  hitstop: %d checks, %d failures" % [_checks, _failures])
		quit(1)
