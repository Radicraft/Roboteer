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
	await _test_mode_switch()
	await _test_enforcer()
	await _test_settings()
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

	# What the HUD is allowed to say about all that.
	_check(not Rules.should_show_ko_count(0.6, true),
		"a count under a second is not shown: that is the immobility window, not a count")
	_check(Rules.should_show_ko_count(1.0, true), "at one full second it is shown")
	_check(Rules.should_show_ko_count(7.5, true), "and it stays shown while it runs")
	_check(not Rules.should_show_ko_count(7.5, false),
		"a frozen count is hidden, however far it had got: a pinned bot is not being counted out")
	_check(not Rules.should_show_ko_count(0.0, false), "and a count of zero is never shown")


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
	_check(rows[0] == [1, 0.5, -0.25, 1, 0, 0.0],
		"the row is [tick, x, y, fire, secondary, turn] (got %s)" % JSON.stringify(rows[0]))

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


# ---------------------------------------------------------------- Stage 4 modes

## docs/stage4-spec.md §5 and §6: the shell keeps ONE Godot process alive from launch and
## the arena shows whatever it was last sent. `workshop_config` puts the stage up,
## `fight_config` puts the fight up, and a `workshop_config` arriving mid fight means the
## player walked out.
func _test_mode_switch() -> void:
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

	var config := _stage3_config()
	var bot_config: Dictionary = (config.get("bots", []) as Array)[0]

	# --- workshop from LOADING
	_sent.clear()
	bridge.inject_from_host({"type": "workshop_config", "json": JSON.stringify({"bot": bot_config})})
	await process_frame
	await process_frame
	_check(str(fight.get("_view")) == "workshop", "workshop_config puts the arena in the workshop view")
	_check(fight.get("_arena") == null, "the fight arena is torn down, so the Yard is not lit behind the stage")
	var hud: Node = fight.get("_hud")
	_check(hud != null and not bool(hud.get("visible")), "the fight HUD is hidden in the workshop")
	var stage: Node = fight.get("_workshop_stage")
	if stage != null and stage.has_method("is_active"):
		_check(bool(stage.call("is_active")), "the workshop stage is active")
	# The stage answers workshop_ready itself; exactly one must go out, never two.
	_check(_count_sent("workshop_ready") == 1,
		"exactly one workshop_ready goes out per workshop_config (got %d)"
			% _count_sent("workshop_ready"))

	# --- back to the fight
	_sent.clear()
	bridge.inject_from_host({"type": "fight_config", "json": JSON.stringify(config)})
	await process_frame
	_check(str(fight.get("_view")) == "fight", "fight_config puts the arena back in the fight view")
	_check(fight.get("_arena") != null, "and builds the arena again")
	_check(bool(hud.get("visible")), "and brings the HUD back")
	if stage != null and stage.has_method("is_active"):
		_check(not bool(stage.call("is_active")), "and turns the workshop stage off")

	# --- the player walks out mid fight
	fight.set("state", 2)                       # State.FIGHTING
	_sent.clear()
	bridge.inject_from_host({"type": "workshop_config", "json": JSON.stringify({"bot": bot_config})})
	await process_frame
	_check(_sent_with("fight_state", "state", "abandoned"),
		"leaving mid fight sends fight_state abandoned")
	_check(_count_sent("fight_result") == 0,
		"and sends no fight_result: a fight nobody watched has no result")
	_check(int(fight.get("state")) == 0, "and the state machine goes back to LOADING")

	# --- menu mode is the same switch with a different camera
	bridge.inject_from_host({"type": "workshop_config",
		"json": JSON.stringify({"bot": bot_config, "mode": "menu"})})
	await process_frame
	_check(str(fight.get("_view")) == "menu", "a workshop_config with mode menu asks for the menu camera")

	# --- test mode
	var test_config := _stage3_config()
	test_config["rules"] = {"mode": "test", "ko_count_s": 10}
	((test_config["bots"] as Array)[1] as Dictionary)["controller"] = "dummy"
	test_config["debug"] = {"opponent_ai": "normal"}
	_sent.clear()
	bridge.inject_from_host({"type": "fight_config", "json": JSON.stringify(test_config)})
	await process_frame
	_check(str(fight.get("_rules_mode")) == "test", "rules.mode test is read off the config")
	_check(fight.get("_ai") == null,
		"a dummy opponent gets no driver, even though the shell always sends opponent_ai normal")
	_check(fight.get("_test_overlay") != null, "the test overlay is up in test mode")
	var arena: Node = fight.get("_arena")
	_check(arena != null and arena.has_method("target_pad"),
		"test mode loads the test arena, which has the target pad")
	if arena != null and arena.has_method("seconds_to_spike_rise"):
		_check(float(arena.call("seconds_to_spike_rise")) > 100.0,
			"and the test arena has no spike hazard to dodge")

	# The clock does not run and nothing can be won or lost.
	fight.set("state", 2)
	var time_before := float(fight.get("_time_left"))
	for i in 40:
		await physics_frame
	_check(is_equal_approx(float(fight.get("_time_left")), time_before),
		"the fight clock does not run in test mode")
	_check(_count_sent("fight_result") == 0, "and no result is sent in test mode")

	# --- the knockout readout follows the same rule at the fight level
	fight.set("_bot_names", ["Tinribs", "Scrapheap"])
	fight.set("_ko_count_s", 10.0)
	fight.set("_ko_count", [0.5, 0.0])
	fight.set("_ko_advancing", [true, false])
	_check(not bool((fight.call("ko_count_display") as Dictionary)["show"]),
		"half a second of immobility shows nothing")
	fight.set("_ko_count", [8.0, 0.0])
	fight.set("_ko_advancing", [false, false])
	var frozen: Dictionary = fight.call("ko_count_display")
	_check(not bool(frozen["show"]),
		"a clinch that freezes the count at 8 s shows nothing, not KNOCKOUT COUNT 10")
	fight.set("_ko_advancing", [true, false])
	var running: Dictionary = fight.call("ko_count_display")
	_check(bool(running["show"]) and int(running["seconds_left"]) == 2
			and str(running["name"]) == "Tinribs",
		"once it is running again it says who and how long (%s)" % JSON.stringify(running))

	# --- test_reset rebuilds both machines
	_sent.clear()
	bridge.inject_from_host({"type": "test_reset", "json": "{}"})
	await process_frame
	var bots: Array = fight.get("_bots") as Array
	_check(bots[0] != null and bots[1] != null, "test_reset leaves both machines standing")
	_check(float((fight.get("_scrap") as Array)[0]) == 0.0, "and clears the scrap tally")

	root.remove_child(fight)
	fight.queue_free()
	bridge.message_sent.disconnect(_on_message_sent)
	await process_frame


# ---------------------------------------------------------------- settings routing

## docs/stage4-swift-notes.md: `settings` arrives after arena_ready and again on every
## change. It is presentation only, and it has to survive a new fight, because a fight
## builds a new world with a new camera rig and a new FX in it.
func _test_settings() -> void:
	var bridge: Node = root.get_node_or_null("Bridge")
	var fight: Node = (load("res://fight/fight.tscn") as PackedScene).instantiate()
	root.add_child(fight)
	await process_frame

	# Fakes for the three nodes that own a setting each, so this tests the routing rather
	# than three other agents' implementations.
	var controls := FakeControls.new()
	var rig := FakeRig.new()
	var fx := FakeFx.new()
	var hud := FakeHud.new()
	fight.set("_controls", controls)
	fight.set("_camera_rig", rig)
	fight.set("_fx", fx)
	fight.set("_hud", hud)

	bridge.inject_from_host({"type": "settings", "json": JSON.stringify({
		"scheme": "southpaw", "director_cut": true, "haptics": false, "volume": 0.5,
		"controller_connected": true, "controller_kind": "xbox",
	})})
	await process_frame
	_check(controls.scheme == "southpaw", "scheme goes to the controls (%s)" % controls.scheme)
	_check(rig.director_cut, "director_cut goes to the camera rig")
	_check(fx.haptics == false, "haptics goes to the FX")
	_check(hud.connected and hud.kind == "xbox",
		"the controller hints go to the HUD (%s, %s)" % [str(hud.connected), hud.kind])
	_check(not AudioServer.is_bus_mute(0), "a volume above zero is not a mute")
	_check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(0)), 0.5),
		"volume sets the master bus (%.3f)" % db_to_linear(AudioServer.get_bus_volume_db(0)))

	# Zero is silence, and linear_to_db(0) is minus infinity, so it mutes instead.
	bridge.inject_from_host({"type": "settings", "json": JSON.stringify({"volume": 0.0})})
	await process_frame
	_check(AudioServer.is_bus_mute(0), "a volume of zero mutes rather than sending minus infinity dB")
	bridge.inject_from_host({"type": "settings", "json": JSON.stringify({"volume": 1.0})})
	await process_frame
	_check(not AudioServer.is_bus_mute(0), "and turning it back up unmutes")

	# A setting the arena does not know about is ignored, not warned about: the shell is
	# allowed to grow the message without the arena being updated first.
	_sent.clear()
	bridge.message_sent.connect(_on_message_sent)
	bridge.inject_from_host({"type": "settings", "json": JSON.stringify({"future_key": 1})})
	await process_frame
	_check(_count_sent("arena_log") == 0, "an unknown settings key is ignored quietly")
	bridge.message_sent.disconnect(_on_message_sent)

	# The player's choices survive the next fight, which builds a whole new world.
	var kept: Dictionary = fight.get("_settings")
	_check(str(kept.get("scheme", "")) == "southpaw" or kept.has("volume"),
		"the last settings are remembered so a rebuilt world can be told again")
	var fresh_rig := FakeRig.new()
	fight.set("_camera_rig", fresh_rig)
	fight.set("_settings", {"director_cut": true, "volume": 1.0})
	fight.call("_reapply_settings")
	_check(fresh_rig.director_cut, "and a rebuilt camera rig is told again rather than reverting")

	root.remove_child(fight)
	fight.queue_free()
	await process_frame


class FakeControls extends Node:
	var scheme := ""
	func set_scheme(value: String) -> void:
		scheme = value


class FakeRig extends Node:
	var director_cut := false
	func set_director_cut(on: bool) -> void:
		director_cut = on


class FakeFx extends Node:
	var haptics := true
	func set_haptics_enabled(on: bool) -> void:
		haptics = on


class FakeHud extends Node:
	var connected := false
	var kind := ""
	func set_controller_hints(is_connected: bool, controller_kind: String) -> void:
		connected = is_connected
		kind = controller_kind


# ---------------------------------------------------------------- the enforcer

## brief §8: the bosses "appear in gauntlet events and to punish inactivity". A career
## fight naming one in `rules.enforcer` gets it sent in after fifteen seconds without the
## two machines touching, and it withdraws once they are fighting again.
##
## Driven by setting the clock rather than by waiting fifteen real seconds: the rule is
## about elapsed fight time and nothing else, and a test that took fifteen seconds to
## prove it would not be run.
func _test_enforcer() -> void:
	if not ResourceLoader.exists("res://fight/fight.tscn"):
		_check(false, "fight.tscn exists")
		return
	var bridge: Node = root.get_node_or_null("Bridge")
	var fight: Node = (load("res://fight/fight.tscn") as PackedScene).instantiate()
	root.add_child(fight)
	await process_frame

	var config := _stage3_config()
	config["rules"] = {"mode": "fight", "duration_s": 90, "ko_count_s": 10, "enforcer": "cinder"}
	bridge.inject_from_host({"type": "fight_config", "json": JSON.stringify(config)})
	await process_frame
	_check(str(fight.get("_enforcer_id")) == "cinder", "rules.enforcer names the boss that is on call")
	_check(fight.get("_enforcer") == null, "and nothing is on the floor while the fight is young")

	fight.set("state", 2)                       # State.FIGHTING
	# Fourteen seconds of nothing: still not enough.
	fight.set("_fight_time", 14.0)
	fight.set("_last_contact_s", 0.0)
	fight.call("_tick_enforcer", 1.0 / 60.0)
	_check(fight.get("_enforcer") == null, "fourteen seconds of no contact is not enough")

	# Fifteen, and the gate opens.
	fight.set("_fight_time", 15.5)
	fight.set("_last_contact_s", 0.0)
	fight.call("_tick_enforcer", 1.0 / 60.0)
	var enforcer: Node = fight.get("_enforcer")
	_check(enforcer != null, "fifteen seconds of no contact sends the enforcer in")
	if enforcer != null:
		var chassis: Node3D = enforcer.get("chassis") as Node3D
		var gate: Vector3 = fight.get("_enforcer_gate")
		_check(absf(gate.x) > FightTypes.ARENA_SIZE * 0.5 - 1.5,
			"and it comes in from a gate on the wall (%s)" % str(gate))
		_check(gate.distance_to(FightTypes.SPAWN_PLAYER) > 4.0
				and gate.distance_to(FightTypes.SPAWN_OPPONENT) > 4.0,
			"on a wall neither machine spawned against")
		if chassis != null and chassis.is_inside_tree():
			_check(chassis.global_position.distance_to(gate) < 1.5, "standing at its gate")

	# It is not a competitor: no tally, no scrap, and it cannot win or lose the fight.
	_check(int(fight.call("_index_of", "enforcer-1")) == -1,
		"the enforcer is not one of the two scored machines, so nothing it does is scored")
	_check((fight.get("_scrap") as Array).size() == 2, "and there are still only two scrap tallies")

	# Contact comes back, and after three seconds it goes home. The two machines are put
	# nose to nose for real rather than the flag being set, so this exercises the contact
	# test as well as the timer.
	var pair: Array = fight.get("_bots") as Array
	if pair[0] != null and pair[1] != null:
		for i in 2:
			var body: Node3D = (pair[i] as Node).get("chassis") as Node3D
			if body != null and body.is_inside_tree():
				body.global_position = Vector3(float(i) * 0.6, 0.25, 0.0)
	fight.set("_fight_time", 16.0)
	fight.call("_tick_enforcer", 1.0 / 60.0)
	_check(float(fight.get("_contact_since_s")) >= 0.0,
		"the machines touching again starts the calm clock")
	# It spawned standing on its gate, so put it out on the floor first: an enforcer that
	# withdraws from the gate it is already on leaves in the same tick and proves nothing.
	var boss_body: Node3D = null
	if fight.get("_enforcer") != null:
		boss_body = (fight.get("_enforcer") as Node).get("chassis") as Node3D
	if boss_body != null and boss_body.is_inside_tree():
		boss_body.global_position = Vector3(0.0, 0.25, 0.0)
	fight.set("_fight_time", 20.0)
	fight.call("_tick_enforcer", 1.0 / 60.0)
	_check(bool(fight.get("_enforcer_withdrawing")),
		"three seconds of the machines fighting again and it withdraws")
	_check(fight.get("_enforcer") != null, "and it is still on the floor on its way out")

	# And once it reaches the gate it leaves the floor entirely.
	if boss_body != null and boss_body.is_inside_tree():
		boss_body.global_position = fight.get("_enforcer_gate")
		fight.call("_tick_enforcer", 1.0 / 60.0)
		_check(fight.get("_enforcer") == null, "and at the gate it leaves the floor")

	# A fight that names no enforcer never gets one, however long the lull.
	var quiet := _stage3_config()
	quiet["rules"] = {"mode": "fight", "duration_s": 90, "ko_count_s": 10}
	fight.set("state", 3)                       # RESULT, so a new config is accepted
	bridge.inject_from_host({"type": "fight_config", "json": JSON.stringify(quiet)})
	await process_frame
	fight.set("state", 2)
	fight.set("_fight_time", 60.0)
	fight.set("_last_contact_s", 0.0)
	fight.call("_tick_enforcer", 1.0 / 60.0)
	_check(fight.get("_enforcer") == null,
		"a fight with no rules.enforcer is left alone however long the lull")

	root.remove_child(fight)
	fight.queue_free()
	await process_frame


func _count_sent(type: String) -> int:
	var n := 0
	for entry in _sent:
		if entry["type"] == type:
			n += 1
	return n


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
