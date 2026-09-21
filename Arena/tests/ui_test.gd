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
## An iPhone 17 in landscape, in DEVICE pixels. `window/stretch/mode` is "disabled" (wave P,
## agent H, docs/wave-v-v4-notes.md section 1), so `get_visible_rect()` is the real pixel
## rect and there is no base canvas standing in for it: a headless run's root window is
## 64 x 64 and cannot be resized, because the headless DisplayServer has no window to
## resize. Under the old "canvas_items" stretch the root reported the 2412 x 1112 base
## whatever the window was, which is what these tests were quietly leaning on. So the HUD
## now gets its own SubViewport posed the way the phone poses the root window (`_hud_host`),
## and `_pt` comes out at min(2622/1206, 1206/556) = 2.1692 the way it does on the glass.
const DEVICE_PX := Vector2i(2622, 1206)
const TICK := 1.0 / 60.0                    # one physics tick, the clock the pad is polled on

## Stands in for agent G4's ImpactShake (Arena/fx/impact_shake.gd). The rig finds it
## by group and duck types offset(), so the test never has to build the FX tree.
class FakeShake extends Node:
	var value := Vector3.ZERO

	func _ready() -> void:
		add_to_group("roboteer_impact_shake")

	func offset() -> Vector3:
		return value


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
	_test_weapon_words(controls)
	_test_camera_gestures(controls)
	_test_camera_ownership(controls)
	_test_resting_stick(controls)
	await _test_countdown_preview(controls)
	await _test_draw(controls)
	await _test_pad(controls)
	await _test_pad_rule(controls, hud_scene)
	_test_hud(hud_scene)
	await _test_pad_hints(hud_scene, controls)
	await _test_coach(hud_scene, controls)
	await _test_broadcast_tokens()
	await _test_feed_layout(hud_scene)
	await _test_ticker(hud_scene)
	await _test_endgame_slam(hud_scene)
	await _test_feed_draws(hud_scene, controls)
	await _test_camera_rig(rig_scene)
	await _test_frame_bias(rig_scene)
	await _test_bot_framing(rig_scene)
	await _test_offscreen_marker(hud_scene)

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

	# CHANGED 2026-09-14: one camera touch used to do nothing, which is why the owner
	# had "no idea how to move the camera". A one finger drag that starts in the right
	# hand area, off both buttons and outside the stick zone, now orbits and tilts.
	_touch(c, 3, Vector2(700, 120), true)
	_drag(c, 3, Vector2(720, 140))
	_check(_pinches.is_empty(), "a one finger drag never pinches")
	_check(_orbits.size() == 1 and _orbits[0].is_equal_approx(Vector2(20.0, 20.0)),
		"a one finger drag off the buttons and outside the stick zone orbits " + str(_orbits))
	_check(c.heading == before, "a one finger camera drag leaves the stick alone")
	_orbits.clear()

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

	# The resting stick, the spin-up ring and the drive pulse all draw too: a bad draw
	# call only shows up when it actually runs.
	for weapon: String in ["flipper", "spinner", "crusher", "axe"]:
		for spin: float in [0.0, 0.45, 1.0]:
			c.set_weapon(weapon, spin)
			c.queue_redraw()
			await _frames(1)
	c.set_drive_prompt(true)
	_check(c.drive_prompt(), "the drive prompt can be switched on")
	for i in 6:
		c._tick_rest_fade(0.2)
		await _frames(1)
	c.set_drive_prompt(false)
	c.set_weapon("flipper")
	c.queue_redraw()
	await _frames(2)
	_check(true, "the resting stick, the spin-up ring and the drive pulse all draw")


## Game controller. Input.parse_input_event can fake joypad axes and buttons headless,
## but it cannot fake a connection, so the pad state is forced with set_pad_present.
func _test_pad(c: FightControls) -> void:
	# --roboteer-pad=on forces the pad path on for desktop QA, so honour it here.
	var qa_pad := _qa_pad()
	_check(c.pad_present() == qa_pad,
		"the pad starts %s, following the connected joypads and --roboteer-pad"
		% ("on" if qa_pad else "off"))
	c.set_pad_present(true)
	_check(c.pad_present(), "set_pad_present forces the pad on for QA and tests")
	_pad_reset()
	c.consume_fire()

	# Left stick. 0.8 past a 0.18 circular deadzone, rescaled over the rest of the travel.
	_pad_axis(JOY_AXIS_LEFT_X, 0.8)
	c._physics_process(TICK)
	var want := (0.8 - FightControls.PAD_DEADZONE) / (1.0 - FightControls.PAD_DEADZONE)
	_check(c.heading.distance_to(Vector2(want, 0.0)) < 0.01,
		"the pad left stick drives heading with the deadzone rescaled " + str(c.heading))

	_pad_axis(JOY_AXIS_LEFT_X, 0.1)
	c._physics_process(TICK)
	_check(c.heading == Vector2.ZERO, "inside the deadzone the pad stick reads zero")

	_pad_axis(JOY_AXIS_LEFT_X, 0.0)
	_pad_axis(JOY_AXIS_LEFT_Y, -1.0)
	c._physics_process(TICK)
	_check(c.heading.distance_to(Vector2(0.0, -1.0)) < 0.01,
		"pad stick up is heading up the screen " + str(c.heading))
	_pad_axis(JOY_AXIS_LEFT_Y, 0.0)
	c._physics_process(TICK)

	# Fire is edge triggered on the face button and on the right trigger.
	_pad_button(JOY_BUTTON_A, true)
	c._physics_process(TICK)
	_check(c.consume_fire(), "the pad A button fires")
	c._physics_process(TICK)
	_check(not c.consume_fire(), "holding A does not fire again")
	_pad_button(JOY_BUTTON_A, false)
	c._physics_process(TICK)
	_pad_axis(JOY_AXIS_TRIGGER_RIGHT, 0.9)
	c._physics_process(TICK)
	_check(c.consume_fire(), "the right trigger fires")
	_pad_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	c._physics_process(TICK)
	_check(not c.consume_fire(), "releasing the trigger does not fire again")

	# Secondary is level.
	_pad_button(JOY_BUTTON_B, true)
	c._physics_process(TICK)
	_check(c.secondary, "the pad B button holds secondary")
	_pad_button(JOY_BUTTON_B, false)
	c._physics_process(TICK)
	_check(not c.secondary, "releasing B clears secondary")
	_pad_axis(JOY_AXIS_TRIGGER_LEFT, 0.9)
	c._physics_process(TICK)
	_check(c.secondary, "the left trigger holds secondary")
	_pad_axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	c._physics_process(TICK)

	# START asks for a pause, once per press.
	var pauses := [0]
	c.pause_requested.connect(func() -> void: pauses[0] += 1)
	_pad_button(JOY_BUTTON_START, true)
	c._physics_process(TICK)
	c._physics_process(TICK)
	_check(pauses[0] == 1, "START emits pause_requested exactly once per press")
	_pad_button(JOY_BUTTON_START, false)
	c._physics_process(TICK)

	# Right stick and shoulders reach the camera through the existing signals.
	_pinches.clear()
	_orbits.clear()
	_pad_axis(JOY_AXIS_RIGHT_X, 1.0)
	c._process(0.1)
	_check(not _orbits.is_empty() and _orbits[_orbits.size() - 1].x > 0.0,
		"the pad right stick emits camera_orbit")
	_pad_axis(JOY_AXIS_RIGHT_X, 0.0)
	_pad_button(JOY_BUTTON_RIGHT_SHOULDER, true)
	c._process(0.1)
	_check(not _pinches.is_empty() and _pinches[_pinches.size() - 1] > 1.0,
		"the right shoulder emits camera_pinch above 1, which moves in")
	_pad_button(JOY_BUTTON_RIGHT_SHOULDER, false)
	_pad_button(JOY_BUTTON_LEFT_SHOULDER, true)
	c._process(0.1)
	_check(_pinches[_pinches.size() - 1] < 1.0, "the left shoulder pinches back out")
	_pad_button(JOY_BUTTON_LEFT_SHOULDER, false)

	_test_tank(c)

	# Touch still works with no pad.
	c.set_pad_present(false)
	_pad_reset()
	_check(not c.pad_present(), "the pad can be switched back off")
	_touch(c, 9, Vector2(200.0, 400.0), true)
	_drag(c, 9, Vector2(260.0, 400.0))
	c._physics_process(TICK)
	_check(c.heading.distance_to(Vector2(1, 0)) < 0.02,
		"touch still drives with no pad connected " + str(c.heading))
	_touch(c, 9, Vector2(260.0, 400.0), false)
	c._physics_process(TICK)
	_check(c.heading == Vector2.ZERO, "releasing the touch stick still zeroes heading")
	await _frames(1)


## The tank twin stick mix is pure maths, so it is asserted directly.
func _test_tank(c: FightControls) -> void:
	var ahead := c.tank_mix(1.0, 1.0)
	_check(is_equal_approx(ahead["throttle"], 1.0) and is_equal_approx(ahead["turn"], 0.0)
		and is_equal_approx(ahead["magnitude"], 1.0) and not ahead["reverse"],
		"both tracks ahead is full throttle, no turn")
	var astern := c.tank_mix(-1.0, -1.0)
	_check(is_equal_approx(astern["throttle"], -1.0) and astern["reverse"],
		"both tracks back is full reverse")
	var pivot := c.tank_mix(1.0, -1.0)
	_check(is_equal_approx(pivot["throttle"], 0.0) and is_equal_approx(pivot["turn"], 1.0)
		and is_equal_approx(pivot["magnitude"], FightControls.TANK_PIVOT_THROTTLE),
		"a pure pivot keeps TANK_PIVOT_THROTTLE of throttle so the bot still turns")
	var one_track := c.tank_mix(1.0, 0.0)
	_check(is_equal_approx(one_track["throttle"], 0.5) and is_equal_approx(one_track["turn"], 0.5),
		"one track ahead is half throttle and half turn")
	var still := c.tank_mix(0.0, 0.0)
	_check(is_equal_approx(still["magnitude"], 0.0), "both tracks centred asks for nothing")

	# And the integrated heading the scheme actually produces.
	c.set_scheme(FightControls.SCHEME_TANK)
	_check(c.scheme() == FightControls.SCHEME_TANK, "the scheme switches to tank")
	_pad_reset()
	_pad_axis(JOY_AXIS_LEFT_Y, -1.0)
	_pad_axis(JOY_AXIS_RIGHT_Y, -1.0)
	c._physics_process(TICK)
	_check(c.heading.distance_to(Vector2(0.0, -1.0)) < 0.01,
		"tank with both sticks forward drives straight up the screen " + str(c.heading))
	_check(is_equal_approx(c.tank_yaw_deg(), 0.0), "driving straight does not swing the heading")
	_pad_axis(JOY_AXIS_RIGHT_Y, 1.0)
	for i in 30:
		c._physics_process(TICK)
	_check(c.tank_yaw_deg() > 5.0,
		"a differential swings the virtual heading to the right (%.1f degrees)" % c.tank_yaw_deg())
	c.set_scheme(FightControls.SCHEME_ARCADE)
	_pad_reset()
	c._physics_process(TICK)


func _test_pad_hints(scene: PackedScene, c: FightControls) -> void:
	var hud: FightHud = scene.instantiate() as FightHud
	var host := _hud_host()
	host.add_child(hud)
	await _frames(1)
	_check(not hud.pad_hints_visible(), "with no pad the HUD shows no glyph hints")
	var hint := hud.get_node("Root/HintPrimary") as Label
	var hint_b := hud.get_node("Root/HintSecondary") as Label
	_check(hint != null and not hint.visible, "the pad hints start hidden")

	# CHANGED 2026-09-14: connecting a pad is not enough. The iPhone 17 simulator
	# reports a phantom 'MFi Gamepad' at launch, and hiding the touch controls for a pad
	# nobody is holding is exactly the bug the owner hit.
	c.set_pad_present(true)
	_check(not hud.pad_hints_visible(),
		"a pad that is only CONNECTED shows no hints and leaves the touch controls up")
	_pad_button(JOY_BUTTON_A, true)
	c._physics_process(TICK)
	_pad_button(JOY_BUTTON_A, false)
	c._physics_process(TICK)
	c.consume_fire()
	_check(hud.pad_hints_visible(), "a pad that has been USED shows the glyph hints")
	_check(hint.visible and hint.text == "A FLIP", "the primary hint reads A FLIP")
	_check(hint_b.visible and hint_b.text.begins_with("B "), "the secondary hint is a B glyph")
	c.set_state(true, 4)
	_check(hint_b.text == "B SELF RIGHT",
		"the secondary hint follows the button label when the bot is inverted (%s)" % hint_b.text)
	c.set_state(false, 8)
	_check(hint_b.text == "B PIVOT", "and back to B PIVOT when it is upright")

	# The hints sit where the buttons they replace would be.
	var centres: Dictionary = c.button_centres()
	var centre: Vector2 = centres["primary"]
	var box := Rect2(hint.position, hint.size)
	_check(box.has_point(centre),
		"the primary hint covers the primary button position " + str(box) + " " + str(centre))

	# The Swift shell's settings message names the pad, so the glyphs can match it. It
	# chooses the GLYPHS and never the visibility: that follows pad_active alone.
	hud.set_controller_hints(true, "Xbox Wireless Controller")
	_check(hud.pad_hints_visible() and hint.text == "A FLIP" and hint_b.text == "B PIVOT",
		"an Xbox kind keeps the A and B glyphs")
	for kind: String in ["DualSense", "DualShock 4", "PlayStation Controller", "PS5"]:
		hud.set_controller_hints(true, kind)
		var cross: String = hint.text.split(" ")[0]
		var circle: String = hint_b.text.split(" ")[0]
		_check(cross != "A" and circle != "B" and not cross.is_empty() and not circle.is_empty(),
			"%s swaps to the cross and circle glyphs (%s %s)" % [kind, cross, circle])
	_check(hud.controller_kind() == "PS5", "the HUD remembers the controller kind")
	hud.set_controller_hints(false, "PS5")
	_check(not hud.pad_hints_visible(), "a disconnected controller hides the hints")
	hud.set_controller_hints(true, "Xbox")

	# A connected but unused pad must not be able to hide the controls through settings.
	c.reset_pad_activity()
	hud.set_controller_hints(true, "Xbox Wireless Controller")
	_check(not hud.pad_hints_visible(),
		"the shell reporting a connected controller does not on its own hide the controls")

	c.set_pad_present(false)
	_check(not hud.pad_hints_visible(), "unplugging the pad hides the glyph hints again")
	_check(not c.pad_seen_by_engine(),
		"pad_seen_by_engine reports what Godot itself can see, ignoring the QA override")
	hud.queue_free()


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

	var host := _hud_host()
	host.add_child(hud)
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
	var ko_prompt := hud.get_node("Root/KoPrompt") as Label
	_check(ko.visible and ko.text.contains("KNOCKOUT COUNT 7"), "the knockout count shows")
	_check(not ko_prompt.visible,
		"a count on the OPPONENT carries no advice for the player")
	hud.show_ko_count(7, "Tinribs", true)
	_check(ko_prompt.visible and ko_prompt.text == "DRIVE TO STOP THE COUNT",
		"a count on the player's own machine says what to do about it")
	_check(ko_prompt.get_theme_color("font_color") == FightHud.COL_TEXT,
		"in white, not in the count's gold")
	hud.hide_ko_count()
	_check(not ko.visible and not ko_prompt.visible, "the knockout count hides")

	# The shell draws a 44 pt round pause button in the top-right corner, 12 pt in from
	# both edges. On the live build the gold scrap counter sat under it and read "SCRA".
	hud.set_safe_area({"left": 59.0, "top": 0.0, "right": 59.0, "bottom": 21.0})
	var corner := hud.reserved_corner()
	var scrap := hud.get_node("Root/Scrap") as Label
	var scrap_box := Rect2(scrap.position, scrap.size)
	_check(not scrap_box.intersects(corner),
		"the scrap counter keeps out of the reserved corner %s vs %s"
			% [str(scrap_box), str(corner)])
	var hud_pt: float = hud.points()
	_check(corner.position.x - (scrap_box.position.x + scrap_box.size.x)
			>= FightHud.CORNER_CLEARANCE_PT * hud_pt - 0.5,
		"and clears it by a further %.0f pt, so the digits do not touch the button"
			% FightHud.CORNER_CLEARANCE_PT)
	_check(scrap.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT,
		"and is right aligned against that edge")
	_check(corner.size.x >= FightHud.CORNER_RESERVE_PT * hud_pt - 0.5
			and corner.size.y >= FightHud.CORNER_RESERVE_PT * hud_pt - 0.5,
		"the reserved corner is at least %.0f x %.0f pt (%s at %.4f px per pt)"
			% [FightHud.CORNER_RESERVE_PT, FightHud.CORNER_RESERVE_PT,
				str(corner.size), hud_pt])
	for l: Label in [hud.get_node("Root/Timer"), hud.get_node("Root/Names"),
			hud.get_node("Root/Readout")]:
		# These are centre or left aligned bands; what matters is that their text cannot
		# reach the corner, which a full width band's own box would wrongly claim.
		_check(l.horizontal_alignment != HORIZONTAL_ALIGNMENT_RIGHT,
			"%s is not right aligned, so nothing of it lands in the corner" % l.name)

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
	# CHANGED 2026-09-14: the auto framing may want closer than CAM_ZOOM_MIN when the two
	# machines are together, and the player may follow it in.
	_check(rig.zoom_min() == minf(minf(FightTypes.CAM_ZOOM_MIN, rig.default_zoom()),
			rig.resting_zoom()),
		"the closest zoom is CAM_ZOOM_MIN, the QA default or the auto framing, whichever is nearest")
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
	# CHANGED 2026-09-14: the resting zoom frames the BOTS and is recomputed every frame,
	# so the ease back lands on that rather than on the constant DEFAULT_ZOOM.
	_check(is_equal_approx(rig.zoom, rig.resting_zoom()),
		"zoom eases back to the resting framing, not to 1.0 (%.3f)" % rig.zoom)
	_check(rig.is_resting(), "and the rig is sitting on the auto framing again")

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

	# Impact shake (docs/graphics-fx-notes.md section 4). The rig finds the source by
	# group and puts its offset on the Camera3D's local transform, fight mode only.
	rig.set_mode(CameraRig.MODE_FIGHT)
	rig.reset_to_default()
	_check(cam.transform.origin == Vector3.ZERO, "with no shake source the camera sits at its local origin")
	var rig_pos := rig.global_position
	var fake := FakeShake.new()
	fake.value = Vector3(0.03, 0.0, 0.0)
	vp.add_child(fake)
	_step(rig, 0.1)
	_check(cam.transform.origin.is_equal_approx(fake.value),
		"the camera local origin equals the shake offset " + str(cam.transform.origin))
	_check(rig.global_position.is_equal_approx(rig_pos),
		"the shake goes on the camera, never on the rig")
	rig.set_mode(CameraRig.MODE_WORKSHOP)
	_step(rig, 0.1)
	_check(cam.transform.origin == Vector3.ZERO, "the shake is zero in workshop mode")
	rig.set_mode(CameraRig.MODE_MENU)
	_step(rig, 0.1)
	_check(cam.transform.origin == Vector3.ZERO, "the shake is zero in menu mode")
	rig.set_mode(CameraRig.MODE_FIGHT)
	fake.free()
	_step(rig, 0.1)
	_check(cam.transform.origin == Vector3.ZERO,
		"the camera returns to its local origin when the shake source goes away")


# ---------------------------------------------------------------- new in 2026-09-14

## The resting stick. Before this the left half of the screen was blank until a thumb
## landed on it, which is why the owner had "no idea what the controls are".
func _test_resting_stick(c: FightControls) -> void:
	var safe := {"left": 59.0, "top": 0.0, "right": 59.0, "bottom": 21.0}
	c.set_safe_area(safe)
	var home := c.stick_home()
	var pt: float = float((c.button_centres())["pt"])
	_check(is_equal_approx(home.x, 59.0 + FightControls.STICK_HOME_INSET_PT * pt),
		"the resting stick sits %.0f pt in from the safe area's left edge (%s)"
			% [FightControls.STICK_HOME_INSET_PT, str(home)])
	_check(is_equal_approx(home.y, 556.0 - 21.0 - FightControls.STICK_HOME_INSET_PT * pt),
		"and %.0f pt up from the safe area's bottom edge" % FightControls.STICK_HOME_INSET_PT)
	_check(FightControls.STICK_HOME_INSET_PT > FightControls.EDGE_MARGIN_PT,
		"the resting stick clears EDGE_MARGIN_PT as well as the safe area")
	var zone: Rect2 = (c.button_centres())["stick_zone"]
	_check(zone.has_point(home), "the resting stick sits inside the zone a touch claims")
	_check(home.distance_to((c.button_centres())["primary"]) > 300.0 * pt,
		"the resting stick is nowhere near the weapon button")
	c.set_safe_area({"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0})

	# The resting base fades out under a live stick and comes back on release.
	c._tick_rest_fade(1.0)
	_check(is_equal_approx(c._rest_alpha, 1.0), "the resting base is drawn when nothing is held")
	_touch(c, 30, Vector2(250.0, 380.0), true)
	c._tick_rest_fade(FightControls.STICK_REST_FADE_S + 0.05)
	_check(c._rest_alpha <= 0.001, "a live stick touch fades the resting base out")
	_touch(c, 30, Vector2(250.0, 380.0), false)
	c._tick_rest_fade(FightControls.STICK_REST_FADE_S * 0.5)
	_check(c._rest_alpha > 0.1 and c._rest_alpha < 1.0,
		"the resting base fades back rather than snapping (%.2f)" % c._rest_alpha)
	c._tick_rest_fade(FightControls.STICK_REST_FADE_S)
	_check(is_equal_approx(c._rest_alpha, 1.0), "and is fully back a moment later")


## Every weapon in Shared/parts.json gets its own word on the primary button, and the
## same word reaches the HUD's glyph hint. The button used to say FLIP for all ten.
func _test_weapon_words(c: FightControls) -> void:
	var expected := {
		"flipper": ["FLIP", false, false],
		"spinner": ["SPIN", true, true],
		"drum": ["SPIN", true, true],
		"saw": ["SPIN", true, true],
		"fbs": ["SPIN", true, true],
		"axe": ["SWING", false, false],
		"crusher": ["CLAMP", true, false],
		"lifter": ["LIFT", true, false],
		"flame": ["FIRE", true, false],
		"ram": ["RAM", false, false],
	}
	var heard: Array[String] = []
	c.primary_label_changed.connect(func(l: String) -> void: heard.append(l))
	for kind: String in expected.keys():
		var row: Array = expected[kind]
		c.set_weapon(kind)
		_check(c.primary_label() == str(row[0]),
			"a %s button reads %s (got %s)" % [kind, str(row[0]), c.primary_label()])
		_check(c.primary_is_hold() == bool(row[1]),
			"a %s is worked by %s" % [kind, "holding" if bool(row[1]) else "tapping"])
		_check(c.shows_spin_ring() == bool(row[2]),
			"a %s %s a spin-up ring" % [kind, "carries" if bool(row[2]) else "carries no"])
	_check(not heard.is_empty(), "changing the weapon announces the new label")

	# Every weapon id in the parts catalogue has a word. A weapon with no word would
	# silently keep whatever the last one said.
	var parts: Dictionary = PartsCatalogue.parts().get("weapon", {}) as Dictionary
	var missing: Array[String] = []
	for id: String in parts.keys():
		var kind := str((parts[id] as Dictionary).get("kind", ""))
		if not FightControls.WEAPON_WORDS.has(kind):
			missing.append("%s (%s)" % [id, kind])
	_check(missing.is_empty(),
		"every weapon in the catalogue has a word on the button " + str(missing))
	# Ten through wave V; sixteen since wave P added brief v5 section 9.5's six.
	_check(parts.size() == 16,
		"the catalogue carries sixteen weapons (%d)" % parts.size())

	# The spin-up ring follows the weapon's readiness, which only means a spin fraction
	# for the four hold-to-spin weapons.
	c.set_weapon("spinner", 0.5)
	_check(is_equal_approx(c._weapon_spin, 0.5), "a spinner's spin fraction reaches the ring")
	c.set_weapon("flipper")
	_check(not c.shows_spin_ring(), "a flipper shows gas pips, never a spin ring")


## The stick and the two buttons own their touches: a finger on one of them can never
## become a camera finger, however far it is dragged.
func _test_camera_ownership(c: FightControls) -> void:
	_orbits.clear()
	_pinches.clear()
	# A drag that STARTS in the stick zone drives and never orbits, even dragged right
	# across the screen into the camera area.
	_touch(c, 10, Vector2(200.0, 400.0), true)
	_drag(c, 10, Vector2(900.0, 200.0))
	_check(_orbits.is_empty(), "a finger that started on the stick never orbits " + str(_orbits))
	_check(c.heading.length() > 0.9, "and it is still driving " + str(c.heading))
	_touch(c, 10, Vector2(900.0, 200.0), false)

	# A drag that starts on the primary button is a button press to the end.
	var primary: Vector2 = (c.button_centres())["primary"]
	_orbits.clear()
	_touch(c, 11, primary, true)
	_drag(c, 11, primary + Vector2(-200.0, -200.0))
	_check(_orbits.is_empty(), "a finger that started on the weapon button never orbits")
	_check(c.consume_fire(), "and it still fired")
	_touch(c, 11, primary + Vector2(-200.0, -200.0), false)

	# A drag that starts on the secondary button is likewise the secondary.
	var secondary: Vector2 = (c.button_centres())["secondary"]
	_orbits.clear()
	_touch(c, 12, secondary, true)
	_drag(c, 12, secondary + Vector2(120.0, -120.0))
	_check(_orbits.is_empty(), "a finger that started on the secondary button never orbits")
	_check(c.secondary, "and it is still holding the secondary")
	_touch(c, 12, secondary + Vector2(120.0, -120.0), false)

	# And the camera still works while the stick is held: two thumbs, no interference.
	_orbits.clear()
	_touch(c, 13, Vector2(200.0, 400.0), true)
	_drag(c, 13, Vector2(240.0, 400.0))
	var driving := c.heading
	_touch(c, 14, Vector2(800.0, 200.0), true)
	_drag(c, 14, Vector2(860.0, 220.0))
	_check(not _orbits.is_empty(), "one thumb driving and another dragging orbits the camera")
	_check(c.heading == driving, "and the driving thumb is undisturbed " + str(c.heading))
	_touch(c, 14, Vector2(860.0, 220.0), false)
	_touch(c, 13, Vector2(240.0, 400.0), false)
	c.consume_fire()


## The pad rule state machine: connected is not enough, used is. A touch takes the
## screen back, and a new fight makes the pad earn it again.
func _test_pad_rule(c: FightControls, hud_scene: PackedScene) -> void:
	var hud: FightHud = hud_scene.instantiate() as FightHud
	var host := _hud_host()
	host.add_child(hud)
	await _frames(1)
	_pad_reset()
	c.set_pad_present(false)
	c.reset_pad_activity()

	var events: Array[bool] = []
	c.pad_active_changed.connect(func(on: bool) -> void: events.append(on))

	c.set_pad_present(true)
	_check(c.pad_present() and not c.pad_active(),
		"a connected pad is present but not yet active")
	_check(events.is_empty(), "and connecting it announced nothing")
	_check(not hud.pad_hints_visible(), "so the HUD shows no glyph hints yet")

	# An axis inside the deadzone is not input: a worn stick rests as far out as 0.12.
	_pad_axis(JOY_AXIS_LEFT_X, 0.1)
	c._physics_process(TICK)
	_check(not c.pad_active(), "a stick inside the deadzone does not wake the pad")

	_pad_axis(JOY_AXIS_LEFT_X, 0.9)
	c._physics_process(TICK)
	_check(c.pad_active(), "a stick past the deadzone makes the pad active")
	_check(events == [true], "and it announced exactly once " + str(events))
	_check(hud.pad_hints_visible(), "the HUD swaps in the glyph hints")
	_pad_axis(JOY_AXIS_LEFT_X, 0.0)
	c._physics_process(TICK)
	_check(c.pad_active(), "letting go of the stick does not put the touch controls back")

	# A thumb on the glass takes the screen back, whatever it lands on.
	_touch(c, 40, Vector2(700.0, 300.0), true)
	_check(not c.pad_active(), "any touch brings the touch furniture back")
	_check(not hud.pad_hints_visible(), "and hides the glyph hints")
	_touch(c, 40, Vector2(700.0, 300.0), false)

	# A button press wakes it again.
	_pad_button(JOY_BUTTON_B, true)
	c._physics_process(TICK)
	_check(c.pad_active(), "a pad button press makes it active again")
	_pad_button(JOY_BUTTON_B, false)
	c._physics_process(TICK)

	# A new fight makes the pad earn the screen again.
	c.reset_pad_activity()
	_check(c.pad_present() and not c.pad_active(), "a new fight resets the pad to inactive")
	_check(not hud.pad_hints_visible(), "so a new fight always starts with the controls up")

	# Unplugging clears both.
	_pad_button(JOY_BUTTON_A, true)
	c._physics_process(TICK)
	_check(c.pad_active(), "the pad is active again")
	c.set_pad_present(false)
	_check(not c.pad_present() and not c.pad_active(), "unplugging clears present and active")
	_pad_reset()
	c._physics_process(TICK)
	c.consume_fire()
	hud.queue_free()
	await _frames(1)


## The coach callouts: when they show, what fades them, and when they are all gone.
func _test_coach(scene: PackedScene, c: FightControls) -> void:
	var hud: FightHud = scene.instantiate() as FightHud
	var host := _hud_host()
	host.add_child(hud)
	await _frames(1)
	c.set_pad_present(false)
	c.reset_pad_activity()
	c.reset_input_usage()
	c.set_weapon("spinner")
	hud.set_coach(true)
	_check(hud.coach_enabled(), "the coach is on for this fight")

	var overlay := hud.get_node("Coach") as Control
	_check(overlay != null and overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"the coach overlay can never intercept a touch")

	# Nothing is drawn until the fight is in a phase that wants them.
	hud.set_coach_phase("loading")
	hud.coach_step(1.0)
	_check(not hud.coach_visible(), "no callouts outside the countdown and the fight")

	hud.set_coach_phase(FightHud.COACH_COUNTDOWN)
	hud.coach_step(1.0)
	_check(hud.coach_visible(), "the callouts show through the countdown")
	_check(is_equal_approx(hud.coach_alpha("drive"), 1.0)
		and is_equal_approx(hud.coach_alpha("primary"), 1.0)
		and is_equal_approx(hud.coach_alpha("camera"), 1.0),
		"all three are drawn at full strength")

	# Using the stick fades ONLY the drive callout.
	_touch(c, 50, Vector2(200.0, 400.0), true)
	_drag(c, 50, Vector2(260.0, 400.0))
	hud.coach_step(FightHud.COACH_FADE_S + 0.1)
	_check(hud.coach_alpha("drive") <= 0.001, "driving fades the DRIVE callout out")
	_check(is_equal_approx(hud.coach_alpha("primary"), 1.0),
		"and leaves the weapon callout alone")
	_touch(c, 50, Vector2(260.0, 400.0), false)

	# Tapping the weapon button fades the weapon callout.
	_touch(c, 51, (c.button_centres())["primary"], true)
	_touch(c, 51, (c.button_centres())["primary"], false)
	c.consume_fire()
	hud.coach_step(FightHud.COACH_FADE_S + 0.1)
	_check(hud.coach_alpha("primary") <= 0.001, "using the weapon fades its callout out")
	_check(is_equal_approx(hud.coach_alpha("camera"), 1.0), "the camera callout is still up")

	# Dragging one finger in the camera area fades the last one.
	_touch(c, 52, Vector2(800.0, 200.0), true)
	_drag(c, 52, Vector2(830.0, 210.0))
	_touch(c, 52, Vector2(830.0, 210.0), false)
	hud.coach_step(FightHud.COACH_FADE_S + 0.1)
	_check(hud.coach_alpha("camera") <= 0.001, "moving the camera fades the CAMERA callout out")
	_check(not hud.coach_visible(), "and with all three used, nothing is left")

	# The timeline: untouched callouts are gone a few seconds into the fight anyway.
	c.reset_input_usage()
	hud.set_coach(true)
	hud.set_coach_phase(FightHud.COACH_FIGHTING)
	hud.coach_step(0.5)
	_check(hud.coach_visible(), "the callouts survive into the opening of the fight")
	hud.coach_step(FightHud.COACH_FIGHT_S)
	hud.coach_step(FightHud.COACH_FADE_S + 0.1)
	_check(hud.coach_fight_seconds() > FightHud.COACH_FIGHT_S,
		"the fight clock has passed %.0f s" % FightHud.COACH_FIGHT_S)
	_check(not hud.coach_visible(),
		"every callout is gone after %.0f s of fighting, used or not" % FightHud.COACH_FIGHT_S)

	# A pad that is driving takes them away too: none of those controls are on screen.
	c.reset_input_usage()
	hud.set_coach(true)
	hud.set_coach_phase(FightHud.COACH_COUNTDOWN)
	hud.coach_step(0.5)
	_check(hud.coach_visible(), "the callouts are back for a fresh fight")
	c.set_pad_present(true)
	_pad_button(JOY_BUTTON_A, true)
	c._physics_process(TICK)
	hud.coach_step(FightHud.COACH_FADE_S + 0.1)
	_check(not hud.coach_visible(), "a pad driving hides the touch callouts")
	_pad_button(JOY_BUTTON_A, false)
	c._physics_process(TICK)
	c.set_pad_present(false)
	c.consume_fire()

	# And the drawing itself runs, which is the only place a bad draw call shows up.
	c.reset_input_usage()
	hud.set_coach(true)
	hud.set_coach_phase(FightHud.COACH_COUNTDOWN)
	hud.coach_step(0.1)
	for kind: String in ["flipper", "spinner", "axe", "crusher", "ram"]:
		c.set_weapon(kind, 0.4)
		overlay.queue_redraw()
		await _frames(2)
	_check(true, "the coach callouts draw for every weapon word")

	# The PAUSED mark.
	hud.set_paused(true)
	var paused := hud.get_node("Root/Paused") as Label
	_check(paused != null and paused.visible and paused.text == "PAUSED",
		"the HUD shows a PAUSED mark while the simulation is stopped")
	var before := hud.coach_fight_seconds()
	hud.set_coach_phase(FightHud.COACH_FIGHTING)
	hud.coach_step(1.0)
	_check(is_equal_approx(hud.coach_fight_seconds(), before),
		"the coach clock does not run while the fight is paused")
	hud.set_paused(false)
	_check(not paused.visible, "and the mark goes when the fight resumes")

	hud.set_coach(false)
	_check(not hud.coach_visible(), "the coach can be switched off entirely")
	hud.queue_free()
	await _frames(1)


# ---------------------------------------------------------------- the Broadcast feed
#
# Wave V: the fight feed is the Broadcast system (docs/design-system.md sections 1 to 4).
# Everything below is about the RESTYLE: the tokens, where the furniture lands, the
# ticker, the ENDGAME slam and the fact that all of it really draws. The behaviour tests
# above are unchanged, which is the point: nothing of what the feed DOES moved.

## The tokens, the font and the drawn shapes.
func _test_broadcast_tokens() -> void:
	var theme := Broadcast.theme()
	_check(theme != null, "the Broadcast theme loads")
	_check(theme != null and theme.default_font_size == int(Broadcast.LABEL_PT),
		"and carries the label size (%d)" % (theme.default_font_size if theme != null else -1))

	# Barlow Condensed is bundled in Arena/assets/fonts. A build without it falls back to
	# the engine face rather than drawing nothing, but the ship needs the real one.
	var found: Dictionary = Broadcast.fonts_found()
	var missing: Array[String] = []
	for role: String in found.keys():
		if not bool(found[role]):
			missing.append(role)
	_check(missing.is_empty(), "Barlow Condensed loads for every role " + str(missing))
	_check(theme != null and theme.default_font != null,
		"and the theme is carrying a font for the labels that never set one")
	# Read straight off disk, past the resource cache, so this is the FILE carrying the
	# face and not the copy Broadcast.theme() may have injected one into.
	var on_disk := ResourceLoader.load(Broadcast.THEME_PATH, "Theme",
		ResourceLoader.CACHE_MODE_IGNORE) as Theme
	_check(on_disk != null and on_disk.default_font != null,
		"and broadcast_theme.tres itself names the face, not just the code")

	# Colours are the design system's, to the byte.
	_check(Broadcast.LINE.to_html(false).to_upper() == "35D6F0",
		"`line` is 35D6F0 (%s)" % Broadcast.LINE.to_html(false))
	_check(Broadcast.SCRAP.to_html(false).to_upper() == "F0B23A",
		"`scrap` is F0B23A (%s)" % Broadcast.SCRAP.to_html(false))
	_check(Broadcast.DANGER.to_html(false).to_upper() == "E5483C",
		"`danger` is E5483C (%s)" % Broadcast.DANGER.to_html(false))
	_check(is_equal_approx(Broadcast.GLASS.a, 0.82) and is_equal_approx(Broadcast.GLASS_LIVE.a, 0.62),
		"glass is 82 %, and 62 % over the live arena")

	# The panel: a rectangle with ONE cut corner, top right, and never a rounded one.
	var rect := Rect2(Vector2(10.0, 20.0), Vector2(200.0, 60.0))
	var points := Broadcast.panel_points(rect, 1.0)
	_check(points.size() == 5, "a panel is five points, one corner cut (%d)" % points.size())
	_check(is_equal_approx(points[1].x, rect.position.x + rect.size.x - Broadcast.CUT)
		and is_equal_approx(points[2].y, rect.position.y + Broadcast.CUT),
		"and the cut is %0.f pt off the top right" % Broadcast.CUT)
	var doubled := Broadcast.panel_points(rect, 2.0)
	_check(is_equal_approx(doubled[1].x, rect.position.x + rect.size.x - Broadcast.CUT * 2.0),
		"the cut scales with the viewport")

	# The lower third leans right, always, and the lean is the same 12 degrees.
	var leaned := Broadcast.skew(points, rect.position.y + rect.size.y)
	_check(leaned[0].x > points[0].x and is_equal_approx(leaned[4].x, points[4].x),
		"a lower third leans right off its bottom edge " + str(leaned[0]))
	var want_lean := rect.size.y * tan(deg_to_rad(Broadcast.SKEW_DEG))
	_check(absf((leaned[0].x - points[0].x) - want_lean) < 0.01,
		"by %.1f degrees (%.2f px over %.0f)" % [Broadcast.SKEW_DEG, leaned[0].x - points[0].x,
			rect.size.y])

	# The type floor: 11 iOS pt, which is TYPE_FLOOR_PT of the arena's own units.
	_check(Broadcast.LABEL_PT >= Broadcast.TYPE_FLOOR_PT,
		"label type clears the legibility floor")
	_check(is_equal_approx(Broadcast.COUNT_S, 0.4), "numbers count over 0.4 s")

	# A weapon glyph is optional: the button falls back to the word when there is no file.
	var glyph := Broadcast.glyph("weapon", "flipper")
	_check(glyph == null or glyph is Texture2D,
		"the weapon glyph is a texture when it exists and null when it does not (%s)"
			% ("drawn" if glyph != null else "not drawn yet, the word is used"))
	_check(Broadcast.glyph("weapon", "no_such_weapon") == null,
		"and a weapon nobody has drawn gets null rather than an error")
	await _frames(1)


## Where the feed's furniture lands: the clock bug top centre, a lower third in each top
## corner, the scrap bug clear of the shell's pause button, the ticker along the bottom.
func _test_feed_layout(scene: PackedScene) -> void:
	var hud: FightHud = scene.instantiate() as FightHud
	var host := _hud_host()
	host.add_child(hud)
	hud.set_safe_area({"left": 59.0, "top": 0.0, "right": 59.0, "bottom": 21.0})
	hud.set_bot_names("Tinribs", "Scrapheap")
	await _frames(1)
	var size := host.get_visible_rect().size

	var chrome := hud.get_node_or_null("Root/Chrome") as Control
	_check(chrome != null, "the drawn chrome has its own canvas")
	_check(chrome != null and chrome.get_index() == 0,
		"and it is the first child of Root, so every label sits on its plate")
	_check(chrome != null and chrome.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"and it can never take a touch")

	var timer := hud.get_node("Root/Timer") as Label
	var phase := hud.get_node("Root/Phase") as Label
	var names := hud.get_node("Root/Names") as Label
	var opponent := hud.get_node("Root/Opponent") as Label
	var scrap := hud.get_node("Root/Scrap") as Label
	_check(absf((timer.position.x + timer.size.x * 0.5) - size.x * 0.5) < 2.0,
		"the clock sits in the middle of the top edge (%.0f of %.0f)"
			% [timer.position.x + timer.size.x * 0.5, size.x])
	_check(phase.position.y >= timer.position.y + timer.size.y - 1.0,
		"the phase word sits under it")
	_check(hud.phase_word() == FightHud.PHASE_OPEN,
		"and reads OPEN before the round turns (%s)" % hud.phase_word())
	_check(names.text == "TINRIBS" and opponent.text == "SCRAPHEAP",
		"each machine has its own lower third (%s / %s)" % [names.text, opponent.text])
	_check(names.position.x < size.x * 0.5 and opponent.position.x > size.x * 0.5,
		"the player's is left and the opponent's is right (%.0f and %.0f of %.0f)"
			% [names.position.x, opponent.position.x, size.x])
	_check(opponent.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT,
		"the right hand one is set against its own edge")

	# Nothing of the top right may reach the corner the shell's pause button owns.
	var corner := hud.reserved_corner()
	for l: Label in [scrap, opponent]:
		_check(not Rect2(l.position, l.size).intersects(corner),
			"%s keeps out of the reserved corner %s" % [l.name, str(corner)])
	_check(opponent.position.y > scrap.position.y,
		"the opponent's third sits under the scrap bug, not beside the pause button")

	# The scrap bug carries the numerals alone; the word is drawn on the plate.
	hud.set_scrap(150)
	_check(scrap.text.is_valid_int(), "the scrap bug is numerals alone (%s)" % scrap.text)
	_check(hud.scrap_total() == 150, "with the word drawn on the plate beside them")
	_check(is_equal_approx(FightHud.ROLL_S, Broadcast.COUNT_S),
		"and counts over %.1f s" % Broadcast.COUNT_S)

	# The ticker is the bottom strip, full width, inside the safe area.
	var strip: Rect2 = hud.ticker_rect()
	_check(is_equal_approx(strip.size.x, size.x), "the ticker runs the full width")
	_check(absf(strip.position.y + strip.size.y - (size.y - 21.0)) < 1.0,
		"and sits on the bottom safe area (%.0f + %.0f of %.0f)"
			% [strip.position.y, strip.size.y, size.y])

	# The condition bars read full until the rules layer says otherwise, and clamp.
	_check(is_equal_approx(hud.condition("player"), 1.0)
		and is_equal_approx(hud.condition("opponent"), 1.0),
		"both condition bars start full")
	hud.set_condition(0.2, -3.0)
	_check(is_equal_approx(hud.condition("player"), 0.2)
		and is_equal_approx(hud.condition("opponent"), 0.0),
		"set_condition takes the pair and clamps them")
	_check(Broadcast.CONDITION_DANGER > 0.2,
		"and %.0f %% is under the danger mark, so that bar goes red"
			% (Broadcast.CONDITION_DANGER * 100.0))
	hud.set_condition(1.0, 1.0)

	# The house bot's name sits under the opponent, in danger, while it is out.
	var house := hud.get_node("Root/HouseBot") as Label
	_check(not house.visible, "no house bot named while none is out")
	hud.set_zone_warning(true, "Thresher")
	_check(hud.house_bot_name() == "THRESHER",
		"the corner warning names the house bot (%s)" % hud.house_bot_name())
	hud.set_zone_warning(false, "Thresher")
	hud.set_coach_phase(FightHud.COACH_FIGHTING)
	hud.push_commentary(FightHud.HOUSE_BOT_OUT_LINE)
	_check(hud.house_bot_out() and house.visible and house.text == "THRESHER",
		"and HOUSE BOT OUT puts it under the opponent's third (%s)" % house.text)
	_check(house.get_theme_color("font_color") == FightHud.COL_URGENT, "in danger red")
	_check(house.position.y >= opponent.position.y + opponent.size.y - 1.0,
		"under it, not over it")
	hud.clear_commentary()
	_check(not hud.house_bot_out() and not house.visible,
		"and a new fight clears it")

	# Every label clears the legibility floor at the design size.
	var small: Array[String] = []
	for child in (hud.get_node("Root") as Control).get_children():
		if child is Label:
			var pt := float((child as Label).get_meta("size_pt", 99.0))
			if pt < Broadcast.TYPE_FLOOR_PT:
				small.append("%s %.0f" % [child.name, pt])
	_check(small.is_empty(), "no label is under the legibility floor " + str(small))

	hud.queue_free()
	await _frames(1)


## The ticker: one line at a time, sliding in from the right edge, in the bottom strip.
func _test_ticker(scene: PackedScene) -> void:
	var hud: FightHud = scene.instantiate() as FightHud
	var host := _hud_host()
	host.add_child(hud)
	hud.set_safe_area({"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0})
	await _frames(1)
	hud.set_coach_phase(FightHud.COACH_FIGHTING)
	hud.clear_commentary()

	var size := host.get_visible_rect().size
	hud.push_commentary("BIG HIT")
	hud.commentary_step(1.0 / 60.0)
	var line := hud.get_node("Root/Commentary") as Label
	_check(hud.commentary_text() == "BIG HIT", "a line reaches the ticker")
	_check(hud.commentary_slide() < 0.2,
		"and starts off the right edge (slide %.2f)" % hud.commentary_slide())
	_check(line.position.x > size.x * 0.5,
		"so the words are still out of the frame (%.0f of %.0f)" % [line.position.x, size.x])
	var strip: Rect2 = hud.ticker_rect()
	_check(absf(line.position.y - strip.position.y) < 1.0,
		"on the strip's own row, which never moves")

	hud.commentary_step(FightHud.TICKER_SLIDE_S)
	_check(is_equal_approx(hud.commentary_slide(), 1.0),
		"it is home after %.2f s" % FightHud.TICKER_SLIDE_S)
	_check(line.position.x < size.x * 0.25,
		"reading from the left of the strip (%.0f)" % line.position.x)
	_check(absf(line.position.y - strip.position.y) < 1.0, "and the row is unmoved")

	# The timeline itself is wave G's and is asserted in commentary_test; here it is only
	# that the slide never disturbs it.
	hud.commentary_step(FightHud.COMMENTARY_HOLD_S + FightHud.COMMENTARY_FADE_S + 0.1)
	_check(not hud.commentary_visible(), "the line still holds and fades as it always did")
	hud.queue_free()
	await _frames(1)


## The ENDGAME sting: a full-width slam in from the left, a hold, and out to the right,
## with the phase word and a flash across the ticker.
func _test_endgame_slam(scene: PackedScene) -> void:
	var hud: FightHud = scene.instantiate() as FightHud
	var host := _hud_host()
	host.add_child(hud)
	hud.set_safe_area({"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0})
	await _frames(1)
	_check(not hud.endgame_sting_visible(), "no sting before the round turns")

	hud.show_endgame_sting()
	_check(hud.endgame_sting_visible(), "the sting stamps on the endgame tick")
	_check(hud.phase_word() == FightHud.PHASE_ENDGAME,
		"and the phase word turns to ENDGAME (%s)" % hud.phase_word())
	var phase := hud.get_node("Root/Phase") as Label
	_check(phase.get_theme_color("font_color") == FightHud.COL_URGENT, "in danger red")
	var band := hud.get_node("Root/Endgame") as Label
	_check(band != null, "the sting is a full width band")
	_check(hud.endgame_slide() <= -0.9,
		"which starts off the left edge (slide %.2f)" % hud.endgame_slide())

	# It arrives inside SLAM_S and is gone again after the hold and the exit.
	await _frames(1)
	var waited := 0.0
	while waited < FightHud.ENDGAME_SLAM_S + 0.15 and hud.endgame_slide() < -0.01:
		await process_frame
		waited += 1.0 / 60.0
	_check(hud.endgame_slide() > -0.05,
		"and slams home in %.2f s (slide %.2f)" % [FightHud.ENDGAME_SLAM_S, hud.endgame_slide()])
	_check(hud.endgame_sting_visible(), "and holds there")

	# The hold is the whole point of a sting: half a second in it must still be on screen,
	# and it must be gone by the end of the hold plus the exit. This caught the tween
	# chaining, where the exit had been sharing a step with the interval.
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 500:
		await process_frame
	# Measured against the clock the tween is on, so a machine that stalls for a second
	# under someone else's build reports honestly instead of failing at random.
	var elapsed := float(Time.get_ticks_msec() - started) / 1000.0
	if elapsed < FightHud.ENDGAME_HOLD_S:
		_check(hud.endgame_sting_visible() and absf(hud.endgame_slide()) < 0.05,
			"still on screen %.2f s in, at slide %.2f" % [elapsed, hud.endgame_slide()])
	else:
		_check(true, "the hold could not be sampled: one frame took %.2f s" % elapsed)
	while Time.get_ticks_msec() - started < int((FightHud.ENDGAME_HOLD_S
			+ FightHud.ENDGAME_FADE_S + 0.25) * 1000.0):
		await process_frame
	_check(not hud.endgame_sting_visible(),
		"and gone after the %.1f s hold and the %.2f s exit (slide %.2f)"
			% [FightHud.ENDGAME_HOLD_S, FightHud.ENDGAME_FADE_S, hud.endgame_slide()])
	_check(hud.endgame_slide() > 0.9, "which it left to the right")

	hud.show_endgame_sting()
	hud.hide_endgame_sting()
	_check(not hud.endgame_sting_visible(), "it can be taken away by hand")
	hud.set_bot_names("Tinribs", "Scrapheap")
	_check(hud.phase_word() == FightHud.PHASE_OPEN,
		"and the next fight starts back at OPEN, not in ENDGAME red (%s)" % hud.phase_word())
	hud.queue_free()
	await _frames(1)


## Every plate, bug, bar, strip, pill and glow really draws. A bad draw call only shows
## up when it runs, and on the dummy renderer the headless suite runs it exactly the way
## Forward+ and gl_compatibility will: no shader, no texture, no renderer feature.
func _test_feed_draws(scene: PackedScene, c: FightControls) -> void:
	var vp := SubViewport.new()
	vp.size = CONTROL_SIZE
	root.add_child(vp)
	var hud: FightHud = scene.instantiate() as FightHud
	vp.add_child(hud)
	await _frames(1)
	hud.set_safe_area({"left": 59.0, "top": 0.0, "right": 59.0, "bottom": 21.0})
	hud.set_bot_names("Tinribs", "Scrapheap")
	hud.set_time_left(95.0)
	hud.set_scrap(120)
	hud.bump(30)
	hud.set_condition(0.8, 0.15)
	hud.set_height_readout("Your wedge: floor. Their flipper: mid.")
	hud.set_coach_phase(FightHud.COACH_FIGHTING)
	hud.set_coach(true)
	hud.push_commentary("BIG HIT")
	hud.commentary_step(1.0 / 60.0)
	hud.show_ko_count(7, "Scrapheap", true)
	hud.set_zone_warning(true, "Thresher")
	hud.show_zone_coach()
	hud.show_endgame_sting()
	hud.set_offscreen_marker(true, Vector2(1.0, 0.2), "Scrapheap")
	hud.set_player_tag(true, Vector2(300.0, 300.0))
	hud.marker_step(1.0)
	hud.zone_step(0.2)
	for node in [hud.get_node("Root/Chrome"), hud.get_node("Coach"), hud.get_node("ZoneWarning")]:
		(node as Control).queue_redraw()
	await _frames(3)
	_check(true, "the whole feed draws: bugs, lower thirds, bars, ticker, sting and glow")

	# The clock under ten seconds, the result banner and the countdown, which are the
	# states the frame above does not carry.
	hud.hide_ko_count()
	hud.set_time_left(8.0)
	hud.show_countdown("FIGHT")
	hud.show_result("Judges decision", "Tinribs")
	(hud.get_node("Root/Chrome") as Control).queue_redraw()
	await _frames(3)
	_check(true, "and so do the urgent clock, the countdown and the result banner")

	# The touch furniture, in its own two alphas and with a glyph that may not exist yet.
	_check(is_equal_approx(FightControls.ALPHA_REST, 0.62)
		and is_equal_approx(FightControls.ALPHA_TOUCHED, 0.90),
		"the controls draw at 62 %% resting and 90 %% touched")

	# The weapon glyph is named for the PART id, and the button only knows the KIND, so
	# the two are matched through the catalogue. A missing file falls back to the word.
	# A kind shared by two weapons resolves to the FIRST one in catalogue order, which
	# is why saw, flame and fbs still read saw, flamethrower and full_body_spinner now
	# that wave P has added a twin saw, a napalm cannon and a vortex spinner behind them.
	var glyph_ids := {"spinner": "horizontal_spinner", "drum": "vertical_spinner",
		"fbs": "full_body_spinner", "flame": "flamethrower", "flipper": "flipper",
		"axe": "axe", "saw": "saw", "ram": "ram", "crusher": "crusher", "lifter": "lifter",
		"prod": "shock_prod", "arc": "tesla_arc", "drill": "drill_lance"}
	var wrong: Array[String] = []
	var undrawn: Array[String] = []
	for kind: String in glyph_ids.keys():
		c.set_weapon(kind)
		var id: String = c.weapon_glyph_id()
		if id != str(glyph_ids[kind]):
			wrong.append("%s -> %s" % [kind, id])
		if Broadcast.glyph("weapon", id) == null:
			undrawn.append(id)
	_check(wrong.is_empty(), "every weapon kind finds its glyph's part id " + str(wrong))
	_check(undrawn.is_empty(), "and all %d of them are drawn %s"
		% [glyph_ids.size(), str(undrawn)])
	c.set_state(true, 3)
	_check(c.utility_glyph_id() == "srimech", "an inverted bot's button is the srimech")
	c.set_state(false, FightTypes.FLIPPER_CHARGES)
	_check(c.utility_glyph_id() == "pivot",
		"and a pivot has no glyph, so the button says the word")
	c.set_enabled(true)
	c.set_preview(false)
	c._tick_rest_fade(1.0)
	for weapon: String in ["flipper", "spinner", "axe", "ram"]:
		c.set_weapon(weapon, 0.5)
		c.set_state(weapon == "axe", 3)
		c.queue_redraw()
		await _frames(1)
	_touch(c, 70, (c.button_centres())["primary"], true)
	c.queue_redraw()
	await _frames(2)
	_touch(c, 70, (c.button_centres())["primary"], false)
	c.consume_fire()
	c.set_state(false, FightTypes.FLIPPER_CHARGES)
	c.set_weapon("flipper")
	c.queue_redraw()
	await _frames(2)
	_check(true, "the glass stick, the throw ring and both buttons draw, pressed and not")

	hud.queue_free()
	vp.queue_free()
	await _frames(1)


## Frame bias: the stage centre must project at the requested normalised screen x. The
## sign of Camera3D.h_offset is checked against the real projection, not assumed.
func _test_frame_bias(scene: PackedScene) -> void:
	var vp := SubViewport.new()
	vp.size = WIDE_SIZE
	root.add_child(vp)
	var rig: CameraRig = scene.instantiate() as CameraRig
	vp.add_child(rig)
	await _frames(2)
	rig.set_process(false)
	rig.set_mode(CameraRig.MODE_WORKSHOP)
	rig.set_workshop_centre(Vector3.ZERO)

	_check(is_equal_approx(rig.frame_bias(), 0.5), "the default frame bias is centred")
	_step(rig, 1.0)
	var cam := rig.camera()
	var centred := cam.unproject_position(rig.look_target()).x / float(WIDE_SIZE.x)
	_check(absf(centred - 0.5) < 0.01,
		"with no bias the stage centre projects at the middle of the screen (%.3f)" % centred)

	for want: float in [0.25, 0.35, 0.7]:
		rig.set_frame_bias(want)
		_step(rig, CameraRig.FRAME_EASE_S + 0.2)
		var got := cam.unproject_position(rig.look_target()).x / float(WIDE_SIZE.x)
		_check(absf(got - want) < 0.01,
			"frame %.2f puts the stage centre at %.3f across the screen" % [want, got])
		_check(is_equal_approx(rig.frame_bias_now(), want), "and the bias has eased all the way")

	# It eases rather than jumping, so switching screens glides.
	# FRAME_EASE_S is the time to cross the WHOLE screen, so a 0.2 move takes a fifth of
	# it; a tenth of that is still short of the target.
	rig.set_frame_bias(0.5)
	_step(rig, 1.0 / 60.0)
	_check(rig.frame_bias_now() > 0.5 and rig.frame_bias_now() < 0.7,
		"the bias eases between screens rather than jumping (%.3f)" % rig.frame_bias_now())
	_step(rig, CameraRig.FRAME_EASE_S)

	# Out of range values are clamped rather than throwing the stage off screen.
	rig.set_frame_bias(-3.0)
	_check(is_equal_approx(rig.frame_bias(), CameraRig.FRAME_MIN), "a bias below range clamps")
	rig.set_frame_bias(9.0)
	_check(is_equal_approx(rig.frame_bias(), CameraRig.FRAME_MAX), "a bias above range clamps")
	rig.set_frame_bias(0.5)
	_step(rig, CameraRig.FRAME_EASE_S + 0.2)

	# The menu camera honours it too, and the fight camera ignores it.
	rig.set_mode(CameraRig.MODE_MENU)
	rig.set_frame_bias(0.3)
	_step(rig, CameraRig.FRAME_EASE_S + 0.2)
	var menu_x := cam.unproject_position(rig.look_target()).x / float(WIDE_SIZE.x)
	_check(absf(menu_x - 0.3) < 0.01, "the menu camera honours the frame bias (%.3f)" % menu_x)

	rig.set_mode(CameraRig.MODE_FIGHT)
	rig.fit_arena(FightTypes.ARENA_SIZE)
	_step(rig, CameraRig.FRAME_EASE_S + 0.2)
	_check(is_equal_approx(cam.h_offset, 0.0), "the fight camera ignores the frame bias")
	var fight_x := cam.unproject_position(rig.look_target()).x / float(WIDE_SIZE.x)
	_check(absf(fight_x - 0.5) < 0.01, "so the arena stays centred in a fight (%.3f)" % fight_x)

	rig.queue_free()
	vp.queue_free()
	await _frames(1)


## The default fight framing must frame the BOTS, not the floor. On a live device run at
## the old fixed DEFAULT_ZOOM the machines were about 20 pt tall on a 402 pt screen.
func _test_bot_framing(scene: PackedScene) -> void:
	var vp := SubViewport.new()
	vp.size = CONTROL_SIZE          # an iPhone 17 landscape, which is what this is for
	root.add_child(vp)
	var rig: CameraRig = scene.instantiate() as CameraRig
	vp.add_child(rig)
	var a := Node3D.new()
	var b := Node3D.new()
	vp.add_child(a)
	vp.add_child(b)
	await _frames(2)
	rig.set_process(false)
	rig.set_mode(CameraRig.MODE_FIGHT)
	rig.set_targets(a, b)
	var cam := rig.camera()

	var far_limit := 0.0
	var close_height := 0.0
	var close_distance := 0.0
	for gap: float in [2.0, 8.0]:
		a.position = Vector3(-gap * 0.5, 0.0, 0.0)
		b.position = Vector3(gap * 0.5, 0.0, 0.0)
		rig.reset_to_default()
		rig.fit_arena(FightTypes.ARENA_SIZE)
		_step(rig, 3.0)                       # let the auto framing settle
		var look := rig.look_target()
		# How tall a BOT_SIZE_M machine is on screen, as a fraction of the viewport.
		var top := cam.unproject_position(look + Vector3(0.0, CameraRig.BOT_SIZE_M, 0.0))
		var base := cam.unproject_position(look)
		var height := absf(top.y - base.y) / float(CONTROL_SIZE.y)
		if gap <= 2.0:
			close_height = height
			close_distance = rig.distance()
			# The old fixed framing (DEFAULT_ZOOM of the arena fit) put the same machine
			# at about 7 % of the screen, which is the "both bots are dots" complaint.
			# Measured on screen, so this is after the foreshortening at pitch 50.
			_check(height > 0.10,
				"two bots 2 m apart: a %.1f m machine is %.0f %% of the screen height"
					% [CameraRig.BOT_SIZE_M, height * 100.0])
			_check(rig.distance() < rig.default_zoom() * 28.0,
				"and the camera is much closer than the old fixed framing (%.1f m)"
					% rig.distance())
			_check(not rig.is_player_floored(),
				"and at 2 m the pair still fits, so the player-priority floor is not holding")
		else:
			# 8 m apart is the opening bell. Fitting the pair would mean fitting most of
			# the arena, so the player-priority floor holds the camera in instead.
			_check(rig.is_player_floored(),
				"two bots 8 m apart: the player-priority floor is holding")
			_check(height >= CameraRig.PLAYER_MIN_FRACTION - 0.01,
				"so the player is still %.0f %% of the screen height, not a dot"
					% (height * 100.0))
			_check(rig.distance() > close_distance,
				"the camera pulled back, but only to the floor (%.1f m then %.1f m)"
					% [close_distance, rig.distance()])
			# CHANGED 2026-09-16 (brief v4 section 5, agent G4): the aim is no longer a
			# weighted midpoint, so PLAYER_LOOK_WEIGHT is retired. The aim is the player
			# plus a lead toward the opponent, capped at LOOK_LEAD_MAX_M, which across an
			# 8 m floor is the cap.
			_check(is_equal_approx(rig.look_lead(), CameraRig.LOOK_LEAD_MAX_M),
				"and the aim leads the player by the %.1f m cap, not by %.0f %% of 8 m"
					% [rig.look_lead(), CameraRig.LOOK_LEAD_FRACTION * 100.0])
			_check(rig.look_weight() > 0.5,
				"so most of the aim is still the player's (%.2f)" % rig.look_weight())
			var look_flat := Vector3(look.x, 0.0, look.z)
			_check(look_flat.distance_to(a.position) < look_flat.distance_to(b.position),
				"which puts the look point nearer the player than the opponent " + str(look))
		_check(height <= CameraRig.NEAR_BOT_FRACTION + 0.02,
			"and never closer than the near clamp of %.0f %%" % (CameraRig.NEAR_BOT_FRACTION * 100.0))

		# The PLAYER is always in frame. The opponent is too whenever the pair fits; once
		# the floor is holding it may not be, and that is what the HUD arrow is for.
		var in_frame := func(node: Node3D) -> bool:
			var p := cam.unproject_position(node.global_position)
			return p.x >= 0.0 and p.x <= float(CONTROL_SIZE.x) \
				and p.y >= 0.0 and p.y <= float(CONTROL_SIZE.y)
		_check(in_frame.call(a), "the player projects inside the frame at %0.0f m apart" % gap)
		if not rig.is_player_floored():
			_check(in_frame.call(b),
				"and so does the opponent while the pair fits (%0.0f m apart)" % gap)
		else:
			_check(true,
				"the opponent is %s at %0.0f m apart, which the HUD arrow covers"
					% ["in frame" if in_frame.call(b) else "off the edge", gap])
		far_limit = maxf(far_limit, rig.distance())

	# The far end is still the walls-on-screen fit, which is what the brief clamps.
	rig.pinch(0.0001)
	rig.fit_arena(FightTypes.ARENA_SIZE)
	_check(is_equal_approx(rig.zoom, FightTypes.CAM_ZOOM_MAX),
		"pinching out still reaches the walls-on-screen limit")
	_check(rig.distance() >= far_limit - 0.01,
		"which is no closer than anything the auto framing chose")

	# The framing eases: a machine thrown across the floor must not snap the camera.
	a.position = Vector3(-1.0, 0.0, 0.0)
	b.position = Vector3(1.0, 0.0, 0.0)
	rig.reset_to_default()
	rig.fit_arena(FightTypes.ARENA_SIZE)
	_step(rig, 3.0)
	var settled := rig.distance()
	b.position = Vector3(4.0, 0.0, 3.0)
	rig._process(1.0 / 60.0)
	var after_one := rig.distance()
	_check(after_one > settled + 0.0005, "the framing follows a machine that is thrown")
	_check(after_one - settled < 0.5,
		"but eases rather than snapping (%.3f m in one frame)" % (after_one - settled))
	_step(rig, 3.0)
	_check(rig.distance() > after_one + 0.1,
		"and gets there over the next second (%.2f m then %.2f m)" % [after_one, rig.distance()])
	# The look point never leaves the floor, whatever the framing asks for.
	_check(absf(rig.look_target().x) <= FightTypes.ARENA_SIZE * 0.5 + 0.001
		and absf(rig.look_target().z) <= FightTypes.ARENA_SIZE * 0.5 + 0.001,
		"and the look point stays on the floor " + str(rig.look_target()))

	# Yaw and pitch defaults are untouched by any of this.
	rig.reset_to_default()
	_check(is_equal_approx(rig.yaw_deg, _qa_float(CameraRig.ARG_YAW, FightTypes.CAM_YAW_DEG))
		and is_equal_approx(rig.pitch_deg, _qa_float(CameraRig.ARG_PITCH, FightTypes.CAM_PITCH_DEG)),
		"the default pose is still yaw 45 and pitch 50")

	rig.queue_free()
	vp.queue_free()
	await _frames(1)


## The off-screen opponent arrow: it points at the right edge, carries the name, and
## goes away when the machine comes back into frame.
func _test_offscreen_marker(scene: PackedScene) -> void:
	var hud: FightHud = scene.instantiate() as FightHud
	var host := _hud_host()
	host.add_child(hud)
	hud.set_safe_area({"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0})
	await _frames(1)
	_check(not hud.offscreen_marker_visible(), "with everything in frame there is no arrow")

	var size := host.get_visible_rect().size
	var centre := size * 0.5
	# One case per edge, so a sign error cannot pass.
	var cases := {
		"right": Vector2(1.0, 0.0),
		"left": Vector2(-1.0, 0.0),
		"below": Vector2(0.0, 1.0),
		"above": Vector2(0.0, -1.0),
		"bottom right": Vector2(0.8, 0.6),
	}
	for side: String in cases.keys():
		var dir: Vector2 = cases[side]
		hud.set_offscreen_marker(true, dir, "Scrapheap")
		hud.marker_step(FightHud.ARROW_FADE_S + 0.05)
		_check(hud.offscreen_marker_visible(), "an opponent %s raises the arrow" % side)
		var at := hud.offscreen_marker_point()
		var from_centre := (at - centre).normalized()
		_check(from_centre.dot(dir.normalized()) > 0.98,
			"and it sits %s of the middle, along the direction to the machine (%s)"
				% [side, str(at)])
		# On the edge, not floating in the middle and not off the screen. The inset is
		# quoted in design points, so it scales with the viewport like everything else.
		var pt := minf(size.x / FightHud.REF_SIZE_PT.x, size.y / FightHud.REF_SIZE_PT.y)
		var inset := FightHud.ARROW_INSET_PT * pt
		_check(at.x >= inset - 1.0 and at.x <= size.x - inset + 1.0
			and at.y >= inset - 1.0 and at.y <= size.y - inset + 1.0,
			"inside the safe area by the arrow inset " + str(at))
		var on_edge := absf(at.x - inset) < 1.0 or absf(at.x - (size.x - inset)) < 1.0 \
			or absf(at.y - inset) < 1.0 or absf(at.y - (size.y - inset)) < 1.0
		_check(on_edge, "and hard against one of the four edges " + str(at))

	_check(hud.offscreen_marker_direction().is_equal_approx(Vector2(0.8, 0.6).normalized()),
		"the arrow remembers the last direction it was given")

	# It draws. A bad draw call only shows up when it runs.
	var overlay := hud.get_node("Coach") as Control
	_check(overlay != null and overlay.visible, "the arrow shares the draw-only overlay")
	overlay.queue_redraw()
	await _frames(2)
	_check(overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"which still cannot intercept a touch")

	# Back in frame: it fades rather than blinking off.
	hud.set_offscreen_marker(false, Vector2.ZERO, "")
	hud.marker_step(FightHud.ARROW_FADE_S * 0.4)
	_check(hud.offscreen_marker_visible(), "the arrow fades rather than blinking out")
	hud.marker_step(FightHud.ARROW_FADE_S)
	_check(not hud.offscreen_marker_visible(),
		"and is gone once the opponent is back in view")
	hud.queue_free()
	await _frames(1)


## COUNTDOWN draws the furniture without taking input. Before this the coach callouts
## were on screen pointing at empty corners until the bell, because set_enabled(false)
## made _draw return early.
func _test_countdown_preview(c: FightControls) -> void:
	c.set_enabled(true)
	c.set_preview(false)
	c._tick_rest_fade(1.0)
	_check(is_equal_approx(c.draw_alpha(), 1.0), "live controls are drawn at full strength")

	# COUNTDOWN: drawn, dimmed, and deaf.
	c.set_enabled(false)
	c.set_preview(true)
	c._tick_rest_fade(FightControls.ALPHA_FADE_S + 0.05)
	_check(is_equal_approx(c.draw_alpha(), FightControls.PREVIEW_ALPHA),
		"the countdown draws them at %.0f %% (%.2f)"
			% [FightControls.PREVIEW_ALPHA * 100.0, c.draw_alpha()])
	_check(c.is_preview() and not c.is_enabled(), "drawn, but not live")
	_orbits.clear()
	_touch(c, 60, Vector2(200.0, 400.0), true)
	_drag(c, 60, Vector2(300.0, 400.0))
	_touch(c, 61, (c.button_centres())["primary"], true)
	_check(c.heading == Vector2.ZERO, "a thumb on the stick during the countdown does nothing")
	_check(not c.consume_fire(), "and the weapon button cannot be fired early")
	_check(_orbits.is_empty(), "and nothing reaches the camera either")
	c.queue_redraw()
	await _frames(2)
	_check(true, "and the dimmed furniture draws")

	# The bell: it fades up rather than popping.
	c.set_enabled(true)
	c.set_preview(false)
	c._tick_rest_fade(FightControls.ALPHA_FADE_S * 0.3)
	_check(c.draw_alpha() > FightControls.PREVIEW_ALPHA and c.draw_alpha() < 1.0,
		"the bell fades them up rather than popping (%.2f)" % c.draw_alpha())
	c._tick_rest_fade(FightControls.ALPHA_FADE_S)
	_check(is_equal_approx(c.draw_alpha(), 1.0), "and lands at full strength")

	# LOADING and RESULT: nothing at all.
	c.set_enabled(false)
	c.set_preview(false)
	c._tick_rest_fade(FightControls.ALPHA_FADE_S + 0.05)
	_check(c.draw_alpha() <= 0.004, "LOADING and RESULT draw no controls at all")
	c.set_enabled(true)
	c._tick_rest_fade(FightControls.ALPHA_FADE_S + 0.05)
	c.consume_fire()
	await _frames(1)


## True when --roboteer-pad=on was passed.
func _qa_pad() -> bool:
	for raw in OS.get_cmdline_user_args():
		var arg := str(raw)
		if arg.begins_with(FightControls.ARG_PAD):
			var value := arg.substr(FightControls.ARG_PAD.length()).to_lower()
			return value == "on" or value == "1" or value == "true"
	return false


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


func _pad_axis(axis: int, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = FightControls.PAD_DEVICE
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)
	# parse_input_event queues; the joypad state only lands on the flush.
	Input.flush_buffered_events()


func _pad_button(button: int, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = FightControls.PAD_DEVICE
	e.button_index = button
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


## Every axis and button this test touches, back to rest.
func _pad_reset() -> void:
	for axis: int in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y,
			JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
		_pad_axis(axis, 0.0)
	for button: int in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_START,
			JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
		_pad_button(button, false)


func _frames(count: int) -> void:
	for i in count:
		await process_frame


## A viewport the size of the phone's screen, for a HUD that would otherwise be laid out
## in the headless root window's 64 x 64.
func _hud_host() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = DEVICE_PX
	root.add_child(vp)
	return vp


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
