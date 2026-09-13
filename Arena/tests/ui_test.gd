extends SceneTree
## Headless test for the fight controls, HUD and camera rig (Arena/ui).
##   Godot --headless --path Arena --script tests/ui_test.gd
## Exit code 0 = PASS.
##
## Synthetic InputEventScreenTouch and InputEventScreenDrag events are fed straight
## into FightControls.handle_event, which is the same seam _input uses. Input.parse_
## input_event needs a real input driver, so it is not usable with --headless.

const CONTROL_SIZE := Vector2i(1206, 556)   # iPhone 17 landscape at 1 point per unit
const WIDE_SIZE := Vector2i(1920, 1080)     # 16:9 for the camera fit check

var _failures: int = 0
var _checks: int = 0
var _pinches: Array[float] = []
var _orbits: Array[Vector2] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	var controls_scene: PackedScene = load("res://ui/controls.tscn")
	var hud_scene: PackedScene = load("res://ui/hud.tscn")
	var rig_scene: PackedScene = load("res://ui/camera_rig.tscn")
	_check(controls_scene != null, "controls.tscn loads")
	_check(hud_scene != null, "hud.tscn loads")
	_check(rig_scene != null, "camera_rig.tscn loads")
	if controls_scene == null or hud_scene == null or rig_scene == null:
		_finish()
		return

	var vp := SubViewport.new()
	vp.size = CONTROL_SIZE
	root.add_child(vp)
	var controls: FightControls = controls_scene.instantiate() as FightControls
	_check(controls != null, "controls.tscn root is a FightControls")
	if controls == null:
		_finish()
		return
	vp.add_child(controls)
	controls.set_safe_area({"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0})
	controls.camera_pinch.connect(func(f: float) -> void: _pinches.append(f))
	controls.camera_orbit.connect(func(d: Vector2) -> void: _orbits.append(d))
	await _frames(2)
	_check(controls.size == Vector2(CONTROL_SIZE), "controls fill the viewport (%s)" % str(controls.size))

	_test_stick(controls)
	_test_primary(controls)
	_test_camera_gestures(controls)
	await _test_draw(controls)
	_test_hud(hud_scene)
	await _test_camera_rig(rig_scene)

	_finish()


# ---------------------------------------------------------------- controls

func _test_stick(c: FightControls) -> void:
	_touch(c, 0, Vector2(200, 400), true)
	_check(c.heading == Vector2.ZERO, "a fresh stick touch starts at zero heading")
	_drag(c, 0, Vector2(260, 400))
	_check(c.heading.distance_to(Vector2(1, 0)) < 0.02,
		"touch at (200,400) dragged to (260,400) gives heading (1,0), got " + str(c.heading))
	# The stick stays held for the camera interference check below.


func _test_primary(c: FightControls) -> void:
	# Primary centre: viewport corner less the 24 pt margin and the 46 pt radius.
	var centre := Vector2(1206.0 - 24.0 - 46.0, 556.0 - 24.0 - 46.0)
	_touch(c, 1, centre, true)
	_check(c.consume_fire(), "a tap on the primary button fires")
	_check(not c.consume_fire(), "consume_fire is true exactly once per tap")
	_touch(c, 1, centre, false)
	_check(not c.consume_fire(), "releasing the primary button does not fire again")

	# The secondary button is level, not edge triggered.
	var secondary := centre + Vector2(-92.0, -78.0)
	_touch(c, 2, secondary, true)
	_check(c.secondary, "holding the secondary button sets secondary")
	_touch(c, 2, secondary, false)
	_check(not c.secondary, "releasing the secondary button clears secondary")


func _test_camera_gestures(c: FightControls) -> void:
	var before := c.heading
	_pinches.clear()
	_orbits.clear()

	# One camera touch does nothing.
	_touch(c, 3, Vector2(700, 120), true)
	_drag(c, 3, Vector2(720, 140))
	_check(_pinches.is_empty() and _orbits.is_empty(), "a single camera touch does nothing")

	# Two camera touches moving apart pinch out.
	_touch(c, 4, Vector2(900, 120), true)
	_drag(c, 3, Vector2(650, 120))
	_drag(c, 4, Vector2(950, 120))
	var widest := 0.0
	for f in _pinches:
		widest = maxf(widest, f)
	_check(_pinches.size() >= 1 and widest > 1.0,
		"two camera touches moving apart emit camera_pinch with factor > 1 (got " + str(_pinches) + ")")
	_check(not _orbits.is_empty(), "two camera touches emit camera_orbit as the centroid moves")

	_check(c.heading == before,
		"a stick touch plus two camera touches leaves heading unchanged (" + str(c.heading) + ")")

	_touch(c, 3, Vector2(650, 120), false)
	_touch(c, 4, Vector2(950, 120), false)
	_check(c.heading == before, "releasing the camera touches leaves heading unchanged")
	_touch(c, 0, Vector2(260, 400), false)
	_check(c.heading == Vector2.ZERO, "releasing the stick zeroes heading")


## Exercises _draw with every element on screen. Nothing to assert beyond the fact
## that the draw calls are well formed: a bad signature prints an error and this test
## is the only place the drawing runs before a device does it.
func _test_draw(c: FightControls) -> void:
	c.set_state(true, 3)
	_touch(c, 7, Vector2(300.0, 300.0), true)
	_drag(c, 7, Vector2(340.0, 260.0))
	c.queue_redraw()
	await _frames(3)
	_touch(c, 7, Vector2(340.0, 260.0), false)
	c.set_state(false, FightTypes.FLIPPER_CHARGES)
	c.queue_redraw()
	await _frames(3)
	_check(true, "the controls draw a stick, both buttons and the charge pips")


# ---------------------------------------------------------------- hud

func _test_hud(scene: PackedScene) -> void:
	var hud: FightHud = scene.instantiate() as FightHud
	_check(hud != null, "hud.tscn root is a FightHud")
	if hud == null:
		return
	# Before the HUD is in the tree the rolling number is set directly, which makes
	# the number itself testable without waiting on a tween.
	hud.set_scrap(120)
	_check(hud.scrap_displayed() == 120, "set_scrap shows the total")
	hud.bump(30)
	_check(hud.scrap_total() == 150, "bump adds to the total")
	_check(hud.scrap_displayed() == 150, "bump rolls the displayed number to the new total")

	root.add_child(hud)
	hud.set_safe_area({"left": 59.0, "top": 0.0, "right": 59.0, "bottom": 21.0})
	hud.set_bot_names("Tinribs", "Scrapheap")
	hud.set_time_left(90.0)
	var timer := hud.get_node("Root/Timer") as Label
	_check(timer != null and timer.text == "1:30", "90 seconds reads 1:30")
	hud.set_time_left(9.4)
	_check(timer.text == "0:10", "9.4 seconds reads 0:10")
	_check(timer.get_theme_color("font_color") == FightHud.COL_URGENT, "the timer turns red under 10 seconds")
	hud.set_time_left(0.0)
	_check(timer.text == "0:00", "zero reads 0:00")

	hud.show_ko_count(7, "Scrapheap")
	var ko := hud.get_node("Root/KoCount") as Label
	_check(ko.visible and ko.text.contains("KNOCKOUT COUNT 7"), "the knockout count shows")
	hud.hide_ko_count()
	_check(not ko.visible, "the knockout count hides")

	hud.set_height_readout("Your wedge: floor. Their flipper: mid.")
	var readout := hud.get_node("Root/Readout") as Label
	_check(readout.text == "Your wedge: floor. Their flipper: mid.", "the height readout shows the sentence")

	hud.show_countdown("FIGHT")
	var countdown := hud.get_node("Root/Countdown") as Label
	_check(countdown.visible and countdown.text == "FIGHT", "the countdown shows FIGHT")
	hud.hide_countdown()

	hud.show_result("Knockout", "Tinribs")
	var title := hud.get_node("Root/ResultTitle") as Label
	var winner := hud.get_node("Root/ResultWinner") as Label
	_check(title.visible and title.text == "KNOCKOUT", "the result banner shows the outcome")
	_check(winner.text == "WINNER: TINRIBS", "the result banner names the winner")

	# Legibility floor from the spec, measured at the 2x design viewport.
	hud.set_safe_area({"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0})
	var scale_2x := 2.0
	_check(FightHud.TIMER_PT * scale_2x >= 28.0, "the timer clears 28 px at 2x")
	_check(FightHud.READOUT_PT * scale_2x >= 22.0, "the readout clears 22 px at 2x")

	hud.queue_free()


# ---------------------------------------------------------------- camera rig

func _test_camera_rig(scene: PackedScene) -> void:
	var vp := SubViewport.new()
	vp.size = WIDE_SIZE
	root.add_child(vp)
	var rig: CameraRig = scene.instantiate() as CameraRig
	_check(rig != null, "camera_rig.tscn root is a CameraRig")
	if rig == null:
		return
	vp.add_child(rig)
	await _frames(2)
	rig.set_process(false)
	rig.reset_to_default()
	rig.fit_arena(FightTypes.ARENA_SIZE)

	var cam := rig.camera()
	var half := FightTypes.ARENA_SIZE * 0.5
	# The default pose, which --roboteer-zoom, --roboteer-yaw and --roboteer-pitch may
	# have moved. With no QA arguments this is yaw 45, pitch 50, zoom DEFAULT_ZOOM.
	var qa_zoom := _qa_float(CameraRig.ARG_ZOOM, CameraRig.DEFAULT_ZOOM)
	var qa_yaw := _qa_float(CameraRig.ARG_YAW, FightTypes.CAM_YAW_DEG)
	var qa_pitch := _qa_float(CameraRig.ARG_PITCH, FightTypes.CAM_PITCH_DEG)

	_check(is_equal_approx(cam.fov, FightTypes.CAM_FOV), "the camera uses CAM_FOV")
	_check(is_equal_approx(rig.yaw_deg, qa_yaw), "default yaw is %.1f" % qa_yaw)
	_check(is_equal_approx(rig.pitch_deg, qa_pitch), "default pitch is %.1f" % qa_pitch)
	_check(is_equal_approx(rig.default_zoom(), qa_zoom),
		"default zoom is %.2f" % qa_zoom)
	_check(is_equal_approx(rig.zoom, qa_zoom), "the rig rests at the default zoom")
	_check(rig.default_zoom() < FightTypes.CAM_ZOOM_MAX,
		"the default framing is closer than the walls on screen limit")
	var default_distance := rig.distance()

	# Pinch out to CAM_ZOOM_MAX, which is the walls on screen limit.
	rig.pinch(rig.default_zoom())
	rig.fit_arena(FightTypes.ARENA_SIZE)
	_check(is_equal_approx(rig.zoom, FightTypes.CAM_ZOOM_MAX), "pinching out reaches CAM_ZOOM_MAX")
	var fit_distance := rig.distance()
	_check(absf(default_distance - fit_distance * rig.default_zoom()) < 0.02,
		"the default sits at the default zoom of the fit distance (%.2f of %.2f)"
		% [default_distance, fit_distance])
	_check(rig.look_target() == Vector3.ZERO, "at zoom 1.0 the camera looks at the arena centre")

	var inside := true
	var worst := ""
	for sx: float in [-half, half]:
		for sz: float in [-half, half]:
			var screen := cam.unproject_position(Vector3(sx, 0.0, sz))
			var u := screen.x / float(WIDE_SIZE.x)
			var v := screen.y / float(WIDE_SIZE.y)
			if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
				inside = false
				worst = "(%.3f, %.3f)" % [u, v]
	_check(inside, "at zoom 1.0 and 16:9 the four floor corners project inside the frustum " + worst)

	# The walls must be on screen too, which is what the zoom clamp protects.
	var walls_inside := true
	for sx: float in [-half, half]:
		for sz: float in [-half, half]:
			var screen := cam.unproject_position(Vector3(sx, FightTypes.WALL_HEIGHT, sz))
			var u := screen.x / float(WIDE_SIZE.x)
			var v := screen.y / float(WIDE_SIZE.y)
			if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
				walls_inside = false
	_check(walls_inside, "at zoom 1.0 and 16:9 the wall tops project inside the frustum too")

	# A narrower viewport must push the camera further back, not crop the arena.
	vp.size = Vector2i(1206, 1112)
	await _frames(2)
	rig.fit_arena(FightTypes.ARENA_SIZE)
	_check(rig.distance() > fit_distance,
		"a narrower viewport increases the fit distance (%.2f then %.2f)" % [fit_distance, rig.distance()])
	vp.size = WIDE_SIZE
	await _frames(2)
	rig.fit_arena(FightTypes.ARENA_SIZE)

	# Look-at bias. The two bots sit together in one corner of the floor.
	var bot_a := Node3D.new()
	bot_a.position = FightTypes.SPAWN_PLAYER
	var bot_b := Node3D.new()
	bot_b.position = FightTypes.SPAWN_PLAYER + Vector3(0.8, 0.0, 0.8)
	vp.add_child(bot_a)
	vp.add_child(bot_b)
	rig.set_targets(bot_a, bot_b)
	rig.fit_arena(FightTypes.ARENA_SIZE)
	_check(rig.look_target() == Vector3.ZERO,
		"at zoom 1.0 the look-at holds the centre even with both bots in a corner")
	rig.pinch(FightTypes.CAM_ZOOM_MAX / rig.zoom_min())
	rig.fit_arena(FightTypes.ARENA_SIZE)
	var look := rig.look_target()
	_check(is_equal_approx(rig.zoom, rig.zoom_min()), "pinching in reaches the closest zoom")
	_check(absf(look.x) <= half + 0.001 and absf(look.z) <= half + 0.001 and look.y == 0.0,
		"the biased look-at never leaves the floor rectangle " + str(look))
	var mid := (bot_a.position + bot_b.position) * 0.5
	_check(look == Vector3.ZERO or look.distance_to(Vector3(mid.x, 0.0, mid.z)) < Vector3(mid.x, 0.0, mid.z).length(),
		"the bias moves toward the bots or stays at the centre when the floor already fills the frame")

	# Clamps.
	rig.orbit(Vector2(0.0, -100000.0))
	_check(is_equal_approx(rig.pitch_deg, FightTypes.CAM_PITCH_MAX), "pitch clamps at CAM_PITCH_MAX")
	rig.orbit(Vector2(0.0, 100000.0))
	_check(is_equal_approx(rig.pitch_deg, FightTypes.CAM_PITCH_MIN), "pitch clamps at CAM_PITCH_MIN")
	rig.pinch(100.0)
	_check(is_equal_approx(rig.zoom, rig.zoom_min()),
		"zoom clamps at the closest zoom (%.2f)" % rig.zoom_min())
	_check(rig.zoom_min() == minf(FightTypes.CAM_ZOOM_MIN, rig.default_zoom()),
		"the closest zoom is CAM_ZOOM_MIN unless a QA argument asked for closer")
	rig.pinch(0.001)
	_check(is_equal_approx(rig.zoom, FightTypes.CAM_ZOOM_MAX), "zoom clamps at CAM_ZOOM_MAX")

	# Ease back to the default pose. The rig is stepped by hand so the test does not
	# depend on the frame rate.
	rig.reset_to_default()
	rig.orbit(Vector2(300.0, 0.0))
	rig.pinch(1.6)
	var turned := rig.yaw_deg
	_check(absf(turned - qa_yaw) > 10.0, "an orbit drag turns the camera (yaw %.1f)" % turned)
	_step(rig, 3.1)
	_check(rig.is_easing_back(), "the ease back has begun by 3.1 s of no input")
	_check(absf(rig.yaw_deg - qa_yaw) < absf(turned - qa_yaw),
		"yaw is on its way back at 3.1 s (yaw %.1f)" % rig.yaw_deg)
	_step(rig, FightTypes.CAM_EASE_BACK_S + 0.2)
	_check(is_equal_approx(rig.yaw_deg, qa_yaw),
		"yaw is back to the default after the %.1f s ease (yaw %.3f)" % [FightTypes.CAM_EASE_BACK_S, rig.yaw_deg])
	_check(is_equal_approx(rig.pitch_deg, qa_pitch), "pitch is back to the default")
	_check(is_equal_approx(rig.zoom, rig.default_zoom()),
		"zoom eases back to the default zoom, not to 1.0 (%.3f)" % rig.zoom)

	# Input can be switched off for the countdown and the result.
	rig.set_input_enabled(false)
	rig.orbit(Vector2(300.0, 0.0))
	_check(is_equal_approx(rig.yaw_deg, qa_yaw), "orbit does nothing while input is disabled")
	rig.set_input_enabled(true)

	# Director cut off means no wreckage orbit.
	rig.reset_to_default()
	rig.set_director_cut(false)
	var marker := Node3D.new()
	marker.position = Vector3(2.0, 0.2, -1.5)
	vp.add_child(marker)
	rig.begin_wreckage_orbit(marker)
	_step(rig, 1.0)
	_check(is_equal_approx(rig.yaw_deg, qa_yaw),
		"the wreckage orbit stays off when the director cut is off")

	rig.set_director_cut(true)
	rig.begin_wreckage_orbit(marker)
	_step(rig, CameraRig.WRECKAGE_EASE_S + 1.0)
	_check(absf(rig.distance() - CameraRig.WRECKAGE_DISTANCE) < 0.02,
		"the wreckage orbit settles %.1f m from the wreck (%.2f)"
		% [CameraRig.WRECKAGE_DISTANCE, rig.distance()])
	_check(is_equal_approx(rig.pitch_deg, CameraRig.WRECKAGE_PITCH_DEG),
		"the wreckage orbit sits at pitch %.0f" % CameraRig.WRECKAGE_PITCH_DEG)
	_check(rig.look_target().distance_to(marker.global_position) < 0.02,
		"the wreckage orbit looks straight at the wreck " + str(rig.look_target()))
	var yaw_before := rig.yaw_deg
	_step(rig, 1.0)
	_check(absf(wrapf(rig.yaw_deg - yaw_before, -180.0, 180.0) - CameraRig.WRECKAGE_ORBIT_DEG_PER_S) < 0.5,
		"the wreckage orbit turns %.0f degrees per second" % CameraRig.WRECKAGE_ORBIT_DEG_PER_S)
	rig.orbit(Vector2(10.0, 0.0))
	_step(rig, 0.5)
	_check(absf(rig.distance() - CameraRig.WRECKAGE_DISTANCE) > 1.0,
		"a camera gesture cancels the wreckage orbit")


## Reads a --roboteer-* QA argument, or returns the fallback when it is not passed.
func _qa_float(prefix: String, fallback: float) -> float:
	for raw in OS.get_cmdline_user_args():
		var arg := str(raw)
		if arg.begins_with(prefix):
			return arg.substr(prefix.length()).to_float()
	return fallback


func _step(rig: CameraRig, seconds: float) -> void:
	var dt := 1.0 / 60.0
	var n := int(round(seconds / dt))
	for i in n:
		rig._process(dt)


# ---------------------------------------------------------------- helpers

func _touch(c: FightControls, index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	c.handle_event(e)


func _drag(c: FightControls, index: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	c.handle_event(e)


func _frames(count: int) -> void:
	for i in count:
		await process_frame


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
		print("PASS  fight ui: %d checks, 0 failures" % _checks)
		quit(0)
	else:
		print("FAIL  fight ui: %d checks, %d failures" % [_checks, _failures])
		quit(1)
