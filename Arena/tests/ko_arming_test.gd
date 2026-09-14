extends SceneTree
## Knockout count arming (added 2026-09-14).
##   Godot --headless --path Arena --script tests/ko_arming_test.gd
##
## On a live device run the owner's machine was under "KNOCKOUT COUNT" from the first
## second of every fight and lost by knockout without ever having moved: seven fights,
## zero wins. The count on the PLAYER's machine now arms only once the player has asked
## for any drive, or PLAYER_KO_GRACE_S after the countdown, whichever comes first.
##
## The arming rule is a pure function of the recorded input stream and the simulation
## clock (FightRules.ko_count_armed), never of wall clock or presentation state, so a
## replay arms on exactly the tick the fight did. The timeline below is simulated at the
## fixed tick rate rather than measured off a physics world, so it asserts the rule
## itself; the last section then checks the real fight scene is wired to it.

const FIGHT_SCENE := "res://fight/fight.tscn"
const BOT_SCENE := "res://bot/bot.tscn"
const FIXTURE := "res://fight/fixtures/stage3_config.json"

const TICK := 1.0 / 60.0
const KO_S := 10.0
## How far into the fight the integration check looks. Comfortably past the grace.
const WATCH_TICKS := 480

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	_test_rule()
	_test_never_drives()
	_test_drives_then_stops()
	await _test_real_fight()
	_finish()


## The pure rule.
func _test_rule() -> void:
	_check(not FightRules.ko_count_armed(false, 0.0),
		"a player who has not driven is not counted at the whistle")
	_check(not FightRules.ko_count_armed(false, FightRules.PLAYER_KO_GRACE_S - 0.1),
		"nor a tenth of a second before the grace runs out")
	_check(FightRules.ko_count_armed(false, FightRules.PLAYER_KO_GRACE_S),
		"the count arms %.0f s after the countdown even if nothing was touched"
			% FightRules.PLAYER_KO_GRACE_S)
	_check(FightRules.ko_count_armed(true, 0.0),
		"and it arms the instant the player asks for any drive")
	_check(is_equal_approx(FightRules.PLAYER_KO_GRACE_S, 10.0),
		"the grace is %.0f s" % FightRules.PLAYER_KO_GRACE_S)


## Fifteen seconds of a player who never touches anything: the count starts at the grace
## and the knockout lands a full count later.
func _test_never_drives() -> void:
	var run := _simulate(-1.0, 25.0)
	_check(absf(float(run["count_started_s"]) - FightRules.PLAYER_KO_GRACE_S) < 0.02,
		"no input: the count starts at %.2f s" % float(run["count_started_s"]))
	_check(absf(float(run["knockout_s"]) - (FightRules.PLAYER_KO_GRACE_S + KO_S)) < 0.05,
		"and the knockout lands at %.2f s" % float(run["knockout_s"]))
	_check(float(run["count_at_15s"]) > 4.0 and float(run["count_at_15s"]) < 6.0,
		"at 15 s the count has reached %.1f, not %.1f" % [float(run["count_at_15s"]), 15.0])


## The same machine, but the player drives for the first three seconds and then stops.
## From there it must behave exactly as it always did.
func _test_drives_then_stops() -> void:
	var run := _simulate(3.0, 25.0)
	_check(absf(float(run["count_started_s"]) - 3.0) < 0.02,
		"driving until 3 s: the count starts the moment the input stops (%.2f s)"
			% float(run["count_started_s"]))
	_check(absf(float(run["knockout_s"]) - (3.0 + KO_S)) < 0.05,
		"and the knockout lands a full count later, at %.2f s" % float(run["knockout_s"]))
	_check(float(run["knockout_s"]) < float((_simulate(-1.0, 25.0))["knockout_s"]),
		"a player who drives early is counted sooner than one who never moves")


## One fixed-tick timeline. `drive_until_s` below zero means the player never drives.
## Returns when the count first advanced, when it reached a knockout, and where it was
## at 15 s.
func _simulate(drive_until_s: float, seconds: float) -> Dictionary:
	var t := 0.0
	var count := 0.0
	var has_driven := false
	var started := -1.0
	var knocked := -1.0
	var at_15 := 0.0
	var ticks := int(round(seconds / TICK))
	for i in ticks:
		t += TICK
		var driving := drive_until_s > 0.0 and t <= drive_until_s
		if driving:
			has_driven = true
		# The machine is immobile whenever the player is not driving it.
		var immobile := not driving
		if FightRules.ko_count_armed(has_driven, t):
			count = FightRules.ko_count_next(count, immobile, TICK, false)
		else:
			count = 0.0
		if started < 0.0 and count > 0.0:
			started = t
		if knocked < 0.0 and FightRules.is_knockout(count, KO_S):
			knocked = t
		if absf(t - 15.0) < TICK * 0.5:
			at_15 = count
	return {"count_started_s": started, "knockout_s": knocked, "count_at_15s": at_15}


## The real fight scene, wired the way the shell drives it: no touches, no scripted
## inputs, the player bot simply sitting there. Its count must stay at zero through the
## grace, and `player_has_driven()` must still be false.
func _test_real_fight() -> void:
	if not ResourceLoader.exists(BOT_SCENE) or not ResourceLoader.exists(FIGHT_SCENE):
		print("SKIP  ko arming: the bot or fight scene is absent, nothing to simulate")
		return
	var config := _fixture()
	if config.is_empty():
		_check(false, "the desktop QA fixture loads")
		return
	var fight: Node = (load(FIGHT_SCENE) as PackedScene).instantiate()
	root.add_child(fight)
	await process_frame
	fight.call("start_fight", config.duplicate(true))

	var frames := 0
	var seen_armed_zero := false
	while frames < 6000 and int(fight.get("_tick")) < WATCH_TICKS:
		if int(fight.get("state")) == 3:      # State.RESULT
			break
		await process_frame
		frames += 1
		var t := float(fight.get("_fight_time"))
		if t > 1.0 and t < FightRules.PLAYER_KO_GRACE_S - 0.5:
			var counts: Array = fight.get("_ko_count") as Array
			if float(counts[0]) <= 0.0:
				seen_armed_zero = true
			else:
				seen_armed_zero = false
				break

	_check(not bool(fight.call("player_has_driven")),
		"a player who touches nothing has not driven")
	_check(seen_armed_zero,
		"and their knockout count stays at zero through the grace")
	_check(int(fight.get("state")) != 3 or str(fight.get("_hud_banner")) != "KNOCKOUT",
		"so an untouched fight is not lost by knockout inside the grace")
	var display: Dictionary = fight.call("ko_count_display")
	_check(display.has("is_player"),
		"ko_count_display says whether the count is on the player's own machine")
	fight.queue_free()
	await process_frame


func _fixture() -> Dictionary:
	if not FileAccess.file_exists(FIXTURE):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	return parsed as Dictionary if parsed is Dictionary else {}


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
		print("PASS  ko arming: %d checks, 0 failures" % _checks)
		quit(0)
	else:
		print("FAIL  ko arming: %d checks, %d failures" % [_checks, _failures])
		quit(1)
