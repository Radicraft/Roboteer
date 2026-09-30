extends SceneTree
## Walk-outs and the tale of the tape change NOTHING in the fight (wave D,
## docs/wave-d-walkout-notes.md).
##   Godot --headless --path Arena --script tests/walkout_test.gd
##
## Before the hazard fly-past each machine rolls out of its corner under its gate with its
## card on screen (the opponent, then the player, then in a full career intro the house bot
## in its corner). The machine on screen is a ghost; the real one never leaves its mark and
## the intro takes no tick. This test fights the fixture with a rival and a house bot in
## three arenas with intro NONE, FULL (career walk-outs), SHORT, a quick fight's FULL and a
## full intro SKIPPED by a tap in the middle of the first walk-out, and hashes every 30th
## arena tick from the first (the arena and fight ticks, the state, both chassis transforms
## bit exact, both machines' condition, the hazard read and schedule). All identical.
##
## Also: the walk-out plan and its timings; the real machines hidden and put back exactly;
## no ghost, spot or card left; the commentary got walkout_opponent, walkout_player and
## prediction with the right machines; the cards' words (rivals' and house bots' written
## lines, the defaults, the shell's words winning, trimming and capping); the house bot's
## small card when it comes out; every card fits 874 x 402 and 956 x 440 with safe areas.

const FIGHT_SCENE := "res://fight/fight.tscn"
const BOT_SCENE := "res://bot/bot.tscn"
const FIXTURE := "res://fight/fixtures/stage3_config.json"

const SAMPLE_TICKS := 30
const TARGET_ARENA_TICKS := 480
const FRAME_BUDGET := 30000
const FAST := 3.0
const ARENAS := ["yard", "coliseum", "crush"]

var _checks := 0
var _failures := 0
var _fight: Node = null
var _ctx: HashingContext = null
var _last := -1
var _events: Array = []
## Both machines' meshes (path -> [visible, transform]) straight after a start with no intro.
var _ref: Dictionary = {}


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	if not ResourceLoader.exists(BOT_SCENE) or not ResourceLoader.exists(FIGHT_SCENE):
		print("SKIP  walkout: the fight or bot scene is absent")
		quit(0)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	if not parsed is Dictionary:
		_check(false, "the desktop QA fixture loads")
		_finish()
		return
	var fixture: Dictionary = parsed
	_check_words(fixture)
	_check_fit()

	var order: Array = ARENAS.duplicate()
	for raw in OS.get_cmdline_user_args():
		if str(raw).begins_with("--walkout-arenas="):
			order = Array(str(raw).get_slice("=", 1).split(","))
	for arena_id in order:
		FightIntro.test_speed = FAST
		var none: Dictionary = await _simulate(fixture, arena_id, "none", "career")
		_ref = none["snap"]
		var full: Dictionary = await _simulate(fixture, arena_id, "full", "career")
		print("INFO  %s: none %s, full %s (planned %.2f s, walk-outs %s)" % [arena_id,
			str(none["hash"]), str(full["hash"]), float(full["planned"]), str(full["walks"])])
		_check(int(none["samples"]) > 10, "%s: the reference run sampled the fight (%d rows)" % [arena_id, int(none["samples"])])
		_check(str(full["hash"]) == str(none["hash"]),
			"%s: career walk-outs + FULL intro hash the same as NONE, tick for tick (%s)" % [arena_id, str(full["hash"])])
		_check_run(arena_id + " full", full, ["opponent", "player", "house"], FightIntro.WALK_CAREER_FULL_S)
		var short: Dictionary = await _simulate(fixture, arena_id, "short", "career")
		_check(str(short["hash"]) == str(none["hash"]),
			"%s: career walk-outs + SHORT intro hash the same as NONE (%s)" % [arena_id, str(short["hash"])])
		_check_run(arena_id + " short", short, ["opponent", "player"], FightIntro.WALK_CAREER_SHORT_S)
		if arena_id == "yard":
			var quick: Dictionary = await _simulate(fixture, arena_id, "full", "quick")
			_check(str(quick["hash"]) == str(none["hash"]),
				"yard: a quick fight's walk-outs hash the same as NONE (%s)" % str(quick["hash"]))
			_check_run("yard quick", quick, ["opponent", "player"], FightIntro.WALK_QUICK_FULL_S)
		if arena_id == "coliseum":
			FightIntro.test_speed = 1.0
			var skipped: Dictionary = await _simulate(fixture, arena_id, "full", "career", 0.5)
			_check(bool(skipped["skipped"]), "coliseum: a tap skipped the intro during the first walk-out")
			_check(str(skipped["hash"]) == str(none["hash"]),
				"coliseum: a walk-out SKIPPED halfway hashes the same as NONE (%s)" % str(skipped["hash"]))
			_check(bool(skipped["clean"]), "coliseum skipped: everything put back (%s)" % str(skipped["dirty"]))
			_check(bool(skipped["on_spawn"]), "coliseum skipped: both machines on their marks")
			_check(float(skipped["ran"]) < 1.5, "coliseum skipped: it went straight to the drop (%.2f s)" % float(skipped["ran"]))
	# The house bot's small card when it comes out mid-fight.
	FightIntro.test_speed = FAST
	var cfg := _config(fixture, "yard", "none", "career")
	_fight.call("start_fight", cfg)
	for i in 3:
		await process_frame
	_fight.call("_tape_house_bot_out")
	await process_frame
	var overlay: TapeCardOverlay = _fight.call("tape_overlay")
	_check(overlay != null and overlay.card_visible() and overlay.is_compact()
		and str(overlay.card().get("name", "")) == "THRESHER",
		"the house bot coming out puts up its small card (%s)" % (str(overlay.card().get("name", "")) if overlay != null else "no overlay"))
	# A replay gets no walk-outs (no intro at all).
	var replay_cfg := _config(fixture, "yard", "full", "career")
	replay_cfg["replay"] = {"seed": replay_cfg.get("seed", 0), "tick_hz": 60, "inputs": [[1, 0.0, 0.0, 0, 0]]}
	_fight.call("start_fight", replay_cfg)
	await process_frame
	_check(_fight.call("intro") == null and not overlay.card_visible(), "a replay plays no walk-outs and shows no card")
	FightIntro.test_speed = 1.0
	_finish()


# ---------------------------------------------------------------- words

func _check_words(fixture: Dictionary) -> void:
	var parts := PartsCatalogue.parts()
	var rivals: Dictionary = parts.get("rivals", {})
	var bosses: Dictionary = parts.get("bosses", {})
	var all_ok := true
	var seen := {}
	for table in [rivals, bosses]:
		for id in table.keys():
			var r: Dictionary = table[id]
			for key in ["strength", "weakness"]:
				var line := str(r.get(key, ""))
				if line == "" or line.length() > TapeCards.LINE_MAX or line.find("—") >= 0 \
						or line.find("!") >= 0 or seen.has(line):
					all_ok = false
					print("INFO  bad written line ", id, " ", key, ": '", line, "'")
				seen[line] = true
	_check(all_ok and rivals.size() == 8 and bosses.size() == 5,
		"every rival (%d) and house bot (%d) has its own strength and weakness, 60 characters or fewer, no em dash, no exclamation mark"
		% [rivals.size(), bosses.size()])
	var player: Dictionary = (fixture["bots"] as Array)[0]
	var lines := TapeCards.default_lines(player)
	_check(str(lines[0]).ends_with("of flipper.") and str(lines[1]) == "The back end is mostly hope.",
		"the fixture's default lines come from its build (%s / %s)" % [lines[0], lines[1]])
	var two := player.duplicate(true)
	(two["armour"] as Dictionary)["rear"] = {"material": "steel", "thickness": 2}
	two["drive"] = "2wd"
	_check(str(TapeCards.default_lines(two)[1]) == "Two wheels, both load bearing.", "a 2WD's default weakness")
	var tough := player.duplicate(true)
	(tough["armour"] as Dictionary)["rear"] = {"material": "steel", "thickness": 2}
	(tough["armour"] as Dictionary)["top"] = {"material": "steel", "thickness": 2}
	_check(str(TapeCards.default_lines(tough)[1]) == "It knows it.", "nothing obvious wrong: 'It knows it.'")
	_check(TapeCards.clean("  Built\nin a   shed.  ") == "Built in a shed.", "a typed line is trimmed to one line")
	var long := "This line was typed by somebody with a great deal to say about their machine"
	var capped := TapeCards.clean(long)
	_check(capped.length() <= TapeCards.LINE_MAX and long.begins_with(capped) and not capped.ends_with(" "),
		"a long line is cut at a word within 60 characters ('%s')" % capped)
	# The shell's words win, field by field; what it leaves out is made here.
	var cfg := fixture.duplicate(true)
	(cfg["bots"] as Array)[1]["name"] = "Clatterbox"
	cfg["tape"] = {"style": "quick", "cards": [
		{"side": "player", "strength": "  Built in a shed. ", "weakness": "", "record": "First meeting"},
	]}
	var cards := TapeCards.cards(cfg, "anvil")
	var p: Dictionary = cards["player"]
	var o: Dictionary = cards["opponent"]
	var h: Dictionary = cards["house"]
	_check(str(p["strength"]) == "Built in a shed." and str(p["weakness"]) == str(TapeCards.default_lines(player)[1])
		and str(p["record"]) == "First meeting" and str(p["name"]) == "Tinribs",
		"the player's typed line wins, an empty one falls back to the build's")
	_check(str(o["roboteer"]) == "Dot Ferris" and str(o["strength"]) == str((rivals["clatterbox"] as Dictionary)["strength"]),
		"a rival's card carries its roboteer and its written lines with no shell words")
	_check(str(h["name"]) == "ANVIL" and str(h["weakness"]) == "The sides are another matter." and str(h["label"]) == "HOUSE BOT",
		"the house bot's card is its own")
	_check(TapeCards.style(cfg) == "quick" and TapeCards.style({}) == "career", "the style key")
	_check(is_equal_approx(FightIntro.walk_seconds("full", "career"), 2.2) and is_equal_approx(FightIntro.walk_seconds("short", "career"), 1.0)
		and FightIntro.walk_seconds("full", "quick") < FightIntro.walk_seconds("full", "career")
		and FightIntro.walk_seconds("none", "career") == 0.0, "walk-out seconds per mode and style")


## Every card, the longest words it can hold, inside the safe area on both phones.
func _check_fit() -> void:
	var overlay := TapeCardOverlay.new()
	root.add_child(overlay)
	var worst := {"name": "IRON SPRAT THE SECOND", "label": "OPPONENT", "roboteer": "Quill Adeoye-Haverly",
		"mass": "99.5 kg", "drive": "Adaptive tracks", "weapon": "Full body spinner",
		"stats": [{"label": "SPEED", "value": "5/5"}, {"label": "HIT", "value": "5/5"}, {"label": "ARMOUR", "value": "32.5 kg"}],
		"record": "Won 12, lost 11 against Iron Sprat The Second",
		"strength": "Made from a car bonnet, a MOWER DECK and a great deal of hope",
		"weakness": "Wobbles When Wet, Worries Whenever Wheels Wander Westwards."}
	for phone in [[Vector2(2622, 1206), {"left": 186.0, "top": 0.0, "right": 186.0, "bottom": 63.0}],
			[Vector2(2868, 1320), {"left": 186.0, "top": 0.0, "right": 186.0, "bottom": 63.0}]]:
		var size: Vector2 = phone[0]
		overlay.set_safe_area(phone[1])
		for compact in [false, true]:
			overlay.show_card(worst, compact)
			var lay: Dictionary = overlay.call("_layout", size, overlay.call("_pt", size))
			var rect: Rect2 = lay["rect"]
			var safe: Dictionary = phone[1]
			var inside := Rect2(Vector2(float(safe["left"]), float(safe["top"])),
				size - Vector2(float(safe["left"]) + float(safe["right"]), float(safe["top"]) + float(safe["bottom"])))
			var lines_ok := true
			for r in lay["rows"]:
				if str(r[0]) == "lines" and (r[1] as Array).size() > 2:
					lines_ok = false
			_check(inside.encloses(rect) and rect.size.x <= size.x * 0.42 and lines_ok,
				"%s card fits %dx%d inside the safe area (%s), each line on two rows at most" % [
					"compact" if compact else "full", int(size.x), int(size.y), str(rect)])
	overlay.queue_free()


# ---------------------------------------------------------------- one fight

func _config(fixture: Dictionary, arena_id: String, mode: String, style: String) -> Dictionary:
	var config := fixture.duplicate(true)
	config["arena"] = arena_id
	var rules: Dictionary = config.get("rules", {}) as Dictionary
	rules["duration_s"] = 180
	rules["mode"] = "fight"
	rules["enforcer"] = "thresher"
	rules["enforcer_mode"] = "zone"
	rules["enforcer_speed"] = 0.6
	config["rules"] = rules
	(config["bots"] as Array)[1]["name"] = "Clatterbox"
	if mode != "":
		config["intro"] = mode
	config["tape"] = {"style": style, "cards": [
		{"side": "player", "strength": "Built in a shed.", "weakness": "Knows it.", "record": "First meeting"},
		{"side": "opponent", "record": "First meeting", "stats": [{"label": "SPEED", "value": "3/5"}]},
	]}
	return config


func _simulate(fixture: Dictionary, arena_id: String, mode: String, style: String, skip_at: float = -1.0) -> Dictionary:
	if _fight == null:
		_fight = (load(FIGHT_SCENE) as PackedScene).instantiate()
		root.add_child(_fight)
		await process_frame
	_install_listener()
	_events.clear()
	var config := _config(fixture, arena_id, mode, style)
	_ctx = HashingContext.new()
	_ctx.start(HashingContext.HASH_SHA256)
	_last = -1
	var samples := [0]
	var done := [false]
	var on_step := func() -> void:
		if done[0]:
			return
		var row: Variant = _sample()
		if row == null:
			return
		samples[0] += 1
		if int(row) >= TARGET_ARENA_TICKS or int(_fight.get("state")) == 3:
			done[0] = true
	var out := {"planned": 0.0, "ran": 0.0, "walks": [], "walk_s": [], "held": false, "on_spawn": false,
		"clean": true, "dirty": [], "skipped": false, "done_beat": false, "card_seen": []}
	var beat_cb := func(beat_name: String, info: Dictionary) -> void:
		if beat_name == "walkout":
			(out["walks"] as Array).append(str(info.get("side", "")))
			var ov: TapeCardOverlay = _fight.call("tape_overlay")
			(out["card_seen"] as Array).append(str(ov.card().get("name", "")) if ov != null else "")
		if beat_name == "walkouts_done":
			out["done_beat"] = true
		if beat_name == "intro_skipped":
			out["skipped"] = true
		if beat_name == "intro_end":
			var arena: Node = _fight.get("_arena")
			out["held"] = int(arena.get("_ticks")) == 0 and int(_fight.get("_tick")) == 0
			out["on_spawn"] = _bots_where() == out.get("spawn", [])
			out["ran"] = float(info.get("at_s", 0.0))
			out["dirty"] = _dirty()
			out["clean"] = (out["dirty"] as Array).is_empty()
	physics_frame.connect(on_step)
	_fight.connect("intro_beat", beat_cb)
	_fight.call("start_fight", config)
	out["spawn"] = _bots_where()
	out["snap"] = _bot_snapshot()
	var intro: FightIntro = _fight.call("intro")
	if intro != null:
		out["planned"] = intro.planned_length()
		for s in intro.shots():
			if str(s["kind"]) in ["walkout", "house"]:
				(out["walk_s"] as Array).append([str(s.get("side", "")), float(s["dur"])])
		# While it waits: the real machines that walk out are hidden, and never moved.
		out["hidden_at_start"] = _hidden_count(out["snap"])
	var frames := 0
	var skip_sent := false
	while not done[0] and frames < FRAME_BUDGET:
		if skip_at >= 0.0 and not skip_sent and intro != null and is_instance_valid(intro) \
				and intro.holding() and intro.elapsed() >= skip_at:
			skip_sent = true
			var touch := InputEventScreenTouch.new()
			touch.pressed = true
			touch.position = Vector2(400, 300)
			Input.parse_input_event(touch)
		await process_frame
		frames += 1
	physics_frame.disconnect(on_step)
	if _fight.is_connected("intro_beat", beat_cb):
		_fight.disconnect("intro_beat", beat_cb)
	out["events"] = _events.duplicate(true)
	out["hash"] = _ctx.finish().hex_encode().substr(0, 16)
	out["samples"] = samples[0]
	return out


func _check_run(tag: String, r: Dictionary, sides: Array, each_s: float) -> void:
	_check(r["walks"] == sides, "%s: the walk-outs were %s (%s)" % [tag, str(sides), str(r["walks"])])
	var timing_ok := true
	for w in r["walk_s"]:
		var want := each_s if str(w[0]) != "house" else FightIntro.HOUSE_SHOT_S
		timing_ok = timing_ok and is_equal_approx(float(w[1]), want)
	_check(timing_ok, "%s: each walk-out lasts %.1f s (%s)" % [tag, each_s, str(r["walk_s"])])
	_check(int(r.get("hidden_at_start", 0)) > 0, "%s: the real machines wait out of sight (%d meshes)" % [tag, int(r.get("hidden_at_start", 0))])
	_check(bool(r["held"]), "%s: the intro held the clock" % tag)
	_check(bool(r["on_spawn"]), "%s: both machines exactly on their fight marks at the end" % tag)
	_check(bool(r["clean"]), "%s: everything put back: machine meshes, no ghost, no spot, no card (%s)" % [tag, str(r["dirty"])])
	var names: Array = r["card_seen"]
	_check(names.size() >= 2 and str(names[0]) == "Clatterbox" and str(names[1]) == "Tinribs",
		"%s: each walk-out had its own card up (%s)" % [tag, str(names)])
	var keys: Array = (r["events"] as Array).map(func(e: Array) -> String: return str(e[0]))
	var ok := keys.slice(0, 3) == ["walkout_opponent", "walkout_player", "prediction"] and bool(r["done_beat"])
	if ok:
		var first: Dictionary = r["events"][0][1]
		var second: Dictionary = r["events"][1][1]
		ok = str(first.get("attacker", "")) == "Clatterbox" and str(first.get("victim", "")) == "Tinribs" \
			and str(second.get("attacker", "")) == "Tinribs" and str(first.get("arena", "")) != ""
	_check(ok, "%s: commentary got walkout_opponent, walkout_player, prediction with the machines named (%s)" % [tag, str(keys)])


# ---------------------------------------------------------------- the commentary listener

## A commentary object that records `call_event`, standing in for wave-d-commentary's.
func _install_listener() -> void:
	var script := GDScript.new()
	script.source_code = "extends \"res://fight/commentary.gd\"\nvar sink: Callable\nfunc call_event(key: String, ctx: Dictionary) -> void:\n\tif sink.is_valid():\n\t\tsink.call(key, ctx)\n"
	script.reload()
	var c: Object = script.new()
	c.set("sink", func(key: String, ctx: Dictionary) -> void: _events.append([key, ctx]))
	_fight.set("_commentary", c)


# ---------------------------------------------------------------- sampling

func _sample() -> Variant:
	var arena: Node = _fight.get("_arena")
	if arena == null or not is_instance_valid(arena):
		return null
	var at := int(arena.get("_ticks"))
	var state := int(_fight.get("state"))
	if at == _last:
		return null
	_last = at
	if at % SAMPLE_TICKS != 0 and at < TARGET_ARENA_TICKS and state != 3:
		return null
	var row := [at, int(_fight.get("_tick")), state]
	for bot in (_fight.get("_bots") as Array):
		if bot == null or not is_instance_valid(bot):
			row.append(null)
			continue
		var chassis: Node3D = bot.get("chassis") as Node3D
		row.append(chassis.global_transform if chassis != null and chassis.is_inside_tree() and state != 3 else null)
		row.append(bot.call("condition") if bot.has_method("condition") else {})
	if arena.has_method("hazard_helpers"):
		row.append(arena.call("hazard_helpers"))
	if arena.has_method("hazard_schedule"):
		var sched := []
		for e in arena.call("hazard_schedule"):
			sched.append([str(e["id"]), float(e["in_s"]), bool(e["active"]), bool(e.get("contact", false))])
		row.append(sched)
	_ctx.update(var_to_bytes(row))
	return at


func _bots_where() -> Array:
	var out := []
	for bot in (_fight.get("_bots") as Array):
		if bot == null or not is_instance_valid(bot):
			out.append(null)
			continue
		var chassis: Node3D = bot.get("chassis") as Node3D
		out.append(chassis.global_transform if chassis != null and chassis.is_inside_tree() else null)
	return out


## Every mesh of both machines: path under the fight -> [visible, local transform].
func _bot_snapshot() -> Dictionary:
	var snap := {}
	for bot in (_fight.get("_bots") as Array):
		if bot == null or not is_instance_valid(bot):
			continue
		for n in (bot as Node).find_children("*", "MeshInstance3D", true, false):
			snap[str(_fight.get_path_to(n))] = [(n as MeshInstance3D).visible, (n as MeshInstance3D).transform]
	return snap


## Meshes drawn in the no-intro reference that are not drawn now.
func _hidden_count(now: Dictionary) -> int:
	var n := 0
	for path in _ref.keys():
		if now.has(path) and bool(_ref[path][0]) and not bool(now[path][0]):
			n += 1
	return n


func _dirty() -> Array:
	var out := []
	var now := _bot_snapshot()
	if now.size() != _ref.size():
		out.append("machine mesh count %d, reference %d" % [now.size(), _ref.size()])
	for path in _ref.keys():
		if not now.has(path):
			continue
		if bool(now[path][0]) != bool(_ref[path][0]):
			out.append("visibility of " + path.get_file())
		if (now[path][1] as Transform3D) != (_ref[path][1] as Transform3D):
			out.append("transform of " + path.get_file())
	var world: Node = _fight.get("_world")
	var ghosts: Node = world.get_node_or_null("IntroGhosts") if world != null else null
	if ghosts != null and not ghosts.is_queued_for_deletion():
		out.append("ghost root left")
	var overlay: TapeCardOverlay = _fight.call("tape_overlay")
	if overlay != null and overlay.card_visible():
		out.append("tape card still up")
	var arena: Node = _fight.get("_arena")
	var kit: Node = arena.get_node_or_null("VenueKit") if arena != null else null
	if kit != null and kit.has_method("entrance_playing") and bool(kit.call("entrance_playing")):
		out.append("venue entrance still playing")
	var rig: Node = _fight.get("_camera_rig")
	if rig != null and rig.has_method("camera"):
		var cam := rig.call("camera") as Camera3D
		if cam == null or not cam.current:
			out.append("fight camera not current")
	return out


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS  ", label)
	else:
		_failures += 1
		printerr("FAIL  ", label)
		print("FAIL  ", label)


func _finish() -> void:
	print("")
	if _failures == 0:
		print("PASS  walkout: %d checks, 0 failures" % _checks)
		quit(0)
	else:
		print("FAIL  walkout: %d checks, %d failures" % [_checks, _failures])
		quit(1)
