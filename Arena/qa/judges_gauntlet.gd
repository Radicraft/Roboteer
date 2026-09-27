extends SceneTree
## QA (judges, wave B, 2026-09-27): do the judges' decisions follow what a viewer saw?
## Owner on the phone: "i virtually had no damage one game but the judges decided the
## opponent won". Real AI-vs-AI career fights (or a phone fight re-simulated from its
## stored config and input log), and for each one the raw judges' tallies, where every
## control second came from, and how much of each machine's condition came off. Not a
## test: nothing passes or fails. One JSON line per fight ("JUDGES {...}", and `--out=`);
## docs/wave-b-judges-notes.md reads them.
##
##   Godot --headless --fixed-fps 60 --path Arena --script qa/judges_gauntlet.gd -- \
##       --arenas=yard,crush --pairs=ram:flipper,saw:horizontal_spinner --seeds=11,22 \
##       --secs=180 --endgame=120 --out=/tmp/j.jsonl
##   ... --script qa/judges_gauntlet.gd -- --replay=/path/config.json --inputs=/path/replay.json
##
## `--pairs` is subject:opponent weapon pairs; both are `weapons_gauntlet.legal_build` at
## regional (an even tier, so fights go the distance), subject a brawler, opponent a
## technician, with the arena's career house bot.

const FIGHT_SCENE := "res://fight/fight.tscn"
const FIXTURE := "res://fight/fixtures/stage3_config.json"
const WG := preload("res://qa/weapons_gauntlet.gd")
const AG := preload("res://qa/arena_gauntlet.gd")
const ALL_ARENAS := ["yard", "grinder", "drop_zone", "furnace", "crush", "coliseum"]
const STATE_FIGHTING := 2
const STATE_RESULT := 3

var _arenas: Array = ALL_ARENAS.duplicate()
var _pairs: Array = ["ram:flipper", "flipper:horizontal_spinner", "saw:crusher",
	"horizontal_spinner:ram"]
var _seeds: Array = [11, 22]
var _secs := 180
var _endgame := 120
var _out := ""
var _replay := ""
var _inputs := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() < 2:
			continue
		match kv[0]:
			"--arenas": _arenas = Array(kv[1].split(","))
			"--pairs": _pairs = Array(kv[1].split(","))
			"--seeds":
				_seeds = []
				for s in kv[1].split(","):
					_seeds.append(int(s))
			"--secs": _secs = int(kv[1])
			"--endgame": _endgame = int(kv[1])
			"--out": _out = kv[1]
			"--replay": _replay = kv[1]
			"--inputs": _inputs = kv[1]
	_run()


func _run() -> void:
	await process_frame
	if _replay != "":
		var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_replay))
		if _inputs != "":
			config["replay"] = JSON.parse_string(FileAccess.get_file_as_string(_inputs))
		var row := await _fight(config, "replay")
		_emit(row)
		quit(0)
		return
	for arena in _arenas:
		for pair in _pairs:
			var p := str(pair).split(":")
			for s in _seeds:
				var row := await _fight(_config(str(arena), p[0], p[1], int(s)), str(pair))
				_emit(row)
	quit(0)


func _config(arena: String, subject_weapon: String, opp_weapon: String, seed_value: int) -> Dictionary:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var a: Dictionary = WG.legal_build(subject_weapon, "player-1", "A")
	a["ai_skill"] = "regional"
	a["temperament"] = "brawler"
	var b: Dictionary = WG.legal_build(opp_weapon, "ai-1", "B")
	b["controller"] = "ai"
	b["ai_skill"] = "regional"
	b["temperament"] = "technician"
	var h: Array = AG.career_house(arena)
	var rules := {"mode": "fight", "duration_s": _secs, "ko_count_s": 10,
		"endgame_at_s": _endgame, "enforcer": str(h[0]), "enforcer_mode": "zone",
		"enforcer_speed": float(h[1])}
	config["seed"] = seed_value
	config["arena"] = arena
	config["rules"] = rules
	config["debug"] = {"opponent_ai": "normal", "player_ai": "normal"}
	config["bots"] = [a, b]
	return config


func _emit(row: Dictionary) -> void:
	var line := JSON.stringify(row)
	print("JUDGES ", line)
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


func _fight(config: Dictionary, label: String) -> Dictionary:
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
	var arena: Node = fight.get("_arena")
	# Where every control second came from, per scorer: the opponent was airborne,
	# inverted, or neither (so it was the spikes), and, for the spikes, whether they were
	# actually up and whether the scorer was on the patch as well (a clinch).
	var why := [{"air": 0.0, "inv": 0.0, "spike": 0.0, "spike_up": 0.0, "clinch": 0.0},
		{"air": 0.0, "inv": 0.0, "spike": 0.0, "spike_up": 0.0, "clinch": 0.0}]
	var prev := [0.0, 0.0]
	var frames := 0
	var budget := (int((config.get("rules", {}) as Dictionary).get("duration_s", 180)) + 15) * 60 * 3
	while frames < budget and int(fight.get("state")) != STATE_RESULT:
		await physics_frame
		frames += 1
		if int(fight.get("state")) != STATE_FIGHTING:
			continue
		var tallies: Array = fight.get("_tallies") as Array
		for i in 2:
			var now := float((tallies[i] as Dictionary).get("control_s", 0.0))
			var d := now - float(prev[i])
			prev[i] = now
			if d <= 0.0:
				continue
			var fi := 1 - i
			var foe: Node = fbots[fi]
			if bool(fight.call("_is_inverted", foe)):
				why[i]["inv"] += d
			elif bool(fight.call("_is_airborne", foe, fi)):
				why[i]["air"] += d
			else:
				why[i]["spike"] += d
				if arena != null and arena.has_method("spikes_risen") and bool(arena.call("spikes_risen")):
					why[i]["spike_up"] += d
				var me: Vector3 = (fbots[i].get("chassis") as Node3D).global_position
				if FightRules.is_on_spike_patch(me):
					why[i]["clinch"] += d

	var payload: Dictionary = result["payload"]
	var tallies_out: Array = []
	for t in (fight.get("_tallies") as Array):
		tallies_out.append((t as Dictionary).duplicate())
	var ids := ["player-1", "ai-1"]
	var cond_start: Dictionary = payload.get("condition_start", {}) as Dictionary
	var cond_end: Dictionary = payload.get("damage", {}) as Dictionary
	var lost := []
	var lost_frac := []
	var parts := []
	for id in ids:
		var s: Dictionary = cond_start.get(id, {}) as Dictionary
		var e: Dictionary = cond_end.get(id, {}) as Dictionary
		lost.append(snappedf(FightRules.condition_removed(s, e), 0.001))
		var st := FightRules.condition_total(s)
		lost_frac.append(snappedf(FightRules.condition_removed(s, e) / st, 0.001) if st > 0.0 else 0.0)
		parts.append(((payload.get("parts_lost", {}) as Dictionary).get(id, []) as Array).size())
	var o: Dictionary = payload.get("outcome", {}) as Dictionary
	var bots_cfg: Array = config.get("bots", []) as Array
	var row := {
		"label": label, "arena": str(config.get("arena", "")), "seed": int(config.get("seed", 0)),
		"a": "%s/%s/%s" % [bots_cfg[0].get("chassis"), bots_cfg[0].get("drive"), bots_cfg[0].get("weapon")],
		"b": "%s/%s/%s" % [bots_cfg[1].get("chassis"), bots_cfg[1].get("drive"), bots_cfg[1].get("weapon")],
		"outcome": str(o.get("type", "")), "winner": str(o.get("winner", "")),
		"at_s": snappedf(float(o.get("at_s", 0.0)), 0.1),
		"tallies": tallies_out, "why": why,
		"cond_lost": lost, "cond_lost_frac": lost_frac, "parts_lost": parts,
		"judges": payload.get("judges", {}),
		"verdict": payload.get("verdict", {}),
		"payoffs": fight.call("payoffs") if fight.has_method("payoffs") else [],
	}
	bridge.message_sent.disconnect(on_sent)
	root.remove_child(fight)
	fight.queue_free()
	await process_frame
	await process_frame
	return row
