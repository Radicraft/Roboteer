extends SceneTree
## Wave B judges (docs/wave-b-judges-notes.md, "How the judges score").
##   Godot --headless --path Arena --script tests/judges_test.gd
##
## Owner, 2026-09-27: "i virtually had no damage one game but the judges decided the
## opponent won". Scripted fixtures, no physics:
##   * a one-sided damage fight is won by the damage leader, whatever the other machine
##     did for control (hazard payoffs included) and aggression
##   * the owner's own fight (his ram took the flipper off; the flipper had him on his back
##     for 21 s), from the result his phone stored, is his win
##   * a fight with no damage is decided by control, and then by aggression
##   * a parts knocked out count: a lost weapon outweighs a scuffed armour face
##   * the spikes: two machines clinched on the patch give neither control; a machine put
##     on the RISEN patch by the other one does; a retracted patch, or an arena with no
##     spikes at all (the Furnace), gives nothing
##   * end to end at the bell: the damage leader wins on the cards, and the result carries
##     the card and `judges_detail`

const FIGHT_SCENE := "res://fight/fight.tscn"
const Rules := preload("res://fight/rules.gd")
const DT := 1.0 / 60.0
const STATE_FIGHTING := 2

var _checks := 0
var _failures := 0
var _sent: Array = []


func _initialize() -> void:
	await _run()


func _run() -> void:
	print("Roboteer judges test, Godot ", Engine.get_version_info()["string"])
	_test_one_sided_damage()
	_test_owner_fight()
	_test_no_damage()
	_test_parts_count()
	_test_reason()
	if not ResourceLoader.exists(FIGHT_SCENE):
		print("SKIP: ", FIGHT_SCENE, " is missing")
		_finish()
		return
	await _test_spikes()
	await _test_bell()
	_finish()


# ---------------------------------------------------------------- fixtures

func _tally(lost: float, control: float = 0.0, aggression: float = 0.0, payoff: float = 0.0,
		parts: int = 0, vital: int = 0, hits: int = 0) -> Dictionary:
	var t := Rules.empty_tally()
	t["lost_frac"] = lost
	t["control_s"] = control
	t["aggression_s"] = aggression
	t["payoff_s"] = payoff
	t["parts_out"] = parts
	t["vital_out"] = vital
	t["weapon_hits"] = hits
	return t


func _condition(wheels: Array, weapon: float, front: float, sides: float, rear: float,
		top: float, drive: float = 1.0, core: float = 1.0) -> Dictionary:
	return {"wheels": wheels, "weapon": weapon,
		"armour": {"front": front, "sides": sides, "rear": rear, "top": top},
		"drive": drive, "core": core}


# ---------------------------------------------------------------- 1. damage leads

func _test_one_sided_damage() -> void:
	# The damage leader lost 5 %; the other machine lost 40 % and its weapon, but had the
	# leader on the spikes, shoved it into a hazard and killed a part there (20 s of
	# payoffs), and did all the driving in.
	var leader := _tally(0.05)
	var bully := _tally(0.40, 45.0, 120.0, Rules.PAYOFF_HAZARD_S + Rules.PAYOFF_KILL_S, 1, 1, 30)
	_check(Rules.judges_winner_index(leader, bully) == 0,
		"a one-sided damage fight is the damage leader's, whatever the other did (%s)"
			% JSON.stringify(Rules.judge_cards(leader, bully)))
	_check(Rules.judges_winner_index(bully, leader) == 1, "from either side of the table")

	# A 4 to 1 damage fight takes the whole damage column.
	var cards := Rules.judge_cards(_tally(0.08), _tally(0.32))
	_check(is_equal_approx(float(cards[0]["damage"]), FightTypes.JUDGE_DAMAGE_POINTS),
		"4 to 1 on damage takes all %s damage points (%s)"
			% [FightTypes.JUDGE_DAMAGE_POINTS, JSON.stringify(cards)])

	# The limit case: a damage sweep against a sweep of control AND aggression is 5 to 5 on
	# the printed cards, and the tie goes to damage.
	var limit := Rules.judge_cards(_tally(0.08), _tally(0.32, 60.0, 90.0))
	_check(is_equal_approx(Rules.score_total(limit[0]), Rules.score_total(limit[1]))
		and Rules.judges_winner_index(_tally(0.08), _tally(0.32, 60.0, 90.0)) == 0,
		"a damage sweep against a sweep of everything else is level, and damage has it (%s)"
			% JSON.stringify(limit))

	# And never saturates for both: the old card gave both machines 10 once each had taken
	# 2.5 condition points off the other. Now two heavy hitters are told apart.
	var heavy := Rules.judge_cards(_tally(0.30), _tally(0.60))
	_check(float(heavy[0]["damage"]) > float(heavy[1]["damage"]) + 1.0,
		"two heavily damaged machines are still told apart on damage (%s)" % JSON.stringify(heavy))


## The owner's fight on 2026-09-27, 20:36, from the result the phone stored (the Yard,
## 3:00, Tinribs box ram against Penny Dread wedge flipper). The old card: Tinribs 7 / 0 / 4,
## Penny Dread 3 / 7 / 3, and Penny Dread won 13 to 11 on 21 s of control.
func _test_owner_fight() -> void:
	var tinribs_start := _condition([1.0, 1.0, 1.0, 1.0], 1.0, 1.0, 1.0, 1.0, 1.0)
	var tinribs_end := _condition([0.888888888888889, 1.0, 1.0, 0.166666666666667], 1.0,
		0.914466495349489, 1.0, 0.82889509529903, 0.934031644147334, 0.763888888888889)
	var penny_start := _condition([1.0, 1.0], 1.0, 1.0, 1.0, 1.0, 1.0)
	var penny_end := _condition([1.0, 1.0], 0.0, 1.0, 1.0, 0.93073463666028, 0.299743514573574)
	var tinribs := Rules.empty_tally()
	var penny := Rules.empty_tally()
	Rules.fill_damage_taken(tinribs, tinribs_start, tinribs_end)
	Rules.fill_damage_taken(penny, penny_start, penny_end)
	_check(int(penny["parts_out"]) == 1 and int(penny["vital_out"]) == 1
		and int(tinribs["parts_out"]) == 0,
		"Penny Dread lost its flipper; nothing came off Tinribs")
	# Aggression and control as the old card showed them (4 and 3 of 90 s; 0 and 7 of 30 s).
	tinribs["aggression_s"] = 36.0
	penny["aggression_s"] = 27.0
	penny["control_s"] = 21.0
	var cards := Rules.judge_cards(tinribs, penny)
	_check(Rules.judges_winner_index(tinribs, penny) == 0,
		"the owner's fight is Tinribs's on the cards (%s)" % JSON.stringify(cards))
	_check(float(cards[1]["control"]) > float(cards[0]["control"]),
		"and Penny Dread still takes the control column for having him on his back")


# ---------------------------------------------------------------- 2. no damage

func _test_no_damage() -> void:
	var pusher := _tally(0.0, 18.0, 20.0)
	var runner := _tally(0.0, 2.0, 40.0)
	_check(Rules.judges_winner_index(pusher, runner) == 0,
		"with no damage on either side, control decides (%s)"
			% JSON.stringify(Rules.judge_cards(pusher, runner)))
	var chaser := _tally(0.0, 5.0, 50.0)
	var sitter := _tally(0.0, 5.0, 5.0)
	_check(Rules.judges_winner_index(sitter, chaser) == 1,
		"and with control level too, aggression decides")
	var even := Rules.judge_cards(_tally(0.0), _tally(0.0))
	_check(is_equal_approx(float(even[0]["damage"]), float(even[1]["damage"])),
		"no damage at all splits the damage column evenly")
	# A scratch is not a damage fight: 1 % against nothing leans, it does not sweep.
	var scratch := Rules.judge_cards(_tally(0.0), _tally(0.01))
	_check(float(scratch[0]["damage"]) < FightTypes.JUDGE_DAMAGE_POINTS * 0.7,
		"a scratch leans the damage column, it does not sweep it (%s)" % JSON.stringify(scratch))


func _test_parts_count() -> void:
	# Same condition lost; one of them lost it as its weapon.
	var armour_only := _tally(0.12)
	var weaponless := _tally(0.12, 0.0, 0.0, 0.0, 1, 1)
	_check(Rules.judges_winner_index(armour_only, weaponless) == 0,
		"a weapon knocked out counts for more than the same condition off the armour")
	# A part that was already out when the fight began is not knocked out again.
	var t := Rules.empty_tally()
	var start := _condition([1.0, 1.0], 0.0, 1.0, 1.0, 1.0, 1.0)
	Rules.fill_damage_taken(t, start, start)
	_check(int(t["parts_out"]) == 0 and float(t["lost_frac"]) == 0.0,
		"a weapon already gone at the start is not counted against it again")


func _test_reason() -> void:
	var cards := Rules.judge_cards(_tally(0.05, 0.0, 40.0), _tally(0.40, 20.0, 10.0))
	var words := Rules.judges_reason(cards[0], cards[1])
	_check(words == "Won on damage and aggression. Lost on control.",
		"the decision reads in plain words (%s)" % words)
	_check(not words.contains("—"), "and without em dashes")


# ---------------------------------------------------------------- 3. the spikes

func _test_spikes() -> void:
	var fight := await _start("yard")
	var arena: Node = fight.get("_arena")
	var centre: Vector3 = arena.call("spike_patch_centre")
	var extent := float(arena.call("spike_patch_extent"))
	_check(extent > 0.0, "the Yard has a spike patch (%s m)" % extent)
	var off := centre + Vector3(extent * 0.5 + 0.7, 0.0, 0.0)
	arena.set("_spikes_up", true)
	_check(not bool(fight.call("_spikes_control", centre, centre + Vector3(0.2, 0, 0.1))),
		"two machines clinched on the risen patch: neither has put the other there")
	_check(bool(fight.call("_spikes_control", off, centre)),
		"a machine on the risen patch with the other one off it: control")
	arena.set("_spikes_up", false)
	_check(not bool(fight.call("_spikes_control", off, centre)),
		"the same, with the spikes down: that is floor, not control")

	# Through the tally itself: both on the risen patch, touching, for a second.
	arena.set("_spikes_up", true)
	_place(fight, 0, centre + Vector3(-0.3, 0, 0))
	_place(fight, 1, centre + Vector3(0.3, 0, 0))
	for _i in 60:
		fight.call("_update_tallies", DT)
	var tallies: Array = fight.get("_tallies")
	_check(float(tallies[0]["control_s"]) == 0.0 and float(tallies[1]["control_s"]) == 0.0,
		"a clinch in the middle of the Yard scores nobody control (%s, %s)"
			% [tallies[0]["control_s"], tallies[1]["control_s"]])
	_place(fight, 0, off)
	_place(fight, 1, centre)
	for _i in 60:
		fight.call("_update_tallies", DT)
	_check(float(tallies[0]["control_s"]) > 0.9 and float(tallies[1]["control_s"]) == 0.0,
		"holding them on the risen spikes from outside the patch is control (%s)"
			% tallies[0]["control_s"])
	await _stop(fight)

	# The Furnace has no spike patch: its middle is floor.
	fight = await _start("furnace")
	arena = fight.get("_arena")
	_check(float(arena.call("spike_patch_extent")) == 0.0, "the Furnace has no spikes")
	_place(fight, 0, Vector3(1.2, 0, 0))
	_place(fight, 1, Vector3(0.1, 0, 0.1))
	for _i in 60:
		fight.call("_update_tallies", DT)
	tallies = fight.get("_tallies")
	_check(float(tallies[0]["control_s"]) == 0.0,
		"the middle of the Furnace is not on the spikes (%s)" % tallies[0]["control_s"])
	await _stop(fight)


# ---------------------------------------------------------------- 4. at the bell

func _test_bell() -> void:
	# Penny Dread's machine starts without its weapon and with a battered top, and the
	# fight is told it started whole: at the bell it has lost them. Tinribs is untouched.
	var fight := await _start("yard", {1: _condition([1.0, 1.0, 1.0, 1.0], 0.0, 1.0, 1.0, 0.9, 0.3)})
	var bots: Array = fight.get("_bots")
	var whole: Dictionary = ((bots[1] as Node).call("condition") as Dictionary).duplicate(true)
	whole["weapon"] = 1.0
	whole["armour"] = {"front": 1.0, "sides": 1.0, "rear": 1.0, "top": 1.0}
	fight.set("_start_condition", [
		((bots[0] as Node).call("condition") as Dictionary).duplicate(true), whole])
	var tallies: Array = fight.get("_tallies")
	tallies[1]["control_s"] = 30.0
	tallies[1]["payoff_s"] = Rules.PAYOFF_HAZARD_S
	tallies[1]["aggression_s"] = 20.0
	tallies[0]["aggression_s"] = 10.0
	_sent = []
	var bridge: Node = root.get_node_or_null("Bridge")
	bridge.message_sent.connect(_on_sent)
	fight.set("_tick", int(round(180.0 * FightTypes.TICK_HZ)))
	fight.set("_fight_time", 180.0)
	fight.set("_time_left", 0.0)
	fight.call("_check_win_conditions", DT)
	bridge.message_sent.disconnect(_on_sent)
	var result: Dictionary = {}
	for entry in _sent:
		if entry[0] == FightTypes.MSG_FIGHT_RESULT:
			result = entry[1]
	_check(not result.is_empty(), "the bell produced a result")
	var outcome: Dictionary = result.get("outcome", {}) as Dictionary
	_check(str(outcome.get("type", "")) == "judges" and str(outcome.get("winner", "")) == "player-1",
		"at the bell the machine that lost its weapon loses on the cards, control or not (%s)"
			% JSON.stringify(result.get("judges", {})))
	var judges: Dictionary = result.get("judges", {}) as Dictionary
	var mine: Dictionary = judges.get("player-1", {}) as Dictionary
	var theirs: Dictionary = judges.get("ai-1", {}) as Dictionary
	_check(Rules.score_total(mine) > Rules.score_total(theirs),
		"and the printed card agrees with the decision (%s against %s)"
			% [Rules.score_total(mine), Rules.score_total(theirs)])
	var detail: Dictionary = result.get("judges_detail", {}) as Dictionary
	var penny: Dictionary = detail.get("ai-1", {}) as Dictionary
	_check(int(penny.get("parts_out", 0)) == 1 and int(penny.get("lost_pct", 0)) > 5
		and is_equal_approx(float(penny.get("control_s", 0.0)), 30.0)
		and is_equal_approx(float(penny.get("payoff_s", 0.0)), Rules.PAYOFF_HAZARD_S),
		"the result says what the card was made from (%s)" % JSON.stringify(detail))
	await _stop(fight)


# ---------------------------------------------------------------- plumbing

func _start(arena_id: String, damage: Dictionary = {}) -> Node:
	var bridge: Node = root.get_node_or_null("Bridge")
	var fight: Node = (load(FIGHT_SCENE) as PackedScene).instantiate()
	root.add_child(fight)
	await process_frame
	var config: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://fight/fixtures/stage3_config.json"))
	config["rules"] = {"mode": "fight", "duration_s": 180, "ko_count_s": 10}
	config["arena"] = arena_id
	for i in damage.keys():
		(config["bots"] as Array)[int(i)]["damage"] = damage[i]
	bridge.inject_from_host({"type": "fight_config", "json": JSON.stringify(config)})
	await process_frame
	fight.call("_set_state", STATE_FIGHTING)
	return fight


func _stop(fight: Node) -> void:
	root.remove_child(fight)
	fight.queue_free()
	await process_frame


func _place(fight: Node, index: int, at: Vector3) -> void:
	var bots: Array = fight.get("_bots")
	var ch: RigidBody3D = (bots[index] as Node).get("chassis")
	var y := ch.global_position.y
	ch.global_position = Vector3(at.x, y, at.z)
	ch.linear_velocity = Vector3.ZERO


func _on_sent(type: String, payload: Dictionary) -> void:
	_sent.append([type, payload])


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
		print("PASS  judges: %d checks, 0 failures" % _checks)
		quit(0)
	else:
		print("FAIL  judges: %d checks, %d failures" % [_checks, _failures])
		quit(1)
