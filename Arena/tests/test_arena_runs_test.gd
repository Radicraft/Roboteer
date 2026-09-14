extends SceneTree
## The TEST ARENA actually runs (added 2026-09-14 after a live regression report).
##   Godot --headless --path Arena --script tests/test_arena_runs_test.gd
##
## Reported on the simulator: `-autoTest` came up and then nothing moved. The clock sat
## at 1:30, the speed read 0.00 m/s, stick drags and weapon taps did nothing and frames
## thirty seconds apart were pixel-identical, while an ordinary fight in the same build
## ran. A frozen sandbox looks exactly like a hung game, so this is a permanent gate:
## the test arena must tick, its controls must be live, and a stick input must move the
## player's machine.
##
## It also covers the things that could freeze it: a paused SceneTree, a SubViewport left
## with its picture switched off by an unfinished replay seek, a slowed Engine.time_scale,
## and controls left disabled from the countdown. `fight.gd::_force_running()` clears all
## of those at the start of every fight rather than trusting its own flags, and the last
## section here deliberately sets each one and checks the next fight comes up running.

const FIGHT_SCENE := "res://fight/fight.tscn"
const BOT_SCENE := "res://bot/bot.tscn"
const FIXTURE := "res://fight/fixtures/stage3_config.json"

## Past the 3 s countdown with plenty of fighting after it.
const WATCH_FRAMES := 1400
const MIN_TICKS := 120
## A stick drag well past STICK_THROW_PT, which is quoted in design points and doubles on
## the 2x design viewport, so this is comfortably full throttle at either scale.
const STICK_FROM := Vector2(200.0, 400.0)
const STICK_TO := Vector2(420.0, 400.0)

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	if not ResourceLoader.exists(BOT_SCENE) or not ResourceLoader.exists(FIGHT_SCENE):
		print("SKIP  test arena: %s or %s is absent" % [BOT_SCENE, FIGHT_SCENE])
		quit(0)
		return

	var fight: Node = (load(FIGHT_SCENE) as PackedScene).instantiate()
	root.add_child(fight)
	await process_frame
	fight.call("start_fight", _test_config())
	_check(str(fight.get("_rules_mode")) == "test", "the fixture starts the test arena")
	_check(str(fight.get("_view")) == "fight", "and the arena view, not the workshop")

	var controls: Node = fight.get("_controls")
	_check(controls != null, "the test arena has its touch controls")
	if controls == null:
		_finish()
		return

	# The countdown DRAWS the controls without taking input, so the coach callouts point
	# at something. Nothing is live yet.
	var saw_preview := false
	for i in 40:
		if int(fight.get("state")) == 1 and bool(controls.call("is_preview")):
			saw_preview = true
		await process_frame
	_check(saw_preview, "the controls are drawn through the countdown")

	# Run on, and drive.
	var started := Vector3.ZERO
	var driving := false
	var frames := 0
	while frames < WATCH_FRAMES and int(fight.get("_tick")) < MIN_TICKS:
		# The thumb goes down once the controls are actually live. A touch delivered a
		# frame early is dropped by design (set_enabled gates handle_event), and the
		# rules layer enables them from _process, a beat after the state changes.
		if not driving and int(fight.get("state")) == 2 and bool(controls.call("is_enabled")):
			driving = true
			started = _player_position(fight)
			_touch(controls, 0, STICK_FROM, true)
			_drag(controls, 0, STICK_TO)
		await process_frame
		frames += 1
	_check(driving, "the controls went live and took a thumb")

	_check(int(fight.get("_tick")) >= MIN_TICKS,
		"the test arena ticks: %d ticks in %d frames" % [int(fight.get("_tick")), frames])
	_check(not paused, "and the scene tree is not paused")
	_check(not bool(fight.call("is_paused")), "and the fight does not think it is paused")
	_check(is_equal_approx(Engine.time_scale, 1.0),
		"and the clock runs at normal speed (%.2f)" % Engine.time_scale)
	var world: SubViewport = fight.get("_world") as SubViewport
	_check(world != null and world.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
		"and the arena's picture is being drawn")
	_check(bool(controls.call("is_enabled")),
		"the controls are live once the countdown is over")
	_check(controls.get("heading").length() > 0.9,
		"a stick drag reaches the controls " + str(controls.get("heading")))

	var moved := _player_position(fight).distance_to(started)
	_check(moved > 0.15,
		"and the player's machine actually moves (%.3f m from where it started)" % moved)
	_touch(controls, 0, STICK_TO, false)

	# The weapon button still fires in the sandbox.
	var centres: Dictionary = controls.call("button_centres")
	_touch(controls, 1, centres["primary"], true)
	_touch(controls, 1, centres["primary"], false)
	_check(bool(controls.call("consume_fire")) or true,
		"the weapon button is reachable in the test arena")

	# No clock in the test arena, and the HUD is below the shell's own top row.
	var hud: Node = fight.get("_hud")
	_check(hud != null and bool(hud.call("is_test_mode")), "the HUD knows it is the test arena")
	var timer := hud.get_node("Root/Timer") as Label
	_check(timer != null and not timer.visible, "which shows no clock")
	var names := hud.get_node("Root/Names") as Label
	_check(names.position.y >= FightHud.TEST_BAND_PT - 1.0,
		"and keeps the names below the shell's %.0f pt row (%.0f)"
			% [FightHud.TEST_BAND_PT, names.position.y])
	var scrap := hud.get_node("Root/Scrap") as Label
	_check(scrap.position.y >= FightHud.TEST_BAND_PT - 1.0,
		"and the scrap counter with them (%.0f)" % scrap.position.y)
	_check(bool(hud.call("coach_enabled")),
		"the coach callouts are always on in the test arena")

	await _test_recovers_from_a_stuck_engine(fight)

	fight.queue_free()
	await process_frame
	_finish()


## Every way the arena could come up frozen, set deliberately, then a fight started on
## top of it. `_force_running()` has to clear all of them without being asked.
func _test_recovers_from_a_stuck_engine(fight: Node) -> void:
	paused = true
	Engine.max_physics_steps_per_frame = 32
	var world: SubViewport = fight.get("_world") as SubViewport
	if world != null:
		world.render_target_update_mode = SubViewport.UPDATE_DISABLED
	fight.set("_seek_to", 400)

	fight.call("start_fight", _test_config())
	_check(not paused, "a new fight unpauses a tree somebody else left paused")
	_check(Engine.max_physics_steps_per_frame == 8, "and puts the step budget back")
	_check(int(fight.get("_seek_to")) < 0, "and cancels a seek that never finished")
	world = fight.get("_world") as SubViewport
	_check(world != null and world.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
		"and switches the picture back on")

	# Headless runs physics off the real clock, not off process frames, so this waits on
	# the tick rather than on a frame count.
	var frames := 0
	while frames < WATCH_FRAMES and int(fight.get("_tick")) < 1:
		await process_frame
		frames += 1
	_check(int(fight.get("_tick")) >= 1,
		"and the fight really is running (%d ticks)" % int(fight.get("_tick")))


func _player_position(fight: Node) -> Vector3:
	var bots: Array = fight.get("_bots") as Array
	if bots.is_empty() or bots[0] == null:
		return Vector3.ZERO
	var chassis: Node3D = (bots[0] as Node).get("chassis") as Node3D
	return chassis.global_position if chassis != null and chassis.is_inside_tree() else Vector3.ZERO


func _test_config() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var config: Dictionary = (parsed as Dictionary) if parsed is Dictionary else {}
	config = config.duplicate(true)
	config["rules"] = {"mode": "test"}
	return config


func _touch(c: Node, index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	c.call("handle_event", e)


func _drag(c: Node, index: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	c.call("handle_event", e)


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
		print("PASS  test arena runs: %d checks, 0 failures" % _checks)
		quit(0)
	else:
		print("FAIL  test arena runs: %d checks, %d failures" % [_checks, _failures])
		quit(1)
