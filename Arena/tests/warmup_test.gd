extends SceneTree
## `warmup`: the catalogue warm up the shell's loading screen stands in front of
## (2026-09-21, docs/stage-bug-2026-09-21.md).
##
##   Godot --headless --path Arena --script tests/warmup_test.gd
##
## Headless has no renderer, so the off screen warm DRAW is skipped by design and cannot
## be asserted on here. What is asserted is everything that decides whether the player
## waits: that the walk covers every part in the manifest, every material slot and every
## paint overlay, that it reports progress that only ever moves forwards and ends at 1.0,
## that it answers `preload_done`, that a second `begin` is answered rather than run
## again, and that after the walk every model, material and paint overlay the game can ask
## for is already in the resource cache.

const STAGE_SCENE := "res://workshop/stage.tscn"
const FIXTURE := "res://fight/fixtures/stage3_config.json"

var _failures := 0
var _checks := 0
var _sent: Array = []


func _initialize() -> void:
	_run()


func _run() -> void:
	# The Bridge autoload is reached by node, not by its global identifier: in a
	# `--script` run this SceneTree script is compiled before the autoload globals are
	# registered, the way workshop_test.gd and bridge_test.gd already do it.
	var bridge: Node = root.get_node_or_null("Bridge")
	_check(bridge != null, "the Bridge autoload is present")
	if bridge == null:
		_finish()
		return
	bridge.connect("message_sent", func(type: String, payload: Dictionary) -> void:
		_sent.append({"type": type, "payload": payload}))

	var warmup := ArenaWarmUp.new()
	root.add_child(warmup)
	await process_frame

	_check(not warmup.running(), "a fresh warm up is idle")
	_check(not warmup.finished(), "and has not finished")

	# --- what the walk covers
	var parts: Dictionary = PartsCatalogue.manifest().get("parts", {}) as Dictionary
	_check(parts.size() > 0, "the manifest has parts in it (%d)" % parts.size())

	# The shell sends `{}`, which asks for the off screen draw too. Headless has no
	# renderer, so the walk must notice that and finish on the reading alone rather than
	# stand up a viewport that will never draw (the simulator's dummy path relies on it).
	warmup.begin({})
	_check(warmup.running(), "begin() starts the walk")

	var guard := 0
	while warmup.running() and guard < 600:
		guard += 1
		await process_frame
	_check(warmup.finished(), "the walk finishes (%d frames)" % guard)

	# --- the progress it reported
	var progress: Array = []
	var done_messages: Array = []
	for entry in _sent:
		if str(entry["type"]) == ArenaWarmUp.MSG_PRELOAD_PROGRESS:
			progress.append(entry["payload"])
		elif str(entry["type"]) == ArenaWarmUp.MSG_PRELOAD_DONE:
			done_messages.append(entry["payload"])

	_check(progress.size() >= 2, "it reported progress at least twice (%d)" % progress.size())
	var last := -1.0
	var monotonic := true
	for payload_variant in progress:
		var payload: Dictionary = payload_variant
		var fraction := float(payload.get("fraction", -1.0))
		if fraction < last - 0.0001:
			monotonic = false
		last = fraction
	_check(monotonic, "the fraction never goes backwards")
	_check(absf(last - 1.0) < 0.0001, "and ends at exactly 1.0 (%.4f)" % last)
	_check(str((progress[progress.size() - 1] as Dictionary).get("line", "")) == "Ready",
		"the last line is the one the loading screen ends on")

	_check(done_messages.size() == 1, "it answered preload_done exactly once (%d)" % done_messages.size())
	var done: Dictionary = done_messages[0] if not done_messages.is_empty() else {}
	_check(int(done.get("models", 0)) == parts.size(),
		"every part in the manifest was read (%d of %d)" % [int(done.get("models", 0)), parts.size()])
	# Seven material slots plus the paint overlays, which is more than one file per job.
	_check(int(done.get("materials", 0)) >= PartVisuals.MATERIAL_FILES.size() + Livery.ids().size(),
		"every material slot and every paint overlay was read (%d)" % int(done.get("materials", 0)))
	_check(int(done.get("warmed", -1)) == 0, "headless draws nothing (%d drawn)" % int(done.get("warmed", -1)))
	_check(int(done.get("scenes", 0)) >= 12,
		"the stage, the fight scenes and every arena were read (%d)" % int(done.get("scenes", 0)))
	var sound_paths: Dictionary = {}
	for key in AudioMix.SOUNDS.keys():
		sound_paths[str(AudioMix.SOUNDS[key])] = true
	_check(int(done.get("sounds", 0)) >= sound_paths.size(),
		"every sound the mixer can ask for was read (%d of at least %d)"
		% [int(done.get("sounds", 0)), sound_paths.size()])
	print("TIMING the walk, headless (reading only): %.1f ms" % float(done.get("ms", -1.0)))
	_check(float(done.get("ms", -1.0)) >= 0.0, "it reports how long it took (%.1f ms)"
		% float(done.get("ms", -1.0)))
	_check(warmup.elapsed_ms() >= 0.0, "and says so through elapsed_ms()")

	# --- a second begin is answered, never run again
	var before := _sent.size()
	warmup.begin({"models": false})
	await process_frame
	_check(not warmup.running(), "a second begin() does not start a second walk")
	var extra_done := 0
	for i in range(before, _sent.size()):
		if str((_sent[i] as Dictionary)["type"]) == ArenaWarmUp.MSG_PRELOAD_DONE:
			extra_done += 1
	_check(extra_done == 1, "it answers preload_done again so a retrying shell is never stuck")

	# --- the point of the whole thing: nothing is left to read
	_test_everything_is_cached()
	await _test_the_draw_path_runs()
	await _report_bind_cost()

	_finish()


## What the walk actually buys. The bind itself is NOT file work: measured on this Mac it
## costs about 95 ms warm or cold, because it is building procedural geometry and wiring
## bodies, not reading the disk. What the walk buys is that every model, material and paint
## overlay the game can ask for is already in the resource cache and already drawn once, so
## no later screen pays for a read or, on the phone, for a pipeline compile. The cache is
## what can be asserted headless; the draw is asserted by the sim screenshots in
## docs/stage-bug-2026-09-21.md.
func _test_everything_is_cached() -> void:
	var parts: Dictionary = PartsCatalogue.manifest().get("parts", {}) as Dictionary
	var missing: Array = []
	for id in parts.keys():
		var entry: Dictionary = parts[id] as Dictionary
		var path: String = str(entry.get("path", ""))
		if path == "" or not ResourceLoader.exists(path):
			continue
		if not ResourceLoader.has_cached(path):
			missing.append(path)
	_check(missing.is_empty(), "every part model is in the resource cache after the walk (%d missing)"
		% missing.size())

	var missing_materials: Array = []
	for slot in PartVisuals.MATERIAL_FILES.keys():
		var path: String = str(PartVisuals.MATERIAL_FILES[slot])
		if ResourceLoader.exists(path) and not ResourceLoader.has_cached(path):
			missing_materials.append(path)
	_check(missing_materials.is_empty(),
		"every material slot is in the resource cache (%d missing)" % missing_materials.size())

	var missing_other: Array = []
	var others: Array = ["res://workshop/stage.tscn", "res://fight/fight_world.tscn",
		"res://ui/hud.tscn", "res://fx/fx.tscn", "res://arena/yard.tscn", "res://arena/events/sumo.tscn"]
	for key in AudioMix.SOUNDS.keys():
		others.append(str(AudioMix.SOUNDS[key]))
	for path in others:
		if ResourceLoader.exists(path) and not ResourceLoader.has_cached(path):
			missing_other.append(path)
	_check(missing_other.is_empty(),
		"the stage, the fight scenes, the arenas and every sound are cached (%s missing)" % str(missing_other))

	# The draw plan, which headless cannot run, is still checked for coverage: every part,
	# one carrier per paint job and one emitter per particle flavour.
	var planned := 0
	var paints := 0
	var fx := 0
	var venues := 0
	for batch in ArenaWarmUp._plan_batches():
		for job_variant in batch:
			var job: Dictionary = job_variant
			if job.has("fx"):
				fx += 1
			elif job.has("venue"):
				venues += 1
			elif job.has("paint"):
				paints += 1
			else:
				planned += 1
	_check(planned == parts.size(), "the draw plan stands up every part (%d of %d)" % [planned, parts.size()])
	_check(venues == ArenaWarmUp.VENUE_SCENES.size(), "and every dressed venue, whole (%d)" % venues)
	_check(paints == Livery.ids().size(), "and one chassis per paint job (%d)" % paints)
	_check(fx == FxEmitters.FLAVOURS, "and one emitter per particle flavour (%d)" % fx)

	var dir: String = Livery.TEXTURE_DIR
	var missing_paint: Array = []
	for paint_id in Livery.ids():
		var path: String = dir + str(paint_id) + "_albedo.png"
		if ResourceLoader.exists(path) and not ResourceLoader.has_cached(path):
			missing_paint.append(path)
	_check(missing_paint.is_empty(),
		"every paint overlay is in the resource cache (%d missing)" % missing_paint.size())


## The draw needs a renderer and headless has none, but the PATH can still be walked:
## with `force_draw` the walk stands every batch up in its viewport, binds the runtime
## materials, dresses the emitters and frees them again. What this proves is that the
## code the phone runs has no script error in it and always reaches `preload_done`.
func _test_the_draw_path_runs() -> void:
	var errors_before := _sent.size()
	var warmup := ArenaWarmUp.new()
	warmup.force_draw = true
	root.add_child(warmup)
	await process_frame
	warmup.begin({})
	var guard := 0
	while warmup.running() and guard < 2000:
		guard += 1
		await process_frame
	_check(warmup.finished(), "the forced draw path finishes (%d frames)" % guard)
	var done: Dictionary = {}
	for i in range(errors_before, _sent.size()):
		var entry: Dictionary = _sent[i]
		if str(entry["type"]) == ArenaWarmUp.MSG_PRELOAD_DONE:
			done = entry["payload"]
	var parts: Dictionary = PartsCatalogue.manifest().get("parts", {}) as Dictionary
	var expected := parts.size() + Livery.ids().size() + FxEmitters.FLAVOURS + ArenaWarmUp.VENUE_SCENES.size()
	_check(int(done.get("warmed", 0)) == expected,
		"it stood up every part, paint carrier and emitter (%d of %d)" % [int(done.get("warmed", 0)), expected])
	_check(Livery.current == "", "and left no paint job behind in Livery.current")
	await process_frame
	_check(warmup.get_node_or_null("WarmUpViewport") == null, "and freed its viewport")
	print("TIMING forced draw path, headless (no compile): %.1f ms over %d frames"
		% [warmup.elapsed_ms(), guard])
	warmup.queue_free()


## Information, not a check: the bind is procedural work and costs the same either way.
## It is printed so the number in the notes can be reproduced.
func _report_bind_cost() -> void:
	var stage_scene: PackedScene = load(STAGE_SCENE)
	if stage_scene == null:
		print("SKIP  bind timing: stage.tscn is absent")
		return
	var stage: WorkshopStage = stage_scene.instantiate() as WorkshopStage
	root.add_child(stage)
	await process_frame
	await process_frame

	var text := FileAccess.get_file_as_string(FIXTURE)
	var parsed: Variant = JSON.parse_string(text)
	var config: Dictionary = ((parsed as Dictionary)["bots"] as Array)[0] as Dictionary

	var at := Time.get_ticks_usec()
	stage.show_bot(config)
	var ms := (Time.get_ticks_usec() - at) / 1000.0
	print("TIMING bind after the walk: %.1f ms" % ms)
	_check(stage.bot() != null, "the machine stands on the turntable after the walk")


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("PASS  " + what)
	else:
		_failures += 1
		print("FAIL  " + what)


func _finish() -> void:
	print("")
	if _failures == 0:
		print("PASS  warm up: %d checks, 0 failures" % _checks)
		quit(0)
	else:
		print("FAIL  warm up: %d checks, %d failures" % [_checks, _failures])
		quit(1)
