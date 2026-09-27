extends SceneTree
## The fight intro changes NOTHING in the fight (wave B, docs/wave-b-intro-notes.md).
##   Godot --headless --path Arena --script tests/intro_test.gd
##
## The intro is a camera fly-past before the countdown, and the arena ticks through the
## countdown (hazard phases are folded from FIGHT = arena tick 181), so the claim that
## matters is that the intro adds no tick and moves no phase. Each of the six arenas fights
## the desktop fixture with intro NONE and FULL (and the Yard and the Coliseum with SHORT,
## the Crush with a full intro SKIPPED by a tap), and every run hashes, on every 30th arena
## tick from the first: the arena's own tick counter, the fight tick, the state, both chassis
## transforms (var_to_bytes, bit exact), both machines' condition, the AI's hazard read and
## every hazard's schedule (id, seconds to act, active). The hashes must be identical.
##
## Also checked: the intro really held the clock (arena tick 0, the countdown not started,
## both machines exactly on their spawn transforms when it ended); it named what it showed;
## it put back everything it touched (no ghost left, every hidden mesh shown, the spinners
## where they were, the fight camera current); a replay, the test arena and a configuration
## without the key get no intro; a tap skips.

const FIGHT_SCENE := "res://fight/fight.tscn"
const BOT_SCENE := "res://bot/bot.tscn"
const FIXTURE := "res://fight/fixtures/stage3_config.json"

const SAMPLE_TICKS := 30
## Arena ticks per run: the 180 of the countdown and five seconds of fight.
const TARGET_ARENA_TICKS := 480
const ORDER := ["yard", "grinder", "drop_zone", "furnace", "crush", "coliseum"]
const FRAME_BUDGET := 30000
## The intro runs this much faster in most runs (FightIntro.test_speed); the Coliseum's full
## intro runs at 1x so the real timings are covered once.
const FAST := 3.0

var _checks := 0
var _failures := 0
var _fight: Node = null
var _ctx: HashingContext = null
var _last := -1


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	if not ResourceLoader.exists(BOT_SCENE) or not ResourceLoader.exists(FIGHT_SCENE):
		print("SKIP  intro: the fight or bot scene is absent")
		quit(0)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	if not parsed is Dictionary:
		_check(false, "the desktop QA fixture loads")
		_finish()
		return
	var fixture: Dictionary = parsed

	# The mode rules, without a fight.
	_check(FightIntro.mode_for({}, "fight", false) == "none", "no intro key: no intro")
	_check(FightIntro.mode_for({"intro": "full"}, "fight", false) == "full", "intro full honoured")
	_check(FightIntro.mode_for({"intro": "short"}, "rumble", false) == "short", "intro short honoured")
	_check(FightIntro.mode_for({"intro": "full"}, "fight", true) == "none", "a replay never gets an intro")
	_check(FightIntro.mode_for({"intro": "full"}, "test", false) == "none", "the test arena never gets an intro")
	_check(FightIntro.mode_for({"intro": "loud"}, "fight", false) == "none", "an unknown intro value is none")

	var order: Array = ORDER.duplicate()
	for raw in OS.get_cmdline_user_args():
		if str(raw).begins_with("--intro-arenas="):
			order = Array(str(raw).get_slice("=", 1).split(","))
	for arena_id in order:
		FightIntro.test_speed = FAST
		var none: Dictionary = await _simulate(fixture, arena_id, "none")
		FightIntro.test_speed = 1.0 if arena_id == "coliseum" else FAST
		var full: Dictionary = await _simulate(fixture, arena_id, "full")
		print("INFO  %s: none %s, full %s (intro %.2f s planned, %.2f s run, shots %s)"
			% [arena_id, str(none["hash"]), str(full["hash"]), float(full["planned"]),
				float(full["ran"]), str(full["titles"])])
		_check(str(none["mode"]) == "none" and str(full["mode"]) == "full",
			"%s: the modes were what was asked (%s, %s)" % [arena_id, none["mode"], full["mode"]])
		_check(int(none["samples"]) > 10, "%s: the reference run sampled the fight (%d rows)"
			% [arena_id, int(none["samples"])])
		_check(str(full["hash"]) == str(none["hash"]),
			"%s: intro FULL hashes the same as NONE, tick for tick (%s)" % [arena_id, str(full["hash"])])
		_check_intro_run(arena_id, full)
		if arena_id in ["yard", "coliseum"]:
			FightIntro.test_speed = FAST
			var short: Dictionary = await _simulate(fixture, arena_id, "short")
			_check(str(short["hash"]) == str(none["hash"]),
				"%s: intro SHORT hashes the same as NONE (%s)" % [arena_id, str(short["hash"])])
			_check(float(short["planned"]) <= 2.2 and float(short["planned"]) >= 1.5,
				"%s: the short intro is about two seconds (%.2f s)" % [arena_id, float(short["planned"])])
			_check_intro_run(arena_id + " short", short)
		if arena_id == "crush":
			FightIntro.test_speed = 1.0
			var skipped: Dictionary = await _simulate(fixture, arena_id, "full", 0.6)
			_check(bool(skipped["skipped"]), "crush: a tap skipped the intro")
			_check(float(skipped["ran"]) < float(skipped["planned"]) - 1.5,
				"crush: the skip cut it short (%.2f s of %.2f s)" % [float(skipped["ran"]), float(skipped["planned"])])
			_check(str(skipped["hash"]) == str(none["hash"]),
				"crush: a SKIPPED intro hashes the same as NONE (%s)" % str(skipped["hash"]))
			_check_intro_run(arena_id + " skipped", skipped)
		if arena_id == "coliseum":
			_check(float(full["planned"]) >= 5.0 and float(full["planned"]) <= 6.6,
				"coliseum: the full intro is five to six and a half seconds (%.2f s)" % float(full["planned"]))
			_check(absf(float(full["ran"]) - float(full["planned"])) < 0.25,
				"coliseum: at 1x it ran its planned length (%.2f of %.2f s)" % [float(full["ran"]), float(full["planned"])])

	# A replay of an intro'd configuration gets none, through the real start path.
	FightIntro.test_speed = FAST
	var replay_cfg := _config(fixture, "yard", "full")
	replay_cfg["replay"] = {"seed": replay_cfg.get("seed", 0), "tick_hz": 60, "inputs": [[1, 0.0, 0.0, 0, 0]]}
	_fight.call("start_fight", replay_cfg)
	await process_frame
	_check(str(_fight.call("intro_mode")) == "none" and _fight.call("intro") == null,
		"a replay configuration carrying intro full plays no intro")
	var test_cfg := _config(fixture, "yard", "full")
	(test_cfg["rules"] as Dictionary)["mode"] = "test"
	_fight.call("start_fight", test_cfg)
	await process_frame
	_check(str(_fight.call("intro_mode")) == "none", "the test arena plays no intro")
	FightIntro.test_speed = 1.0
	_finish()


func _check_intro_run(tag: String, r: Dictionary) -> void:
	_check(bool(r["held"]), "%s: the intro held the clock (arena tick %d, countdown %.3f s at its end)"
		% [tag, int(r["arena_ticks_at_end"]), float(r["countdown_at_end"])])
	_check(bool(r["on_spawn"]), "%s: both machines were exactly on their spawn transforms when it ended" % tag)
	_check(not (r["titles"] as Array).is_empty(), "%s: it named what it showed %s" % [tag, str(r["titles"])])
	_check(bool(r["clean"]), "%s: it put everything back (%s)" % [tag, str(r["dirty"])])


func _config(fixture: Dictionary, arena_id: String, mode: String) -> Dictionary:
	var config := fixture.duplicate(true)
	config["arena"] = arena_id
	var rules: Dictionary = config.get("rules", {}) as Dictionary
	rules["duration_s"] = 180
	config["rules"] = rules
	if mode != "":
		config["intro"] = mode
	return config


func _simulate(fixture: Dictionary, arena_id: String, mode: String, skip_at: float = -1.0) -> Dictionary:
	if _fight == null:
		_fight = (load(FIGHT_SCENE) as PackedScene).instantiate()
		root.add_child(_fight)
		await process_frame
	var config := _config(fixture, arena_id, mode)
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
	var out := {"mode": "", "planned": 0.0, "ran": 0.0, "titles": [], "held": false,
		"on_spawn": false, "clean": true, "dirty": [], "skipped": false,
		"arena_ticks_at_end": -1, "countdown_at_end": -1.0}
	var titles: Array = out["titles"]
	var beat_cb := func(beat_name: String, info: Dictionary) -> void:
		if beat_name in ["intro_arena", "intro_hazard"]:
			titles.append(str(info.get("title", "")))
		if beat_name == "intro_skipped":
			out["skipped"] = true
		if beat_name == "intro_end":
			var arena: Node = _fight.get("_arena")
			out["arena_ticks_at_end"] = int(arena.get("_ticks")) if arena != null else -1
			out["countdown_at_end"] = float(_fight.get("_countdown_time"))
			out["held"] = int(out["arena_ticks_at_end"]) == 0 and float(out["countdown_at_end"]) == 0.0 \
				and int(_fight.get("_tick")) == 0
			out["on_spawn"] = _bots_where(_fight) == out.get("spawn", [])
			out["ran"] = float(info.get("at_s", 0.0))
			var dirty: Array = _dirty(out.get("watch", {}))
			out["clean"] = dirty.is_empty()
			out["dirty"] = dirty
	physics_frame.connect(on_step)
	_fight.connect("intro_beat", beat_cb)
	_fight.call("start_fight", config)
	out["mode"] = str(_fight.call("intro_mode"))
	out["spawn"] = _bots_where(_fight)
	var intro: FightIntro = _fight.call("intro")
	if intro != null:
		out["planned"] = intro.planned_length()
		# Transforms now, before anything could have turned; visibility after the frame in
		# which the venue kit builds (it hides the arena's own grid and caps, deferred) and
		# before the first hazard shot (the establishing shot has no ghost).
		out["watch"] = _watch_list(_fight.get("_arena"))
		await process_frame
		_watch_visibility(out["watch"], _fight.get("_arena"))
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
	if intro != null and not out.has("watch"):
		out["clean"] = false
	if intro != null and int(out["arena_ticks_at_end"]) < 0:
		out["clean"] = false
		(out["dirty"] as Array).append("the intro never ended")
	out.erase("watch")
	out["hash"] = _ctx.finish().hex_encode().substr(0, 16)
	out["samples"] = samples[0]
	return out


## One row on every SAMPLE_TICKS-th arena tick (countdown included). Returns the arena tick
## sampled, or null.
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


func _bots_where(fight: Node) -> Array:
	var out := []
	for bot in (fight.get("_bots") as Array):
		if bot == null or not is_instance_valid(bot):
			out.append(null)
			continue
		var chassis: Node3D = bot.get("chassis") as Node3D
		out.append(chassis.global_transform if chassis != null and chassis.is_inside_tree() else null)
	return out


## Every mesh under the arena with its visibility, and the paint-only spinners' transforms,
## as they were before the intro touched anything.
func _watch_list(arena: Node) -> Dictionary:
	var meshes := {}
	if arena == null:
		return {}
	for n in arena.find_children("*", "MeshInstance3D", true, false):
		meshes[n] = [(n as MeshInstance3D).visible, (n as MeshInstance3D).transform]
	return {"meshes": meshes, "arena": arena}


func _watch_visibility(watch: Dictionary, arena: Node) -> void:
	var vis := {}
	if arena != null and is_instance_valid(arena):
		for n in arena.find_children("*", "MeshInstance3D", true, false):
			vis[n] = (n as MeshInstance3D).visible
	watch["visible"] = vis


func _dirty(watch: Dictionary) -> Array:
	var out := []
	var world: Node = _fight.get("_world")
	var ghosts: Node = world.get_node_or_null("IntroGhosts") if world != null else null
	if ghosts != null and not ghosts.is_queued_for_deletion():
		out.append("ghost root left")
	var rig: Node = _fight.get("_camera_rig")
	if rig != null and rig.has_method("camera"):
		var cam := rig.call("camera") as Camera3D
		if cam == null or not cam.current:
			out.append("fight camera not current")
	# No tick has run yet when the intro ends, so EVERY mesh in the arena must be exactly
	# as it was when the fight was built: visible or not, and where it was (the ghosts'
	# hidden originals, the spun grinder discs and turntable tops included).
	var meshes: Dictionary = watch.get("meshes", {})
	for n in meshes.keys():
		if not is_instance_valid(n):
			continue
		var mi := n as MeshInstance3D
		var was: Array = meshes[n]
		if mi.transform != (was[1] as Transform3D):
			out.append("transform of " + _short(mi))
	var vis: Dictionary = watch.get("visible", {})
	for n in vis.keys():
		if is_instance_valid(n) and (n as MeshInstance3D).visible != bool(vis[n]):
			out.append("visibility of " + _short(n))
	return out


func _short(n: Node) -> String:
	var p := str(n.get_path())
	var i := p.find("/Arena/")
	return p.substr(i + 7) if i >= 0 else p


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
		print("PASS  intro: %d checks, 0 failures" % _checks)
		quit(0)
	else:
		print("FAIL  intro: %d checks, %d failures" % [_checks, _failures])
		quit(1)
