extends "res://tests/hitstop_test.gd"
## BOOST and UNSTICK (wave B pacing, docs/wave-b-boost-notes.md).
##   Godot --headless --path Arena --script tests/boost_test.gd
##
## 1. The record: a seven wide replay row carries the boost level, a six wide one (recorded
##    before the boost) replays with none.
## 2. The dash in a real fight: the edge fires it once, the cooldown refuses a second press
##    inside BOOST_COOLDOWN_TICKS, it fires again once charged, and a dash goes further than
##    the same stick without one.
## 3. UNSTICK: a machine driving into a wall far from the opponent is nudged inside a few
##    seconds; the same machine with the opponent held against its tail (a pin) is not. The
##    referee's lock-up break comes at LOCKUP_S (3 s), once.
## 4. Bit exactness with the player boosting: hitstop_test's whole matrix (hit-stop on, 0.25x,
##    0.5x, a seek) on a script that presses BOOST every 200 ticks. The boost and nudge counts
##    are folded into the compared hash, so a replay that dashed on a different tick fails.

var _boost_counts: Array = []
## Every 175 ticks. It was 200 (6 damage events on 1463099, 150 and 300 gave none once the
## arenas escalated); fitment pass 2 carried the box's drum 0.17 m further out and 200, 225
## and 250 then gave none, 175 gives 2. If a later change empties it, pick another period.
const BOOST_EVERY := 175


func _run() -> void:
	await process_frame
	_test_record()
	await _test_dash()
	await _test_unstick()
	await _test_lockup()
	await super._run()


func _test_record() -> void:
	var row := FightTypes.replay_row(7, {"heading": Vector2(0.5, 0.0), "fire": false,
		"secondary": false, "boost": true})
	_check(row.size() == 7 and int(row[6]) == 1, "a replay row is seven wide with boost in column 7")
	var rec := ReplayRecorder.new()
	rec.play([row, [8, 0.0, 0.0, 0, 0, 0.0]])
	_check(bool(rec.input_for(7).get("boost", false)), "a seven wide row replays its boost")
	_check(not bool(rec.input_for(8).get("boost", true)), "a six wide row replays with no boost")
	_check(not bool(FightTypes.empty_input().get("boost", true)), "the empty input does not boost")


## One fight, the player driving straight at 0.6 stick: BOOST pressed at ticks 30 (fires),
## 60 (inside the cooldown: refused) and 30 + cooldown + 5 (fires again).
func _test_dash() -> void:
	var config := _config()
	config["rules"] = {"duration_s": 90, "ko_count_s": 10, "mode": "test"}
	config["debug"] = {"opponent_ai": "idle"}
	var cool := int(Bot.BOOST_COOLDOWN_TICKS)
	var presses := [30, 60, 30 + cool + 5]
	var plain := await _dash_run(config, [])
	var dashed := await _dash_run(config, presses)
	_check(int(dashed["boosts"]) == 2,
		"three presses, one inside the cooldown, fire exactly two dashes (%d)" % int(dashed["boosts"]))
	_check(int(plain["boosts"]) == 0, "no press, no dash")
	_check(float(dashed["dist_60"]) > float(plain["dist_60"]) + 0.3,
		"a dash covers more ground in the first second (%.2f m against %.2f m)"
		% [float(dashed["dist_60"]), float(plain["dist_60"])])
	_check(float(dashed["peak"]) > float(plain["peak"]) * 1.25,
		"and runs faster than the drive's top speed (peak %.2f against %.2f m/s)"
		% [float(dashed["peak"]), float(plain["peak"])])


func _dash_run(config: Dictionary, presses: Array) -> Dictionary:
	if _fight == null:
		_fight = (load(FIGHT_SCENE) as PackedScene).instantiate()
		root.add_child(_fight)
		await process_frame
	var rows: Array = []
	for tick in range(1, 400):
		var b := 0
		for p in presses:
			if tick >= int(p) and tick < int(p) + 3:
				b = 1
		rows.append([tick, 0.0, -0.6, 0, 0, 0.0, b])
	_fight.call("start_fight", config.duplicate(true), rows)
	var bot: Node = (_fight.get("_bots") as Array)[0]
	var chassis: RigidBody3D = bot.get("chassis")
	var start := Vector3.ZERO
	var peak := 0.0
	var dist_60 := 0.0
	var frames := 0
	while frames < 6000 and int(_fight.get("_tick")) < 380:
		await physics_frame
		frames += 1
		var t := int(_fight.get("_tick"))
		if t <= 29:
			start = chassis.global_position
			continue
		var v := chassis.linear_velocity
		peak = maxf(peak, Vector2(v.x, v.z).length())
		if t == 90:
			dist_60 = Vector2(chassis.global_position.x - start.x,
				chassis.global_position.z - start.z).length()
	return {"boosts": int(bot.get("boosts_fired")), "peak": peak, "dist_60": dist_60}


## hitstop_test's spiral with BOOST pressed for 3 ticks every BOOST_EVERY.
func _scripted_inputs() -> Array:
	var rows: Array = super._scripted_inputs()
	for row_variant in rows:
		var row: Array = row_variant
		row.append(0.0)
		row.append(1 if int(row[0]) % BOOST_EVERY < 3 else 0)
	return rows


func _simulate(config: Dictionary, script: Array, opts: Dictionary) -> Dictionary:
	var snap: Dictionary = await super._simulate(config, script, opts)
	var bots: Array = _fight.get("_bots") as Array
	var boosts := [int(bots[0].get("boosts_fired")), int(bots[1].get("boosts_fired"))]
	_boost_counts.append(boosts)
	snap["hash"] = "%s|boosts %d/%d|nudges %d|breaks %d" % [str(snap["hash"]), boosts[0],
		boosts[1], int(_fight.get("unstick_nudges")), int(_fight.get("lockup_breaks"))]
	return snap


func _finish() -> void:
	if not _boost_counts.is_empty():
		var first: Array = _boost_counts[0]
		_check(int(first[0]) >= 3, "the player dashed in the compared fight (%d)" % int(first[0]))
		print("NOTE  boosts per run (player/AI): ", str(_boost_counts))
	super._finish()


func _fight_mode_config() -> Dictionary:
	var config := _config()
	config["rules"] = {"duration_s": 90, "ko_count_s": 10, "mode": "fight"}
	config["debug"] = {"opponent_ai": "idle"}
	return config


## The player sits 0.7 m off the -x wall facing it and drives into it for 5 s.
func _wall_run(foe_behind: bool) -> Dictionary:
	if _fight == null:
		_fight = (load(FIGHT_SCENE) as PackedScene).instantiate()
		root.add_child(_fight)
		await process_frame
	var rows: Array = []
	for tick in range(1, 330):
		rows.append([tick, -1.0, 0.0, 0, 0, 0.0, 0])
	_fight.call("start_fight", _fight_mode_config(), rows)
	var bots: Array = _fight.get("_bots") as Array
	var half := float(_fight.call("_arena_half_extent"))
	var frames := 0
	while int(_fight.get("state")) != 2 and frames < 2000:
		await physics_frame
		frames += 1
	_fight.call("set_down", bots[0], Vector3(-half + 0.7, 0.3, 0.0), Vector3.LEFT)
	var foe_at := Vector3(-half + 1.45, 0.3, 0.0) if foe_behind else Vector3(half - 1.0, 0.3, half - 1.0)
	_fight.call("set_down", bots[1], foe_at, Vector3.LEFT)
	var first_nudge := -1
	while frames < 8000 and int(_fight.get("_tick")) < 320 and int(_fight.get("state")) == 2:
		await physics_frame
		frames += 1
		if first_nudge < 0 and int(_fight.get("unstick_nudges")) > 0:
			first_nudge = int(_fight.get("_tick"))
	return {"nudges": int(_fight.get("unstick_nudges")), "first": first_nudge}


func _test_unstick() -> void:
	var free := await _wall_run(false)
	_check(int(free["nudges"]) >= 1,
		"a machine driving into the wall, nobody near it, is nudged (%d, first at tick %d)"
		% [int(free["nudges"]), int(free["first"])])
	var pinned := await _wall_run(true)
	_check(int(pinned["nudges"]) == 0,
		"with the opponent against its tail it is held, and never nudged (%d)" % int(pinned["nudges"]))


## Two still machines 1.2 m apart, nobody driving: one referee break, at LOCKUP_S after the
## half second immobility window, and not before.
func _test_lockup() -> void:
	var rows: Array = []
	for tick in range(1, 330):
		rows.append([tick, 0.0, 0.0, 0, 0, 0.0, 0])
	_fight.call("start_fight", _fight_mode_config(), rows)
	var bots: Array = _fight.get("_bots") as Array
	var frames := 0
	while int(_fight.get("state")) != 2 and frames < 2000:
		await physics_frame
		frames += 1
	_fight.call("set_down", bots[0], Vector3(-0.6, 0.3, 0.0), Vector3.RIGHT)
	_fight.call("set_down", bots[1], Vector3(0.6, 0.3, 0.0), Vector3.LEFT)
	var at_150 := -1
	while frames < 8000 and int(_fight.get("_tick")) < 320 and int(_fight.get("state")) == 2:
		await physics_frame
		frames += 1
		if int(_fight.get("_tick")) == 150:
			at_150 = int(_fight.get("lockup_breaks"))
	_check(at_150 == 0, "no referee break inside LOCKUP_S (%d at 2.5 s)" % at_150)
	_check(int(_fight.get("lockup_breaks")) == 1,
		"one referee break by 5.3 s (%d; LOCKUP_S %.1f)"
		% [int(_fight.get("lockup_breaks")), float(_fight.get("LOCKUP_S"))])
