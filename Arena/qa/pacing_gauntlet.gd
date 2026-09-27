extends SceneTree
## QA (pacing, wave B, 2026-09-27): is a fight a fight? Real AI-vs-AI career fights in
## every arena, measured for the things the owner felt on the phone ("easy to just drive
## around or get stuck, without much drama or skill"): how many go to the judges, how
## many end on a knockout / a hazard / a ring-out, blows per minute (overall and per
## stage of the round), time to the first blow, stuck time and the mean distance
## between the machines. Not a test: nothing passes or fails. One JSON line per fight
## ("PACING {...}", and `--out=`), summarised by docs/qa/pacing.md.
##
##   Godot --headless --fixed-fps 60 --path Arena --script qa/pacing_gauntlet.gd -- \
##       --arenas=yard,crush --weapons=flipper,horizontal_spinner --seeds=11,22,33 \
##       --secs=180 --endgame=120 --house=career --out=/tmp/p.jsonl
##
## The subject (bots[0]) is `weapons_gauntlet.legal_build(weapon)` at national/brawler;
## the opponent is `opponent_for(weapon, "weapon")` (the hero wedge flipper, or a box
## bar spinner when the subject IS the flipper) at regional/technician, the same pairing
## the weapons gauntlet uses, so the numbers read against its 2026-09-27 table.

const FIGHT_SCENE := "res://fight/fight.tscn"
const FIXTURE := "res://fight/fixtures/stage3_config.json"
const WG := preload("res://qa/weapons_gauntlet.gd")
const AG := preload("res://qa/arena_gauntlet.gd")
const ALL_ARENAS := ["yard", "grinder", "drop_zone", "furnace", "crush", "coliseum"]
const STATE_FIGHTING := 2
const STATE_RESULT := 3
## Damage events from one attacker closer together than this are one blow (as the
## weapons gauntlet counts them).
const BLOW_GAP_S := 0.25
## Arena damage events on one victim closer together than this are one hazard contact.
const HAZARD_GAP_S := 1.0
## Stage windows for the per-stage blow rate, seconds from the bell. Fixed so the before
## and after tables read against the same buckets.
const WINDOWS := [[0.0, 45.0], [45.0, 90.0], [90.0, 120.0], [120.0, 155.0], [155.0, 999.0]]
const AIR_M := 0.45

var _arenas: Array = ALL_ARENAS.duplicate()
var _weapons: Array = ["flipper", "horizontal_spinner", "crusher", "saw"]
var _seeds: Array = [11, 22, 33]
var _secs := 180
var _endgame := 120
var _house := "career"
var _out := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() < 2:
			continue
		match kv[0]:
			"--arenas": _arenas = Array(kv[1].split(","))
			"--weapons": _weapons = Array(kv[1].split(","))
			"--seeds":
				_seeds = []
				for s in kv[1].split(","):
					_seeds.append(int(s))
			"--secs": _secs = int(kv[1])
			"--endgame": _endgame = int(kv[1])
			"--house": _house = kv[1]
			"--out": _out = kv[1]
	_run()


func _run() -> void:
	await process_frame
	for arena in _arenas:
		for weapon in _weapons:
			for s in _seeds:
				var row := await _fight(str(arena), str(weapon), int(s))
				_emit(row)
	quit(0)


func _emit(row: Dictionary) -> void:
	var line := JSON.stringify(row)
	print("PACING ", line)
	if _out == "":
		return
	var f: FileAccess
	if FileAccess.file_exists(_out):
		f = FileAccess.open(_out, FileAccess.READ_WRITE)
		f.seek_end()
	else:
		f = FileAccess.open(_out, FileAccess.WRITE)
	f.store_line(line)
	f.close()


func _fight(arena: String, weapon: String, seed_value: int) -> Dictionary:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var a: Dictionary = WG.legal_build(weapon, "player-1", "A")
	a["ai_skill"] = "national"
	a["temperament"] = "brawler"
	var b: Dictionary = WG.opponent_for(weapon, "weapon")
	b["controller"] = "ai"
	b["ai_skill"] = "regional"
	b["temperament"] = "technician"
	var rules := {"mode": "fight", "duration_s": _secs, "ko_count_s": 10, "endgame_at_s": _endgame}
	var house := ""
	if _house == "career":
		var h: Array = AG.career_house(arena)
		house = str(h[0])
		rules["enforcer"] = house
		rules["enforcer_mode"] = "zone"
		rules["enforcer_speed"] = float(h[1])
	elif _house != "none":
		house = _house
		rules["enforcer"] = house
		rules["enforcer_mode"] = "zone"
		rules["enforcer_speed"] = 1.0
	config["seed"] = seed_value
	config["arena"] = arena
	config["rules"] = rules
	config["debug"] = {"opponent_ai": "normal", "player_ai": "normal"}
	config["bots"] = [a, b]

	var fight: Node = (load(FIGHT_SCENE) as PackedScene).instantiate()
	root.add_child(fight)
	await process_frame
	var result := {"payload": {}}
	var bridge: Node = root.get_node("Bridge")
	var on_sent := func(type: String, payload: Dictionary) -> void:
		if type == FightTypes.MSG_FIGHT_RESULT:
			result["payload"] = payload
	bridge.message_sent.connect(on_sent)
	fight.call("start_fight", config)
	await process_frame

	var fbots: Array = fight.get("_bots") as Array
	var ids := ["player-1", "ai-1"]
	var st := {
		"blow_times": [[], []],        # per attacker index: fight times of bot-on-bot damage
		"haz_times": [[], []],         # per victim: arena damage times
		"haz_credit": [[], []],        # per victim: credited hazard contact times
		"haz_dmg": [0.0, 0.0],
		"dmg_by": [0.0, 0.0],
		"last_arena_at": [-99.0, -99.0],
		"first_hit": -1.0,
		"parts_off": [0, 0],
		"payoffs": [],
		"stages": [],
	}
	for i in 2:
		var idx := i
		var bot: Node = fbots[i]
		bot.damage_event.connect(func(info: Dictionary) -> void:
			var att := str(info.get("attacker", ""))
			var sev := float(info.get("severity", 0.0))
			var t := float(fight.call("fight_time"))
			if att == "arena":
				st["haz_dmg"][idx] += sev
				st["last_arena_at"][idx] = t
				var times: Array = st["haz_times"][idx]
				if times.is_empty() or t - float(times.back()) > HAZARD_GAP_S:
					times.append(t)
					var by: Array = fight.get("_last_touch_by")
					var at: Array = fight.get("_last_touch_at")
					if str(by[idx]) != "" and t - float(at[idx]) <= 2.0:
						(st["haz_credit"][idx] as Array).append(t)
				else:
					times.append(t)
			elif att in ids and att != ids[idx]:
				var ai := ids.find(att)
				(st["blow_times"][ai] as Array).append(t)
				st["dmg_by"][ai] += sev
				if float(st["first_hit"]) < 0.0:
					st["first_hit"] = t)
		bot.part_detached.connect(func(_p: String) -> void: st["parts_off"][idx] += 1)
	# Wave B pacing (after): the fight's payoff and stage signals, when this build has them.
	if fight.has_signal("payoff"):
		fight.connect("payoff", func(info: Dictionary) -> void:
			(st["payoffs"] as Array).append({"kind": str(info.get("kind", "")),
				"by": str(info.get("by", "")), "at": snappedf(float(fight.call("fight_time")), 0.1)}))
	if fight.has_signal("stage_changed"):
		fight.connect("stage_changed", func(stage: int, word: String) -> void:
			(st["stages"] as Array).append([stage, word, snappedf(float(fight.call("fight_time")), 0.1)]))

	var stuck := [0, 0]
	var ticks := 0
	var dist_sum := 0.0
	var close_ticks := 0
	var throws := [0, 0]
	var was_up := [false, false]
	var dist_by_window := []
	var ticks_by_window := []
	for w in WINDOWS:
		dist_by_window.append(0.0)
		ticks_by_window.append(0)
	var frames := 0
	var budget := (_secs + 15) * 60 * 3
	while frames < budget and int(fight.get("state")) != STATE_RESULT:
		await physics_frame
		frames += 1
		if int(fight.get("state")) != STATE_FIGHTING:
			continue
		ticks += 1
		var t := float(fight.call("fight_time"))
		var p0: Vector3 = (fbots[0].get("chassis") as Node3D).global_position
		var p1: Vector3 = (fbots[1].get("chassis") as Node3D).global_position
		var d := Vector2(p0.x - p1.x, p0.z - p1.z).length()
		dist_sum += d
		var wi := _window(t)
		dist_by_window[wi] += d
		ticks_by_window[wi] += 1
		if d < 1.2:
			close_ticks += 1
		for i in 2:
			var bot: Node = fbots[i]
			var ch: RigidBody3D = bot.get("chassis")
			if ch.linear_velocity.length() < 0.05 and d > 1.5 and not bool(bot.call("is_inverted")):
				stuck[i] += 1
			var up := ch.global_position.y > AIR_M
			if up and not bool(was_up[i]):
				throws[i] += 1
			was_up[i] = up

	var payload: Dictionary = result["payload"]
	var outcome := ""
	var winner := ""
	var at_s := float(fight.call("fight_time"))
	if payload.get("outcome") is Dictionary:
		var o: Dictionary = payload["outcome"]
		outcome = str(o.get("type", ""))
		winner = str(o.get("winner", ""))
		at_s = float(o.get("at_s", at_s))
	else:
		outcome = str(payload.get("outcome_type", payload.get("outcome", "")))
		winner = str(payload.get("winner", ""))
	# How the loser went: a hazard finish is a KO / core kill with hazard damage in the
	# last 3 s, or a ring-out; a pit finish is a ring-out near the middle of Drop Zone.
	var loser := 1 if winner == "player-1" else 0
	var lp: Vector3 = (fbots[loser].get("chassis") as Node3D).global_position
	var finish := outcome
	if outcome in ["ko", "component_kill"] and at_s - float(st["last_arena_at"][loser]) <= 3.0:
		finish = "hazard_" + outcome
	elif outcome == "out_of_arena":
		finish = "pit" if arena == "drop_zone" and absf(lp.x) < 1.6 and absf(lp.z) < 1.6 else "ring_out"

	var blows := 0
	var blows_w := []
	for w in WINDOWS:
		blows_w.append(0)
	for i in 2:
		var last := -99.0
		for tv in (st["blow_times"][i] as Array):
			var bt := float(tv)
			if bt - last > BLOW_GAP_S:
				blows += 1
				blows_w[_window(bt)] += 1
			last = bt
	var haz_contacts := 0
	var haz_credited := 0
	for i in 2:
		var last := -99.0
		for tv in (st["haz_times"][i] as Array):
			if float(tv) - last > HAZARD_GAP_S:
				haz_contacts += 1
			last = float(tv)
		haz_credited += (st["haz_credit"][i] as Array).size()
	var mins := maxf(at_s, 1.0) / 60.0
	var bpm_w := []
	var dist_w := []
	for wi in WINDOWS.size():
		var w: Array = WINDOWS[wi]
		var span := clampf(at_s, float(w[0]), float(w[1])) - float(w[0])
		bpm_w.append(snappedf(float(blows_w[wi]) / (span / 60.0), 0.1) if span > 5.0 else -1.0)
		dist_w.append(snappedf(float(dist_by_window[wi]) / float(ticks_by_window[wi]), 0.01)
			if int(ticks_by_window[wi]) > 0 else -1.0)
	var row := {
		"arena": arena, "weapon": weapon, "seed": seed_value, "house": house,
		"a": "%s/%s/%s" % [a["chassis"], a["drive"], a["weapon"]],
		"b": "%s/%s/%s" % [b["chassis"], b["drive"], b["weapon"]],
		"outcome": outcome, "finish": finish, "winner": winner, "at_s": snappedf(at_s, 0.1),
		"blows": blows, "bpm": snappedf(float(blows) / mins, 0.01), "bpm_by_stage": bpm_w,
		"first_hit_s": snappedf(float(st["first_hit"]), 0.1),
		"stuck_s": [snappedf(stuck[0] / 60.0, 0.1), snappedf(stuck[1] / 60.0, 0.1)],
		"mean_dist": snappedf(dist_sum / maxf(ticks, 1.0), 0.01), "dist_by_stage": dist_w,
		"close_s": snappedf(close_ticks / 60.0, 0.1),
		"haz_contacts": haz_contacts, "haz_credited": haz_credited,
		"haz_dmg": [snappedf(float(st["haz_dmg"][0]), 0.01), snappedf(float(st["haz_dmg"][1]), 0.01)],
		"dmg_by": [snappedf(float(st["dmg_by"][0]), 0.01), snappedf(float(st["dmg_by"][1]), 0.01)],
		"throws": throws, "parts_off": st["parts_off"],
		"payoffs": st["payoffs"], "stages": st["stages"],
		"judges": payload.get("judges", {}),
	}
	bridge.message_sent.disconnect(on_sent)
	root.remove_child(fight)
	fight.queue_free()
	await process_frame
	await process_frame
	return row


static func _window(t: float) -> int:
	for i in WINDOWS.size():
		if t < float(WINDOWS[i][1]):
			return i
	return WINDOWS.size() - 1
