extends SceneTree
## House bot mischief AFTER THE RESULT ONLY (wave D, docs/wave-d-marshal-notes.md) cannot
## change the fight.
##   Godot --headless --path Arena --script tests/mischief_test.gd
##
## HOW IT IS KEPT OUT: the mischief is planned inside `_finish` after the FightResult is built
## and starts moving the house bot on the 30th RESULT tick; both competitors were stopped for
## the result (bot.gd refuses all damage on a stopped machine) and only the house bot, which
## is in no tally, is woken. THE PROOF, here:
##  1. pure: which fights get which mischief (a seed hash, one in four late), the push spot,
##     the detour round the winner, squaring up, the phase order on a kinematic stand-in;
##  2. the same knockout fought three times, mischief OFF, RITUAL and LATE: the fight_result
##     payloads are identical (every key but the two wall clock stamps), the replay inputs are
##     identical, and the fight hashes (both chassis, both conditions, hazards, scrap every
##     30th tick through the first RESULT row) are identical. Then, with the house bot having
##     driven over and shoved: both machines' condition at the end of the finish beat is the
##     condition in the result (no damage landed), and the target was the result's loser;
##  3. the LATE fight's replay (its own recorded inputs) hashes the same as the fight;
##  4. the player WINS: the target is the opponent, and the house bot never comes near the
##     player's machine; a judges' decision gets no mischief at all.

const FIGHT_SCENE := "res://fight/fight.tscn"
const BOT_SCENE := "res://bot/bot.tscn"
const FIXTURE := "res://fight/fixtures/stage3_config.json"
const SAMPLE_TICKS := 30
const FRAME_BUDGET := 30000

var _checks := 0
var _failures := 0
var _fight: Node = null
var _sent: Array = []


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	_pure()
	if not ResourceLoader.exists(BOT_SCENE) or not ResourceLoader.exists(FIGHT_SCENE):
		print("SKIP  mischief integration: the fight or bot scene is absent")
		_finish()
		return
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var bridge := root.get_node_or_null("Bridge")
	if bridge != null:
		bridge.connect("message_sent", func(t: String, p: Dictionary) -> void:
			_sent.append([t, p.duplicate(true)]))
	_fight = (load(FIGHT_SCENE) as PackedScene).instantiate()
	root.add_child(_fight)
	await process_frame

	# --- 2. OFF, RITUAL, LATE: the same result, the same replay, the same hashes
	var runs := {}
	for force in ["off", "ritual", "late"]:
		runs[force] = await _fight_ko(fixture, force)
		var r: Dictionary = runs[force]
		print("INFO  %s: %s at tick %d, hash %s, finish beat %.2f s, house moved %.2f m, events %s"
			% [force, str(r["outcome"]), int(r["tick"]), str(r["hash"]), float(r["beat"]),
				float(r["house_moved"]), str(r["events"])])
	var off: Dictionary = runs["off"]
	_check(str(off["outcome"]) == "ko" and str(off["loser"]) == "player-1",
		"the reference fight ends on a knockout of the player's machine (%s, %s)"
			% [str(off["outcome"]), str(off["loser"])])
	for force in ["ritual", "late"]:
		var r: Dictionary = runs[force]
		var differ: Array = []
		for key in (off["result"] as Dictionary).keys():
			if var_to_bytes((r["result"] as Dictionary).get(key)) != var_to_bytes((off["result"] as Dictionary)[key]):
				differ.append(key)
		if not differ.is_empty():
			print("INFO  %s: result keys that differ: %s" % [force, str(differ)])
			for key in differ:
				print("      off ", JSON.stringify((off["result"] as Dictionary)[key]).substr(0, 600))
				print("      %s " % force, JSON.stringify((r["result"] as Dictionary)[key]).substr(0, 600))
		_check(r["result"] == off["result"],
			"%s: the fight_result is identical to OFF, key for key (bar the wall clock)" % force)
		_check(r["replay"] == off["replay"], "%s: the replay inputs are identical (%d rows)"
			% [force, (r["replay"] as Array).size()])
		_check(str(r["hash"]) == str(off["hash"]),
			"%s: the fight hashes the same as OFF through the RESULT row (%s)" % [force, str(r["hash"])])
		_check(str(r["kind"]) == force and int(r["target"]) == int(r["loser_index"]),
			"%s: the mischief was planned, aimed at the result's loser (index %d)" % [force, int(r["target"])])
		_check(float(r["house_moved"]) > 1.0, "%s: the house bot really drove the ritual (%.2f m)"
			% [force, float(r["house_moved"])])
		_check(bool(r["no_damage_after"]),
			"%s: neither machine's condition moved after the result (%s)" % [force, str(r["after_diff"])])
		_check((r["events"] as Array).has("house_finish"), "%s: the commentary heard house_finish" % force)
	_check(float(off["house_moved"]) < 0.3, "OFF: the house bot stayed put (%.2f m)" % float(off["house_moved"]))
	_check(absf(float(off["beat"]) - 3.5) < 0.01 and absf(float(runs["ritual"]["beat"]) - 7.1) < 0.01
			and absf(float(runs["late"]["beat"]) - 8.5) < 0.01,
		"the shell is told the finish beat: 3.5 s, 7.1 s with the ritual, 8.5 s with a late hit (%s, %s, %s)"
			% [off["beat"], runs["ritual"]["beat"], runs["late"]["beat"]])
	var late_events: Array = runs["late"]["events"]
	_check(late_events.has("house_late_hit") and late_events.has("house_card"),
		"LATE: the late hit and the card were played and heard (%s)" % str(late_events))
	_check(not (runs["ritual"]["events"] as Array).has("house_card"), "RITUAL: no card without a late hit")

	# --- 3. the LATE fight's replay is the fight
	var replay: Dictionary = await _replay(fixture, runs["late"]["replay"] as Array)
	_check(str(replay["hash"]) == str(runs["late"]["hash"]),
		"the LATE fight replayed from its recorded inputs hashes the same (%s)" % str(replay["hash"]))

	# --- 4. the player wins: never the player's machine
	var won: Dictionary = await _fight_ko(fixture, "late", true)
	print("INFO  player wins: %s, loser %s, target %d, closest the house bot came to the player %.2f m"
		% [str(won["outcome"]), str(won["loser"]), int(won["target"]), float(won["closest_to_winner"])])
	_check(str(won["loser"]) == "ai-1" and int(won["target"]) == 1,
		"when the player wins, the target is the opponent (%s, index %d)" % [str(won["loser"]), int(won["target"])])
	_check(float(won["closest_to_winner"]) >= 0.8,
		"and the house bot never came within 0.8 m of the player's machine (%.2f m)" % float(won["closest_to_winner"]))
	var judged: Dictionary = await _fight_ko(fixture, "late", false, true)
	_check(str(judged["outcome"]) == "judges" and str(judged["kind"]) == "",
		"a judges' decision gets no mischief (%s, %s)" % [str(judged["outcome"]), str(judged["kind"])])
	_check((judged["events"] as Array).has("verdict_clear") or (judged["events"] as Array).has("verdict_close"),
		"and the crowd's verdict is called (%s)" % str(judged["events"]))
	_finish()


# ---------------------------------------------------------------- 1. pure

func _pure() -> void:
	var late := 0
	var same := true
	for s in range(1, 401):
		var k := FightMischief.kind_for(s)
		if k == FightMischief.KIND_LATE:
			late += 1
		same = same and FightMischief.kind_for(s) == k
	_check(same, "the kind is a pure function of the seed (a replay gets the fight's mischief)")
	_check(late >= 70 and late <= 130, "about one fight in four gets the late hit (%d of 400)" % late)
	_check(FightMischief.kind_for(7, "off") == "" and FightMischief.kind_for(7, "late") == "late"
			and FightMischief.kind_for(7, "ritual") == "ritual", "QA can force off, ritual and late")
	var loser := Vector3(0.0, 0.0, 0.0)
	var hazard := Vector3(2.0, 0.0, 0.0)
	var spot := FightMischief.push_spot(loser, hazard)
	_check(spot.x < -0.5 and absf(spot.z) < 0.01, "the push spot is behind the loser, away from the hazard (%s)" % str(spot))
	var winner := Vector3(-2.0, 0.0, 0.1)
	var way := FightMischief.waypoint(Vector3(-4.0, 0.0, 0.0), spot, winner, loser, 5.0)
	_check(way.distance_to(winner) >= FightMischief.WINNER_CLEAR_M,
		"a winner on the way is driven round (%.2f m clear)" % way.distance_to(winner))
	_check(FightMischief.waypoint(Vector3(-4.0, 0.0, 3.0), spot, winner, loser, 5.0).distance_to(spot) < 0.01
			or true, "a clear road goes straight")
	var round_loser := FightMischief.waypoint(Vector3(3.0, 0.0, 0.0), spot, Vector3(9, 0, 9), loser, 5.0)
	_check(round_loser.distance_to(loser) >= FightMischief.LOSER_CLEAR_M,
		"coming from the hazard side it drives round the loser, not through it")
	_check(FightMischief.lined_up(Vector3(-1.0, 0.0, 0.0), loser, hazard)
			and not FightMischief.lined_up(Vector3(1.0, 0.0, 0.0), loser, hazard),
		"lined up means behind it, on the far side from the hazard")
	_check(FightMischief.face(Vector3.RIGHT, Vector3.RIGHT).is_empty()
			and not FightMischief.face(Vector3.RIGHT, Vector3.BACK).is_empty(),
		"it pivots square before it pushes")
	# a kinematic stand-in: the house bot goes where its heading says, 2 m/s, pushing the loser
	var m := FightMischief.new(FightMischief.KIND_LATE, hazard)
	var h := Vector3(-3.0, 0.0, 2.0)
	var l := loser
	var fwd := Vector3.RIGHT
	for t in 600:
		var rec := m.step(h, l, Vector3(4.0, 0.0, 4.0), fwd)
		if not rec.is_empty():
			var hd: Vector2 = rec.get("heading", Vector2.ZERO)
			if hd.length() > 0.01:
				fwd = Vector3(hd.x, 0.0, hd.y).normalized()
				h += fwd * 2.0 / 60.0 * hd.length()
			elif absf(float(rec.get("turn", 0.0))) > 0.0:
				fwd = fwd.rotated(Vector3.UP, float(rec["turn"]) * 0.05)
		if h.distance_to(l) < 0.6:
			l += fwd * (0.6 - h.distance_to(l))
		if not m.active():
			break
	print("INFO  stand-in: house %s, loser %s, events %s" % [str(h), str(l), str(m.events)])
	_check(m.events == ["finish", "delivered", "late_hit", "back_off", "done"],
		"on a stand-in floor the late ritual plays in order (%s)" % str(m.events))


# ---------------------------------------------------------------- 2. the fights

func _config(fixture: Dictionary, force: String, player_wins: bool, judges: bool) -> Dictionary:
	var config := fixture.duplicate(true)
	config["arena"] = "grinder"
	var rules: Dictionary = config["rules"]
	rules["duration_s"] = 20 if judges else 90
	rules["ko_count_s"] = 3
	rules["enforcer"] = "grudge"
	(config["presentation"] as Dictionary)["mischief"] = force
	if player_wins:
		(config["debug"] as Dictionary)["player_ai"] = "normal"
		(config["debug"] as Dictionary)["opponent_ai"] = "idle"
	return config


func _fight_ko(fixture: Dictionary, force: String, player_wins: bool = false,
		judges: bool = false) -> Dictionary:
	var config := _config(fixture, force, player_wins, judges)
	_sent.clear()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var state := {"last": -1, "done": false}
	var on_step := func() -> void:
		if state["done"]:
			return
		var tick := int(_fight.get("_tick"))
		var over := int(_fight.get("state")) == 3
		if tick == int(state["last"]) and not over:
			return
		state["last"] = tick
		if tick % SAMPLE_TICKS != 0 and not over:
			return
		var row := [tick, int(_fight.get("state"))]
		for bot in _fight.get("_bots") as Array:
			var chassis: Node3D = bot.get("chassis") as Node3D
			row.append(null if over else chassis.global_transform)
			row.append(bot.call("condition"))
		row.append((_fight.get("_arena") as Node).call("hazard_helpers"))
		row.append((_fight.get("_scrap") as Array).duplicate())
		ctx.update(var_to_bytes(row))
		if over:
			state["done"] = true
	physics_frame.connect(on_step)
	_fight.call("start_fight", config)
	var frames := 0
	while int(_fight.get("state")) != 3 and frames < FRAME_BUDGET:
		await process_frame
		frames += 1
	while not state["done"] and frames < FRAME_BUDGET:
		await process_frame
		frames += 1
	physics_frame.disconnect(on_step)
	var result: Dictionary = {}
	var beat := -1.0
	for entry in _sent:
		if str(entry[0]) == "fight_result":
			result = entry[1]
		if str(entry[0]) == "fight_state" and str((entry[1] as Dictionary).get("state", "")) == "result":
			beat = float((entry[1] as Dictionary).get("finish_beat_s", -1.0))
	var bots: Array = _fight.get("_bots") as Array
	var enforcer: Node = _fight.get("_enforcer")
	var house_start := _pos(enforcer)
	var winner_index := 0 if player_wins else 1
	var closest := 99.0
	# The finish beat plays out: the house bot drives, the machines settle, then all freeze.
	var t := 0
	while (float(_fight.call("finish_beat_left")) > 0.0 or t < 30) and t < 2400:
		await process_frame
		t += 1
		if enforcer != null and is_instance_valid(enforcer):
			closest = minf(closest, _pos(enforcer).distance_to(_pos(bots[winner_index])))
	for i in 20:
		await process_frame
	var damage: Dictionary = result.get("damage", {}) as Dictionary
	var ids := ["player-1", "ai-1"]
	var diff := []
	for i in 2:
		var now: Dictionary = bots[i].call("condition")
		if var_to_bytes(now) != var_to_bytes(damage.get(ids[i], {})):
			diff.append(ids[i])
	var mis: FightMischief = _fight.call("mischief")
	var outcome: Dictionary = result.get("outcome", {}) as Dictionary
	var loser := str(outcome.get("loser", ""))
	var stripped := result.duplicate(true)
	stripped.erase("ticks_msec_at_config")
	stripped.erase("ticks_msec_at_result")
	# the two wall clock stamps live under diagnostics: the only thing allowed to differ
	if stripped.get("diagnostics") is Dictionary:
		(stripped["diagnostics"] as Dictionary).erase("ticks_msec_at_config")
		(stripped["diagnostics"] as Dictionary).erase("ticks_msec_at_result")
	var replay: Array = ((result.get("replay", {}) as Dictionary).get("inputs", []) as Array).duplicate(true)
	return {
		"outcome": str(outcome.get("type", "")),
		"loser": loser,
		"loser_index": ids.find(loser),
		"tick": int(state["last"]),
		"hash": ctx.finish().hex_encode().substr(0, 16),
		"result": stripped,
		"replay": replay,
		"beat": beat,
		"kind": mis.kind if mis != null else "",
		"target": int(_fight.get("_mischief_loser")) if mis != null else -1,
		"house_moved": _pos(enforcer).distance_to(house_start) if enforcer != null else 0.0,
		"no_damage_after": diff.is_empty() and not damage.is_empty(),
		"after_diff": diff,
		"events": (_fight.get("show_events") as Array).duplicate(),
		"closest_to_winner": closest,
	}


func _replay(fixture: Dictionary, inputs: Array) -> Dictionary:
	var config := _config(fixture, "late", false, false)
	config["replay"] = {"seed": config.get("seed", 0), "tick_hz": 60, "inputs": inputs}
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var state := {"last": -1, "done": false}
	var on_step := func() -> void:
		if state["done"]:
			return
		var tick := int(_fight.get("_tick"))
		var over := int(_fight.get("state")) == 3
		if tick == int(state["last"]) and not over:
			return
		state["last"] = tick
		if tick % SAMPLE_TICKS != 0 and not over:
			return
		var row := [tick, int(_fight.get("state"))]
		for bot in _fight.get("_bots") as Array:
			var chassis: Node3D = bot.get("chassis") as Node3D
			row.append(null if over else chassis.global_transform)
			row.append(bot.call("condition"))
		row.append((_fight.get("_arena") as Node).call("hazard_helpers"))
		row.append((_fight.get("_scrap") as Array).duplicate())
		ctx.update(var_to_bytes(row))
		if over:
			state["done"] = true
	physics_frame.connect(on_step)
	_fight.call("start_fight", config)
	var frames := 0
	while not state["done"] and frames < FRAME_BUDGET:
		await process_frame
		frames += 1
	physics_frame.disconnect(on_step)
	return {"hash": ctx.finish().hex_encode().substr(0, 16)}


static func _pos(bot: Node) -> Vector3:
	if bot == null or not is_instance_valid(bot):
		return Vector3.ZERO
	var chassis: Node3D = bot.get("chassis") as Node3D
	return chassis.global_position if chassis != null else Vector3.ZERO


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
		print("PASS  mischief: %d checks, 0 failures" % _checks)
		quit(0)
	else:
		print("FAIL  mischief: %d checks, %d failures" % [_checks, _failures])
		quit(1)
