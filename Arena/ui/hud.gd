class_name FightHud extends CanvasLayer
## Fight HUD: timer, scrap counter, knockout count, height readout, countdown and
## result banner. Spec: docs/stage3-spec.md section 10.
##
## Full colour, not the GBC chrome (docs/stage2-art-direction.md): white type with a
## dark outline so it survives the pale steel floor, and gold used only for scrap so
## it stays in the same visual family as the bolts.
##
## Presentation only. Every animation is a Tween on the idle frame; nothing here is
## read back by the simulation. All children are built in code so the scene works
## whether it is instanced from hud.tscn or constructed with FightHud.new().

## Design reference, matching FightControls: an iPhone 17 landscape is 1206 x 556 pt.
const REF_SIZE_PT := Vector2(1206.0, 556.0)

const PAD_PT := 18.0
## Kept clear in the top-right corner, measured in from the safe area, for the shell's
## own pause button (44 pt, 12 pt in from both edges).
const CORNER_RESERVE_PT := 64.0
## And the scrap counter keeps this much clear of the reserve on top, because digits
## sitting flush against the button still read as touching it.
const CORNER_CLEARANCE_PT := 12.0
## TEST ARENA: the shell draws its own Back / TEST ARENA / Reset row across the top, so
## the HUD starts below it and shows no clock (the spec says there is no clock there).
const TEST_BAND_PT := 60.0
const TIMER_PT := 40.0
const SCRAP_PT := 32.0
const NAMES_PT := 18.0
const KO_PT := 34.0
## The line under a count running on the player's own machine.
const KO_PROMPT_PT := 20.0
const READOUT_PT := 22.0
const COUNTDOWN_PT := 96.0
const RESULT_TITLE_PT := 58.0
const RESULT_WINNER_PT := 26.0
## Pad hints, shown where the on screen buttons are when a controller is driving.
const HINT_PT := 16.0
## The PAUSED mark: small and out of the way, because the shell draws the real overlay.
const PAUSED_PT := 20.0

# ---------------------------------------------------------------- coach callouts
#
# How-to-play labels anchored to the real controls, for a first fight or the test
# arena. Draw only: the overlay never takes a touch, so nothing they sit on stops
# working. Each one fades the moment its input is first used, and they are all gone a
# few seconds into the fight whether or not anything was touched.

const COACH_PT := 15.0
## Seconds of FIGHTING after which every callout has gone, used or not.
const COACH_FIGHT_S := 8.0
const COACH_FADE_S := 0.35
## Gap between a callout and the control it points at.
const COACH_GAP_PT := 18.0
const COL_COACH := Color(1.0, 1.0, 1.0, 0.95)
const COL_COACH_LINE := Color(1.0, 1.0, 1.0, 0.45)
## Phases the rules layer reports, so the HUD does not have to know State.
const COACH_COUNTDOWN := "countdown"
const COACH_FIGHTING := "fighting"

## Off-screen opponent arrow. While the camera is holding the player-priority floor the
## opponent can be outside the frame; this says which way, at the screen edge, with the
## name under it. White with the same dark outline, and it fades rather than blinking.
const ARROW_PT := 15.0
const ARROW_NAME_PT := 12.0
const ARROW_INSET_PT := 26.0
const ARROW_FADE_S := 0.18

## "YOU" over the player's own machine through the countdown and the opening seconds of
## the fight, so nobody takes the opponent for their own bot (the owner did, 2026-09-16).
## A chevron pointing down at the chassis with the word above it, white, outlined.
const TAG_PT := 12.0
const TAG_TEXT := "YOU"
const TAG_FADE_S := 0.25

const COL_TEXT := Color(1.0, 1.0, 1.0)
const COL_DIM := Color(0.78, 0.83, 0.87)
const COL_OUTLINE := Color(0.03, 0.05, 0.07, 0.92)
const COL_URGENT := Color(0.93, 0.26, 0.20)
const COL_KO := Color(1.0, 0.86, 0.45)
const COL_HINT := Color(1.0, 1.0, 1.0, 0.88)

## Controller kinds whose face buttons are a cross and a circle rather than A and B.
## Matched case insensitively as a substring, so "DualSense", "DualShock 4", "PS5" and
## "PlayStation Controller" all land on the same glyphs.
const PLAYSTATION_KINDS := ["dualsense", "dualshock", "playstation", "ps3", "ps4", "ps5"]
## The real symbols, with letter fallbacks for a font that has no glyph for them.
const GLYPH_CROSS := "\u2715"
const GLYPH_CIRCLE := "\u25cb"

## FightControls adds itself to this group, so the HUD can find the button geometry
## without the rules layer having to wire the two together.
const CONTROLS_GROUP := "roboteer_fight_controls"

const ROLL_S := 0.28
const FLASH_S := 0.30
const COUNTDOWN_HOLD_S := 0.75

var _pt: float = 1.0
var _safe: Dictionary = {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
var _player_name: String = "PLAYER"
var _opponent_name: String = "OPPONENT"
var _scrap_total: int = 0
var _scrap_shown: float = 0.0
var _time_urgent: bool = false

var _root: Control
var _timer: Label
var _scrap: Label
var _names: Label
var _ko: Label
var _readout: Label
var _countdown: Label
var _result_title: Label
var _result_winner: Label
var _hint_primary: Label
var _hint_secondary: Label
var _paused_label: Label
var _ko_prompt: Label

var _paused: bool = false
## The test arena: no clock, and everything below the shell's own top row.
var _test_mode: bool = false

## Coach callouts.
var _coach_on: bool = false
var _coach_phase: String = ""
var _coach_fight_s: float = 0.0
var _coach_overlay: Control = null
## Per callout alpha, 1 fully drawn, 0 gone. Keys: drive, primary, camera.
var _coach_alpha: Dictionary = {"drive": 1.0, "primary": 1.0, "camera": 1.0}
var _coach_used: Dictionary = {"drive": false, "primary": false, "camera": false}

## Off-screen opponent marker.
var _marker_on: bool = false
var _marker_alpha: float = 0.0
var _marker_dir: Vector2 = Vector2.RIGHT
var _marker_name: String = ""
## Player tag.
var _tag_on: bool = false
var _tag_alpha: float = 0.0
var _tag_at: Vector2 = Vector2.ZERO

var _pad_hints: bool = false
var _hint_primary_text: String = "A FLIP"
var _hint_secondary_text: String = "B PIVOT"
var _glyph_primary: String = "A"
var _glyph_secondary: String = "B"
var _hint_action_primary: String = "FLIP"
var _hint_action_secondary: String = "PIVOT"
var _controller_kind: String = ""
var _controls: Node = null

var _roll_tween: Tween
var _flash_tween: Tween
var _countdown_tween: Tween
var _result_tween: Tween


func _ready() -> void:
	_build()
	if not Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.connect(_on_joy_connection_changed)
	bind_controls(_find_controls())
	_refresh_pad()
	_relayout()
	if is_inside_tree():
		var vp := get_viewport()
		if vp != null and not vp.size_changed.is_connected(_relayout):
			vp.size_changed.connect(_relayout)


# ---------------------------------------------------------------- public API

func set_safe_area(px: Dictionary) -> void:
	for key in ["left", "top", "right", "bottom"]:
		_safe[key] = float(px.get(key, 0.0))
	_relayout()


func set_bot_names(player: String, opponent: String) -> void:
	_player_name = player.to_upper()
	_opponent_name = opponent.to_upper()
	_build()
	_names.text = "%s  vs  %s" % [_player_name, _opponent_name]


## Seconds remaining in the fight. Turns red under 10 seconds.
func set_time_left(s: float) -> void:
	_build()
	var clamped := maxf(s, 0.0)
	var whole := int(ceil(clamped - 0.0001))
	_timer.text = "%d:%02d" % [whole / 60, whole % 60]
	var urgent := clamped < 10.0
	if urgent != _time_urgent:
		_time_urgent = urgent
		_timer.add_theme_color_override("font_color", COL_URGENT if urgent else COL_TEXT)


## Authoritative total. Rolls the displayed number to it.
func set_scrap(total: int) -> void:
	_build()
	_scrap_total = maxi(total, 0)
	_roll_to(_scrap_total, false)


## An award has just landed (B calls this as bolts arrive). Adds to the total and
## animates with a small overshoot plus a gold flash.
func bump(amount: int) -> void:
	_build()
	if amount == 0:
		return
	_scrap_total = maxi(_scrap_total + amount, 0)
	_roll_to(_scrap_total, true)
	_flash()


## `on_player` adds the line that says what to do about it. A count running on your own
## machine before you have driven is the one the owner lost seven fights to; it is its
## own white label because the count itself is gold and a Label carries one colour.
func show_ko_count(seconds_left: int, bot_name: String, on_player: bool = false) -> void:
	_build()
	_ko.text = "%s\nKNOCKOUT COUNT %d" % [bot_name.to_upper(), maxi(seconds_left, 0)]
	_ko.visible = true
	_ko_prompt.visible = on_player


func hide_ko_count() -> void:
	_build()
	_ko.visible = false
	_ko_prompt.visible = false


## True while the "drive to stop the count" line is up.
func ko_prompt_visible() -> bool:
	return _ko_prompt != null and _ko_prompt.visible


## R builds the sentence, for example "Your wedge: floor. Their flipper: mid."
func set_height_readout(text: String) -> void:
	_build()
	_readout.text = text


## step is "3", "2", "1" or "FIGHT".
func show_countdown(step: String) -> void:
	_build()
	_countdown.text = step
	_countdown.visible = true
	_countdown.modulate = Color(1, 1, 1, 1)
	_countdown.scale = Vector2(1.6, 1.6)
	if _countdown_tween != null and _countdown_tween.is_valid():
		_countdown_tween.kill()
	if not is_inside_tree():
		_countdown.scale = Vector2.ONE
		return
	_countdown_tween = create_tween()
	_countdown_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_countdown_tween.tween_property(_countdown, "scale", Vector2.ONE, 0.22)
	_countdown_tween.tween_interval(COUNTDOWN_HOLD_S)
	_countdown_tween.tween_property(_countdown, "modulate:a", 0.0, 0.18)
	_countdown_tween.tween_callback(func() -> void: _countdown.visible = false)


func hide_countdown() -> void:
	_build()
	if _countdown_tween != null and _countdown_tween.is_valid():
		_countdown_tween.kill()
	_countdown.visible = false


## title is "KNOCKOUT", "OUT OF THE ARENA", "JUDGES DECISION" or "CORE DESTROYED".
func show_result(title: String, winner_name: String) -> void:
	_build()
	hide_ko_count()
	_result_title.text = title.to_upper()
	_result_winner.text = "WINNER: " + winner_name.to_upper()
	_result_title.visible = true
	_result_winner.visible = true
	_result_title.modulate = Color(1, 1, 1, 0)
	_result_winner.modulate = Color(1, 1, 1, 0)
	_result_title.scale = Vector2(1.25, 1.25)
	if not is_inside_tree():
		_result_title.modulate = Color(1, 1, 1, 1)
		_result_winner.modulate = Color(1, 1, 1, 1)
		_result_title.scale = Vector2.ONE
		return
	if _result_tween != null and _result_tween.is_valid():
		_result_tween.kill()
	_result_tween = create_tween()
	_result_tween.set_parallel(true)
	_result_tween.tween_property(_result_title, "modulate:a", 1.0, 0.25)
	_result_tween.tween_property(_result_title, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_result_tween.tween_property(_result_winner, "modulate:a", 1.0, 0.25).set_delay(0.15)


func hide_result() -> void:
	_build()
	_result_title.visible = false
	_result_winner.visible = false


## Subscribe to a FightControls node for its pad state, its button geometry and its
## secondary label. Called automatically from _ready via the controls group; pass one
## explicitly only if the group lookup cannot work.
func bind_controls(c: Node) -> void:
	if c == null or c == _controls:
		return
	_controls = c
	# pad_ACTIVE, not pad_present: a controller that is merely connected must not take
	# the touch furniture away, or a phantom 'MFi Gamepad' leaves the player with a
	# blank screen and no idea what the controls are.
	if c.has_signal("pad_active_changed") \
			and not c.is_connected("pad_active_changed", _on_pad_active_changed):
		c.connect("pad_active_changed", _on_pad_active_changed)
	if c.has_signal("pad_present_changed") \
			and not c.is_connected("pad_present_changed", _on_pad_present_changed):
		c.connect("pad_present_changed", _on_pad_present_changed)
	if c.has_signal("secondary_label_changed") \
			and not c.is_connected("secondary_label_changed", _on_secondary_label_changed):
		c.connect("secondary_label_changed", _on_secondary_label_changed)
	if c.has_signal("primary_label_changed") \
			and not c.is_connected("primary_label_changed", _on_primary_label_changed):
		c.connect("primary_label_changed", _on_primary_label_changed)
	if c.has_method("secondary_label"):
		_on_secondary_label_changed(str(c.call("secondary_label")))
	if c.has_method("primary_label"):
		_on_primary_label_changed(str(c.call("primary_label")))
	_refresh_pad()


## Show the controller glyph hints instead of the on screen stick and buttons.
func set_pad_hints(on: bool) -> void:
	_build()
	if on == _pad_hints:
		return
	_pad_hints = on
	_hint_primary.visible = on
	_hint_secondary.visible = on
	if on:
		_relayout()


func pad_hints_visible() -> bool:
	return _pad_hints


## The Swift shell's `settings` message (via the rules layer): whether a controller is
## connected and what kind it is, so the glyphs match the pad in the player's hands.
## A PlayStation kind gets a cross and a circle, anything else gets A and B.
func set_controller_hints(connected: bool, kind: String) -> void:
	_build()
	_controller_kind = kind
	var lower := kind.to_lower()
	var playstation := false
	for name: String in PLAYSTATION_KINDS:
		if lower.contains(name):
			playstation = true
			break
	if playstation:
		_glyph_primary = _glyph_or(GLYPH_CROSS, "X")
		_glyph_secondary = _glyph_or(GLYPH_CIRCLE, "O")
	else:
		_glyph_primary = "A"
		_glyph_secondary = "B"
	_compose_hints()
	# `connected` picks the glyphs; it does NOT decide whether they are shown. Only a pad
	# that has actually been used takes the touch furniture away (FightControls.
	# pad_active), because the shell reports a phantom 'MFi Gamepad' on the simulator and
	# possibly a stale pairing on a phone.
	if not connected:
		set_pad_hints(false)
	else:
		_refresh_pad()


## The controller kind the shell last reported.
func controller_kind() -> String:
	return _controller_kind


## Uses the symbol when the HUD font actually carries a glyph for it, and the letter
## otherwise, because a missing glyph draws as a blank box and reads as a bug.
func _glyph_or(symbol: String, fallback: String) -> String:
	if symbol.is_empty():
		return fallback
	var font := _hint_primary.get_theme_default_font() if _hint_primary != null else null
	if font == null:
		return fallback
	return symbol if font.has_char(symbol.unicode_at(0)) else fallback


func _compose_hints() -> void:
	_hint_primary_text = "%s %s" % [_glyph_primary, _hint_action_primary]
	_hint_secondary_text = "%s %s" % [_glyph_secondary, _hint_action_secondary]
	if _hint_primary != null:
		_hint_primary.text = _hint_primary_text
	if _hint_secondary != null:
		_hint_secondary.text = _hint_secondary_text


## Override the glyph text, for a pad whose face buttons are not labelled A and B.
func set_pad_hint_labels(primary: String, secondary: String) -> void:
	_build()
	_hint_primary_text = primary
	_hint_secondary_text = secondary
	_hint_primary.text = primary
	_hint_secondary.text = secondary


# ---------------------------------------------------------------- pause and coach

## The simulation clock has stopped. The shell draws the real pause overlay; this is
## only the mark that says the arena knows.
func set_paused(on: bool) -> void:
	_build()
	if on == _paused:
		return
	_paused = on
	_paused_label.visible = on


func is_paused() -> bool:
	return _paused


## The test arena has no clock (docs/stage3-spec.md section 6) and the shell owns the top
## TEST_BAND_PT of the screen for its own Back / TEST ARENA / Reset row, so the names and
## the scrap counter move below it.
func set_test_mode(on: bool) -> void:
	_build()
	if on == _test_mode:
		return
	_test_mode = on
	_relayout()


func is_test_mode() -> bool:
	return _test_mode


## Turn the how-to-play callouts on for this fight. The rules layer passes
## `fight_config.coach`, or true in the test arena.
func set_coach(on: bool) -> void:
	_build()
	_coach_on = on
	_coach_phase = ""
	_coach_fight_s = 0.0
	for key in _coach_alpha.keys():
		_coach_alpha[key] = 1.0
		_coach_used[key] = false
	if _coach_overlay != null:
		_coach_overlay.visible = on
		_coach_overlay.queue_redraw()


func coach_enabled() -> bool:
	return _coach_on


## "countdown", "fighting" or anything else (which hides them). The fight's own clock,
## not the frame clock, is what ages the callouts out.
func set_coach_phase(phase: String) -> void:
	var want := phase.strip_edges().to_lower()
	if want == _coach_phase:
		return
	_coach_phase = want
	_coach_dirty()


## Alpha of one callout: "drive", "primary" or "camera". For the headless test.
func coach_alpha(key: String) -> float:
	return float(_coach_alpha.get(key, 0.0))


## True while any callout is still drawn.
func coach_visible() -> bool:
	if not _coach_on:
		return false
	for key in _coach_alpha.keys():
		if float(_coach_alpha[key]) > 0.004:
			return true
	return false


## Seconds of FIGHTING the callouts have aged through.
func coach_fight_seconds() -> float:
	return _coach_fight_s


## Drive the callout clock by hand, for the headless test and for any caller that wants
## the timeline without waiting on real frames.
func coach_step(delta: float) -> void:
	_coach_step(delta)


func _process(delta: float) -> void:
	_marker_step(delta)
	_tag_step(delta)
	if not _coach_on:
		return
	_coach_step(delta)


# ---------------------------------------------------------------- off-screen opponent

## The opponent is outside the frame (the camera is holding the player-priority floor):
## point at it. `direction` is a unit vector in screen space, +x right, +y down, from the
## middle of the screen toward the machine. The rules layer works it out from the fight
## camera and calls this every presentation frame.
func set_offscreen_marker(on: bool, direction: Vector2, label: String) -> void:
	_build()
	_marker_on = on
	if direction.length_squared() > 0.0001:
		_marker_dir = direction.normalized()
	if not label.is_empty():
		_marker_name = label.to_upper()
	if on and _coach_overlay != null:
		_coach_overlay.visible = true


## True while the arrow is drawn at all.
func offscreen_marker_visible() -> bool:
	return _marker_alpha > 0.004


func offscreen_marker_direction() -> Vector2:
	return _marker_dir


## Where the arrow sits, in viewport pixels: the point where the ray from the middle of
## the screen along `_marker_dir` meets the inset edge of the safe area.
func offscreen_marker_point() -> Vector2:
	var size := _viewport_size()
	var inset := ARROW_INSET_PT * _pt
	var left := float(_safe["left"]) + inset
	var top := float(_safe["top"]) + inset
	var right := size.x - float(_safe["right"]) - inset
	var bottom := size.y - float(_safe["bottom"]) - inset
	var centre := Vector2((left + right) * 0.5, (top + bottom) * 0.5)
	var half := Vector2(maxf((right - left) * 0.5, 1.0), maxf((bottom - top) * 0.5, 1.0))
	var d := _marker_dir
	if d.length_squared() < 0.0001:
		d = Vector2.RIGHT
	d = d.normalized()
	var t := minf(half.x / maxf(absf(d.x), 0.0001), half.y / maxf(absf(d.y), 0.0001))
	return centre + d * t


func _marker_step(delta: float) -> void:
	var target := 1.0 if _marker_on else 0.0
	if is_equal_approx(_marker_alpha, target):
		return
	_marker_alpha = move_toward(_marker_alpha, target, delta / maxf(ARROW_FADE_S, 0.001))
	if _coach_overlay != null and is_instance_valid(_coach_overlay):
		_coach_overlay.visible = _coach_on or _marker_alpha > 0.004 or _tag_alpha > 0.004
		_coach_overlay.queue_redraw()


## Show or move the "YOU" tag. `at` is the screen point of the top of the player's chassis,
## in the same viewport space the off-screen arrow uses.
func set_player_tag(on: bool, at: Vector2) -> void:
	_build()
	var moved := on and _tag_at.distance_squared_to(at) > 0.25
	_tag_on = on
	if on:
		_tag_at = at
	if moved and _coach_overlay != null and is_instance_valid(_coach_overlay):
		_coach_overlay.queue_redraw()


## True while the tag is still drawn. For the headless test.
func player_tag_visible() -> bool:
	return _tag_alpha > 0.004


func player_tag_point() -> Vector2:
	return _tag_at


func _tag_step(delta: float) -> void:
	var target := 1.0 if _tag_on else 0.0
	if is_equal_approx(_tag_alpha, target):
		return
	_tag_alpha = move_toward(_tag_alpha, target, delta / maxf(TAG_FADE_S, 0.001))
	if _coach_overlay != null and is_instance_valid(_coach_overlay):
		_coach_overlay.visible = _coach_on or _marker_alpha > 0.004 or _tag_alpha > 0.004
		_coach_overlay.queue_redraw()


## Drive the arrow's fade by hand, for the headless test.
func marker_step(delta: float) -> void:
	_marker_step(delta)


func _viewport_size() -> Vector2:
	if is_inside_tree():
		var vp := get_viewport()
		if vp != null:
			var r := vp.get_visible_rect().size
			if r.x > 1.0 and r.y > 1.0:
				return r
	return REF_SIZE_PT


func _coach_step(delta: float) -> void:
	if _controls == null or not is_instance_valid(_controls):
		_controls = _find_controls()
	if _controls != null and _controls.has_method("input_usage"):
		var usage: Dictionary = _controls.call("input_usage")
		for key in _coach_used.keys():
			if bool(usage.get(key, false)):
				_coach_used[key] = true
	if _coach_phase == COACH_FIGHTING and not _paused:
		_coach_fight_s += delta

	# The whole set is gone outside the countdown and the opening of the fight, and
	# whenever a pad is driving, because then none of these controls are on screen.
	var showing := not _pad_hints \
		and (_coach_phase == COACH_COUNTDOWN
			or (_coach_phase == COACH_FIGHTING and _coach_fight_s < COACH_FIGHT_S))
	var step := delta / maxf(COACH_FADE_S, 0.001)
	var changed := false
	for key in _coach_alpha.keys():
		var target := 0.0 if (bool(_coach_used[key]) or not showing) else 1.0
		var was := float(_coach_alpha[key])
		if is_equal_approx(was, target):
			continue
		_coach_alpha[key] = move_toward(was, target, step)
		changed = true
	if changed:
		_coach_dirty()


func _coach_dirty() -> void:
	if _coach_overlay != null and is_instance_valid(_coach_overlay):
		_coach_overlay.queue_redraw()


## Draws the callouts on the overlay, anchored to where FightControls really put its
## furniture. White type with a dark outline and a thin leader line, nothing warm: the
## bolts are the only warm colour in this arena.
func _draw_coach(on: Control) -> void:
	_draw_offscreen_marker(on)
	_draw_player_tag(on)
	if not _coach_on or _controls == null or not is_instance_valid(_controls):
		return
	if not _controls.has_method("button_centres"):
		return
	var geometry: Dictionary = _controls.call("button_centres")
	var pt := float(geometry.get("pt", _pt))
	var view: Vector2 = geometry.get("size", on.size)
	var gap := COACH_GAP_PT * pt
	var font_px := int(round(COACH_PT * pt))

	var drive_alpha := float(_coach_alpha.get("drive", 0.0))
	if drive_alpha > 0.004:
		var home: Vector2 = geometry.get("stick_home", Vector2.ZERO)
		var radius := float(geometry.get("stick_radius", 0.0))
		var at := home + Vector2(radius + gap, -radius * 0.55)
		_coach_text(on, "DRIVE  slide your thumb here", at, font_px, drive_alpha,
			HORIZONTAL_ALIGNMENT_LEFT)
		_coach_leader(on, at + Vector2(-gap * 0.4, 0.0), home, radius, drive_alpha, pt)

	var primary_alpha := float(_coach_alpha.get("primary", 0.0))
	if primary_alpha > 0.004:
		var centre: Vector2 = geometry.get("primary", Vector2.ZERO)
		var radius := float(geometry.get("primary_radius", 0.0))
		var verb := "hold"
		if _controls.has_method("primary_is_hold") and not bool(_controls.call("primary_is_hold")):
			verb = "tap"
		var at := centre + Vector2(-radius - gap, 0.0)
		_coach_text(on, "%s  %s" % [_hint_action_primary, verb], at, font_px, primary_alpha,
			HORIZONTAL_ALIGNMENT_RIGHT)
		_coach_leader(on, at + Vector2(gap * 0.4, 0.0), centre, radius, primary_alpha, pt)

	var camera_alpha := float(_coach_alpha.get("camera", 0.0))
	if camera_alpha > 0.004:
		# The free right middle band: outside the stick zone, above the two buttons.
		var at := Vector2(view.x * 0.72, view.y * 0.40)
		_coach_text(on, "CAMERA  drag to look, pinch to zoom", at, font_px, camera_alpha,
			HORIZONTAL_ALIGNMENT_CENTER)


## A small arrow at the screen edge pointing at an opponent that is off the frame, with
## its name under it. White, outlined, nothing warm.
func _draw_offscreen_marker(on: Control) -> void:
	if _marker_alpha <= 0.004:
		return
	var font := on.get_theme_default_font()
	var at := offscreen_marker_point()
	var d := _marker_dir.normalized()
	var r := ARROW_PT * _pt
	var side := Vector2(-d.y, d.x)
	var tip := at + d * r
	var points := PackedVector2Array([tip, at - d * r * 0.5 + side * r * 0.7,
		at - d * r * 0.5 - side * r * 0.7])
	on.draw_colored_polygon(points, Color(COL_TEXT, _marker_alpha))
	# Outlined by tracing the same triangle, so it survives a pale floor behind it.
	var outline := PackedVector2Array(points)
	outline.append(points[0])
	on.draw_polyline(outline, Color(COL_OUTLINE, COL_OUTLINE.a * _marker_alpha),
		maxf(2.0 * _pt, 1.0), true)
	if font == null or _marker_name.is_empty():
		return
	var px := int(round(ARROW_NAME_PT * _pt))
	var w := font.get_string_size(_marker_name, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x
	# The name is pushed back INSIDE the frame from the arrow, never off the edge.
	var origin := at - d * (r + 6.0 * _pt) + Vector2(-w * 0.5, px * 0.35)
	on.draw_string_outline(font, origin, _marker_name, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px,
		maxi(int(round(px * 0.25)), 2), Color(COL_OUTLINE, COL_OUTLINE.a * _marker_alpha))
	on.draw_string(font, origin, _marker_name, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px,
		Color(COL_TEXT, _marker_alpha))


## A small chevron pointing down at the player's machine with YOU above it.
func _draw_player_tag(on: Control) -> void:
	if _tag_alpha <= 0.004:
		return
	var r := TAG_PT * _pt
	var tip := _tag_at
	var points := PackedVector2Array([tip, tip + Vector2(-r * 0.6, -r), tip + Vector2(r * 0.6, -r)])
	on.draw_colored_polygon(points, Color(COL_TEXT, _tag_alpha))
	var outline := PackedVector2Array(points)
	outline.append(points[0])
	on.draw_polyline(outline, Color(COL_OUTLINE, COL_OUTLINE.a * _tag_alpha),
		maxf(2.0 * _pt, 1.0), true)
	var font := on.get_theme_default_font()
	if font == null:
		return
	var px := int(round(TAG_PT * _pt))
	var w := font.get_string_size(TAG_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x
	var origin := tip + Vector2(-w * 0.5, -r - 5.0 * _pt)
	on.draw_string_outline(font, origin, TAG_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px,
		maxi(int(round(px * 0.25)), 2), Color(COL_OUTLINE, COL_OUTLINE.a * _tag_alpha))
	on.draw_string(font, origin, TAG_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px,
		Color(COL_TEXT, _tag_alpha))


## One callout. `at` is the anchor; align says which end of the line sits on it.
func _coach_text(on: Control, text: String, at: Vector2, font_px: int, alpha: float,
		align: int) -> void:
	var font := on.get_theme_default_font()
	if font == null:
		return
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_px).x
	var origin := at + Vector2(0.0, font_px * 0.35)
	match align:
		HORIZONTAL_ALIGNMENT_RIGHT:
			origin.x -= w
		HORIZONTAL_ALIGNMENT_CENTER:
			origin.x -= w * 0.5
		_:
			pass
	on.draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_px,
		maxi(int(round(font_px * 0.22)), 2), Color(COL_OUTLINE, COL_OUTLINE.a * alpha))
	on.draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_px,
		Color(COL_COACH, COL_COACH.a * alpha))


## A hairline from the callout to the rim of the control it names.
func _coach_leader(on: Control, from: Vector2, centre: Vector2, radius: float, alpha: float,
		pt: float) -> void:
	var to_centre := centre - from
	if to_centre.length() <= radius + 1.0:
		return
	var end := centre - to_centre.normalized() * radius
	on.draw_line(from, end, Color(COL_COACH_LINE, COL_COACH_LINE.a * alpha),
		maxf(1.5 * pt, 1.0), true)


## Authoritative scrap total behind the rolling number.
func scrap_total() -> int:
	return _scrap_total


## Displayed scrap, rounded. Exposed for the headless test.
func scrap_displayed() -> int:
	return int(round(_scrap_shown))


# ---------------------------------------------------------------- internals

func _roll_to(target: int, overshoot: bool) -> void:
	if _roll_tween != null and _roll_tween.is_valid():
		_roll_tween.kill()
	if not is_inside_tree():
		_set_scrap_display(float(target))
		return
	_roll_tween = create_tween()
	if overshoot:
		_roll_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_roll_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_roll_tween.tween_method(_set_scrap_display, _scrap_shown, float(target), ROLL_S)


func _set_scrap_display(value: float) -> void:
	_scrap_shown = value
	if _scrap != null:
		_scrap.text = "SCRAP %d" % int(round(maxf(value, 0.0)))


func _flash() -> void:
	if not is_inside_tree() or _scrap == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_scrap.pivot_offset = Vector2(_scrap.size.x, _scrap.size.y * 0.5)
	_scrap.modulate = Color(1.7, 1.55, 1.1)
	_scrap.scale = Vector2(1.12, 1.12)
	_flash_tween = create_tween()
	_flash_tween.set_parallel(true)
	_flash_tween.tween_property(_scrap, "modulate", Color(1, 1, 1), FLASH_S)
	_flash_tween.tween_property(_scrap, "scale", Vector2.ONE, FLASH_S) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _build() -> void:
	if _root != null:
		return
	_root = get_node_or_null("Root") as Control
	if _root == null:
		_root = Control.new()
		_root.name = "Root"
		add_child(_root)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_names = _label("Names", NAMES_PT, COL_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	_timer = _label("Timer", TIMER_PT, COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_scrap = _label("Scrap", SCRAP_PT, FightTypes.BOLT_GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	_ko = _label("KoCount", KO_PT, COL_KO, HORIZONTAL_ALIGNMENT_CENTER)
	_readout = _label("Readout", READOUT_PT, COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_countdown = _label("Countdown", COUNTDOWN_PT, COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_result_title = _label("ResultTitle", RESULT_TITLE_PT, COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_result_winner = _label("ResultWinner", RESULT_WINNER_PT, COL_KO, HORIZONTAL_ALIGNMENT_CENTER)
	_hint_primary = _label("HintPrimary", HINT_PT, COL_HINT, HORIZONTAL_ALIGNMENT_CENTER)
	_hint_secondary = _label("HintSecondary", HINT_PT, COL_HINT, HORIZONTAL_ALIGNMENT_CENTER)
	_ko_prompt = _label("KoPrompt", KO_PROMPT_PT, COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_ko_prompt.text = "DRIVE TO STOP THE COUNT"
	_ko_prompt.visible = false
	_paused_label = _label("Paused", PAUSED_PT, COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_paused_label.text = "PAUSED"
	_paused_label.visible = _paused

	# Drawn above every label, and never able to take a touch.
	_coach_overlay = get_node_or_null("Coach") as Control
	if _coach_overlay == null:
		var overlay := CoachOverlay.new()
		overlay.name = "Coach"
		overlay.hud = self
		add_child(overlay)
		_coach_overlay = overlay
	_coach_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coach_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_coach_overlay.visible = _coach_on or _marker_alpha > 0.004 or _tag_alpha > 0.004
	set_process(true)

	_names.text = "%s  vs  %s" % [_player_name, _opponent_name]
	_timer.text = "1:30"
	_scrap.text = "SCRAP 0"
	_readout.text = ""
	_hint_primary.text = _hint_primary_text
	_hint_secondary.text = _hint_secondary_text
	_hint_primary.visible = _pad_hints
	_hint_secondary.visible = _pad_hints
	_ko.visible = false
	_countdown.visible = false
	_result_title.visible = false
	_result_winner.visible = false


func _label(node_name: String, size_pt: float, colour: Color, align: int) -> Label:
	var existing := _root.get_node_or_null(node_name) as Label
	var l := existing
	if l == null:
		l = Label.new()
		l.name = node_name
		_root.add_child(l)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.set_meta("size_pt", size_pt)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_outline_color", COL_OUTLINE)
	return l


func _relayout() -> void:
	_build()
	var s := REF_SIZE_PT
	if is_inside_tree():
		var vp := get_viewport()
		if vp != null:
			var r := vp.get_visible_rect().size
			if r.x > 1.0 and r.y > 1.0:
				s = r
	_pt = minf(s.x / REF_SIZE_PT.x, s.y / REF_SIZE_PT.y)
	if _pt <= 0.0:
		_pt = 1.0

	for l: Label in [_names, _timer, _scrap, _ko, _readout, _countdown, _result_title,
			_result_winner, _hint_primary, _hint_secondary, _paused_label, _ko_prompt]:
		var px := int(round(float(l.get_meta("size_pt", 20.0)) * _pt))
		l.add_theme_font_size_override("font_size", px)
		l.add_theme_constant_override("outline_size", maxi(int(round(px * 0.14)), 2))

	var pad := PAD_PT * _pt
	var left := float(_safe["left"]) + pad
	var right := float(_safe["right"]) + pad
	var top := float(_safe["top"]) + pad
	var bottom := float(_safe["bottom"]) + pad

	var timer_h := TIMER_PT * 1.3 * _pt
	# In the test arena the shell owns the top band and there is no clock at all.
	var band_top := top + (TEST_BAND_PT * _pt if _test_mode else 0.0)
	_timer.visible = not _test_mode
	_band(_names, band_top, timer_h, left, right)
	_band(_timer, top, timer_h, left, right)
	# The shell draws a 44 pt round pause button in the top-right corner, 12 pt in from
	# both edges. Nothing of the HUD's may go under it: on the live build the gold scrap
	# counter sat exactly there and read "SCRA". CORNER_RESERVE_PT is measured from the
	# safe area, so it holds at any inset.
	_band(_scrap, band_top, timer_h, left,
		float(_safe["right"]) + (CORNER_RESERVE_PT + CORNER_CLEARANCE_PT) * _pt)
	# Just under the clock, so the mark reads with the timer it has stopped.
	_band(_paused_label, band_top + timer_h, PAUSED_PT * 1.4 * _pt, left, right)

	var readout_h := READOUT_PT * 1.6 * _pt
	_band(_readout, s.y - bottom - readout_h, readout_h, left, right)

	# Centre furniture. The knockout count sits a little above the middle so it does
	# not land on top of the two bots at the default framing.
	var ko_h := KO_PT * 3.0 * _pt
	var ko_top := s.y * 0.5 - ko_h * 0.5 - 40.0 * _pt
	_band(_ko, ko_top, ko_h, left, right)
	_band(_ko_prompt, ko_top + ko_h, KO_PROMPT_PT * 1.6 * _pt, left, right)
	var cd_h := COUNTDOWN_PT * 1.4 * _pt
	_band(_countdown, s.y * 0.5 - cd_h * 0.5, cd_h, left, right)
	_countdown.pivot_offset = Vector2(_countdown.size.x * 0.5, _countdown.size.y * 0.5)
	var rt_h := RESULT_TITLE_PT * 1.4 * _pt
	_band(_result_title, s.y * 0.5 - rt_h, rt_h, left, right)
	_result_title.pivot_offset = Vector2(_result_title.size.x * 0.5, _result_title.size.y * 0.5)
	var rw_h := RESULT_WINNER_PT * 1.6 * _pt
	_band(_result_winner, s.y * 0.5 + 6.0 * _pt, rw_h, left, right)
	_scrap.pivot_offset = Vector2(_scrap.size.x, _scrap.size.y * 0.5)

	# Pad hints sit exactly where the buttons they replace would be.
	var centres := _button_centres(s)
	var hint_h := HINT_PT * 2.0 * _pt
	var hint_w := 200.0 * _pt
	_place_centred(_hint_primary, centres["primary"], hint_w, hint_h)
	_place_centred(_hint_secondary, centres["secondary"], hint_w, hint_h)


## The rectangle in the top-right corner, inside the safe area, that the HUD keeps empty
## for the shell's pause button. Viewport pixels.
func reserved_corner() -> Rect2:
	var s := REF_SIZE_PT
	if is_inside_tree():
		var vp := get_viewport()
		if vp != null:
			var r := vp.get_visible_rect().size
			if r.x > 1.0 and r.y > 1.0:
				s = r
	var side := CORNER_RESERVE_PT * _pt
	return Rect2(Vector2(s.x - float(_safe["right"]) - side, float(_safe["top"])),
		Vector2(side, side))


## Where FightControls draws its two right thumb buttons. Asks the controls node when
## there is one, and otherwise recomputes it from the same constants and safe area.
func _button_centres(s: Vector2) -> Dictionary:
	if _controls == null or not is_instance_valid(_controls):
		_controls = _find_controls()
	if _controls != null and _controls.has_method("button_centres"):
		var from_controls: Dictionary = _controls.call("button_centres")
		if from_controls.has("primary") and from_controls.has("secondary"):
			return from_controls
	var half_primary := FightControls.PRIMARY_DIAMETER_PT * 0.5 * _pt
	var primary := Vector2(
		s.x - float(_safe["right"]) - FightControls.EDGE_MARGIN_PT * _pt - half_primary,
		s.y - float(_safe["bottom"]) - FightControls.EDGE_MARGIN_PT * _pt - half_primary)
	return {
		"primary": primary,
		"secondary": primary + FightControls.SECONDARY_OFFSET_PT * _pt,
	}


func _find_controls() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(CONTROLS_GROUP)


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	_refresh_pad()


func _on_pad_present_changed(_present: bool) -> void:
	# Connecting or unplugging a pad on its own changes nothing on screen; only using
	# one does. Unplugging clears pad_active too, which arrives on the other signal.
	_refresh_pad()


func _on_pad_active_changed(active: bool) -> void:
	set_pad_hints(active)


func _on_secondary_label_changed(label: String) -> void:
	_build()
	_hint_action_secondary = label.to_upper()
	_compose_hints()


## The primary button now names the fitted weapon (FLIP, SPIN, SWING and the rest), so
## the glyph hint says the same word.
func _on_primary_label_changed(label: String) -> void:
	_build()
	var upper := label.strip_edges().to_upper()
	if upper.is_empty() or upper == _hint_action_primary:
		return
	_hint_action_primary = upper
	_compose_hints()
	_coach_dirty()


func _refresh_pad() -> void:
	if _controls == null or not is_instance_valid(_controls):
		_controls = _find_controls()
	var active := false
	if _controls != null and _controls.has_method("pad_active"):
		active = bool(_controls.call("pad_active"))
	set_pad_hints(active)


## Centres a label on a point, for furniture that is not a full width band.
func _place_centred(l: Label, centre: Vector2, width: float, height: float) -> void:
	l.set_anchors_preset(Control.PRESET_TOP_LEFT, false)
	l.anchor_left = 0.0
	l.anchor_right = 0.0
	l.anchor_top = 0.0
	l.anchor_bottom = 0.0
	l.offset_left = centre.x - width * 0.5
	l.offset_right = centre.x + width * 0.5
	l.offset_top = centre.y - height * 0.5
	l.offset_bottom = centre.y + height * 0.5


## Places a label as a full width band inside the safe area at a given top and height.
func _band(l: Label, top: float, height: float, left: float, right: float) -> void:
	l.set_anchors_preset(Control.PRESET_TOP_WIDE, false)
	l.anchor_left = 0.0
	l.anchor_right = 1.0
	l.anchor_top = 0.0
	l.anchor_bottom = 0.0
	l.offset_left = left
	l.offset_right = -right
	l.offset_top = top
	l.offset_bottom = top + height


## The coach callouts' canvas. A Control only because _draw needs one; it is
## MOUSE_FILTER_IGNORE and sits on a CanvasLayer that never handles input, so it can
## never come between a thumb and the controls underneath it.
class CoachOverlay extends Control:
	var hud: FightHud = null

	func _draw() -> void:
		if hud != null and is_instance_valid(hud):
			hud._draw_coach(self)
