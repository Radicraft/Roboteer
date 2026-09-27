extends SceneTree
## `stage_build`: the machine is put together on the turntable behind the loading screen
## (2026-09-27, direction A of docs/look/loading-options.html).
##
##   Godot --headless --path Arena --script tests/stage_build_test.gd
##
## The warm up (Arena/render/warmup.gd) reports its row as `step` on every
## `preload_progress`; the stage hears the same message go out over the Bridge and shows
## the machine's parts and brings its lights up in step with it. Asserted here: the hull
## stands from the first message and every other part lands when its row is done; the rig
## is dark while the machine is built and comes up through the lights row; a finished build
## can never be started again by a late message; a stalled walk still ends with the machine
## built and lit; and the REAL warm up, run end to end, walks the stage through every row
## in order and leaves it whole.

const FIXTURE := "res://fight/fixtures/stage3_config.json"

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var bridge: Node = root.get_node_or_null("Bridge")
	_check(bridge != null, "the Bridge autoload is present")
	if bridge == null:
		_finish()
		return
	var config: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string(FIXTURE)) as Dictionary)
	var bot_config: Dictionary = (config["bots"] as Array)[0]

	var stage := WorkshopStage.new()
	stage.force_quality_tier("low")
	root.add_child(stage)
	await process_frame
	stage.show_bot(bot_config)
	await process_frame

	_check(stage.build_step() == -1, "a fresh stage is not building")
	_check(_all_visible(stage), "and shows the whole machine")

	# --- the rows, driven through the Bridge exactly as the warm up drives them
	bridge.call("send", "preload_progress", {"step": 0, "step_fraction": 0.0, "fraction": 0.0})
	_check(stage.building(), "the first progress message starts the build")
	_check(_visible_kinds(stage) == ["chassis"], "row 0: only the hull stands (%s)" % [_visible_kinds(stage)])
	var dark := stage.build_light_gains()
	_check(dark.x < 0.5 and dark.y < 0.1, "and it stands in the dark at once, no fade (key %.2f, rig %.2f)" % [dark.x, dark.y])

	bridge.call("send", "preload_progress", {"step": 1, "step_fraction": 0.0})
	_check(not _visible_kinds(stage).has("wheel"), "row 1 current: the drive is not on yet")
	bridge.call("send", "preload_progress", {"step": 2, "step_fraction": 0.0})
	_check(_visible_kinds(stage).has("wheel"), "row 1 done: the drive has landed")
	_check(not _visible_kinds(stage).has("armour"), "and the armour is not on yet")
	bridge.call("send", "preload_progress", {"step": 3, "step_fraction": 0.5})
	_check(_visible_kinds(stage).has("armour"), "row 2 done: the armour has landed")
	_check(not _visible_kinds(stage).has("weapon"), "and the weapon is not on yet")

	# A rebuild mid walk (the shell re-sends the machine) keeps the build where it was.
	stage.show_bot(bot_config)
	_check(not _visible_kinds(stage).has("weapon") and _visible_kinds(stage).has("armour"),
		"a rebuild mid walk keeps the parts where the build had got to")

	# Backwards never happens.
	bridge.call("send", "preload_progress", {"step": 1, "step_fraction": 0.0})
	_check(stage.build_step() == 3, "a late message for an earlier row is ignored (%d)" % stage.build_step())

	bridge.call("send", "preload_progress", {"step": 4, "step_fraction": 0.0})
	_check(_all_visible(stage), "row 3 done: the whole machine is on for the lights row")
	var t0 := stage.build_light_targets()
	_check(is_equal_approx(t0.x, 1.0) and t0.y < 0.1, "the key comes up with the lights row, the rig starts dark")
	bridge.call("send", "preload_progress", {"step": 4, "step_fraction": 0.5})
	var t1 := stage.build_light_targets()
	_check(t1.y > t0.y + 0.3 and t1.y < 0.9, "the rig comes up with the draw's batches (%.2f)" % t1.y)
	for i in 10:
		stage.call("_animate_build", 0.25)
	_check(absf(stage.build_light_gains().y - t1.y) < 0.02, "the lights ease to where the walk is")

	bridge.call("send", "preload_done", {})
	_check(stage.build_step() == 5, "preload_done finishes the build")
	for i in 20:
		stage.call("_animate_build", 0.25)
	_check(stage.build_step() == -1 and not stage.building(), "and once the lights are up the stage is itself again")
	_check(stage.build_light_gains().is_equal_approx(Vector2.ONE), "with the rig at full")
	_check(_all_visible(stage), "and the whole machine on show")

	# Once built, never again: a retrying shell's second walk answers at once, and a stray
	# message must not take the machine apart.
	bridge.call("send", "preload_progress", {"step": 0, "step_fraction": 0.0})
	_check(stage.build_step() == -1 and _all_visible(stage), "a message after the build cannot start it again")
	stage.queue_free()
	await process_frame

	# --- a stalled walk still ends built and lit
	var stalled := WorkshopStage.new()
	stalled.force_quality_tier("low")
	root.add_child(stalled)
	await process_frame
	stalled.show_bot(bot_config)
	stalled.set_build_step(1, 0.2)
	stalled.call("_animate_build", 30.0)
	_check(stalled.building(), "30 s of quiet is still a build in progress")
	stalled.call("_animate_build", 20.0)
	_check(not stalled.building() and _all_visible(stalled),
		"past %d s of quiet the machine is finished anyway" % int(WorkshopStage.BUILD_STALL_S))
	stalled.queue_free()
	await process_frame

	# --- the real warm up, end to end
	var real := WorkshopStage.new()
	real.force_quality_tier("low")
	root.add_child(real)
	await process_frame
	real.show_bot(bot_config)
	var steps: Array = []
	var seen := func(type: String, payload: Dictionary) -> void:
		if type == ArenaWarmUp.MSG_PRELOAD_PROGRESS:
			steps.append(int(payload.get("step", -1)))
			_check(float(payload.get("step_fraction", -1.0)) >= 0.0 and float(payload.get("step_fraction", 2.0)) <= 1.0,
				"step %d: step_fraction in 0..1" % int(payload.get("step", -1)))
	bridge.connect("message_sent", seen)
	var max_seen := [-1]
	var track := func(_type: String, _payload: Dictionary) -> void:
		max_seen[0] = maxi(max_seen[0], real.build_step())
	bridge.connect("message_sent", track)
	var warmup := ArenaWarmUp.new()
	root.add_child(warmup)
	await process_frame
	warmup.begin({})
	var guard := 0
	while warmup.running() and guard < 600:
		guard += 1
		await process_frame
	bridge.disconnect("message_sent", seen)
	bridge.disconnect("message_sent", track)
	var ordered := true
	for i in range(1, steps.size()):
		if int(steps[i]) < int(steps[i - 1]):
			ordered = false
	_check(ordered, "the warm up's steps only move forwards (%s)" % [steps])
	_check(steps.has(0) and steps.has(1) and steps.has(2) and steps.has(3),
		"headless, it walks the hull, drive, armour and weapon rows")
	_check(not steps.is_empty() and int(steps[steps.size() - 1]) == ArenaWarmUp.STEP_DONE, "and ends on STEP_DONE")
	_check(WorkshopStage.BUILD_STEP_DONE == ArenaWarmUp.STEP_DONE and WorkshopStage.BUILD_STEP_LIGHTS == ArenaWarmUp.STEP_LIGHTS,
		"the stage and the warm up agree on the rows")
	for i in 30:
		real.call("_animate_build", 0.25)
	_check(not real.building() and _all_visible(real), "after the real walk the machine is whole and lit")

	_finish()


func _visible_kinds(stage: WorkshopStage) -> Array:
	var out: Array = []
	var hero := stage.bot()
	if hero == null:
		return out
	for part in hero.call("attached_parts"):
		var node := part as Node3D
		var kind := str(node.get("part_kind"))
		if node.visible and not out.has(kind):
			out.append(kind)
	out.sort()
	return out


func _all_visible(stage: WorkshopStage) -> bool:
	var hero := stage.bot()
	if hero == null:
		return false
	for part in hero.call("attached_parts"):
		if not (part as Node3D).visible:
			return false
	return true


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("PASS  " + what)
	else:
		_failures += 1
		print("FAIL  " + what)


func _finish() -> void:
	print("stage_build: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
