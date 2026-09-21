extends SceneTree
## The career scrap ledger and FightResult v2 (brief v5 sections 3, 5 and 9.3; agent C of
## wave P).
##   Godot --headless --path Arena --script tests/scrap_test.gd
##
## What it asserts:
##   * the pure helpers in rules.gd: damage_fraction, damage_bonus, survivor_bonus,
##     flawless_bonus, any_part_zero, scrap_breakdown, parts_lost, part_label,
##     hits_from_tallies
##   * in a headless fight WITH rules.scrap: the HUD's running number is base plus the
##     damage line, a collected bolt adds nothing to the tally, and the result's
##     scrap[bot] is exactly scrap_breakdown[bot].total
##   * the loser still gets a full breakdown (it is data either way; only the career
##     decides not to bank it)
##   * in a headless fight WITHOUT rules.scrap the numbers are the legacy bolt numbers to
##     the unit, every breakdown line is zero, and all four v2 keys are still present
##
## The fight is driven by hand rather than by physics, the way fight_shape_test.gd does
## it: condition is removed with `BotDamage.apply_direct_damage` (the real code path) and
## the matching damage_event is handed to the fight, which is exactly what the Bot's own
## flush does a frame later. No physics is needed to test a ledger derived from state, and
## a hand driven fight cannot drift.

const Rules := preload("res://fight/rules.gd")

const FIGHT_SCENE := "res://fight/fight.tscn"

## fight.gd's State enum, which is not reachable from outside the script.
const STATE_FIGHTING := 2

## A career Series' scrap rules (Shared/parts.json `progression.series[n].scrap` shape).
const SCRAP_RULES := {
	"base": 120, "damage_full": 200, "survivor": 60, "survivor_min": 0.7, "flawless": 100,
}

var _checks := 0
var _failures := 0
var _results: Array = []


func _initialize() -> void:
	await _run()


func _run() -> void:
	print("Roboteer scrap ledger test, Godot ", Engine.get_version_info()["string"])
	_test_damage_fraction()
	_test_bonuses()
	_test_breakdown()
	_test_parts_lost()
	_test_hits()
	_test_words()
	if not ResourceLoader.exists(FIGHT_SCENE):
		print("SKIP: ", FIGHT_SCENE, " is missing")
		_finish()
		return
	await _test_career_fight()
	await _test_legacy_fight()
	_finish()


# ---------------------------------------------------------------- 1. the damage fraction

func _test_damage_fraction() -> void:
	var full := _condition()
	_check(is_equal_approx(Rules.condition_total(full), 11.0),
		"a whole four wheel machine is 11 condition points (%s)"
			% str(Rules.condition_total(full)))
	_check(is_equal_approx(Rules.damage_fraction(full, full), 0.0),
		"an untouched machine has had nothing removed")

	var half := _condition()
	# 5.5 of 11: the weapon, all four armour faces and half a wheel.
	half["weapon"] = 0.0
	half["armour"] = {"front": 0.0, "sides": 0.0, "rear": 0.0, "top": 0.0}
	half["wheels"] = [0.5, 1.0, 1.0, 1.0]
	_check(is_equal_approx(Rules.damage_fraction(full, half), 0.5),
		"half the condition gone is a fraction of 0.5 (%s)"
			% str(Rules.damage_fraction(full, half)))

	var wreck := {
		"wheels": [0.0, 0.0, 0.0, 0.0], "weapon": 0.0,
		"armour": {"front": 0.0, "sides": 0.0, "rear": 0.0, "top": 0.0},
		"drive": 0.0, "core": 0.0,
	}
	_check(is_equal_approx(Rules.damage_fraction(full, wreck), 1.0),
		"a machine with nothing left is a fraction of 1.0")

	# Clamped at both ends, so a repaired part mid fight cannot pay negative scrap and a
	# bot that somehow gains condition cannot pay more than the full bonus.
	var better := _condition()
	better["core"] = 2.0
	_check(is_equal_approx(Rules.damage_fraction(full, better), 0.0),
		"a machine in better condition than it started in still reads zero")
	_check(is_equal_approx(Rules.damage_fraction({}, full), 0.0),
		"an empty start condition reads zero rather than dividing by nothing")

	# Condition carries between matches (brief v5 section 5), so the denominator is what
	# this machine STARTED with, not a full machine.
	var started_damaged := _condition()
	started_damaged["wheels"] = [0.5, 0.5, 0.5, 0.5]
	started_damaged["weapon"] = 0.0
	var ended := started_damaged.duplicate(true)
	ended["wheels"] = [0.0, 0.0, 0.0, 0.0]
	_check(is_equal_approx(Rules.damage_fraction(started_damaged, ended), 2.0 / 8.0),
		"a machine that went in damaged is measured against what it went in with (%s)"
			% str(Rules.damage_fraction(started_damaged, ended)))


# ---------------------------------------------------------------- 2. the three bonuses

func _test_bonuses() -> void:
	var full := _condition()
	var half := _condition()
	half["weapon"] = 0.0
	half["armour"] = {"front": 0.0, "sides": 0.0, "rear": 0.0, "top": 0.0}
	half["wheels"] = [0.5, 1.0, 1.0, 1.0]

	_check(Rules.damage_bonus(SCRAP_RULES, full, half) == 100,
		"half the opponent's condition pays half of damage_full (%d)"
			% Rules.damage_bonus(SCRAP_RULES, full, half))
	_check(Rules.damage_bonus(SCRAP_RULES, full, full) == 0,
		"an untouched opponent pays no damage bonus")
	_check(Rules.damage_bonus({}, full, half) == 0,
		"and a fight with no scrap rules pays no damage bonus at all")

	# survivor_min is 0.7, and the test is >=, so exactly seven tenths pays.
	var at_min := _condition()
	at_min["wheels"] = [1.0, 1.0, 1.0, 1.0]
	at_min["weapon"] = 0.0
	at_min["armour"] = {"front": 0.0, "sides": 0.0, "rear": 1.0, "top": 1.0}
	# 11 - 1 - 2 = 8, and 8 / 11 is 0.727, comfortably over the line.
	_check(Rules.survivor_bonus(SCRAP_RULES, full, at_min) == 60,
		"a machine still at 73 per cent takes the survivor bonus (%d)"
			% Rules.survivor_bonus(SCRAP_RULES, full, at_min))
	var exactly := _condition()
	exactly["core"] = 1.0 - (0.3 * 11.0 - 3.0)   # trims the total to exactly 0.7 x 11
	exactly["weapon"] = 0.0
	exactly["armour"] = {"front": 0.0, "sides": 0.0, "rear": 1.0, "top": 1.0}
	_check(is_equal_approx(Rules.condition_total(exactly), 0.7 * 11.0),
		"the borderline machine is exactly seven tenths (%s)"
			% str(Rules.condition_total(exactly)))
	_check(Rules.survivor_bonus(SCRAP_RULES, full, exactly) == 60,
		"exactly survivor_min pays, because the test is at least")
	var under := _condition()
	under["weapon"] = 0.0
	under["armour"] = {"front": 0.0, "sides": 0.0, "rear": 0.0, "top": 0.0}
	_check(Rules.survivor_bonus(SCRAP_RULES, full, under) == 0,
		"a machine down to 55 per cent takes nothing (%d)"
			% Rules.survivor_bonus(SCRAP_RULES, full, under))
	_check(Rules.survivor_bonus({}, full, full) == 0, "no scrap rules, no survivor bonus")

	_check(Rules.flawless_bonus(SCRAP_RULES, true, full) == 100,
		"a win with nothing at zero is flawless (%d)"
			% Rules.flawless_bonus(SCRAP_RULES, true, full))
	_check(Rules.flawless_bonus(SCRAP_RULES, false, full) == 0,
		"a loss is never flawless, however whole the machine is")
	# Dented is not the same as lost: flawless is about parts at zero, not about damage.
	var dented := _condition()
	dented["wheels"] = [0.1, 0.4, 1.0, 1.0]
	dented["weapon"] = 0.05
	dented["core"] = 0.2
	_check(Rules.flawless_bonus(SCRAP_RULES, true, dented) == 100,
		"a win that comes home dented but whole is still flawless")
	for key in ["wheels", "weapon", "armour", "drive", "core"]:
		var broken := _condition()
		match key:
			"wheels":
				broken["wheels"] = [1.0, 1.0, 0.0, 1.0]
			"armour":
				broken["armour"] = {"front": 1.0, "sides": 0.0, "rear": 1.0, "top": 1.0}
			_:
				broken[key] = 0.0
		_check(Rules.any_part_zero(broken), "a zeroed %s counts as a part lost" % key)
		_check(Rules.flawless_bonus(SCRAP_RULES, true, broken) == 0,
			"and it costs the flawless bonus (%s)" % key)
	_check(not Rules.any_part_zero(full), "a whole machine has lost nothing")
	_check(Rules.flawless_bonus({}, true, full) == 0, "no scrap rules, no flawless bonus")


# ---------------------------------------------------------------- 3. the breakdown

func _test_breakdown() -> void:
	var full := _condition()
	var foe_now := _condition()
	foe_now["weapon"] = 0.0
	foe_now["armour"] = {"front": 0.0, "sides": 0.0, "rear": 0.0, "top": 0.0}
	foe_now["wheels"] = [0.5, 1.0, 1.0, 1.0]

	var won := Rules.scrap_breakdown(SCRAP_RULES, full, full, full, foe_now, true)
	_check(int(won["base"]) == 120 and int(won["damage"]) == 100
			and int(won["survivor"]) == 60 and int(won["flawless"]) == 100,
		"a flawless win pays all four lines (%s)" % str(won))
	_check(int(won["total"]) == 380, "and the total is their sum (%d)" % int(won["total"]))

	# The live tally: base plus damage, nothing else, because survivor and flawless are
	# only true at the bell and a number that can go down is not a tally.
	var live := Rules.scrap_breakdown(SCRAP_RULES, full, full, full, foe_now, false, false)
	_check(int(live["base"]) == 120 and int(live["damage"]) == 100
			and int(live["survivor"]) == 0 and int(live["flawless"]) == 0,
		"the running tally is base plus damage so far (%s)" % str(live))
	_check(int(live["total"]) == 220, "and its total is the number the HUD shows")

	var lost := Rules.scrap_breakdown(SCRAP_RULES, full, foe_now, full, full, false)
	_check(int(lost["base"]) == 120 and int(lost["damage"]) == 0
			and int(lost["survivor"]) == 0 and int(lost["flawless"]) == 0,
		"a loss still reports its lines, and the career is what refuses to bank them (%s)"
			% str(lost))

	var none := Rules.scrap_breakdown({}, full, full, full, foe_now, true)
	_check(int(none["base"]) == 0 and int(none["damage"]) == 0
			and int(none["survivor"]) == 0 and int(none["flawless"]) == 0
			and int(none["total"]) == 0,
		"a fight with no scrap rules reports four zeroes (%s)" % str(none))
	_check(none.has("base") and none.has("total"),
		"and the zero breakdown is a whole breakdown, not an empty dictionary")
	# EMPTY_BREAKDOWN is handed out by value: a caller that writes into one must not
	# poison the next fight.
	none["base"] = 999
	_check(int(Rules.EMPTY_BREAKDOWN["base"]) == 0,
		"the zero breakdown is a copy, not the shared constant")


# ---------------------------------------------------------------- 4. parts lost

func _test_parts_lost() -> void:
	var full := _condition()
	var keys := ["wheel_fl", "wheel_fr", "wheel_rl", "wheel_rr"]
	_check((Rules.parts_lost(full, keys, "") as Array).is_empty(),
		"a machine that lost nothing reports an empty list")

	var hurt := _condition()
	hurt["weapon"] = 0.0
	hurt["wheels"] = [1.0, 1.0, 0.0, 1.0]
	hurt["armour"] = {"front": 0.0, "sides": 1.0, "rear": 1.0, "top": 1.0}
	hurt["drive"] = 0.0
	hurt["core"] = 0.0
	var rows: Array = Rules.parts_lost(hurt, keys, "")
	_check(rows.size() == 5, "five parts lost, five rows (%d)" % rows.size())
	var labels: Array = []
	var parts: Array = []
	var states: Array = []
	for row_variant in rows:
		var row: Dictionary = row_variant as Dictionary
		parts.append(str(row["part"]))
		labels.append(str(row["label"]))
		states.append(str(row["state"]))
	_check(labels == ["Weapon", "Drive", "Rear left wheel", "Front armour", "Core"],
		"in report order, in the words a player reads (%s)" % str(labels))
	_check(parts == ["weapon", "drive", "wheel_rl", "armour_front", "core"],
		"each row names the condition key it came from (%s)" % str(parts))
	_check(states == ["destroyed", "disabled", "destroyed", "destroyed", "destroyed"],
		"a dead drive is disabled, everything at zero is destroyed (%s)" % str(states))

	# A weapon that still has condition but is not answering: jammed or cooked.
	for fault in ["jammed", "cooked"]:
		var jam: Array = Rules.parts_lost(full, keys, fault)
		_check(jam.size() == 1
				and str((jam[0] as Dictionary)["state"]) == "disabled"
				and str((jam[0] as Dictionary)["label"]) == "Weapon",
			"a %s weapon is reported disabled, not destroyed" % fault)
	var zeroed_and_jammed := _condition()
	zeroed_and_jammed["weapon"] = 0.0
	var both: Array = Rules.parts_lost(zeroed_and_jammed, keys, "jammed")
	_check(both.size() == 1 and str((both[0] as Dictionary)["state"]) == "destroyed",
		"a weapon at zero is destroyed once, not destroyed and disabled")
	_check((Rules.parts_lost(full, keys, "") as Array).is_empty(),
		"and a healthy weapon with no fault is not in the list")

	# Tracks and six wheelers get their own words.
	var tracked := _condition()
	tracked["wheels"] = [0.0, 1.0]
	var track_rows: Array = Rules.parts_lost(tracked, ["track_l", "track_r"], "")
	_check(track_rows.size() == 1
			and str((track_rows[0] as Dictionary)["label"]) == "Left track",
		"a track is a track, not a wheel (%s)" % str(track_rows))
	_check(Rules.part_label("wheel_mr") == "Middle right wheel",
		"a six wheeler's middle row has words too")
	_check(Rules.part_label("armour_sides") == "Side armour",
		"the four armour faces read as armour")
	# An unknown key still reads as words rather than as a raw key.
	_check(not Rules.part_label("wheel_x4").contains("_")
			and Rules.part_label("wheel_x4").begins_with("Wheel"),
		"an unknown key is still made readable (%s)" % Rules.part_label("wheel_x4"))
	var no_keys: Array = Rules.parts_lost(tracked, [], "")
	_check(no_keys.size() == 1 and str((no_keys[0] as Dictionary)["part"]) == "wheel_0",
		"with no key list a wheel is named by its index (%s)" % str(no_keys))


# ---------------------------------------------------------------- 5. hits

func _test_hits() -> void:
	var a := Rules.empty_tally()
	var b := Rules.empty_tally()
	a["weapon_hits"] = 7
	b["weapon_hits"] = 3
	var hits: Dictionary = Rules.hits_from_tallies([a, b], ["player-1", "ai-1"])
	_check(int((hits["player-1"] as Dictionary)["landed"]) == 7
			and int((hits["player-1"] as Dictionary)["taken"]) == 3,
		"what one bot landed is what the other took (%s)" % str(hits))
	_check(int((hits["ai-1"] as Dictionary)["landed"]) == 3
			and int((hits["ai-1"] as Dictionary)["taken"]) == 7,
		"and the other way round")
	var c := Rules.empty_tally()
	c["weapon_hits"] = 5
	var three: Dictionary = Rules.hits_from_tallies([a, b, c], ["p", "q", "r"])
	_check(int((three["p"] as Dictionary)["taken"]) == 8,
		"in a Rumble, taken is everyone else's hits (%s)" % str(three))
	_check(Rules.hits_from_tallies([], []).is_empty(), "no tallies, no hits")


# ---------------------------------------------------------------- 6. the words

func _test_words() -> void:
	var bad := 0
	for key in Rules.PART_LABELS.keys():
		var label := str(Rules.PART_LABELS[key])
		if label.contains("—") or label.contains("–") or label.contains("!"):
			bad += 1
		if label.strip_edges() != label or label.is_empty():
			bad += 1
	_check(bad == 0, "every part label is a plain phrase (%d problems)" % bad)


# ---------------------------------------------------------------- 7. a career fight

func _test_career_fight() -> void:
	var bridge: Node = root.get_node_or_null("Bridge")
	var fight: Node = (load(FIGHT_SCENE) as PackedScene).instantiate()
	root.add_child(fight)
	await process_frame

	_results = []
	bridge.message_sent.connect(_on_message_sent)

	var config := _config()
	config["rules"] = {
		"mode": "fight", "duration_s": 180, "ko_count_s": 10,
		"scrap": SCRAP_RULES.duplicate(),
	}
	bridge.inject_from_host({"type": "fight_config", "json": JSON.stringify(config)})
	await process_frame

	var rules_read: Dictionary = fight.get("_scrap_rules") as Dictionary
	_check(int(rules_read.get("base", -1)) == 120,
		"the fight read rules.scrap out of the config (%s)" % str(rules_read))
	var starts: Array = fight.get("_start_condition") as Array
	_check(starts.size() == 2
			and is_equal_approx(Rules.condition_total(starts[0] as Dictionary), 11.0),
		"and snapshotted the condition both machines started in (%s)"
			% str(Rules.condition_total(starts[0] as Dictionary) if starts.size() > 0 else -1.0))

	fight.call("_set_state", STATE_FIGHTING)
	_check(int(fight.call("scrap_running", 0)) == 120,
		"before a blow lands the running number is the base payout (%d)"
			% int(fight.call("scrap_running", 0)))
	fight.call("_update_hud_and_controls")
	var hud: Node = fight.get("_hud")
	if hud != null and hud.has_method("scrap_total"):
		_check(int(hud.call("scrap_total")) == 120,
			"and the HUD's scrap bug is showing it (%d)" % int(hud.call("scrap_total")))

	# Take the weapon and all four armour faces off the opponent: 5 of its 11 points, and
	# no wheel, so nothing bleeds into its drive and the arithmetic is exact.
	var foe: Node = (fight.get("_bots") as Array)[1]
	if foe == null:
		print("SKIP: the fight built no opponent")
		bridge.message_sent.disconnect(_on_message_sent)
		root.remove_child(fight)
		fight.queue_free()
		return
	var removed := 0.0
	for part in ["weapon", "armour_front", "armour_sides", "armour_rear", "armour_top"]:
		removed += _wreck(fight, foe, part)
	_check(is_equal_approx(removed, 5.0),
		"five condition points came off the opponent (%s)" % str(removed))

	var player_total: float = Rules.condition_total(
		(fight.get("_bots") as Array)[0].call("condition") as Dictionary)
	_check(is_equal_approx(player_total, 11.0),
		"and the player is untouched, so its own lines are predictable (%s)"
			% str(player_total))

	# 5 of 11 removed is 0.4545, so 200 x that rounds to 91.
	_check(int(fight.call("scrap_running", 0)) == 120 + 91,
		"the running number is base plus the damage line so far (%d)"
			% int(fight.call("scrap_running", 0)))
	_check(int((fight.get("_scrap") as Array)[0]) == 0,
		"and no bolt has added anything to the tally (%d)"
			% int((fight.get("_scrap") as Array)[0]))

	fight.call("_finish", "ko", 0, 1)
	await process_frame
	var result := _last_result()
	bridge.message_sent.disconnect(_on_message_sent)

	for key in ["hits", "parts_lost", "condition_start", "scrap_breakdown"]:
		_check(result.has(key), "the result carries the v2 key %s" % key)
	_check(int(result.get("schema", 0)) == 1, "and the schema is still 1")

	var breakdowns: Dictionary = result.get("scrap_breakdown", {}) as Dictionary
	var mine: Dictionary = breakdowns.get("player-1", {}) as Dictionary
	_check(int(mine.get("base", -1)) == 120, "base is the Series' base (%s)" % str(mine))
	_check(int(mine.get("damage", -1)) == 91, "the damage line is damage_full x 0.45")
	_check(int(mine.get("survivor", -1)) == 60, "an untouched winner takes the survivor bonus")
	_check(int(mine.get("flawless", -1)) == 100, "and lost no part, so it is flawless")
	_check(int(mine.get("total", -1)) == 371, "the total is the four lines (%s)" % str(mine))

	var scrap: Dictionary = result.get("scrap", {}) as Dictionary
	_check(int(scrap.get("player-1", -1)) == int(mine.get("total", -2)),
		"scrap[bot] IS the breakdown total, so every v1 reader keeps working (%d vs %d)"
			% [int(scrap.get("player-1", -1)), int(mine.get("total", -2))])

	var theirs: Dictionary = breakdowns.get("ai-1", {}) as Dictionary
	_check(int(theirs.get("base", -1)) == 120 and int(theirs.get("damage", -1)) == 0,
		"the loser reports its lines too (%s)" % str(theirs))
	_check(int(theirs.get("survivor", -1)) == 0,
		"it is down to 55 per cent, so no survivor bonus")
	_check(int(theirs.get("flawless", -1)) == 0, "and a loss is never flawless")
	_check(int(scrap.get("ai-1", -1)) == int(theirs.get("total", -2)),
		"and its scrap is its own total (%d)" % int(scrap.get("ai-1", -1)))

	var lost: Dictionary = result.get("parts_lost", {}) as Dictionary
	var foe_rows: Array = lost.get("ai-1", []) as Array
	var foe_labels: Array = []
	for row_variant in foe_rows:
		foe_labels.append(str((row_variant as Dictionary)["label"]))
	_check(foe_labels == ["Weapon", "Front armour", "Side armour", "Rear armour", "Top armour"],
		"the opponent's parts_lost names the five it lost (%s)" % str(foe_labels))
	_check((lost.get("player-1", []) as Array).is_empty(),
		"the winner lost nothing, and its list is empty rather than missing")

	var starts_out: Dictionary = result.get("condition_start", {}) as Dictionary
	_check(is_equal_approx(
			Rules.condition_total(starts_out.get("ai-1", {}) as Dictionary), 11.0),
		"condition_start is what the machine went in with, not what came out")
	var damage_out: Dictionary = result.get("damage", {}) as Dictionary
	_check(is_equal_approx(
			Rules.condition_total(damage_out.get("ai-1", {}) as Dictionary), 6.0),
		"while damage is what came out (%s)"
			% str(Rules.condition_total(damage_out.get("ai-1", {}) as Dictionary)))

	var hits: Dictionary = result.get("hits", {}) as Dictionary
	_check(int((hits.get("player-1", {}) as Dictionary).get("landed", -1)) == 5,
		"five weapon fires landed five hits (%s)" % str(hits))
	_check(int((hits.get("ai-1", {}) as Dictionary).get("taken", -1)) == 5,
		"and the opponent took all five")
	_check(int((hits.get("ai-1", {}) as Dictionary).get("landed", -1)) == 0,
		"the opponent never fired, so it landed nothing")

	root.remove_child(fight)
	fight.queue_free()
	await process_frame


# ---------------------------------------------------------------- 8. a quick fight

func _test_legacy_fight() -> void:
	var bridge: Node = root.get_node_or_null("Bridge")
	var fight: Node = (load(FIGHT_SCENE) as PackedScene).instantiate()
	root.add_child(fight)
	await process_frame

	_results = []
	bridge.message_sent.connect(_on_message_sent)

	# Exactly the wave G configuration: no rules.scrap anywhere.
	var config := _config()
	config["rules"] = {"mode": "fight", "duration_s": 180, "ko_count_s": 10}
	bridge.inject_from_host({"type": "fight_config", "json": JSON.stringify(config)})
	await process_frame

	_check((fight.get("_scrap_rules") as Dictionary).is_empty(),
		"a quick fight carries no scrap rules")

	var foe: Node = (fight.get("_bots") as Array)[1]
	if foe == null:
		print("SKIP: the fight built no opponent")
		bridge.message_sent.disconnect(_on_message_sent)
		root.remove_child(fight)
		fight.queue_free()
		return

	fight.call("_set_state", STATE_FIGHTING)
	_check(int(fight.call("scrap_running", 0)) == 0,
		"and starts on nothing rather than on a base payout (%d)"
			% int(fight.call("scrap_running", 0)))

	var expected := 0
	for part in ["weapon", "armour_front"]:
		var severity := _wreck(fight, foe, part)
		expected += FightTypes.scrap_for(severity, false)
	_check(expected == 80, "two full severity hits are 80 bolt scrap (%d)" % expected)
	_check(int((fight.get("_scrap") as Array)[0]) == expected,
		"the bolt scrap is banked exactly as it always was (%d of %d)"
			% [int((fight.get("_scrap") as Array)[0]), expected])
	_check(int(fight.call("scrap_running", 0)) == expected,
		"and the HUD shows the bolt total, not a career one")

	fight.call("_finish", "ko", 0, 1)
	await process_frame
	var result := _last_result()
	bridge.message_sent.disconnect(_on_message_sent)

	var scrap: Dictionary = result.get("scrap", {}) as Dictionary
	_check(int(scrap.get("player-1", -1)) == expected,
		"the result's scrap is the legacy number to the unit (%d)"
			% int(scrap.get("player-1", -1)))
	var breakdowns: Dictionary = result.get("scrap_breakdown", {}) as Dictionary
	for id in ["player-1", "ai-1"]:
		var lines: Dictionary = breakdowns.get(id, {}) as Dictionary
		_check(int(lines.get("base", -1)) == 0 and int(lines.get("damage", -1)) == 0
				and int(lines.get("survivor", -1)) == 0
				and int(lines.get("flawless", -1)) == 0
				and int(lines.get("total", -1)) == 0,
			"%s's breakdown is four zeroes and a zero total (%s)" % [id, str(lines)])
	for key in ["hits", "parts_lost", "condition_start", "scrap_breakdown"]:
		_check(result.has(key), "and the v2 key %s is present anyway" % key)
	var lost: Dictionary = result.get("parts_lost", {}) as Dictionary
	var foe_rows: Array = lost.get("ai-1", []) as Array
	_check(foe_rows.size() == 2,
		"parts_lost is filled in a quick fight too (%d rows)" % foe_rows.size())

	root.remove_child(fight)
	fight.queue_free()
	await process_frame


# ---------------------------------------------------------------- plumbing

## Remove a whole part from `bot` and hand the fight the damage_event its own flush would
## have produced a frame later, preceded by the weapon fire that made contact. Returns the
## severity applied.
func _wreck(fight: Node, bot: Node, part_key: String) -> float:
	var model: Variant = bot.get("damage")
	if model == null:
		return 0.0
	var applied: float = model.apply_direct_damage(
		part_key, 1.0, "impact", Vector3.ZERO, "player-1", 1.0)
	model.pending.clear()      # the fight is told by hand below, not by the Bot's flush
	fight.call("_on_weapon_fired", 0)
	fight.call("_on_damage_event", {
		"victim": "ai-1", "attacker": "player-1", "part": part_key,
		"severity": applied, "detached": false, "position": Vector3.ZERO,
	})
	return applied


func _condition() -> Dictionary:
	return {
		"wheels": [1.0, 1.0, 1.0, 1.0],
		"weapon": 1.0,
		"armour": {"front": 1.0, "sides": 1.0, "rear": 1.0, "top": 1.0},
		"drive": 1.0,
		"core": 1.0,
	}


func _config() -> Dictionary:
	var text := FileAccess.get_file_as_string("res://fight/fixtures/stage3_config.json")
	var parsed: Variant = JSON.parse_string(text)
	return parsed as Dictionary if parsed is Dictionary else {}


func _on_message_sent(type: String, payload: Dictionary) -> void:
	if type == FightTypes.MSG_FIGHT_RESULT:
		_results.append(payload)


func _last_result() -> Dictionary:
	_check(not _results.is_empty(), "the fight sent a fight_result")
	return (_results[-1] as Dictionary) if not _results.is_empty() else {}


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
		print("PASS  scrap ledger: %d checks, 0 failures" % _checks)
		quit(0)
	else:
		print("FAIL  scrap ledger: %d checks, %d failures" % [_checks, _failures])
		quit(1)
