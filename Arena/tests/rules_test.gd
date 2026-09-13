extends SceneTree
## Headless unit test for the fight rules and the result builder.
##   Godot --headless --path Arena --script tests/rules_test.gd
## No scene, no physics: every function under test is pure (docs/stage3-spec.md §8).

const Rules := preload("res://fight/rules.gd")
const ResultBuilder := preload("res://fight/result_builder.gd")
const Recorder := preload("res://fight/replay_recorder.gd")

const DT := 1.0 / 60.0

## The bridge-spec v1 FightResult example, used as the shape oracle.
const SPEC_RESULT := {
	"schema": 1,
	"outcome": {"type": "ko", "winner": "player-1", "loser": "ai-1", "at_s": 42.5},
	"duration_s": 42.5,
	"judges": {"player-1": {"damage": 0, "aggression": 0, "control": 0},
		"ai-1": {"damage": 0, "aggression": 0, "control": 0}},
	"damage": {"player-1": {}, "ai-1": {}},
	"scrap": {"player-1": 340, "ai-1": 60},
	"replay": {"seed": 123456789, "tick_hz": 60, "inputs": []},
	"diagnostics": {"ticks_msec_at_config": 0, "ticks_msec_at_result": 0, "physics_ticks": 0,
		"echo": {"arena": "yard", "bot_count": 2, "seed": 123456789}},
}

var _failures := 0
var _checks := 0
var _sent: Array = []


func _initialize() -> void:
	_run()


func _run() -> void:
	_test_knockout()
	_test_out_of_arena()
	_test_component_kill()
	_test_condition_maths()
	_test_judges()
	_test_tally_predicates()
	_test_height_readout()
	_test_replay_recorder()
	_test_result_builder()
	await _test_duplicate_config()
	_finish()


# ---------------------------------------------------------------- 1. knockout

func _test_knockout() -> void:
	var count := 0.0
	for i in int(FightTypes.KO_COUNT_S * 60.0) - 1:
		count = Rules.ko_count_next(count, true, DT)
	_check(not Rules.is_knockout(count, FightTypes.KO_COUNT_S),
		"no knockout one tick short of %0.f s (count %0.3f)" % [FightTypes.KO_COUNT_S, count])
	count = Rules.ko_count_next(count, true, DT)
	_check(Rules.is_knockout(count, FightTypes.KO_COUNT_S),
		"knockout after %0.f consecutive seconds immobile" % FightTypes.KO_COUNT_S)

	# Movement resets the count, which is the rule the HUD counter is showing.
	count = 0.0
	for i in 540:
		count = Rules.ko_count_next(count, true, DT)
	_check(count > 8.9, "count reached 9 s while immobile (%0.3f)" % count)
	count = Rules.ko_count_next(count, false, DT)
	_check(count == 0.0, "one moving tick resets the knockout count to zero")
	for i in 540:
		count = Rules.ko_count_next(count, true, DT)
	_check(not Rules.is_knockout(count, FightTypes.KO_COUNT_S),
		"the count starts again from zero after movement")

	_test_knockout_pin()


## A bot being shoved across the floor is immobile by the speed test and is NOT knocked
## out: it is pinned. Measured on the desktop QA build, a bot merely pushed nose to nose
## reached "KNOCKOUT COUNT 8" with its wheels turning the whole time.
func _test_knockout_pin() -> void:
	_check(Rules.is_pinned(0.6, 1.0, false), "close and driving hard is pinned")
	_check(Rules.is_pinned(1.0, 0.25, false), "at the 1 m edge with a quarter of stick is pinned")
	_check(not Rules.is_pinned(1.4, 1.0, false), "driving hard 1.4 m away is not pinned")
	_check(not Rules.is_pinned(0.6, 0.1, false), "close but barely touching the stick is not pinned")
	_check(not Rules.is_pinned(0.6, 0.0, false), "close with no input at all is not pinned")
	_check(not Rules.is_pinned(0.3, 1.0, true),
		"an inverted bot is never pinned: spec section 8 says it counts down even so")

	# Frozen, not reset: a pinned bot keeps whatever count it had arrived with.
	var count := 0.0
	for i in 300:
		count = Rules.ko_count_next(count, true, DT, false)
	_check(is_equal_approx(count, 5.0), "five seconds of genuine immobility counted (%0.3f)" % count)
	var held := count
	for i in 600:
		count = Rules.ko_count_next(count, true, DT, true)
	_check(is_equal_approx(count, held),
		"ten seconds of shoving neither advances nor resets the count (%0.3f)" % count)
	_check(not Rules.is_knockout(count, FightTypes.KO_COUNT_S),
		"so a pinned bot is never knocked out by the push alone")

	# Break the pin and the count runs again from where it was.
	for i in 300:
		count = Rules.ko_count_next(count, true, DT, false)
	_check(Rules.is_knockout(count, FightTypes.KO_COUNT_S),
		"once the pin breaks and it is still dead, the count finishes (%0.3f)" % count)

	# And driving away still resets it outright.
	count = Rules.ko_count_next(count, false, DT, true)
	_check(count == 0.0, "moving resets the count whether pinned or not")


# ---------------------------------------------------------------- 2. out of the arena

func _test_out_of_arena() -> void:
	var half := FightTypes.ARENA_SIZE * 0.5
	_check(not Rules.is_out_of_arena(Vector3(0, 0.25, 0)), "centre of the floor is in the arena")
	_check(not Rules.is_out_of_arena(FightTypes.SPAWN_PLAYER), "the player spawn is in the arena")
	_check(not Rules.is_out_of_arena(FightTypes.SPAWN_OPPONENT), "the opponent spawn is in the arena")
	_check(Rules.is_out_of_arena(Vector3(half + 0.01, 0.25, 0)), "just past the wall is out")
	_check(Rules.is_out_of_arena(Vector3(0, 0.25, -half - 0.01)), "past the far wall is out")
	_check(Rules.is_out_of_arena(Vector3(0, FightTypes.OUT_OF_ARENA_Y - 0.01, 0)),
		"below the out of arena floor is out")
	_check(not Rules.is_out_of_arena(Vector3(half - 0.01, 2.0, half - 0.01)),
		"airborne inside the walls is still in")


# ---------------------------------------------------------------- 4. component kill

func _test_component_kill() -> void:
	_check(not Rules.is_component_kill(_condition(1.0)), "a pristine bot is not a component kill")
	_check(not Rules.is_component_kill(_condition(0.01)), "a core at 0.01 is not a component kill")
	_check(Rules.is_component_kill(_condition(0.0)), "a core at zero is a component kill")
	_check(Rules.is_component_kill(_condition(-0.2)), "a core below zero is a component kill")


# ---------------------------------------------------------------- condition maths

func _test_condition_maths() -> void:
	var pristine := _condition(1.0)
	# 4 wheels + weapon + 4 armour + drive + core = 11 parts at 1.0
	_check(is_equal_approx(Rules.condition_total(pristine), 11.0),
		"a pristine four wheeled bot totals 11 condition points")
	var hurt := _condition(1.0)
	hurt["wheels"] = [0.0, 1.0, 1.0, 1.0]
	(hurt["armour"] as Dictionary)["front"] = 0.5
	_check(is_equal_approx(Rules.condition_removed(pristine, hurt), 1.5),
		"a lost wheel and half a front plate is 1.5 condition points removed")
	_check(is_equal_approx(Rules.condition_removed(hurt, pristine), 0.0),
		"condition removed never goes negative")


# ---------------------------------------------------------------- 3. judges

func _test_judges() -> void:
	var full := {
		"damage_removed": FightTypes.JUDGE_DAMAGE_FULL,
		"aggression_s": FightTypes.JUDGE_AGGRESSION_FULL_S,
		"weapon_hits": 0,
		"control_s": FightTypes.JUDGE_CONTROL_FULL_S,
	}
	var card := Rules.judge_scores(full)
	_check(card["damage"] == 10 and card["aggression"] == 10 and card["control"] == 10,
		"the full card is 10 / 10 / 10 (got %s)" % JSON.stringify(card))
	_check(Rules.score_total(card) == 30.0, "a full card totals 30")

	var half := {
		"damage_removed": FightTypes.JUDGE_DAMAGE_FULL * 0.5,
		"aggression_s": FightTypes.JUDGE_AGGRESSION_FULL_S * 0.5,
		"weapon_hits": 0,
		"control_s": FightTypes.JUDGE_CONTROL_FULL_S * 0.5,
	}
	var half_card := Rules.judge_scores(half)
	_check(half_card["damage"] == 5 and half_card["aggression"] == 5 and half_card["control"] == 5,
		"half of everything is 5 / 5 / 5")

	var over := {"damage_removed": 99.0, "aggression_s": 999.0, "weapon_hits": 99, "control_s": 999.0}
	var over_card := Rules.judge_scores(over)
	_check(over_card["damage"] == 10 and over_card["aggression"] == 10 and over_card["control"] == 10,
		"scores clamp at 10")

	# A weapon fire that made contact is worth one second of aggression (spec §8).
	var hits := Rules.empty_tally()
	hits["weapon_hits"] = 9
	_check(Rules.judge_scores(hits)["aggression"] == 2,
		"nine landed flips score 2 for aggression (9 of 45 seconds)")

	_check(Rules.judge_scores(Rules.empty_tally()) == {"damage": 0, "aggression": 0, "control": 0},
		"an empty tally is a zero card")

	# Winner by total.
	var strong := {"damage_removed": 2.0, "aggression_s": 20.0, "weapon_hits": 0, "control_s": 5.0}
	var weak := {"damage_removed": 0.2, "aggression_s": 5.0, "weapon_hits": 0, "control_s": 1.0}
	_check(Rules.judges_winner_index(strong, weak) == 0, "the higher total wins the decision")
	_check(Rules.judges_winner_index(weak, strong) == 1, "and it wins from either side of the table")

	# Tie on total, broken by damage.
	var tie_a := {"damage_removed": 2.5, "aggression_s": 0.0, "weapon_hits": 0, "control_s": 0.0}
	var tie_b := {"damage_removed": 0.0, "aggression_s": 45.0, "weapon_hits": 0, "control_s": 0.0}
	_check(Rules.score_total(Rules.judge_scores(tie_a)) == Rules.score_total(Rules.judge_scores(tie_b)),
		"the tie fixture really is a tie on total (10 each)")
	_check(Rules.judges_winner_index(tie_a, tie_b) == 0, "a tie on total goes to damage")
	_check(Rules.judges_winner_index(tie_b, tie_a) == 1, "and to damage from the other side too")

	# Tie on total and damage, broken by aggression.
	var agg_a := {"damage_removed": 1.25, "aggression_s": 22.5, "weapon_hits": 0, "control_s": 0.0}
	var agg_b := {"damage_removed": 1.25, "aggression_s": 0.0, "weapon_hits": 0, "control_s": 7.5}
	_check(Rules.judge_scores(agg_a)["damage"] == Rules.judge_scores(agg_b)["damage"],
		"the aggression fixture ties on damage (5 each)")
	_check(Rules.judges_winner_index(agg_a, agg_b) == 0, "a tie on damage goes to aggression")

	# Identical tallies: deterministic, never a crash and never a coin toss.
	_check(Rules.judges_winner_index(agg_a.duplicate(true), agg_a.duplicate(true)) == 0,
		"two identical cards resolve to the first bot rather than nothing")


# ---------------------------------------------------------------- tally predicates

func _test_tally_predicates() -> void:
	var me := Vector3(0, 0.25, 0)
	var them := Vector3(1.0, 0.25, 0)
	_check(Rules.is_aggressive(me, Vector3(2.0, 0, 0), them), "driving at a bot 1 m away is aggression")
	_check(not Rules.is_aggressive(me, Vector3(-2.0, 0, 0), them), "driving away from it is not")
	_check(not Rules.is_aggressive(me, Vector3(2.0, 0, 0), Vector3(3.0, 0.25, 0)),
		"3 m away is outside the 1.5 m aggression range")
	_check(not Rules.is_aggressive(me, Vector3.ZERO, them), "sitting still next to them is not aggression")

	_check(Rules.is_controlling(true, false, false, 0.5), "they are airborne just after my hit: control")
	_check(Rules.is_controlling(false, true, false, 1.9), "inverted inside the 2 s window: control")
	_check(not Rules.is_controlling(true, true, true, 2.5), "outside the 2 s window: no control")
	_check(not Rules.is_controlling(false, false, false, 0.1), "upright and grounded: no control")
	_check(Rules.is_controlling(false, false, true, 0.1), "on the spikes after my push: control")

	_check(Rules.is_on_spike_patch(Vector3(0.5, 0.25, -0.5)), "the centre patch is 1.6 m across")
	_check(not Rules.is_on_spike_patch(Vector3(1.2, 0.25, 0)), "1.2 m out is off the patch")

	_check(Rules.hazard_credit("player-1", 1.0) == "player-1",
		"spike damage inside 2 s of my shove is credited to me")
	_check(Rules.hazard_credit("player-1", 3.0) == "",
		"spike damage 3 s after my last touch is credited to nobody")
	_check(Rules.hazard_credit("", 0.1) == "", "with no last toucher there is nobody to credit")


# ---------------------------------------------------------------- readability

func _test_height_readout() -> void:
	_check(Rules.height_band(0.02) == "floor", "a 2 cm lip is floor")
	_check(Rules.height_band(0.15) == "mid", "15 cm is mid")
	_check(Rules.height_band(0.4) == "high", "40 cm is high")
	var sentence := Rules.height_sentence("wedge", "floor", "flipper", "mid")
	_check(sentence == "Your wedge: floor. Their flipper: mid.",
		"the height readout reads as plain sentences (got '%s')" % sentence)
	_check(not sentence.contains("—"), "no em dashes in the height readout")
	_check(Rules.banner_for("ko") == "KNOCKOUT", "ko banner")
	_check(Rules.banner_for("out_of_arena") == "OUT OF THE ARENA", "out of arena banner")
	_check(Rules.banner_for("judges") == "JUDGES DECISION", "judges banner")
	_check(Rules.banner_for("component_kill") == "CORE DESTROYED", "component kill banner")


# ---------------------------------------------------------------- replay recorder

func _test_replay_recorder() -> void:
	var recorder := Recorder.new()
	recorder.record(1, {"heading": Vector2(0.5, -0.25), "fire": true, "secondary": false})
	recorder.record(2, FightTypes.empty_input())
	var rows := recorder.to_inputs()
	_check(rows.size() == 2, "the recorder appends one row per tick")
	_check(rows[0] == [1, 0.5, -0.25, 1, 0], "the row is [tick, x, y, fire, secondary] (got %s)"
		% JSON.stringify(rows[0]))

	var player := Recorder.new()
	_check(not player.is_playing(), "a fresh recorder is not playing")
	player.play(rows)
	_check(player.is_playing(), "play() switches it to playback")
	var back := player.input_for(1)
	_check(back["heading"] == Vector2(0.5, -0.25) and back["fire"] == true,
		"playback returns the recorded input record")
	_check(player.input_for(99)["heading"] == Vector2.ZERO,
		"a tick the script does not cover plays as no input")

	# The rows survive the JSON wire, which is where replay.inputs actually goes.
	var wire: Variant = JSON.parse_string(JSON.stringify(rows))
	_check(wire is Array and (wire as Array).size() == 2, "replay rows survive JSON.stringify")
	_check(int(((wire as Array)[0] as Array)[0]) == 1, "the tick number survives as a number")


# ---------------------------------------------------------------- result builder

func _test_result_builder() -> void:
	var config := _config()
	var result := ResultBuilder.build({
		"config": config,
		"outcome_type": "ko",
		"winner": "player-1", "loser": "ai-1",
		"at_s": 42.5, "duration_s": 42.5,
		"judges": {"player-1": Rules.judge_scores(Rules.empty_tally()),
			"ai-1": Rules.judge_scores(Rules.empty_tally())},
		"damage": {"player-1": _condition(1.0), "ai-1": _condition(0.0)},
		"scrap": {"player-1": 340, "ai-1": 60},
		"replay_inputs": [[1, 0.0, -1.0, 0, 0]],
		"ticks_msec_at_config": 11, "ticks_msec_at_result": 22, "physics_ticks": 2550,
	})

	_check_shape(result, SPEC_RESULT, "fight_result")

	_check(result["outcome"]["type"] == "ko", "outcome.type is carried through")
	_check(result["outcome"]["winner"] == "player-1", "outcome.winner is carried through")
	_check(int(result["scrap"]["ai-1"]) == 60, "scrap is per bot")
	_check(result["judges"].has("player-1") and result["judges"].has("ai-1"),
		"judges are filled for both bots even on a knockout")
	_check(int(result["diagnostics"]["echo"]["bot_count"]) == 2, "the echo counts the bots")
	_check(str(result["diagnostics"]["echo"]["arena"]) == "yard", "the echo carries the arena")

	# Integers must survive the wire. A seed that came in from JSON is a float in GDScript.
	var text := JSON.stringify(result)
	_check(not text.contains("1.23456789e+08"), "the seed does not stringify in exponent form")
	_check(text.contains("\"seed\":123456789"), "the seed stringifies as a whole number")
	_check(text.contains("\"tick_hz\":60"), "tick_hz stringifies as a whole number")
	_check(text.contains("\"physics_ticks\":2550"), "physics_ticks stringifies as a whole number")
	_check(text.contains("\"damage\":0"), "a zero judges score stringifies as an integer")

	var parsed: Variant = JSON.parse_string(text)
	_check(parsed is Dictionary, "the result survives JSON.stringify then parse_string")
	var back: Dictionary = parsed as Dictionary
	_check(int(back["replay"]["seed"]) == 123456789, "the seed survives the round trip")
	_check(int(back["diagnostics"]["echo"]["seed"]) == 123456789, "so does the echoed seed")
	_check(int(back["replay"]["tick_hz"]) == 60, "tick_hz survives the round trip")
	_check((back["replay"]["inputs"] as Array).size() == 1, "the replay rows survive the round trip")

	# A float seed arriving from a parsed config must still leave as an integer.
	var float_config := _config()
	float_config["seed"] = 123456789.0
	var from_float := ResultBuilder.build({"config": float_config, "outcome_type": "judges"})
	_check(JSON.stringify(from_float).contains("\"seed\":123456789"),
		"a seed that arrived as a JSON float leaves as an integer")
	_check(str(from_float["outcome"]["winner"]) == "", "an unset winner is an empty string, not null")


# ---------------------------------------------------------------- re-arming and duplicates

## docs/stage3-swift-notes.md: the shell keeps ONE Godot process and sends a fresh
## fight_config on every tap of "Fight", and resends the SAME one once if no fight_state
## came back within 3 s. So the arena must start a new fight from RESULT, and must never
## turn two sends of one configuration into two fights.
##
## This drives the real Fight scene through the real Bridge receive seam. It needs no
## physics to settle: the state machine answers within a frame.
func _test_duplicate_config() -> void:
	if not ResourceLoader.exists("res://fight/fight.tscn"):
		_check(false, "fight.tscn exists")
		return

	var bridge: Node = root.get_node_or_null("Bridge")
	if bridge == null:
		_check(false, "the Bridge autoload is present")
		return
	bridge.message_sent.connect(_on_message_sent)

	var fight: Node = (load("res://fight/fight.tscn") as PackedScene).instantiate()
	root.add_child(fight)
	await process_frame
	_check(int(fight.get("state")) == 0, "a fresh Fight scene is in LOADING")

	var config := _stage3_config()
	_sent.clear()
	bridge.inject_from_host({"type": "fight_config", "json": JSON.stringify(config)})
	await process_frame
	_check(int(fight.get("state")) == 1, "a fight_config in LOADING starts the countdown")
	_check(int(fight.get("_fights_run")) == 1, "exactly one fight has been started")
	_check(_sent_with("fight_state", "state", "countdown"), "fight_state countdown went out")

	# The shell's defensive resend, arriving while the countdown is still running.
	_sent.clear()
	bridge.inject_from_host({"type": "fight_config", "json": JSON.stringify(config)})
	await process_frame
	_check(int(fight.get("_fights_run")) == 1,
		"a duplicate fight_config during COUNTDOWN does not start a second fight (fights run %d)"
			% int(fight.get("_fights_run")))
	_check(_warned_about("already running"),
		"the duplicate is logged as an arena_log warn rather than silently dropped")

	# Same again once the fight proper is running.
	fight.set("state", 2)                       # State.FIGHTING
	_sent.clear()
	bridge.inject_from_host({"type": "fight_config", "json": JSON.stringify(config)})
	await process_frame
	_check(int(fight.get("_fights_run")) == 1, "a duplicate during FIGHTING is ignored too")

	# From RESULT a new configuration is a new fight: that is the re-arm the shell needs.
	fight.set("state", 3)                       # State.RESULT
	_sent.clear()
	bridge.inject_from_host({"type": "fight_config", "json": JSON.stringify(config)})
	await process_frame
	_check(int(fight.get("_fights_run")) == 2, "a fight_config in RESULT starts the next fight")
	_check(int(fight.get("state")) == 1, "and puts the arena back into COUNTDOWN")

	# A malformed configuration is refused without disturbing the fight that is running.
	var bad := _stage3_config()
	bad["schema"] = 99
	_sent.clear()
	bridge.inject_from_host({"type": "fight_config", "json": JSON.stringify(bad)})
	await process_frame
	_check(int(fight.get("_fights_run")) == 2, "a config with the wrong schema starts nothing")

	root.remove_child(fight)
	fight.queue_free()
	bridge.message_sent.disconnect(_on_message_sent)
	await process_frame


func _on_message_sent(type: String, payload: Dictionary) -> void:
	_sent.append({"type": type, "payload": payload})


func _sent_with(type: String, key: String, value: String) -> bool:
	for entry in _sent:
		if entry["type"] == type and str((entry["payload"] as Dictionary).get(key, "")) == value:
			return true
	return false


func _warned_about(fragment: String) -> bool:
	for entry in _sent:
		var payload: Dictionary = entry["payload"]
		if entry["type"] == "arena_log" and str(payload.get("level", "")) == "warn" \
				and str(payload.get("text", "")).contains(fragment):
			return true
	return false


func _stage3_config() -> Dictionary:
	var text := FileAccess.get_file_as_string("res://fight/fixtures/stage3_config.json")
	var parsed: Variant = JSON.parse_string(text)
	return parsed as Dictionary if parsed is Dictionary else _config()


## Every key of the oracle exists, at every depth, with the same Variant type.
func _check_shape(actual: Variant, expected: Variant, path: String) -> void:
	if expected is Dictionary:
		if not (actual is Dictionary):
			_fail("%s is a dictionary" % path)
			return
		for key in (expected as Dictionary).keys():
			if not (actual as Dictionary).has(key):
				_fail("%s has key %s" % [path, str(key)])
				continue
			_check_shape((actual as Dictionary)[key], (expected as Dictionary)[key],
				"%s.%s" % [path, str(key)])
		return
	if expected is Array:
		_check(actual is Array, "%s is an array" % path)
		return
	if expected is int:
		_check(actual is int, "%s is an integer" % path)
		return
	if expected is float:
		_check(actual is float or actual is int, "%s is a number" % path)
		return
	_check(typeof(actual) == typeof(expected), "%s is a %s" % [path, type_string(typeof(expected))])


# ---------------------------------------------------------------- fixtures and harness

func _condition(value: float) -> Dictionary:
	return {
		"wheels": [value, value, value, value],
		"weapon": value,
		"armour": {"front": value, "sides": value, "rear": value, "top": value},
		"drive": value,
		"core": value,
	}


func _config() -> Dictionary:
	return {
		"schema": 1, "seed": 123456789, "arena": "yard",
		"rules": {"duration_s": 90, "ko_count_s": 10},
		"bots": [
			{"id": "player-1", "name": "Tinribs", "damage": _condition(1.0)},
			{"id": "ai-1", "name": "Scrapheap", "damage": _condition(1.0)},
		],
	}


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS  ", label)
	else:
		_failures += 1
		printerr("FAIL  ", label)
		print("FAIL  ", label)


func _fail(label: String) -> void:
	_check(false, label)


func _finish() -> void:
	print("")
	if _failures == 0:
		print("PASS  rules: %d checks, 0 failures" % _checks)
		quit(0)
	else:
		print("FAIL  rules: %d checks, %d failures" % [_checks, _failures])
		quit(1)
