extends SceneTree
## QA (systems gauntlet, 2026-09-25): the five side events and the Rumble, run to the end
## with the AI on every machine. Prints "EVENT {json}" per run: the event_result or
## fight_result payload, how long it took, and whether it ended at all.
##
##   Godot --headless --fixed-fps 60 --path Arena --script qa/events_gauntlet.gd -- \
##       --modes=sumo,gauntlet,pinball,football,wall_smash,rumble --seeds=11,22 [--a=wedge/4wd/flipper]

const FIGHT_SCENE := "res://fight/fight.tscn"
const FIXTURE := "res://fight/fixtures/stage3_config.json"
const WG := preload("res://qa/weapons_gauntlet.gd")

var _modes: Array = ["sumo", "gauntlet", "pinball", "football", "wall_smash", "rumble"]
var _seeds: Array = [11, 22]
var _a := "wedge/4wd/flipper"
var _ai_a := "normal"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() < 2:
			continue
		match kv[0]:
			"--modes": _modes = Array(kv[1].split(","))
			"--seeds":
				_seeds = []
				for s in kv[1].split(","):
					_seeds.append(int(s))
			"--a": _a = kv[1]
			"--ai_a": _ai_a = kv[1]
	_run()


func _run() -> void:
	await process_frame
	for m in _modes:
		for s in _seeds:
			print("EVENT ", JSON.stringify(await _one(str(m), int(s))))
	quit(0)


func _one(mode: String, seed_value: int) -> Dictionary:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var p := _a.split("/")
	var a: Dictionary = WG.legal_build(p[2], "player-1", "Player", p[0], p[1])
	a["ai_skill"] = "national"
	var b: Dictionary = WG.legal_build("horizontal_spinner", "ai-1", "B", "box", "4wd")
	b["controller"] = "ai"
	var bots := [a, b]
	if mode == "rumble":
		var c: Dictionary = WG.legal_build("saw", "ai-2", "C", "box", "4wd")
		c["controller"] = "ai"
		bots.append(c)
	config["seed"] = seed_value
	config["arena"] = "yard"
	config["rules"] = {"mode": mode, "duration_s": 180, "ko_count_s": 10}
	config["debug"] = {"opponent_ai": "normal", "player_ai": _ai_a}
	config["bots"] = bots
	var fight: Node = (load(FIGHT_SCENE) as PackedScene).instantiate()
	root.add_child(fight)
	await process_frame
	var got := {"type": "", "payload": {}, "logs": []}
	var bridge: Node = root.get_node("Bridge")
	var on_sent := func(type: String, payload: Dictionary) -> void:
		if type in [FightTypes.MSG_FIGHT_RESULT, "event_result"]:
			got["type"] = type
			got["payload"] = payload
		elif type == FightTypes.MSG_ARENA_LOG and (got["logs"] as Array).size() < 30:
			(got["logs"] as Array).append(str(payload.get("text", "")))
	bridge.message_sent.connect(on_sent)
	fight.call("start_fight", config)
	var frames := 0
	var hud_lines := []
	while frames < 400 * 60 and str(got["type"]) == "":
		await physics_frame
		frames += 1
		var ev: Variant = fight.get("_event")
		if ev != null and frames % 1800 == 0 and (ev as Object).has_method("hud_lines"):
			hud_lines.append(str((ev as Object).call("hud_lines")))
	var row := {
		"mode": mode, "seed": seed_value, "arena_scene": str(fight.get("_arena").scene_file_path) if fight.get("_arena") != null else "",
		"ended": str(got["type"]) != "", "msg": got["type"],
		"t_s": snappedf(float(fight.call("fight_time")), 0.1), "payload": got["payload"],
		"hud": hud_lines.slice(0, 6), "logs": got["logs"],
		"rules_mode": fight.get("_rules_mode"), "bot_count": fight.get("_bot_count"),
	}
	bridge.message_sent.disconnect(on_sent)
	root.remove_child(fight)
	fight.queue_free()
	await process_frame
	await process_frame
	return row
