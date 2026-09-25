extends SceneTree
## QA (systems gauntlet, 2026-09-25): the Godot side of career fights with the configs the
## shell really sends. For each tier: the player's starter-class machine (AI-driven, the
## tier's own skill) against each rival that starts at or before that tier, built with its
## upgrades applied up to that tier, in the tier's arena, with the tier's house bot, the
## round clock (the opener: 120 s, endgame 80; everything else 180 / 120) and the tier's
## ai_skill and the rival's temperament. One JSON line per fight ("CAREER ...").
##
##   Godot --headless --fixed-fps 60 --path Arena --script qa/career_gauntlet.gd -- \
##       --tiers=scrapyard,masters --seeds=11 [--player=wedge/4wd/flipper]

const FIGHT_SCENE := "res://fight/fight.tscn"
const FIXTURE := "res://fight/fixtures/stage3_config.json"
const WG := preload("res://qa/weapons_gauntlet.gd")
const TIERS := ["scrapyard", "regional", "national", "championship", "masters"]
const HOUSE := {
	"scrapyard": ["thresher", 0.5], "regional": ["cinder", 1.0], "national": ["bandsaw", 1.0],
	"championship": ["anvil", 1.0], "masters": ["bandsaw", 1.0],
}
const HOUSE_BY_ARENA := {"furnace": "grudge", "crush": "thresher", "drop_zone": "cinder", "coliseum": "anvil"}

var _tiers: Array = TIERS.duplicate()
var _seeds: Array = [11]
var _player := "wedge/4wd/flipper"
var _out := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() < 2:
			continue
		match kv[0]:
			"--tiers": _tiers = Array(kv[1].split(","))
			"--seeds":
				_seeds = []
				for s in kv[1].split(","):
					_seeds.append(int(s))
			"--player": _player = kv[1]
			"--out": _out = kv[1]
	_run()


func _run() -> void:
	await process_frame
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/parts.json"))
	var tiers: Dictionary = data["career"]["tiers"]
	for tier in _tiers:
		var t: Dictionary = tiers[tier]
		for arena in (t["arenas"] as Array):
			for rival_id in data["rivals"]:
				var rv: Dictionary = data["rivals"][rival_id]
				if TIERS.find(str(rv["from_tier"])) > TIERS.find(str(tier)):
					continue
				for s in _seeds:
					var opener: bool = tier == "scrapyard"
					var row := await _fight(str(tier), str(arena), str(rival_id), _rival_build(rv, str(tier)), int(s), opener)
					var line := JSON.stringify(row)
					print("CAREER ", line)
					if _out != "":
						var f: FileAccess
						if FileAccess.file_exists(_out):
							f = FileAccess.open(_out, FileAccess.READ_WRITE)
							f.seek_end()
						else:
							f = FileAccess.open(_out, FileAccess.WRITE)
						f.store_line(line)
						f.close()
	quit(0)


func _rival_build(rv: Dictionary, tier: String) -> Dictionary:
	var b: Dictionary = (rv["build"] as Dictionary).duplicate(true)
	var ups: Dictionary = rv.get("upgrades", {})
	for tt in TIERS:
		if TIERS.find(tt) > TIERS.find(tier):
			break
		for u in (ups.get(tt, []) as Array):
			var slot := str(u["slot"])
			if slot.begins_with("armour_"):
				b["armour"][slot.substr(7)] = {"material": u["material"], "thickness": u["thickness"]}
			elif slot.begins_with("utility_"):
				var util: Array = b.get("utility", [])
				var idx := int(slot.substr(8)) - 1
				while util.size() <= idx:
					util.append("")
				util[idx] = u["part"]
				b["utility"] = util
			else:
				b[slot] = u["part"]
	b["id"] = "ai-1"
	b["name"] = str(rv["name"])
	b["controller"] = "ai"
	b["temperament"] = str(rv.get("temperament", "brawler"))
	b["ai_skill"] = tier
	b["damage"] = WG._damage()
	return b


func _fight(tier: String, arena: String, rival: String, b: Dictionary, seed_value: int, opener: bool) -> Dictionary:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var p := _player.split("/")
	var a: Dictionary = WG.legal_build(p[2], "player-1", "Player", p[0], p[1])
	a["ai_skill"] = tier
	a["temperament"] = "brawler"
	var house: String = HOUSE_BY_ARENA.get(arena, HOUSE[tier][0]) if tier in ["championship", "masters", "national"] and arena in HOUSE_BY_ARENA else str(HOUSE[tier][0])
	if tier == "national":
		house = "grudge" if arena == "furnace" else "bandsaw"
	var rules := {"mode": "fight", "duration_s": 120 if opener else 180, "ko_count_s": 10,
		"endgame_at_s": 80 if opener else 120, "enforcer": house, "enforcer_mode": "zone",
		"enforcer_speed": float(HOUSE[tier][1])}
	config["seed"] = seed_value
	config["arena"] = arena
	config["rules"] = rules
	config["debug"] = {"opponent_ai": "normal", "player_ai": "normal"}
	config["bots"] = [a, b]
	var legal := BuildRules.is_valid(b)
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
	var frames := 0
	while frames < 200 * 60 * 3 and int(fight.get("state")) != 3:
		await physics_frame
		frames += 1
	var payload: Dictionary = result["payload"]
	var o: Dictionary = payload.get("outcome", {}) if payload.get("outcome") is Dictionary else {}
	var row := {
		"tier": tier, "arena": arena, "rival": rival, "seed": seed_value, "house": house,
		"rival_build": "%s/%s/%s" % [b["chassis"], b["drive"], b["weapon"]], "rival_legal": legal,
		"rival_errors": BuildRules.validate(b), "rival_kg": BuildRules.total_weight(b),
		"outcome": str(o.get("type", payload.get("outcome_type", ""))),
		"winner": str(o.get("winner", payload.get("winner", ""))),
		"at_s": snappedf(float(o.get("at_s", fight.call("fight_time"))), 0.1),
		"judges": payload.get("judges", {}), "damage": payload.get("damage", {}),
		"scrap": payload.get("scrap", {}), "result_keys": payload.keys(),
	}
	bridge.message_sent.disconnect(on_sent)
	root.remove_child(fight)
	fight.queue_free()
	await process_frame
	await process_frame
	return row
