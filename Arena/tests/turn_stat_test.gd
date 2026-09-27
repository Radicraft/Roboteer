extends SceneTree
## D6 (docs/wave-a-drives-ai-notes.md): the "Turn" stat the shop, builder and scouting card
## show is scored on each drive's `measured_turn_rate` (Roboteer/Catalogue.swift), not on the
## `turn_rate` the arena feeds its drive code. The owner kept the pivot FEEL, so the display
## moved to the behaviour. This test keeps the two in step: it pivots every drive on the
## wedge, the box and the pyramid (the drives gauntlet pivot bench: turn held, 3 s, the
## last 2 s counted), divides out each hull's `turn_rate_factor`, and checks the mean is
## within TOLERANCE of the catalogue's measured number. If a drive, hull or scrub change
## moves how fast machines really turn, this fails and the number (and so the pips) is
## re-measured, rather than the shop quietly drifting away from the arena again.
##
## The long low hull is left out of the mean: on 4WD it does not pivot at all (0.6 deg/s,
## hull engineer, noted in the drives notes), which is a bug to fix, not a turn rate.
##   Godot --headless --fixed-fps 60 --path Arena --script tests/turn_stat_test.gd

const FIGHT_SCENE := "res://fight/fight.tscn"
const FIXTURE := "res://fight/fixtures/stage3_config.json"
const WG := preload("res://qa/weapons_gauntlet.gd")
const DRIVES := ["2wd", "4wd", "6wd", "tracks", "omni", "legs", "hover", "adaptive_tracks"]
const HULLS := ["wedge", "box", "pyramid"]
const TOLERANCE := 0.12

var _checks := 0
var _failures := 0


class Scripted extends OpponentAI:
	var input: Dictionary = {"heading": Vector2.ZERO, "fire": false, "secondary": false, "turn": 0.0}
	func think(_me: Object, _foe: Object, _ctx: Dictionary) -> Dictionary:
		return input.duplicate()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	# Both copies of the catalogue carry the same display numbers.
	var shared: Variant = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../Shared/parts.json")))
	for id in DRIVES:
		var row: Dictionary = PartsCatalogue.drive(id)
		_check(row.has("measured_turn_rate"), "%s has a measured_turn_rate" % id)
		if shared is Dictionary:
			var other: Dictionary = ((shared as Dictionary)["drive"] as Dictionary).get(id, {})
			_check(float(other.get("measured_turn_rate", -1.0)) == float(row.get("measured_turn_rate", -2.0)),
				"%s: Shared/parts.json says the same" % id)
	for id in DRIVES:
		var total := 0.0
		var parts: Array = []
		for hull in HULLS:
			var cfg: Dictionary = WG.legal_build("flipper", "player-1", "Subject", hull, id)
			if cfg.is_empty():
				continue
			var rate := await _pivot(cfg)
			var factor := float(PartsCatalogue.chassis(hull).get("turn_rate_factor", 1.0))
			total += rate / factor
			parts.append("%s %.2f" % [hull, rate / factor])
		var mean := total / float(maxi(parts.size(), 1))
		var shown := float(PartsCatalogue.drive(id).get("measured_turn_rate", 0.0))
		_check(parts.size() == HULLS.size() and absf(mean - shown) <= shown * TOLERANCE,
			"%s pivots at %.2f rad/s (%s), the Turn stat says %.1f" % [id, mean, ", ".join(parts), shown])
	_finish()


## rad/s about the vertical with the turn held, from rest, on the Yard, the opponent parked.
func _pivot(subject: Dictionary) -> float:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var opp: Dictionary = WG.opponent_for("flipper", "plain")
	opp["controller"] = "dummy"
	config["seed"] = 11
	config["arena"] = "yard"
	config["rules"] = {"mode": "test"}
	config["debug"] = {"opponent_ai": "idle", "player_ai": "normal"}
	config["bots"] = [subject.duplicate(true), opp]
	var fight: Node = (load(FIGHT_SCENE) as PackedScene).instantiate()
	root.add_child(fight)
	await process_frame
	fight.call("start_fight", config)
	await process_frame
	var drv := Scripted.new(RandomNumberGenerator.new())
	fight.set("_player_ai", drv)
	var bots: Array = fight.get("_bots") as Array
	var guard := 0
	while int(fight.get("state")) != 2 and guard < 600:
		await physics_frame
		guard += 1
	fight.call("set_down", bots[1], Vector3(3.8, 0.3, 3.8), Vector3.RIGHT)
	fight.call("set_down", bots[0], Vector3(0.0, 0.3, 0.0), Vector3.RIGHT)
	var ch: RigidBody3D = (bots[0] as Node).get("chassis")
	for _i in 30:
		await physics_frame
	drv.input["turn"] = 1.0
	var total := 0.0
	var last := _yaw(ch)
	for i in 180:
		await physics_frame
		var y := _yaw(ch)
		if i >= 60:
			total += wrapf(y - last, -PI, PI)
		last = y
	root.remove_child(fight)
	fight.queue_free()
	await process_frame
	return absf(total) / 2.0


func _yaw(rb: RigidBody3D) -> float:
	var f := rb.global_basis.x
	return atan2(-f.z, f.x)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("PASS  ", label)
	else:
		_failures += 1
		printerr("FAIL  ", label)
		print("FAIL  ", label)


func _finish() -> void:
	if _failures == 0:
		print("PASS  turn stat: %d checks, 0 failures" % _checks)
		quit(0)
	else:
		print("FAIL  turn stat: %d checks, %d failures" % [_checks, _failures])
		quit(1)
