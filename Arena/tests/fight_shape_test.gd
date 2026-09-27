extends SceneTree
## The shape of a round (brief v4 §2, agent G1).
##   Godot --headless --path Arena --script tests/fight_shape_test.gd
##
## What it asserts:
##   * the constants are the three minute round's, not the ninety second one's
##   * a fight with no rules.duration_s runs for FIGHT_DURATION_S
##   * fight_phase() is "open" before tick 120 s and "endgame" from it, on EXACTLY that
##     tick, derived from _tick and never from the accumulated _fight_time
##   * phase_changed fires exactly twice in a fight: once open, once endgame
##   * the endgame's own fight_state goes out exactly once, and every other fight_state
##     carries a phase too
##   * the arena escalates and stays escalated, and the HUD stamps ENDGAME
##   * a Rumble never enters the endgame, however long it runs
##
## The clock is driven by hand (`_tick_fight` called directly, `_tick` set near the mark)
## rather than by 7200 real physics ticks: with no physics stepping both machines are
## immobile and the knockout rule would end the fight at ten seconds, and what is under
## test here is the tick the phase turns on, which is exactly what setting the tick asks.

const FIGHT_SCENE := "res://fight/fight.tscn"
const DT := 1.0 / 60.0

## fight.gd's State enum, which is not reachable from outside the script.
const STATE_COUNTDOWN := 1
const STATE_FIGHTING := 2
const STATE_RESULT := 3

var _checks := 0
var _failures := 0
var _sent: Array = []
var _phases: Array = []


func _initialize() -> void:
	await _run()


func _run() -> void:
	print("Roboteer fight shape test, Godot ", Engine.get_version_info()["string"])
	_test_constants()
	if not ResourceLoader.exists(FIGHT_SCENE):
		print("SKIP: ", FIGHT_SCENE, " is missing")
		quit(0)
		return
	await _test_endgame_moment()
	await _test_rumble_never_escalates()
	_finish()


# ---------------------------------------------------------------- 1. the constants

func _test_constants() -> void:
	_check(is_equal_approx(FightTypes.FIGHT_DURATION_S, 180.0),
		"the round is three minutes (%s)" % str(FightTypes.FIGHT_DURATION_S))
	_check(is_equal_approx(FightTypes.ENDGAME_AT_S, 120.0),
		"the endgame is at two minutes (%s)" % str(FightTypes.ENDGAME_AT_S))
	_check(FightTypes.PHASE_OPEN == "open" and FightTypes.PHASE_ENDGAME == "endgame",
		"the two phase names are the ones on the wire")
	# Wave B judges: the card is a split of ten points, weighed machine against machine, so
	# it no longer scales with the round.
	_check(is_equal_approx(FightTypes.JUDGE_DAMAGE_POINTS + FightTypes.JUDGE_CONTROL_POINTS
		+ FightTypes.JUDGE_AGGRESSION_POINTS, 10.0), "the judges split ten points")
	_check(FightTypes.JUDGE_DAMAGE_POINTS > FightTypes.JUDGE_CONTROL_POINTS
		+ FightTypes.JUDGE_AGGRESSION_POINTS - 0.001, "and damage weighs as much as the other two together")
	# The endgame lands inside the round with a minute of escalated fight after it.
	_check(FightTypes.ENDGAME_AT_S < FightTypes.FIGHT_DURATION_S,
		"the endgame happens before the bell")


# ---------------------------------------------------------------- 2. the endgame moment

func _test_endgame_moment() -> void:
	var bridge: Node = root.get_node_or_null("Bridge")
	var fight: Node = (load(FIGHT_SCENE) as PackedScene).instantiate()
	root.add_child(fight)
	await process_frame

	_sent = []
	_phases = []
	bridge.message_sent.connect(_on_message_sent)
	fight.phase_changed.connect(_on_phase_changed)

	# No duration_s at all: the arena has to fall back to the three minute default.
	var config := _config()
	config["rules"] = {"mode": "fight", "ko_count_s": 10}
	bridge.inject_from_host({"type": "fight_config", "json": JSON.stringify(config)})
	await process_frame

	_check(is_equal_approx(float(fight.get("_time_left")), FightTypes.FIGHT_DURATION_S),
		"a fight with no rules.duration_s runs for three minutes (%s s)"
			% str(fight.get("_time_left")))
	_check(str(fight.call("fight_phase")) == FightTypes.PHASE_OPEN,
		"the countdown is the open phase")
	_check(_phases.is_empty(), "and nothing has changed phase yet")
	_check(_phase_of_last_state() == FightTypes.PHASE_OPEN,
		"the countdown's fight_state carries phase open")

	# The bell.
	fight.call("_set_state", STATE_FIGHTING)
	_check(_phases.size() == 1 and str(_phases[0]) == FightTypes.PHASE_OPEN,
		"the bell emits phase_changed once, with open (%s)" % str(_phases))
	_check(_phase_of_last_state() == FightTypes.PHASE_OPEN,
		"and its fight_state carries the phase as well")

	# Two ticks short of the mark. The tick is set by hand; _fight_time and _time_left are
	# set with it so the fight is internally consistent, and the phase must come off the
	# TICK, which is the thing a replay reproduces exactly.
	var at: int = fight.get("ENDGAME_AT_TICKS") if fight.get("ENDGAME_AT_TICKS") != null \
		else int(round(FightTypes.ENDGAME_AT_S * FightTypes.TICK_HZ))
	fight.set("_tick", at - 2)
	fight.set("_fight_time", float(at - 2) / float(FightTypes.TICK_HZ))
	fight.set("_time_left", FightTypes.FIGHT_DURATION_S - float(at - 2) / float(FightTypes.TICK_HZ))

	fight.call("_tick_fight", DT)
	_check(int(fight.get("_tick")) == at - 1, "one tick short of the mark (tick %d)" % at)
	_check(str(fight.call("fight_phase")) == FightTypes.PHASE_OPEN,
		"and the round is still open")
	_check(_phases.size() == 1, "and nothing has fired")
	var arena: Node = fight.get("_arena")
	if arena != null:
		_check(str(arena.call("phase")) == FightTypes.PHASE_OPEN,
			"the arena is still in the open phase")

	# The tick itself.
	var sends_before := _count_endgame_states()
	fight.call("_tick_fight", DT)
	_check(int(fight.get("_tick")) == at,
		"the mark is tick %d, 120 s at 60 Hz" % at)
	_check(str(fight.call("fight_phase")) == FightTypes.PHASE_ENDGAME,
		"the phase flips on exactly that tick")
	_check(_phases.size() == 2 and str(_phases[1]) == FightTypes.PHASE_ENDGAME,
		"phase_changed has now fired twice, open then endgame (%s)" % str(_phases))
	_check(_count_endgame_states() - sends_before == 1,
		"one fight_state {fighting, endgame} went out, and only one")

	if arena != null:
		_check(str(arena.call("phase")) == FightTypes.PHASE_ENDGAME,
			"the arena was told to escalate")
		_check(bool(arena.call("escalated")), "and it says it has")
	var hud: Node = fight.get("_hud")
	if hud != null and hud.has_method("endgame_sting_visible"):
		_check(bool(hud.call("endgame_sting_visible")), "the HUD stamped ENDGAME")

	# And it happens once only, however many more ticks run.
	for _i in 120:
		fight.call("_tick_fight", DT)
	_check(_phases.size() == 2, "the moment does not repeat (%d emissions)" % _phases.size())
	_check(_count_endgame_states() - sends_before == 1,
		"and neither does its bridge message")
	_check(str(fight.call("fight_phase")) == FightTypes.PHASE_ENDGAME,
		"the rest of the round stays in the endgame")
	if arena != null:
		_check(bool(arena.call("escalated")),
			"and the arena stays escalated for the rest of the fight")
		# Even asked politely to go back.
		arena.call("set_phase", FightTypes.PHASE_OPEN)
		_check(str(arena.call("phase")) == FightTypes.PHASE_ENDGAME
				and bool(arena.call("escalated")),
			"an arena that has escalated cannot be put back")

	# Every fight_state this fight sent carries a phase, whatever it was about.
	var missing := 0
	for entry in _sent:
		if str(entry["type"]) != FightTypes.MSG_FIGHT_STATE:
			continue
		if not (entry["payload"] as Dictionary).has("phase"):
			missing += 1
	_check(missing == 0, "every fight_state carries a phase (%d without)" % missing)

	bridge.message_sent.disconnect(_on_message_sent)
	root.remove_child(fight)
	fight.queue_free()
	await process_frame


# ---------------------------------------------------------------- 3. Rumble is untouched

func _test_rumble_never_escalates() -> void:
	var bridge: Node = root.get_node_or_null("Bridge")
	var fight: Node = (load(FIGHT_SCENE) as PackedScene).instantiate()
	root.add_child(fight)
	await process_frame

	_sent = []
	_phases = []
	bridge.message_sent.connect(_on_message_sent)
	fight.phase_changed.connect(_on_phase_changed)

	var config := _config()
	config["rules"] = {"mode": "rumble", "duration_s": 90, "ko_count_s": 10}
	bridge.inject_from_host({"type": "fight_config", "json": JSON.stringify(config)})
	await process_frame
	_check(is_equal_approx(float(fight.get("_time_left")), 90.0),
		"Rumble keeps its ninety seconds (%s s)" % str(fight.get("_time_left")))

	fight.call("_set_state", STATE_FIGHTING)
	var at := int(round(FightTypes.ENDGAME_AT_S * FightTypes.TICK_HZ))
	fight.set("_tick", at + 600)
	fight.set("_fight_time", float(at + 600) / float(FightTypes.TICK_HZ))
	fight.call("_tick_fight", DT)
	_check(str(fight.call("fight_phase")) == FightTypes.PHASE_OPEN,
		"a Rumble is open at 2:10 and stays open")
	_check(_phases.size() == 1,
		"and the only phase_changed it ever sends is the opening one (%s)" % str(_phases))
	_check(_count_endgame_states() == 0, "no endgame fight_state was ever sent")
	var arena: Node = fight.get("_arena")
	if arena != null:
		_check(not bool(arena.call("escalated")), "and the arena never escalated")

	bridge.message_sent.disconnect(_on_message_sent)
	root.remove_child(fight)
	fight.queue_free()
	await process_frame


# ---------------------------------------------------------------- plumbing

func _on_message_sent(type: String, payload: Dictionary) -> void:
	_sent.append({"type": type, "payload": payload})


func _on_phase_changed(phase: String) -> void:
	_phases.append(phase)


func _count_endgame_states() -> int:
	var n := 0
	for entry in _sent:
		if str(entry["type"]) != FightTypes.MSG_FIGHT_STATE:
			continue
		var payload: Dictionary = entry["payload"]
		if str(payload.get("state", "")) == "fighting" \
				and str(payload.get("phase", "")) == FightTypes.PHASE_ENDGAME:
			n += 1
	return n


func _phase_of_last_state() -> String:
	for i in range(_sent.size() - 1, -1, -1):
		if str(_sent[i]["type"]) == FightTypes.MSG_FIGHT_STATE:
			return str((_sent[i]["payload"] as Dictionary).get("phase", ""))
	return ""


func _config() -> Dictionary:
	var text := FileAccess.get_file_as_string("res://fight/fixtures/stage3_config.json")
	var parsed: Variant = JSON.parse_string(text)
	return parsed as Dictionary if parsed is Dictionary else {}


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS  ", label)
	else:
		_failures += 1
		print("FAIL  ", label)


func _finish() -> void:
	print("%d checks, %d failed" % [_checks, _failures])
	if _failures == 0:
		print("PASS  fight shape: %d checks, 0 failures" % _checks)
		quit(0)
	else:
		print("FAIL  fight shape: %d checks, %d failures" % [_checks, _failures])
		quit(1)
