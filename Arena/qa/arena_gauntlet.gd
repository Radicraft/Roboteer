extends SceneTree
## QA (systems gauntlet, 2026-09-25): real AI-vs-AI fights in each of the six arenas with
## the career's house bot on, logging every hazard activation (and whether the shared
## 1.25 s warning ran before it), hazard and house-bot damage per machine, the endgame
## turn, the house bot's release, out-of-arena / pit exits, and machines stuck in geometry.
## Not a test: nothing passes or fails. One JSON line per fight ("ARENA ...", and `--out=`).
##
##   Godot --headless --fixed-fps 60 --path Arena --script qa/arena_gauntlet.gd -- \
##       --arenas=yard,crush --seeds=11,22 --secs=180 --endgame=120 --house=cinder \
##       [--a=wedge/4wd/flipper] [--b=box/6wd/crusher] [--mode=fight|rumble] [--trace=60]
##
## `--house=none` sends no house bot; `--house=career` picks the one CareerEngine would for
## the arena's tier (Scrapyard thresher at 0.5, Regional cinder, ...).

const FIGHT_SCENE := "res://fight/fight.tscn"
const FIXTURE := "res://fight/fixtures/stage3_config.json"
const WG := preload("res://qa/weapons_gauntlet.gd")
const ALL := ["yard", "grinder", "drop_zone", "furnace", "crush", "coliseum"]
const STATE_FIGHTING := 2
const STATE_RESULT := 3

var _arenas: Array = ALL.duplicate()
var _seeds: Array = [11, 22]
var _secs := 180
var _endgame := 120
var _house := "career"
var _a := "wedge/4wd/flipper"
var _b := "box/6wd/crusher"
var _mode := "fight"
var _trace := 0
var _out := ""
var _bosses := ""  # "--boss_b=thresher": the opponent IS that boss build with its boss AI


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() < 2:
			continue
		match kv[0]:
			"--arenas": _arenas = Array(kv[1].split(","))
			"--seeds":
				_seeds = []
				for s in kv[1].split(","):
					_seeds.append(int(s))
			"--secs": _secs = int(kv[1])
			"--endgame": _endgame = int(kv[1])
			"--house": _house = kv[1]
			"--a": _a = kv[1]
			"--b": _b = kv[1]
			"--mode": _mode = kv[1]
			"--trace": _trace = int(kv[1])
			"--out": _out = kv[1]
			"--boss_b": _bosses = kv[1]
	_run()


func _run() -> void:
	await process_frame
	for arena in _arenas:
		for s in _seeds:
			var row := await _fight(str(arena), int(s))
			var line := JSON.stringify(row)
			print("ARENA ", line)
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


static func career_house(arena: String) -> Array:
	match arena:
		"yard": return ["thresher", 0.5]
		"grinder": return ["cinder", 1.0]
		"drop_zone": return ["bandsaw", 1.0]
		"furnace": return ["grudge", 1.0]
		"crush": return ["thresher", 1.0]
		_: return ["anvil", 1.0]


static func build_from(spec: String, id: String, name: String) -> Dictionary:
	var p := spec.split("/")
	var cfg: Dictionary = WG.legal_build(p[2], id, name, p[0], p[1])
	return cfg


static func boss_build(boss_id: String, id: String) -> Dictionary:
	var all: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/parts.json"))
	var b: Dictionary = all["bosses"][boss_id]
	var build: Dictionary = (b["build"] as Dictionary).duplicate(true)
	build["id"] = id
	build["name"] = str(b["name"])
	build["controller"] = "ai"
	build["boss"] = boss_id
	build["damage"] = WG._damage()
	return build


func _fight(arena: String, seed_value: int) -> Dictionary:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var a := build_from(_a, "player-1", "A")
	var b := boss_build(_bosses, "ai-1") if _bosses != "" else build_from(_b, "ai-1", "B")
	b["controller"] = "ai"
	a["ai_skill"] = "national"
	a["temperament"] = "brawler"
	if _bosses == "":
		b["ai_skill"] = "national"
		b["temperament"] = "technician"
	var bots := [a, b]
	var rules := {"mode": _mode, "duration_s": _secs, "ko_count_s": 10, "endgame_at_s": _endgame}
	if _mode == "rumble":
		var c := build_from("box/4wd/horizontal_spinner", "ai-2", "C")
		c["controller"] = "ai"
		bots.append(c)
	var house := ""
	if _house == "career":
		var h := career_house(arena)
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
	config["bots"] = bots

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
	var n := fbots.size()
	var st := {
		"arena_dmg": [], "arena_src": [], "house_dmg": [], "foe_dmg": [], "arena_hits": [],
		"parts_off": [], "phase_at": -1.0, "house_release_at": -1.0,
	}
	for i in n:
		(st["arena_dmg"] as Array).append(0.0)
		(st["arena_src"] as Array).append({})
		(st["house_dmg"] as Array).append(0.0)
		(st["foe_dmg"] as Array).append(0.0)
		(st["arena_hits"] as Array).append(0)
		(st["parts_off"] as Array).append(0)
	for i in n:
		var idx := i
		var bot: Node = fbots[i]
		if bot == null:
			continue
		bot.damage_event.connect(func(info: Dictionary) -> void:
			var att := str(info.get("attacker", ""))
			var sev := float(info.get("severity", 0.0))
			if att == "arena":
				st["arena_dmg"][idx] += sev
				st["arena_hits"][idx] += 1
				var src := str(info.get("source", ""))
				st["arena_src"][idx][src] = int(st["arena_src"][idx].get(src, 0)) + 1
			elif att == "enforcer-1":
				st["house_dmg"][idx] += sev
			else:
				st["foe_dmg"][idx] += sev)
		bot.part_detached.connect(func(_p: String) -> void: st["parts_off"][idx] += 1)
	fight.phase_changed.connect(func(ph: String) -> void:
		if ph == FightTypes.PHASE_ENDGAME:
			st["phase_at"] = float(fight.call("fight_time")))

	var arena_node: Node = fight.get("_arena")
	var acts := {}          # id -> [times]
	var warn_ok := {}       # id -> count of activations with >= 1.2 s of warning clock before
	var warn_bad := {}      # id -> [times] activations without it
	var last_active := {}
	var clock_hist := {}    # id -> ticks of continuous in_s <= lead before activation
	var sounds := {}
	var seen := {}
	var fx: Node = fight.get("_fx")
	var mix: Node = fx.get("_mix") if fx != null else null
	var stuck_run: Array = []
	var stuck_max: Array = []
	var inv_run: Array = []
	var below_floor: Array = []
	var ooa_seen: Array = []
	var escalated_at := -1.0
	for i in n:
		stuck_run.append(0)
		stuck_max.append(0)
		inv_run.append(0)
		below_floor.append(0.0)
		ooa_seen.append(false)
	var house_travel := 0.0
	var house_last := Vector3.INF
	var house_min_gap := 99.0
	var house_pos_samples: Array = []
	var frames := 0
	var budget := (_secs + 15) * 60 * 3
	while frames < budget and int(fight.get("state")) != STATE_RESULT:
		await physics_frame
		frames += 1
		if int(fight.get("state")) != STATE_FIGHTING:
			continue
		var t := float(fight.call("fight_time"))
		var tick := int(fight.get("_tick"))
		if escalated_at < 0.0 and arena_node != null and arena_node.has_method("escalated") \
				and bool(arena_node.call("escalated")):
			escalated_at = t
		if bool(fight.get("_zone_released")) and float(st["house_release_at"]) < 0.0:
			st["house_release_at"] = t
		if arena_node != null and arena_node.has_method("hazard_schedule"):
			for e in (arena_node.call("hazard_schedule") as Array):
				var id := str(e["id"])
				if bool(e.get("always_on", false)):
					if bool(e.get("contact", false)) and not bool(last_active.get(id, false)):
						(acts.get_or_add(id, []) as Array).append(snappedf(t, 0.1))
					last_active[id] = bool(e.get("contact", false))
					continue
				var active := bool(e["active"])
				var in_s := float(e["in_s"])
				if not active:
					if in_s <= ArenaBase.WARN_LEAD_S + 0.001 and in_s > 0.0:
						clock_hist[id] = int(clock_hist.get(id, 0)) + 1
					elif in_s > ArenaBase.WARN_LEAD_S + 0.001:
						clock_hist[id] = 0
				if active and not bool(last_active.get(id, false)):
					(acts.get_or_add(id, []) as Array).append(snappedf(t, 0.1))
					var warned_ticks := int(clock_hist.get(id, 0))
					if warned_ticks >= int(1.2 * 60):
						warn_ok[id] = int(warn_ok.get(id, 0)) + 1
					else:
						(warn_bad.get_or_add(id, []) as Array).append("%.1f(%dt)" % [t, warned_ticks])
					clock_hist[id] = 0
				last_active[id] = active
		if mix != null:
			var active_snd: Dictionary = mix.get("_active")
			for group in active_snd:
				for ent in (active_snd[group] as Array):
					var key := "%s|%s|%d" % [group, str(ent.get("at")), (ent["player"] as Object).get_instance_id() if ent.get("player") != null else 0]
					if not seen.has(key):
						seen[key] = true
						sounds[group] = int(sounds.get(group, 0)) + 1
		var half := float(fight.call("_arena_half_extent")) if fight.has_method("_arena_half_extent") else 5.0
		for i in n:
			var bot: Node = fbots[i]
			if bot == null or bot.get("chassis") == null:
				continue
			var ch: RigidBody3D = bot.get("chassis")
			if not is_instance_valid(ch):
				continue
			var p := ch.global_position
			below_floor[i] = minf(float(below_floor[i]), p.y)
			if absf(p.x) > half or absf(p.z) > half or p.y < -0.5:
				ooa_seen[i] = true
			var inv := bool(bot.call("is_inverted"))
			inv_run[i] = int(inv_run[i]) + 1 if inv else 0
			if ch.linear_velocity.length() < 0.05 and not inv:
				stuck_run[i] = int(stuck_run[i]) + 1
				stuck_max[i] = maxi(int(stuck_max[i]), int(stuck_run[i]))
			else:
				stuck_run[i] = 0
		var enf: Node = fight.get("_enforcer")
		if enf != null and is_instance_valid(enf) and float(st["house_release_at"]) >= 0.0:
			var ecp: Node3D = enf.get("chassis")
			if ecp != null and is_instance_valid(ecp):
				if house_last != Vector3.INF:
					house_travel += Vector2(ecp.global_position.x - house_last.x, ecp.global_position.z - house_last.z).length()
				house_last = ecp.global_position
				for i in n:
					var bb2: Node = fbots[i]
					if bb2 != null and bb2.get("chassis") != null and is_instance_valid(bb2.get("chassis")):
						house_min_gap = minf(house_min_gap, (bb2.get("chassis") as Node3D).global_position.distance_to(ecp.global_position))
		if enf != null and is_instance_valid(enf) and tick % 60 == 0:
			var ec: Node3D = enf.get("chassis")
			if ec != null and is_instance_valid(ec):
				house_pos_samples.append([snappedf(t, 1), snappedf(ec.global_position.x, 0.1), snappedf(ec.global_position.z, 0.1)])
		if _trace > 0 and tick % _trace == 0:
			var parts := []
			for i in n:
				var bb: Node = fbots[i]
				var c3: Node3D = bb.get("chassis") if bb != null else null
				parts.append("%s(%.2f,%.2f,%.2f)inv=%s" % [i, c3.global_position.x, c3.global_position.y, c3.global_position.z, bb.call("is_inverted")] if c3 != null else "-")
			print("TRACE t=%.1f %s ko=%s" % [t, " ".join(parts), str(fight.get("_ko_count"))])

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
	var row := {
		"arena": arena, "seed": seed_value, "house": house, "secs": _secs, "endgame": _endgame,
		"a": _a, "b": _bosses if _bosses != "" else _b, "mode": _mode,
		"outcome": outcome, "winner": winner, "at_s": snappedf(at_s, 0.1),
		"phase_at": snappedf(float(st["phase_at"]), 0.1), "escalated_at": snappedf(escalated_at, 0.1),
		"house_release_at": snappedf(float(st["house_release_at"]), 0.1),
		"activations": acts, "warn_ok": warn_ok, "warn_bad": warn_bad,
		"arena_dmg": _snap(st["arena_dmg"]), "arena_hits": st["arena_hits"], "arena_src": st["arena_src"],
		"house_dmg": _snap(st["house_dmg"]), "foe_dmg": _snap(st["foe_dmg"]), "parts_off": st["parts_off"],
		"stuck_max_s": _ticks_s(stuck_max), "min_y": _snap(below_floor), "ooa_seen": ooa_seen,
		"warn_sounds": _filter(sounds, "warn"), "sounds": sounds,
		"house_path": house_pos_samples.slice(0, 400, 20) if house_pos_samples.size() > 0 else [],
		"eliminated": fight.get("_eliminated"),
		"house_travel_after_release_m": snappedf(house_travel, 0.1),
		"house_min_gap_after_release_m": snappedf(house_min_gap, 0.01),
	}
	bridge.message_sent.disconnect(on_sent)
	root.remove_child(fight)
	fight.queue_free()
	await process_frame
	await process_frame
	return row


static func _snap(a: Array) -> Array:
	var out := []
	for v in a:
		out.append(snappedf(float(v), 0.01))
	return out


static func _ticks_s(a: Array) -> Array:
	var out := []
	for v in a:
		out.append(snappedf(float(v) / 60.0, 0.1))
	return out


static func _filter(d: Dictionary, needle: String) -> Dictionary:
	var out := {}
	for k in d:
		if str(k).find(needle) >= 0:
			out[k] = d[k]
	return out
