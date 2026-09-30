extends SceneTree
## QA (wave D commentary): how does a real fight SOUND? Runs real AI-vs-AI career fights
## headless and writes, per fight, every commentary line with its fight time next to the
## fight log it came from (blows, parts off, flips, stages, payoffs, the house bot, the
## result), so a line can be checked against the event that fired it. Not a test: nothing
## passes or fails. One JSON object per fight to `--out` (JSON lines) and a readable
## transcript on stdout. docs/look/commentary.html is built from the JSON.
##
##   Godot --headless --fixed-fps 60 --path Arena --script qa/commentary_transcript.gd -- \
##       --fights=yard:flipper:Tinribs:Clatterbox:11,furnace:saw:Tinribs:Hob Nail:22 \
##       --out=/tmp/comm.jsonl
##
## Each fight is arena:weapon:player name:opponent name:seed. The builds are the weapons
## gauntlet's (`legal_build(weapon)` against `opponent_for(weapon)`), the house bot the
## career's for that arena, 180 s with the endgame at 120 s: a career fight.

const FIGHT_SCENE := "res://fight/fight.tscn"
const FIXTURE := "res://fight/fixtures/stage3_config.json"
const WG := preload("res://qa/weapons_gauntlet.gd")
const AG := preload("res://qa/arena_gauntlet.gd")
const STATE_COUNTDOWN := 1
const STATE_FIGHTING := 2
const STATE_RESULT := 3
## After the result, keep the presentation running this long so the result lines land.
const TAIL_S := 4.0
## Blows lighter than this are left out of the log (they say nothing and there are many).
const LOG_SEVERITY := 0.05

var _fights: Array = [
	"yard:flipper:Tinribs:Clatterbox:11",
	"drop_zone:horizontal_spinner:Tinribs:Penny Dread:22",
	"furnace:axe:Tinribs:Hob Nail:33",
]
var _out := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() < 2:
			continue
		match kv[0]:
			"--fights": _fights = Array(kv[1].split(","))
			"--out": _out = kv[1]
	_run()


func _run() -> void:
	await process_frame
	for spec in _fights:
		var p := str(spec).split(":")
		var row := await _fight(p[0], p[1], p[2], p[3], int(p[4]))
		_emit(row)
	quit(0)


func _emit(row: Dictionary) -> void:
	print("")
	print("=== %s: %s (%s) v %s (%s), seed %d, house %s ===" % [row["arena"], row["names"][0],
		row["builds"][0], row["names"][1], row["builds"][1], row["seed"], row["house"]])
	for e in row["timeline"]:
		var d: Dictionary = e
		if str(d["type"]) == "line":
			print("  %6.1f  >> %s   [%s]" % [float(d["t"]), str(d["text"]), str(d["key"])])
		else:
			print("  %6.1f     . %s" % [float(d["t"]), str(d["text"])])
	print("  RESULT: %s, winner %s at %.1f s" % [row["outcome"], row["winner"], float(row["at_s"])])
	if _out == "":
		return
	var f: FileAccess
	if FileAccess.file_exists(_out):
		f = FileAccess.open(_out, FileAccess.READ_WRITE)
		f.seek_end()
	else:
		f = FileAccess.open(_out, FileAccess.WRITE)
	f.store_line(JSON.stringify(row))
	f.close()


func _fight(arena: String, weapon: String, player_name: String, foe_name: String,
		seed_value: int) -> Dictionary:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var a: Dictionary = WG.legal_build(weapon, "player-1", player_name)
	a["ai_skill"] = "national"
	a["temperament"] = "brawler"
	var b: Dictionary = WG.opponent_for(weapon, "weapon")
	b["controller"] = "ai"
	b["ai_skill"] = "regional"
	b["temperament"] = "technician"
	b["name"] = foe_name
	var rules := {"mode": "fight", "duration_s": 180, "ko_count_s": 10, "endgame_at_s": 120}
	var h: Array = AG.career_house(arena)
	rules["enforcer"] = str(h[0])
	rules["enforcer_mode"] = "zone"
	rules["enforcer_speed"] = float(h[1])
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

	var timeline: Array = []
	var names := [player_name, foe_name]
	var ids := ["player-1", "ai-1"]
	var t_of := func() -> float:
		return snappedf(float(fight.call("fight_time")), 0.1)
	var comm: FightCommentary = fight.call("commentary")
	var house_name := ""
	if comm != null:
		# The lines themselves are read from comm.said() at the end: the prediction is said
		# on the countdown's first frame, before anything here could connect to a signal.
		house_name = str(fight.call("_house_bot_name"))
	var fbots: Array = fight.get("_bots") as Array
	for i in 2:
		var idx := i
		var bot: Node = fbots[i]
		bot.damage_event.connect(func(info: Dictionary) -> void:
			var att := str(info.get("attacker", ""))
			var sev := float(info.get("severity", 0.0))
			var who: String = "the arena" if att == "arena" else (house_name if att == "enforcer-1"
				else (str(names[ids.find(att)]) if ids.has(att) else att))
			if att == ids[idx]:
				who = "itself"
			var part := str(info.get("part", ""))
			if bool(info.get("detached", false)):
				timeline.append({"type": "log", "t": t_of.call(),
					"text": "%s loses %s (%s)" % [names[idx], part, who]})
			elif sev >= LOG_SEVERITY:
				timeline.append({"type": "log", "t": t_of.call(),
					"text": "%s hit by %s, %s %.2f (%s)" % [names[idx], who, part, sev,
						str(info.get("source", ""))]}))
		bot.inverted_changed.connect(func(inv: bool) -> void:
			if int(fight.get("state")) == STATE_FIGHTING:
				timeline.append({"type": "log", "t": t_of.call(),
					"text": "%s %s" % [names[idx], "is upside down" if inv else "is back upright"]}))
	if fight.has_signal("payoff"):
		fight.connect("payoff", func(info: Dictionary) -> void:
			var by := str(info.get("by", ""))
			timeline.append({"type": "log", "t": t_of.call(), "text": "PAYOFF %s on %s by %s"
				% [str(info.get("name", "")), names[ids.find(str(info.get("victim", "")))],
				names[ids.find(by)] if ids.has(by) else "nobody"]}))
	if fight.has_signal("stage_changed"):
		fight.connect("stage_changed", func(stage: int, word: String) -> void:
			timeline.append({"type": "log", "t": t_of.call(), "text": "STAGE %d %s" % [stage, word]}))
	if fight.has_signal("phase_changed"):
		fight.connect("phase_changed", func(phase: String) -> void:
			timeline.append({"type": "log", "t": t_of.call(), "text": "PHASE %s" % phase}))

	var frames := 0
	var budget := (180 + 20) * 60 * 3
	var was_state := -1
	var jam_was := ["", ""]
	while frames < budget and int(fight.get("state")) != STATE_RESULT:
		await physics_frame
		frames += 1
		var st := int(fight.get("state"))
		if st != was_state:
			timeline.append({"type": "log", "t": t_of.call(), "text": "STATE %d" % st})
			was_state = st
		for i in 2:
			var f := str(fbots[i].call("weapon_fault"))
			if f != str(jam_was[i]):
				if f != "":
					timeline.append({"type": "log", "t": t_of.call(), "text": "%s weapon %s" % [names[i], f]})
				jam_was[i] = f
	# The result lines are said on the presentation frames after it.
	for i in int(TAIL_S * 60.0):
		await process_frame

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
	if comm != null:
		for said_variant in comm.said():
			var sd: Dictionary = said_variant
			timeline.append({"type": "line", "t": snappedf(float(sd["fight_s"]), 0.1),
				"key": str(sd["key"]), "text": str(sd["text"]), "wall": float(sd["at"])})
	# Stable order: by fight time, the fight's own log before the line it drew, lines in
	# the order they were said.
	for n in timeline.size():
		(timeline[n] as Dictionary)["n"] = n
	timeline.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if not is_equal_approx(float(x["t"]), float(y["t"])):
			return float(x["t"]) < float(y["t"])
		var xl := x.has("wall")
		var yl := y.has("wall")
		if xl != yl:
			return yl
		if xl:
			return float(x["wall"]) < float(y["wall"])
		return int(x["n"]) < int(y["n"]))
	var row := {
		"arena": arena, "seed": seed_value, "house": house_name, "names": names,
		"builds": ["%s/%s/%s" % [a["chassis"], a["drive"], a["weapon"]],
			"%s/%s/%s" % [b["chassis"], b["drive"], b["weapon"]]],
		"outcome": outcome, "winner": names[ids.find(winner)] if ids.has(winner) else winner,
		"at_s": snappedf(at_s, 0.1), "timeline": timeline,
		"fired": comm.fired() if comm != null else [],
		"lines": comm.said().size() if comm != null else 0,
	}
	bridge.message_sent.disconnect(on_sent)
	root.remove_child(fight)
	fight.queue_free()
	await process_frame
	await process_frame
	return row
