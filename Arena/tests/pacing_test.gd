extends SceneTree
## Wave B pacing: the round in stages and the big payoffs (docs/wave-b-pacing-notes.md).
##   Godot --headless --path Arena --script tests/pacing_test.gd
##
## What it asserts:
##   * Rules: a payoff is credited to the last machine in contact inside PAYOFF_CREDIT_S
##     and never to the victim; the judges score payoff_s as control
##   * the stage marks: 0:45, 1:30 and 0:25 before the bell in a three minute fight; they
##     scale with rules.endgame_at_s (the opener: 0:30, 1:00, 1:35); each lands on EXACTLY
##     its tick, tells the arena (latched), emits stage_changed once and stamps the HUD
##   * a Rumble and the test arena have no stages
##   * payoffs: a credited hazard visit pays once (8 control-seconds), a kill in the same
##     visit pays once more (12), a visit nobody caused or a shared accident pays nothing,
##     a ring-out is named (and INTO THE PIT in the Drop Zone's pit)
##
## Like fight_shape_test the clock is driven by hand (`_tick_fight` with `_tick` set near
## each mark): what is under test is the tick a stage lands on, not 9000 ticks of physics.

const FIGHT_SCENE := "res://fight/fight.tscn"
const Rules := preload("res://fight/rules.gd")
const DT := 1.0 / 60.0
const STATE_FIGHTING := 2

var _checks := 0
var _failures := 0
var _stages: Array = []
var _payoffs: Array = []


func _initialize() -> void:
	await _run()


func _run() -> void:
	print("Roboteer pacing test, Godot ", Engine.get_version_info()["string"])
	_test_rules()
	if not ResourceLoader.exists(FIGHT_SCENE):
		print("SKIP: ", FIGHT_SCENE, " is missing")
		quit(0)
		return
	await _test_stages({"mode": "fight", "ko_count_s": 10}, "yard",
		{1: 2700, 2: 5400, 4: 9300}, "three minute fight")
	await _test_stages({"mode": "fight", "ko_count_s": 10, "duration_s": 120, "endgame_at_s": 80},
		"crush", {1: 1800, 2: 3600, 4: 5700}, "the opener (endgame 1:20, bell 2:00)")
	await _test_no_stages("rumble")
	await _test_no_stages("test")
	await _test_payoffs()
	await _test_pit()
	_finish()


# ---------------------------------------------------------------- 1. the rules

func _test_rules() -> void:
	_check(Rules.payoff_credit("player-1", 0.5, "ai-1") == "player-1",
		"contact half a second before the hazard bit: the shover gets it")
	_check(Rules.payoff_credit("player-1", Rules.PAYOFF_CREDIT_S + 0.01, "ai-1") == "",
		"contact older than the window: nobody does")
	_check(Rules.payoff_credit("ai-1", 0.1, "ai-1") == "",
		"a machine never gets a payoff for itself")
	_check(Rules.payoff_credit("", 0.1, "ai-1") == "", "no contact at all: nobody")
	var t := Rules.empty_tally()
	_check(t.has("payoff_s") and float(t["payoff_s"]) == 0.0, "the tally carries payoff_s")
	t["payoff_s"] = Rules.PAYOFF_HAZARD_S
	var one := float(Rules.judge_scores(t, Rules.empty_tally())["control"])
	_check(one > FightTypes.JUDGE_CONTROL_POINTS * 0.5,
		"one hazard payoff leads the control column (%s of %s)" % [one, FightTypes.JUDGE_CONTROL_POINTS])
	t["payoff_s"] = Rules.PAYOFF_HAZARD_S + Rules.PAYOFF_KILL_S
	var kill := float(Rules.judge_scores(t, Rules.empty_tally())["control"])
	_check(kill >= FightTypes.JUDGE_CONTROL_POINTS,
		"a hazard kill takes the whole control column (%s of %s)" % [kill, FightTypes.JUDGE_CONTROL_POINTS])
	var a := Rules.empty_tally()
	var b := Rules.empty_tally()
	a["aggression_s"] = 20.0
	b["payoff_s"] = Rules.PAYOFF_HAZARD_S
	_check(Rules.judges_winner_index(a, b) == 1,
		"one shove onto a hazard beats twenty seconds of closing in on the cards")


# ---------------------------------------------------------------- 2. the stage marks

func _test_stages(rules: Dictionary, arena_id: String, want: Dictionary, label: String) -> void:
	var fight := await _start(rules, arena_id)
	var marks: Dictionary = fight.call("stage_ticks")
	var ok := true
	for k in want:
		if int(marks.get(k, -2)) != int(want[k]):
			ok = false
	_check(ok, "%s: stage marks %s (want %s)" % [label, str(marks), str(want)])
	var arena: Node = fight.get("_arena")
	var hud: Node = fight.get("_hud")
	for k in [1, 2, 4]:
		var at := int(want[k])
		_jump(fight, at - 2)
		fight.call("_tick_fight", DT)
		_check(int(fight.call("pacing_stage")) < k and int(arena.call("stage")) < k,
			"%s: stage %d has not landed one tick early" % [label, k])
		var before := _stages.size()
		fight.call("_tick_fight", DT)
		_check(int(fight.get("_tick")) == at and int(fight.call("pacing_stage")) == k,
			"%s: stage %d lands on tick %d exactly" % [label, k, at])
		_check(int(arena.call("stage")) == k, "%s: the arena was told (stage %d)" % [label, k])
		_check(_stages.size() - before == 1 and int((_stages.back() as Array)[0]) == k,
			"%s: stage_changed fired once for stage %d" % [label, k])
		var word := str((_stages.back() as Array)[1]) if not _stages.is_empty() else ""
		_check(not word.is_empty() and word == str(arena.call("stage_word", k)),
			"%s: stage %d is called %s" % [label, k, word])
		fight.call("_update_presentation", DT)
		if hud != null and hud.has_method("stage_sting_text"):
			_check(str(hud.call("stage_sting_text")) == word,
				"%s: the HUD stamped %s (%s)" % [label, word, str(hud.call("stage_sting_text"))])
		for _i in 30:
			fight.call("_tick_fight", DT)
		_check(_stages.size() - before == 1, "%s: stage %d does not repeat" % [label, k])
	_check(bool(arena.call("escalated")), "%s: the endgame ran on the way (latched)" % label)
	_check(int(arena.call("stage")) == 4, "%s: and the arena ends on the final stage" % label)
	await _stop(fight)


func _test_no_stages(mode: String) -> void:
	var fight := await _start({"mode": mode, "duration_s": 180, "ko_count_s": 10}, "yard")
	_jump(fight, 9400)
	fight.call("_tick_fight", DT)
	var arena: Node = fight.get("_arena")
	_check(int(fight.call("pacing_stage")) == 0 and _stages.is_empty()
			and (arena == null or not arena.has_method("stage") or int(arena.call("stage")) == 0),
		"%s: no stages, however long it runs" % mode)
	await _stop(fight)


# ---------------------------------------------------------------- 3. payoffs

func _test_payoffs() -> void:
	var fight := await _start({"mode": "fight", "duration_s": 180, "ko_count_s": 10}, "crush")
	_jump(fight, 600)
	fight.call("_tick_fight", DT)
	var tallies: Array = fight.get("_tallies")

	# Nobody touched the victim: nothing.
	fight.call("_payoff_note_damage", _hazard_hit("ai-1"))
	_check(_payoffs.is_empty(), "a machine that drove itself onto a hazard earns nobody anything")

	# Touched, and moved toward the hazard, but steering there itself: its own doing.
	_advance(fight, 120)
	fight.call("_payoff_note_damage", {"victim": "ai-1", "attacker": "player-1", "severity": 0.02})
	_pushed(fight, 1, 1.0)
	fight.call("_payoff_note_damage", _hazard_hit("ai-1"))
	_check(_payoffs.is_empty(), "a machine that steered in while being touched: no payoff")

	# A blow, then shoved into the hazard, steering away: paid once, to the shover.
	_advance(fight, 120)
	fight.call("_payoff_note_damage", {"victim": "ai-1", "attacker": "player-1", "severity": 0.02})
	_pushed(fight, 1, -0.5)
	fight.call("_payoff_note_damage", _hazard_hit("ai-1"))
	fight.call("_payoff_note_damage", _hazard_hit("ai-1"))
	_check(_payoffs.size() == 1 and str(_payoffs[0]["by"]) == "player-1",
		"a shove then a hazard hit: one payoff, to the shover (%s)" % str(_payoffs))
	_check(is_equal_approx(float(tallies[0]["payoff_s"]), Rules.PAYOFF_HAZARD_S),
		"worth %.0f control-seconds on the card (%s)" % [Rules.PAYOFF_HAZARD_S, str(tallies[0]["payoff_s"])])
	fight.call("_update_presentation", DT)
	var hud: Node = fight.get("_hud")
	if hud != null and hud.has_method("stage_sting_text"):
		_check(str(hud.call("stage_sting_text")) == str(_payoffs[0]["name"]),
			"the HUD names it (%s)" % str(hud.call("stage_sting_text")))
	var hs: HitStop = fight.call("hit_stop")
	_check(hs != null and hs.is_slow(), "the moment plays in slow motion (the hit-stop hold)")

	# The same visit takes a part off: the kill pays once more.
	var detach := _hazard_hit("ai-1")
	detach["detached"] = true
	fight.call("_payoff_note_damage", detach)
	fight.call("_payoff_note_damage", detach)
	_check(_payoffs.size() == 2 and str(_payoffs[1]["name"]) == "HAZARD KILL",
		"a part off in the same visit is a HAZARD KILL, once (%s)" % str(_payoffs.size()))
	_check(is_equal_approx(float(tallies[0]["payoff_s"]), Rules.PAYOFF_HAZARD_S + Rules.PAYOFF_KILL_S),
		"and the kill is on the card too")

	# Both of them in the hazard together: a shared accident, nobody's payoff. (After the
	# victim's cooldown, so it is the shared-accident rule that says no.)
	_advance(fight, int((Rules.PAYOFF_VICTIM_COOLDOWN_S + 1.0) * FightTypes.TICK_HZ))
	var n := _payoffs.size()
	fight.call("_payoff_note_damage", {"victim": "ai-1", "attacker": "player-1", "severity": 0.02})
	_pushed(fight, 1, 0.0)
	fight.call("_payoff_note_damage", _hazard_hit("player-1"))
	fight.call("_payoff_note_damage", _hazard_hit("ai-1"))
	_check(_payoffs.size() == n, "two machines in one hazard together: no payoff")
	_check(float(tallies[1]["payoff_s"]) == 0.0, "and the victim never scores off its own visit")

	# A ring-out is named, credited, and happens once.
	_advance(fight, 180)
	fight.call("_payoff_note_damage", {"victim": "ai-1", "attacker": "player-1", "severity": 0.02})
	fight.call("_payoff_ring_out", 1)
	fight.call("_payoff_ring_out", 1)
	var last: Dictionary = _payoffs.back()
	_check(str(last["name"]) == "OUT OF THE ARENA" and str(last["by"]) == "player-1",
		"a ring-out after a shove is OUT OF THE ARENA, credited (%s)" % str(last))
	_check(_payoffs.size() == n + 1, "and it is paid once")
	await _stop(fight)


func _test_pit() -> void:
	var fight := await _start({"mode": "fight", "duration_s": 180, "ko_count_s": 10}, "drop_zone")
	_jump(fight, 600)
	fight.call("_tick_fight", DT)
	var bots: Array = fight.get("_bots")
	var ch: RigidBody3D = (bots[1] as Node).get("chassis")
	ch.global_position = Vector3(0.2, -1.5, -0.3)
	fight.call("_payoff_ring_out", 1)
	_check(not _payoffs.is_empty() and str((_payoffs.back() as Dictionary)["name"]) == "INTO THE PIT",
		"down the Drop Zone's pit is INTO THE PIT")
	_check(str(fight.call("_pacing_banner", "out_of_arena", "OUT OF THE ARENA")) == "INTO THE PIT",
		"and the result banner says so")
	await _stop(fight)


## Give machine `vi` a second of history: 0.6 m further from the nearest hazard a second
## ago, steering `steer` (1 straight at it, -1 away) all the way.
func _pushed(fight: Node, vi: int, steer: float) -> void:
	var bots: Array = fight.get("_bots")
	var p: Vector3 = ((bots[vi] as Node).get("chassis") as Node3D).global_position
	var arena: Node = fight.get("_arena")
	var best := Vector3.ZERO
	var best_d := 1.0e9
	for e in arena.call("hazard_schedule"):
		if bool((e as Dictionary).get("dormant", false)) or str(e["kind"]) == "turntable":
			continue
		var c: Vector3 = e["position"]
		var d := Vector2(c.x - p.x, c.z - p.z).length()
		if d < best_d:
			best_d = d
			best = c
	var dir := Vector2(best.x - p.x, best.z - p.z).normalized()
	var then := p - Vector3(dir.x, 0.0, dir.y) * 0.6
	var hist: Array = (fight.get("_pay_pos_hist") as Array)[vi]
	hist.clear()
	hist.append([then, dir * steer])
	hist.append([p, dir * steer])


func _hazard_hit(victim: String) -> Dictionary:
	return {"victim": victim, "attacker": "arena", "severity": 0.05, "detached": false,
		"position": Vector3.ZERO}


# ---------------------------------------------------------------- plumbing

func _start(rules: Dictionary, arena_id: String) -> Node:
	_stages = []
	_payoffs = []
	var bridge: Node = root.get_node_or_null("Bridge")
	var fight: Node = (load(FIGHT_SCENE) as PackedScene).instantiate()
	root.add_child(fight)
	await process_frame
	fight.connect("stage_changed", func(s: int, w: String) -> void: _stages.append([s, w]))
	fight.connect("payoff", func(info: Dictionary) -> void: _payoffs.append(info))
	var config := _config()
	config["rules"] = rules
	config["arena"] = arena_id
	bridge.inject_from_host({"type": "fight_config", "json": JSON.stringify(config)})
	await process_frame
	fight.call("_set_state", STATE_FIGHTING)
	return fight


func _stop(fight: Node) -> void:
	root.remove_child(fight)
	fight.queue_free()
	await process_frame


func _jump(fight: Node, tick: int) -> void:
	fight.set("_tick", tick)
	fight.set("_fight_time", float(tick) / float(FightTypes.TICK_HZ))
	var total := 180.0
	fight.set("_time_left", maxf(1.0, total - float(tick) / float(FightTypes.TICK_HZ)))


## Move the clock on without running the fight (the knockout rule would end a fight whose
## machines never move): the payoff windows read `_fight_time`.
func _advance(fight: Node, ticks: int) -> void:
	_jump(fight, int(fight.get("_tick")) + ticks)


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
		print("PASS  pacing: %d checks, 0 failures" % _checks)
		quit(0)
	else:
		print("FAIL  pacing: %d checks, %d failures" % [_checks, _failures])
		quit(1)
