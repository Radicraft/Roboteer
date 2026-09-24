class_name FightControls extends Control
## Fight touch routing: a VISIBLE floating left stick, two right thumb buttons, camera
## gestures. Spec: docs/stage3-spec.md sections 10 and 14, brief-v3.md section 11.
##
## Three things changed after the owner played the first build and said "no idea what
## the controls are ... no idea how to move the camera": the stick is drawn at rest so
## there is something to aim a thumb at, the primary button names the FITTED weapon
## rather than always saying FLIP, and a connected pad no longer hides the touch
## furniture until that pad has actually been used (`pad_active()`).
##
## Presentation node only. The rules layer samples `heading`, `consume_fire()` and
## `secondary` once per physics tick and never the other way round. Nothing here
## touches the simulation.
##
## Coordinates: every touch position is in this Control's local space, which with the
## project's canvas_items stretch is the design viewport. `heading` is screen space,
## +x right, +y down, length 0 to 1; the rules layer maps it into the world.
##
## Three input devices feed the same three outputs and all of them are live at once:
## touch, a physical game controller (Godot wraps iOS GCController in the joypad API)
## and, on desktop only, the keyboard. A deflected pad stick wins the tick; otherwise
## a live touch stick wins; otherwise the keyboard.

signal camera_pinch(factor: float)
signal camera_orbit(delta: Vector2)
## START on the pad. The shell decides what a pause means; this node only reports it.
signal pause_requested()
## A pad was plugged in or unplugged. The HUD swaps its glyph hints on this.
signal pad_present_changed(present: bool)
## A connected pad has actually been USED (or has stopped being the live device because
## a thumb went back on the glass). This, not pad_present_changed, is what hides the
## touch furniture and shows the glyph hints. See `pad_active()`.
signal pad_active_changed(active: bool)
## The secondary button changed its label, so the pad hint can follow it.
signal secondary_label_changed(label: String)
## The primary button changed its label because the fitted weapon changed.
signal primary_label_changed(label: String)

## Design reference: an iPhone 17 in landscape is 1206 x 556 points. Everything below
## is quoted in those points and multiplied by `_pt`, so the layout holds at any viewport
## size. This is a RATIO, not a base canvas: `window/stretch/mode` is "disabled" (wave P,
## agent H), so `get_visible_rect()` is the device pixel rect and an iPhone 17 gives
## `_pt` = 2.1692 rather than the stretched canvas's 2.0. The geometry constants are
## unchanged and every control comes out at the same physical size; the difference is that
## the fight behind them is drawn at the phone's own resolution instead of 85 % of it.
const REF_SIZE_PT := Vector2(1206.0, 556.0)

const STICK_ZONE_FRACTION := 0.45
const STICK_BASE_PT := 60.0
const STICK_KNOB_PT := 28.0
const STICK_THROW_PT := 60.0
const PRIMARY_DIAMETER_PT := 92.0
const SECONDARY_DIAMETER_PT := 68.0
const EDGE_MARGIN_PT := 24.0
## Where the RESTING stick sits: this far in from the left and bottom edges of the safe
## area. Comfortably outside EDGE_MARGIN_PT, so the base (radius STICK_BASE_PT) is drawn
## whole. The stick still floats: a touch anywhere in the zone becomes its origin, and
## this is only where it waits and where it returns to.
const STICK_HOME_INSET_PT := 70.0
## Resting base fade, in and out, when a stick touch starts or ends. Short, because a
## long one reads as lag; no snapping either way.
const STICK_REST_FADE_S := 0.12
## The resting stick pulses while a knockout count is running on the player and the
## player has not driven. Gentle: this is a nudge, not an alarm.
const DRIVE_PULSE_PERIOD_S := 1.1
const DRIVE_PULSE_RING_PT := 14.0
## COUNTDOWN: the furniture is DRAWN but takes no input, so the coach callouts point at
## something rather than at empty corners until the bell. It fades up to full when the
## fight starts. LOADING and RESULT draw nothing at all.
const PREVIEW_ALPHA := 0.6
const ALPHA_FADE_S := 0.25
## Secondary sits above and to the left of the primary centre, thumb sweep distance.
const SECONDARY_OFFSET_PT := Vector2(-92.0, -78.0)
## Fingers are bigger than the drawn art, so hit tests get a little slop.
const HIT_SLOP := 1.15

## Desktop QA rates (spec section 14). Only read when OS.has_feature("pc").
const KEY_ORBIT_PX_PER_S := 700.0
const KEY_TILT_PX_PER_S := 500.0
const KEY_ZOOM_PER_S := 1.5
## InputEventPanGesture delta is in scroll units, not pixels.
const PAN_GESTURE_TO_PX := 26.0

## The HUD finds this node by group so neither has to be wired by the rules layer.
const GROUP := "roboteer_fight_controls"

## Game controller. Joypad 0 only: this is a one player game and a second pad on the
## phone is far more likely to be a stray Bluetooth device than a second driver.
const PAD_DEVICE := 0
## Circular, and the remaining travel is rescaled to 0..1 so the stick still reaches
## full throttle. Sticks on a worn pad rest as far out as 0.12.
const PAD_DEADZONE := 0.18
const PAD_TRIGGER_THRESHOLD := 0.5
## Right stick to camera. Quoted in viewport pixels per second so it goes through the
## same orbit() and pinch() the touch gestures use, with the same clamps and ease back.
const PAD_ORBIT_PX_PER_S := 900.0
const PAD_TILT_PX_PER_S := 600.0
const PAD_ZOOM_PER_S := 1.5

## Control schemes, brief-v3.md section 11. Arcade is the default and the only one
## touch can express; tank is the optional twin stick scheme and needs a pad.
const SCHEME_ARCADE := "arcade"
const SCHEME_TANK := "tank"
## Tank: how fast the virtual heading swings at full differential, radians per second.
const TANK_TURN_RATE := 2.6
## Desktop QA (spec section 14): --roboteer-pad=on forces the pad path on without a
## real controller, the same way the camera's --roboteer-zoom poses the camera.
const ARG_PAD := "--roboteer-pad="

## Tank: the throttle a pure pivot (l = -r) still asks for, because the Bot API takes a
## heading and a throttle and a zero throttle heading turns nothing at all.
const TANK_PIVOT_THROTTLE := 0.35

## Broadcast (docs/design-system.md sections 1 and 4): the stick well and the two thumb
## buttons are black glass discs with a cyan hairline, the knob and the rims are `line`,
## and the only warm thing anywhere near them is the scrap the arena drops. Every colour
## below is a token, never a number of this file's own.
const COL_LINE := Broadcast.LINE
const COL_LINE_DIM := Broadcast.LINE_DIM
const COL_FILL := Broadcast.GLASS_LIVE
const COL_KNOB := Broadcast.LINE
const COL_PIP_FULL := Broadcast.LINE
const COL_PIP_SPENT := Color(Broadcast.LINE, 0.16)
## Pressed: the fill sweeps to `line` at 30 %.
const COL_PRESSED := Color(Broadcast.LINE, 0.30)
const COL_TEXT := Broadcast.TYPE
const COL_RING := Broadcast.LINE
const COL_RING_TRACK := Color(Broadcast.LINE, 0.14)

## Alpha over the live arena: 62 % resting, 90 % while that control is under a thumb.
const ALPHA_REST := 0.62
const ALPHA_TOUCHED := 0.90
## The weapon and utility glyphs (docs/design-system.md section 6) are drawn at this
## fraction of the button's diameter. Until agent V1's files land, the button falls back
## to the weapon's word, which is what wave G shipped.
const GLYPH_FRACTION := 0.46

## The primary button names what the FITTED weapon does, in one word, because the game
## has sixteen weapons and only one of them flips. Keys are `WeaponBase.kind`, which is
## the `kind` column of Shared/parts.json: spinner, drum, flipper, lifter, crusher, axe,
## saw, ram, flame, fbs, and wave P's prod, arc and drill. The HUD's glyph hint uses the
## same word.
const WEAPON_WORDS := {
	"flipper": "FLIP",
	"spinner": "SPIN",
	"drum": "SPIN",
	"saw": "SPIN",
	"fbs": "SPIN",
	"axe": "SWING",
	"crusher": "CLAMP",
	"lifter": "LIFT",
	"flame": "FIRE",
	# B10 (combat feel): the napalm cannon is kind `flame` but fires ONE charge per tap,
	# so the fight names it "napalm" here and the coach no longer tells its player to hold.
	"napalm": "FIRE",
	"ram": "RAM",
	"prod": "SHOCK",
	"arc": "ARC",
	"drill": "DRILL",
}
## Whether the word is worked by a tap or by a held thumb, for the coach callout.
const WEAPON_HOLDS := {
	"flipper": false,
	"spinner": true,
	"drum": true,
	"saw": true,
	"fbs": true,
	"axe": false,
	"crusher": true,
	"lifter": true,
	"flame": true,
	"napalm": false,
	"ram": false,
	"prod": true,
	"arc": true,
	"drill": true,
}
## The weapons whose readiness IS a spin fraction, so a spin-up ring on the button means
## something. Every other weapon's readiness means something else (gas, reset, fuel, the
## charge in a coil) and gets no ring rather than a lying one.
const SPIN_UP_KINDS := ["spinner", "drum", "saw", "fbs", "drill"]
## Until the rules layer names the fitted weapon, the button reads FLIP: the Stage 3
## fixture and the starter bot both carry a flipper.
const DEFAULT_WEAPON_KIND := "flipper"

## Current stick, length 0 to 1. Zero when nothing is held.
var heading: Vector2 = Vector2.ZERO
## Secondary button state, level (held), not edge triggered.
var secondary: bool = false

var _pt: float = 1.0
var _safe: Dictionary = {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
var _enabled: bool = true
var _desktop: bool = false

var _fire_pending: bool = false
var _inverted: bool = false
var _gas_charges: int = FightTypes.FLIPPER_CHARGES

var _stick_index: int = -1
var _stick_origin: Vector2 = Vector2.ZERO
var _stick_knob: Vector2 = Vector2.ZERO
var _primary_index: int = -1
var _secondary_index: int = -1
## index -> last known position, for touches that are neither stick nor button.
var _cam_points: Dictionary = {}
var _cam_dist: float = 0.0
var _cam_centroid: Vector2 = Vector2.ZERO

## Heading contributed by each device this tick, kept apart so one device releasing
## can never wipe another device's input.
var _touch_heading: Vector2 = Vector2.ZERO
var _key_heading: Vector2 = Vector2.ZERO
var _pad_heading: Vector2 = Vector2.ZERO

var _scheme: String = SCHEME_ARCADE
var _pad_present: bool = false
## -1 follow Input.get_connected_joypads(), 0 forced off, 1 forced on (QA and tests).
var _pad_forced: int = -1
var _pad_fire_held: bool = false
var _pad_start_held: bool = false
## Tank only: the virtual heading the differential sticks steer, radians, 0 = up.
var _tank_yaw: float = 0.0

var _layout_size: Vector2 = REF_SIZE_PT
var _primary_centre: Vector2 = Vector2.ZERO
var _secondary_centre: Vector2 = Vector2.ZERO
var _stick_home: Vector2 = Vector2.ZERO
var _secondary_label: String = "Pivot"

## The fitted weapon, its one word label, and its spin fraction when it has one.
var _weapon_kind: String = DEFAULT_WEAPON_KIND
var _primary_label: String = "FLIP"
var _weapon_spin: float = 0.0

## 1.0 = the resting base is fully drawn, 0.0 = a live stick has taken over.
var _rest_alpha: float = 1.0
## The knockout count is running on the player and they have not driven yet.
var _drive_prompt: bool = false
var _pulse_t: float = 0.0
## Drawn but not live (COUNTDOWN), and the eased alpha everything is drawn at.
var _preview: bool = false
var _alpha: float = 0.0

## A pad is connected AND has produced input in this fight. Until it has, the touch
## furniture stays on screen: the iPhone 17 simulator reports a phantom 'MFi Gamepad'
## at launch, and a player whose controls vanished at the whistle has no game.
var _pad_active: bool = false

## What the player has actually used, for the coach callouts. Sticky until reset.
var _used_drive: bool = false
var _used_primary: bool = false
var _used_camera: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = Broadcast.theme()
	if get_parent() != null:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_desktop = OS.has_feature("pc")
	if not resized.is_connected(_relayout):
		resized.connect(_relayout)
	add_to_group(GROUP)
	if not Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_read_qa_arguments()
	_refresh_pad()
	_relayout()
	set_process(true)
	set_physics_process(true)
	# The rules layer samples heading in its own _physics_process, and a parent runs
	# before its children, so the pad has to be polled ahead of it or every pad input
	# would arrive a tick late.
	process_physics_priority = -100


# ---------------------------------------------------------------- public API

## --roboteer-pad=on|off forces the controller path for desktop QA. Desktop only, so a
## device build always follows the real connected joypads.
func _read_qa_arguments() -> void:
	if not OS.has_feature("pc"):
		return
	for raw in OS.get_cmdline_user_args():
		var arg := str(raw)
		if arg.begins_with(ARG_PAD):
			var value := arg.substr(ARG_PAD.length()).to_lower()
			_pad_forced = 1 if (value == "on" or value == "1" or value == "true") else 0


## True exactly once per tap of the primary button (or Space on desktop QA).
func consume_fire() -> bool:
	if not _fire_pending:
		return false
	_fire_pending = false
	return true


## The primary button's LEVEL: true for as long as a thumb (or the pad's fire button, or
## Space) is down. Nine of the ten weapons are worked by holding, not by tapping: the
## spinners spin up while held, the crusher closes while held, the flamethrower burns
## while held. The rules layer ORs this with consume_fire() so the tap edge is never
## lost and the hold actually reaches the weapon.
func primary_held() -> bool:
	if _primary_index != -1:
		return true
	if _pad_present and _pad_fire_held:
		return true
	return _desktop and Input.is_key_pressed(KEY_SPACE)


## Insets in viewport pixels: {"left": float, "top": float, "right": float, "bottom": float}.
func set_safe_area(px: Dictionary) -> void:
	for key in ["left", "top", "right", "bottom"]:
		_safe[key] = float(px.get(key, 0.0))
	_relayout()


## The fitted weapon's `kind` (WeaponBase.kind) and, for a hold-to-spin weapon, how far
## it has spun up (0 to 1; pass anything negative to leave it alone). The rules layer
## calls this every presentation frame from the player bot.
## The word on the primary button while the weapon cannot answer it; "" restores the
## weapon's own word. Set from `Bot.weapon_fault()` every presentation tick.
const FAULT_WORDS := {"jammed": "JAMMED", "cooked": "COOKED"}
var _weapon_fault: String = ""


func weapon_fault() -> String:
	return _weapon_fault


func set_weapon(kind: String, spin: float = -1.0, fault: String = "") -> void:
	var want := kind.strip_edges().to_lower()
	if want != _weapon_kind and WEAPON_WORDS.has(want):
		_weapon_kind = want
		queue_redraw()
	var fault_key := fault.strip_edges().to_lower()
	if not FAULT_WORDS.has(fault_key):
		fault_key = ""
	if fault_key != _weapon_fault:
		_weapon_fault = fault_key
		queue_redraw()
	if WEAPON_WORDS.has(_weapon_kind):
		var label := str(FAULT_WORDS[_weapon_fault]) if _weapon_fault != "" \
			else str(WEAPON_WORDS[_weapon_kind])
		if label != _primary_label:
			_primary_label = label
			primary_label_changed.emit(label)
			queue_redraw()
	if spin >= 0.0:
		var clamped := clampf(spin, 0.0, 1.0)
		if absf(clamped - _weapon_spin) > 0.01:
			_weapon_spin = clamped
			if shows_spin_ring():
				queue_redraw()


## The fitted weapon's kind.
func weapon_kind() -> String:
	return _weapon_kind


## The one word on the primary button, and the word the HUD's glyph hint repeats.
func primary_label() -> String:
	return _primary_label


## True when the fitted weapon is worked by holding the button rather than tapping it.
func primary_is_hold() -> bool:
	return bool(WEAPON_HOLDS.get(_weapon_kind, false))


## True when the button carries a spin-up ring, which is only when the weapon's
## readiness really is a spin fraction.
func shows_spin_ring() -> bool:
	return _weapon_kind in SPIN_UP_KINDS


## Relabels the secondary button and redraws the gas charge pips.
func set_state(inverted: bool, gas_charges: int) -> void:
	if inverted == _inverted and gas_charges == _gas_charges:
		return
	_inverted = inverted
	_gas_charges = maxi(gas_charges, 0)
	var label := "Self right" if inverted else "Pivot"
	if label != _secondary_label:
		_secondary_label = label
		secondary_label_changed.emit(label)
	queue_redraw()


## "arcade" (one stick steers, brief section 11's default) or "tank" (twin stick, one
## stick per track). Anything else is treated as arcade. Tank needs a pad: with one
## floating touch stick there is no second track to drive, so touch stays arcade.
func set_scheme(scheme_name: String) -> void:
	var want := scheme_name.to_lower()
	if want != SCHEME_TANK:
		want = SCHEME_ARCADE
	if want == _scheme:
		return
	_scheme = want
	_tank_yaw = 0.0
	_pad_heading = Vector2.ZERO


func scheme() -> String:
	return _scheme


## The label the secondary button is currently showing, for the pad hint.
func secondary_label() -> String:
	return _secondary_label


## Tank twin stick maths, pure so it can be tested on its own. l and r are the two
## track demands, -1 full reverse to +1 full ahead.
##
## The Bot API takes a heading and a throttle, not two track speeds, so the mix is:
## throttle is the mean of the tracks, turn is half their difference, and the caller
## integrates `turn` into a virtual heading at TANK_TURN_RATE radians per second which
## the bot then chases. The one place this is not faithful is a pure pivot (l = -r):
## the mean throttle is zero and a zero length heading turns nothing, so `magnitude`
## keeps TANK_PIVOT_THROTTLE of the turn instead and the bot pivots slowly on the spot.
func tank_mix(l: float, r: float) -> Dictionary:
	var throttle := clampf((l + r) * 0.5, -1.0, 1.0)
	var turn := clampf((l - r) * 0.5, -1.0, 1.0)
	var magnitude := clampf(maxf(absf(throttle), absf(turn) * TANK_PIVOT_THROTTLE), 0.0, 1.0)
	return {
		"throttle": throttle,
		"turn": turn,
		"magnitude": magnitude,
		"reverse": throttle < -0.001,
	}


## The virtual heading the tank scheme is steering, degrees, 0 = up the screen.
func tank_yaw_deg() -> float:
	return rad_to_deg(_tank_yaw)


## True when a game controller is CONNECTED. On its own this changes nothing on screen:
## GameController reports a phantom 'MFi Gamepad' on the iPhone 17 simulator at launch
## and possibly on a phone with a stale Bluetooth pairing, and hiding the controls for a
## pad nobody is holding is exactly the bug the owner hit.
func pad_present() -> bool:
	return _pad_present


## True when a connected pad has produced input in this fight and no thumb has since
## touched the glass. THIS is what hides the on screen stick and buttons and shows the
## HUD's glyph hints. The touch routing stays live throughout, so a thumb on the (now
## invisible) button still fires and brings the furniture straight back.
func pad_active() -> bool:
	return _pad_present and _pad_active


## New fight: the pad has to earn the screen again. Called by the rules layer from
## start_fight.
func reset_pad_activity() -> void:
	if not _pad_active:
		return
	_pad_active = false
	pad_active_changed.emit(false)
	queue_redraw()


## What the player has used since the last reset: {"drive": bool, "primary": bool,
## "camera": bool}. The coach callouts fade on these; nothing else reads them.
func input_usage() -> Dictionary:
	return {"drive": _used_drive, "primary": _used_primary, "camera": _used_camera}


## New fight: every coach callout is owed again.
func reset_input_usage() -> void:
	_used_drive = false
	_used_primary = false
	_used_camera = false


## What Godot's own joypad layer can see, ignoring any QA override. If the Swift shell
## reports a connected controller and this is still false, the embedded runtime is not
## receiving GCController events and no pad input will arrive (see the notes).
func pad_seen_by_engine() -> bool:
	return not Input.get_connected_joypads().is_empty()


## QA and tests only: force the pad state instead of following the connected joypads.
## Input.parse_input_event can fake joypad axes headless but cannot fake a connection.
func set_pad_present(on: bool) -> void:
	_pad_forced = 1 if on else 0
	_refresh_pad()


## Back to following Input.get_connected_joypads().
func clear_pad_override() -> void:
	_pad_forced = -1
	_refresh_pad()


## Where the on screen furniture sits, so the HUD can put its pad hints in the same
## places without duplicating the layout maths.
func button_centres() -> Dictionary:
	return {
		"primary": _primary_centre,
		"secondary": _secondary_centre,
		"primary_radius": PRIMARY_DIAMETER_PT * 0.5 * _pt,
		"secondary_radius": SECONDARY_DIAMETER_PT * 0.5 * _pt,
		"stick_home": _stick_home,
		"stick_radius": STICK_BASE_PT * _pt,
		"stick_zone": Rect2(Vector2.ZERO,
			Vector2(_layout_size.x * STICK_ZONE_FRACTION, _layout_size.y)),
		"size": _layout_size,
		"pt": _pt,
	}


## Where the resting stick waits. The coach callout anchors to this, and so does the
## player's thumb the first time.
func stick_home() -> Vector2:
	return _stick_home


## A knockout count is running on the player and they have not driven: pulse the resting
## stick gently so the thing they need to touch is the thing that is moving.
func set_drive_prompt(on: bool) -> void:
	if on == _drive_prompt:
		return
	_drive_prompt = on
	_pulse_t = 0.0
	queue_redraw()


func drive_prompt() -> bool:
	return _drive_prompt


## Off during LOADING, COUNTDOWN and RESULT. Releases every live touch. This is about
## INPUT only; see set_preview for whether the furniture is drawn.
func set_enabled(on: bool) -> void:
	if on == _enabled:
		return
	_enabled = on
	if not on:
		_release_all()
	queue_redraw()


func is_enabled() -> bool:
	return _enabled


## Draw the stick and both buttons without taking any input: the COUNTDOWN, where the
## coach callouts are already on screen and were pointing at empty corners. Ignored once
## the controls are live, which is drawn at full strength.
func set_preview(on: bool) -> void:
	if on == _preview:
		return
	_preview = on
	queue_redraw()


func is_preview() -> bool:
	return _preview


## The alpha the furniture is drawn at this frame: 1 live, PREVIEW_ALPHA during the
## countdown, 0 when there is nothing to show. Eased, so the bell fades it up.
func draw_alpha() -> float:
	return _alpha


# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	handle_event(event)


## Public so the headless test can feed synthetic events without a display server.
func handle_event(event: InputEvent) -> void:
	# Pad ACTIVITY is noticed whether or not the controls are live, because a pad that
	# was used during the countdown is a pad in somebody's hands. Polling in
	# _poll_gameplay is the backstop for a pad whose events arrive as state only.
	if event is InputEventJoypadButton:
		if (event as InputEventJoypadButton).pressed:
			_note_pad_input()
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) > PAD_DEADZONE:
			_note_pad_input()
	if not _enabled:
		return
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_on_drag(event as InputEventScreenDrag)
	elif event is InputEventMagnifyGesture:
		_used_camera = true
		camera_pinch.emit((event as InputEventMagnifyGesture).factor)
	elif event is InputEventPanGesture:
		_used_camera = true
		camera_orbit.emit((event as InputEventPanGesture).delta * PAN_GESTURE_TO_PX)
	elif event is InputEventKey and _desktop:
		_on_key(event as InputEventKey)


func _on_touch(event: InputEventScreenTouch) -> void:
	var pos := event.position
	var idx := event.index
	if event.pressed:
		# A thumb on the glass takes the screen back from the pad, whatever it lands on.
		_note_touch_input()
		if _hit(pos, _primary_centre, PRIMARY_DIAMETER_PT * 0.5) and _primary_index == -1:
			_primary_index = idx
			_fire_pending = true
			_used_primary = true
			queue_redraw()
			return
		if _hit(pos, _secondary_centre, SECONDARY_DIAMETER_PT * 0.5) and _secondary_index == -1:
			_secondary_index = idx
			secondary = true
			queue_redraw()
			return
		if _stick_index == -1 and pos.x <= _layout_size.x * STICK_ZONE_FRACTION:
			_stick_index = idx
			_stick_origin = pos
			_stick_knob = pos
			_touch_heading = Vector2.ZERO
			if _pad_heading == Vector2.ZERO:
				heading = Vector2.ZERO
			queue_redraw()
			return
		_cam_points[idx] = pos
		_rebaseline_camera()
		return

	# Release.
	if idx == _primary_index:
		_primary_index = -1
		queue_redraw()
	elif idx == _secondary_index:
		_secondary_index = -1
		secondary = false
		queue_redraw()
	elif idx == _stick_index:
		_stick_index = -1
		_touch_heading = Vector2.ZERO
		if _pad_heading == Vector2.ZERO:
			heading = Vector2.ZERO
		queue_redraw()
	elif _cam_points.has(idx):
		_cam_points.erase(idx)
		_rebaseline_camera()


func _on_drag(event: InputEventScreenDrag) -> void:
	var idx := event.index
	if idx == _stick_index:
		_stick_knob = event.position
		var throw := STICK_THROW_PT * _pt
		var offset := (_stick_knob - _stick_origin) / maxf(throw, 0.001)
		_touch_heading = offset.limit_length(1.0)
		if _touch_heading != Vector2.ZERO:
			_used_drive = true
		if _pad_heading == Vector2.ZERO:
			heading = _touch_heading
		queue_redraw()
		return
	if idx == _primary_index or idx == _secondary_index:
		return
	if not _cam_points.has(idx):
		return
	var was: Vector2 = _cam_points[idx]
	_cam_points[idx] = event.position
	# ONE finger, started outside the stick zone and off both buttons, orbits and tilts.
	# Stage 3 made this do nothing, which meant nothing on screen and nothing in the
	# player's hands ever suggested the camera could move at all.
	if _cam_points.size() == 1:
		var moved := event.position - was
		if moved.length_squared() > 0.0:
			_used_camera = true
			camera_orbit.emit(moved)
		_cam_centroid = event.position
		_cam_dist = 0.0
		return
	if _cam_points.size() != 2:
		return
	var centroid := _camera_centroid()
	var dist := _camera_spread()
	if _cam_dist > 1.0 and dist > 1.0:
		camera_pinch.emit(dist / _cam_dist)
	var delta := centroid - _cam_centroid
	if delta.length_squared() > 0.0:
		camera_orbit.emit(delta)
	if delta.length_squared() > 0.0 or absf(dist - _cam_dist) > 1.0:
		_used_camera = true
	_cam_dist = dist
	_cam_centroid = centroid


func _on_key(event: InputEventKey) -> void:
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_SPACE:
		_fire_pending = true
		_used_primary = true


func _process(delta: float) -> void:
	_tick_rest_fade(delta)
	if not _enabled:
		return
	_poll_camera(delta)


## The resting base fades out while a stick touch is live and back in on release, so the
## stick neither snaps nor sits doubled under the thumb.
## The whole furniture's alpha: full while the controls are live, PREVIEW_ALPHA during
## the countdown, nothing otherwise, eased between them.
func _tick_alpha(delta: float) -> void:
	var target := 0.0
	if _enabled:
		target = 1.0
	elif _preview:
		target = PREVIEW_ALPHA
	if is_equal_approx(_alpha, target):
		return
	_alpha = move_toward(_alpha, target, delta / maxf(ALPHA_FADE_S, 0.001))
	queue_redraw()


func _tick_rest_fade(delta: float) -> void:
	_tick_alpha(delta)
	if _drive_prompt and _stick_index == -1:
		_pulse_t = fposmod(_pulse_t + delta, DRIVE_PULSE_PERIOD_S)
		queue_redraw()
	var target := 0.0 if _stick_index != -1 else 1.0
	if is_equal_approx(_rest_alpha, target):
		return
	_rest_alpha = move_toward(_rest_alpha, target, delta / maxf(STICK_REST_FADE_S, 0.001))
	queue_redraw()


## Gameplay inputs are sampled on the physics tick, which is the clock the rules layer
## reads them on. Presentation (the camera) stays on the frame clock below.
func _physics_process(delta: float) -> void:
	if not _enabled:
		return
	_poll_gameplay(delta)


func _poll_gameplay(delta: float) -> void:
	var pad_secondary := false
	_pad_heading = Vector2.ZERO
	if _pad_present and not _pad_active and _pad_any_input():
		_note_pad_input()
	# Only an ACTIVE pad drives. A pad that is merely listed (the simulator reports a
	# phantom 'MFi Gamepad', and an iPhone with no controller paired still listed one)
	# must never feed a heading, or the bot drives itself.
	if _pad_present and _pad_active:
		if _scheme == SCHEME_TANK:
			_pad_heading = _tank_heading(delta)
		else:
			_pad_heading = _pad_stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)
		var fire := Input.is_joy_button_pressed(PAD_DEVICE, JOY_BUTTON_A) \
			or Input.get_joy_axis(PAD_DEVICE, JOY_AXIS_TRIGGER_RIGHT) > PAD_TRIGGER_THRESHOLD
		if fire and not _pad_fire_held:
			_fire_pending = true
			_used_primary = true
		_pad_fire_held = fire
		pad_secondary = Input.is_joy_button_pressed(PAD_DEVICE, JOY_BUTTON_B) \
			or Input.get_joy_axis(PAD_DEVICE, JOY_AXIS_TRIGGER_LEFT) > PAD_TRIGGER_THRESHOLD
		var start := Input.is_joy_button_pressed(PAD_DEVICE, JOY_BUTTON_START)
		if start and not _pad_start_held:
			pause_requested.emit()
		_pad_start_held = start

	# Keyboard driving, desktop QA only, and only while no touch stick is live.
	_key_heading = Vector2.ZERO
	if _desktop and _stick_index == -1:
		var v := Vector2.ZERO
		if Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			v.x -= 1.0
		if Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			v.x += 1.0
		if Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			v.y -= 1.0
		if Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			v.y += 1.0
		_key_heading = v.limit_length(1.0)

	# A deflected pad stick owns the tick, then a live touch stick, then the keyboard.
	if _pad_heading != Vector2.ZERO:
		heading = _pad_heading
	elif _stick_index != -1:
		heading = _touch_heading
	else:
		heading = _key_heading

	if heading != Vector2.ZERO:
		_used_drive = true

	secondary = _secondary_index != -1 or pad_secondary \
		or (_desktop and Input.is_key_pressed(KEY_SHIFT))


## Any button down or any stick or trigger off its rest. The state poll behind
## `handle_event`'s joypad events: SwiftGodot's iOS joypad path delivers state, and a
## pad that is only ever polled must still be able to claim the screen.
func _pad_any_input() -> bool:
	for button in range(JOY_BUTTON_SDL_MAX):
		if Input.is_joy_button_pressed(PAD_DEVICE, button):
			return true
	for axis: int in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]:
		if absf(Input.get_joy_axis(PAD_DEVICE, axis)) > PAD_DEADZONE:
			return true
	for axis: int in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
		if Input.get_joy_axis(PAD_DEVICE, axis) > PAD_TRIGGER_THRESHOLD:
			return true
	return false


## A connected pad has been used: the touch furniture goes away and the HUD's glyph
## hints come up. Never fires for a pad that is merely plugged in.
func _note_pad_input() -> void:
	if not _pad_present or _pad_active:
		return
	_pad_active = true
	pad_active_changed.emit(true)
	queue_redraw()


## A thumb went back on the glass: the touch furniture returns and the hints go.
func _note_touch_input() -> void:
	if not _pad_active:
		return
	_pad_active = false
	pad_active_changed.emit(false)
	queue_redraw()


func _poll_camera(delta: float) -> void:
	var orbit := Vector2.ZERO
	var zoom := 0.0

	if _desktop:
		if Input.is_physical_key_pressed(KEY_Q):
			orbit.x -= KEY_ORBIT_PX_PER_S * delta
		if Input.is_physical_key_pressed(KEY_E):
			orbit.x += KEY_ORBIT_PX_PER_S * delta
		if Input.is_physical_key_pressed(KEY_R):
			orbit.y -= KEY_TILT_PX_PER_S * delta
		if Input.is_physical_key_pressed(KEY_F):
			orbit.y += KEY_TILT_PX_PER_S * delta
		if Input.is_key_pressed(KEY_EQUAL):
			zoom += KEY_ZOOM_PER_S * delta
		if Input.is_key_pressed(KEY_MINUS):
			zoom -= KEY_ZOOM_PER_S * delta

	if _pad_present:
		var rs := _pad_stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y)
		orbit.x += rs.x * PAD_ORBIT_PX_PER_S * delta
		# In tank the right stick's y axis is the right track, so it cannot also tilt.
		if _scheme != SCHEME_TANK:
			orbit.y += rs.y * PAD_TILT_PX_PER_S * delta
		if Input.is_joy_button_pressed(PAD_DEVICE, JOY_BUTTON_RIGHT_SHOULDER):
			zoom += PAD_ZOOM_PER_S * delta
		if Input.is_joy_button_pressed(PAD_DEVICE, JOY_BUTTON_LEFT_SHOULDER):
			zoom -= PAD_ZOOM_PER_S * delta

	if orbit.length_squared() > 0.0:
		camera_orbit.emit(orbit)
	if zoom != 0.0:
		camera_pinch.emit(1.0 + zoom)


## One pad stick, circular deadzone, remaining travel rescaled to 0..1. The joypad y
## axis is already negative upward, which is this node's screen space convention.
func _pad_stick(axis_x: int, axis_y: int) -> Vector2:
	var v := Vector2(Input.get_joy_axis(PAD_DEVICE, axis_x), Input.get_joy_axis(PAD_DEVICE, axis_y))
	var length := v.length()
	if length <= PAD_DEADZONE:
		return Vector2.ZERO
	var scaled := clampf(inverse_lerp(PAD_DEADZONE, 1.0, minf(length, 1.0)), 0.0, 1.0)
	return v / length * scaled


## One axis, same deadzone and rescale, sign preserved.
func _pad_axis(axis: int) -> float:
	var v := Input.get_joy_axis(PAD_DEVICE, axis)
	var magnitude := absf(v)
	if magnitude <= PAD_DEADZONE:
		return 0.0
	var scaled := clampf(inverse_lerp(PAD_DEADZONE, 1.0, minf(magnitude, 1.0)), 0.0, 1.0)
	return scaled if v > 0.0 else -scaled


## Tank scheme: left stick y is the left track, right stick y is the right track, both
## negative upward on a pad, so they are flipped to "ahead is positive" first.
func _tank_heading(delta: float) -> Vector2:
	var l := -_pad_axis(JOY_AXIS_LEFT_Y)
	var r := -_pad_axis(JOY_AXIS_RIGHT_Y)
	var mix := tank_mix(l, r)
	_tank_yaw = wrapf(_tank_yaw + float(mix["turn"]) * TANK_TURN_RATE * delta, -PI, PI)
	var magnitude := float(mix["magnitude"])
	if magnitude <= 0.0:
		return Vector2.ZERO
	var dir := Vector2(sin(_tank_yaw), -cos(_tank_yaw))
	if bool(mix["reverse"]):
		dir = -dir
	return dir * magnitude


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	_refresh_pad()


func _refresh_pad() -> void:
	var present := not Input.get_connected_joypads().is_empty()
	if _pad_forced >= 0:
		present = _pad_forced == 1
	if present == _pad_present:
		return
	_pad_present = present
	if not present:
		_pad_fire_held = false
		_pad_start_held = false
		_pad_heading = Vector2.ZERO
		_tank_yaw = 0.0
		if _pad_active:
			_pad_active = false
			pad_active_changed.emit(false)
	pad_present_changed.emit(present)
	queue_redraw()


# ---------------------------------------------------------------- layout

func _relayout() -> void:
	var s := size
	if s.x <= 1.0 or s.y <= 1.0:
		if is_inside_tree():
			s = get_viewport_rect().size
	if s.x <= 1.0 or s.y <= 1.0:
		s = REF_SIZE_PT
	_layout_size = s
	_pt = minf(s.x / REF_SIZE_PT.x, s.y / REF_SIZE_PT.y)
	if _pt <= 0.0:
		_pt = 1.0
	var half_primary := PRIMARY_DIAMETER_PT * 0.5 * _pt
	_primary_centre = Vector2(
		s.x - float(_safe["right"]) - EDGE_MARGIN_PT * _pt - half_primary,
		s.y - float(_safe["bottom"]) - EDGE_MARGIN_PT * _pt - half_primary)
	_secondary_centre = _primary_centre + SECONDARY_OFFSET_PT * _pt
	# The resting stick, bottom left, inside the safe area and well inside EDGE_MARGIN.
	# Clamped into the stick zone so a very narrow viewport cannot push it out of the
	# region a touch would actually claim.
	var inset := STICK_HOME_INSET_PT * _pt
	var zone_right := s.x * STICK_ZONE_FRACTION - STICK_BASE_PT * _pt
	_stick_home = Vector2(
		minf(float(_safe["left"]) + inset, maxf(zone_right, inset)),
		s.y - float(_safe["bottom"]) - inset)
	queue_redraw()


func _hit(pos: Vector2, centre: Vector2, radius_pt: float) -> bool:
	var r := radius_pt * _pt * HIT_SLOP
	return pos.distance_squared_to(centre) <= r * r


func _camera_centroid() -> Vector2:
	var sum := Vector2.ZERO
	for key in _cam_points:
		sum += _cam_points[key]
	return sum / float(maxi(_cam_points.size(), 1))


func _camera_spread() -> float:
	if _cam_points.size() < 2:
		return 0.0
	var keys := _cam_points.keys()
	var a: Vector2 = _cam_points[keys[0]]
	var b: Vector2 = _cam_points[keys[1]]
	return a.distance_to(b)


func _rebaseline_camera() -> void:
	_cam_centroid = _camera_centroid()
	_cam_dist = _camera_spread()


func _release_all() -> void:
	_stick_index = -1
	_primary_index = -1
	_secondary_index = -1
	_cam_points.clear()
	_cam_dist = 0.0
	_touch_heading = Vector2.ZERO
	_pad_heading = Vector2.ZERO
	heading = Vector2.ZERO
	secondary = false
	_fire_pending = false
	_rest_alpha = 1.0
	_pulse_t = 0.0


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	# A pad player who is actually USING the pad gets the HUD's glyph hints instead. A
	# pad that is merely connected changes nothing: the touch furniture stays until the
	# pad earns the screen. The touch routing is live either way, so a thumb on the
	# (invisible) button still fires and brings everything straight back.
	if pad_active() or _alpha <= 0.004:
		return
	_draw_primary()
	_draw_secondary()
	# The resting base and the live one cross-fade, so the stick is always somewhere on
	# screen and never in two places at full strength.
	if _rest_alpha > 0.004:
		_draw_rest_stick(_rest_alpha)
	if _stick_index != -1:
		_draw_stick()


## Every colour in this node is drawn through here, so the countdown preview and the
## live controls are the same drawing at two strengths.
func _c(colour: Color, extra: float = 1.0) -> Color:
	return Color(colour, colour.a * _alpha * extra)


## The design system's alpha over the arena: 62 % at rest, 90 % while a thumb is on this
## control. Multiplied into `_c`, so it never disturbs `draw_alpha()`, which is still the
## countdown's dimming and nothing else.
func _touch(active: bool) -> float:
	return ALPHA_TOUCHED if active else ALPHA_REST


## The live stick: a glass well with a `lineDim` rim, the throw ring as a hairline, and a
## `line` knob.
func _draw_stick() -> void:
	var base_r := STICK_BASE_PT * _pt
	var knob_r := STICK_KNOB_PT * _pt
	var throw := STICK_THROW_PT * _pt
	var a := _touch(true)
	draw_circle(_stick_origin, base_r, _c(COL_FILL, a))
	draw_arc(_stick_origin, base_r, 0.0, TAU, 48, _c(COL_LINE_DIM, a), maxf(1.5 * _pt, 1.0), true)
	# The throw ring: how far the thumb has to travel for full throttle.
	draw_arc(_stick_origin, throw, 0.0, TAU, 56, _c(COL_LINE_DIM, a * 0.7),
		maxf(1.0 * _pt, 1.0), true)
	var knob := _stick_origin + heading * throw
	draw_circle(knob, knob_r, _c(Color(COL_KNOB, 0.45), a))
	draw_arc(knob, knob_r, 0.0, TAU, 32, _c(COL_LINE, a), maxf(2.0 * _pt, 1.0), true)


## The stick at rest, knob centred, with the word under it. This is the whole point of
## the change: before it the left half of the screen was blank and the player had no way
## to know a stick was there at all.
func _draw_rest_stick(alpha: float) -> void:
	var base_r := STICK_BASE_PT * _pt
	var knob_r := STICK_KNOB_PT * _pt
	var a := alpha * _touch(false)
	draw_circle(_stick_home, base_r, _c(COL_FILL, a))
	draw_arc(_stick_home, base_r, 0.0, TAU, 48, _c(COL_LINE_DIM, a), maxf(1.5 * _pt, 1.0), true)
	draw_circle(_stick_home, knob_r, _c(Color(COL_KNOB, 0.45), a))
	draw_arc(_stick_home, knob_r, 0.0, TAU, 32, _c(COL_LINE, a), maxf(2.0 * _pt, 1.0), true)
	_draw_label("DRIVE", _stick_home + Vector2(0.0, base_r + 15.0 * _pt),
		Broadcast.LABEL_PT * _pt, a * _alpha)
	if _drive_prompt:
		# One ring per period, growing out of the base and fading as it goes.
		var k := _pulse_t / maxf(DRIVE_PULSE_PERIOD_S, 0.001)
		var r := base_r + DRIVE_PULSE_RING_PT * _pt * k
		draw_arc(_stick_home, r, 0.0, TAU, 48, _c(COL_LINE, a * (1.0 - k) * 0.9),
			2.5 * _pt, true)


## The primary weapon button: a glass disc with a `line` rim and the fitted weapon's
## glyph, pressed fills `line` at 30 %.
func _draw_primary() -> void:
	var r := PRIMARY_DIAMETER_PT * 0.5 * _pt
	var pressed := _primary_index != -1
	var a := _touch(pressed)
	draw_circle(_primary_centre, r, _c(COL_PRESSED if pressed else COL_FILL, a))
	draw_arc(_primary_centre, r, 0.0, TAU, 48, _c(COL_LINE, a), maxf(2.0 * _pt, 1.0), true)
	_draw_button_face(Broadcast.glyph("weapon", weapon_glyph_id()), _primary_label,
		_primary_centre, r, a, Broadcast.BUTTON_PT)
	if shows_spin_ring():
		_draw_spin_ring(r, a)
	elif _weapon_kind == "flipper":
		_draw_pips(r, a)


## Hold-to-spin weapons: a ring just outside the button that fills as the weapon reaches
## speed. Only drawn for the weapons whose readiness really IS a spin fraction; every
## other weapon gets nothing rather than a ring that means something else.
func _draw_spin_ring(button_r: float, alpha: float = 1.0) -> void:
	var ring := button_r + 9.0 * _pt
	var width := 4.0 * _pt
	draw_arc(_primary_centre, ring, 0.0, TAU, 56, _c(COL_RING_TRACK, alpha), width, true)
	if _weapon_spin <= 0.005:
		return
	# Fills clockwise from the top, so a half filled ring reads as half speed.
	var start := -PI * 0.5
	draw_arc(_primary_centre, ring, start, start + TAU * _weapon_spin,
		maxi(int(56.0 * _weapon_spin) + 2, 4), _c(COL_RING, alpha), width, true)


## Gas charges as pips on a ring just outside the primary button. The flipper is the
## only weapon that spends a charge per shot, so it is the only one that shows them.
func _draw_pips(button_r: float, alpha: float = 1.0) -> void:
	var total := FightTypes.FLIPPER_CHARGES
	if total <= 0:
		return
	var ring := button_r + 11.0 * _pt
	var pip := 4.0 * _pt
	# A 240 degree fan opening away from the screen corner, so the thumb never covers it.
	var start := deg_to_rad(150.0)
	var sweep := deg_to_rad(240.0)
	for i in total:
		var t := float(i) / float(maxi(total - 1, 1))
		var ang := start + sweep * t
		var p := _primary_centre + Vector2(cos(ang), sin(ang)) * ring
		draw_circle(p, pip, _c(COL_PIP_FULL if i < _gas_charges else COL_PIP_SPENT, alpha))


## The secondary button: the same disc at its smaller size, with the utility glyph.
func _draw_secondary() -> void:
	var r := SECONDARY_DIAMETER_PT * 0.5 * _pt
	var pressed := _secondary_index != -1
	var a := _touch(pressed)
	draw_circle(_secondary_centre, r, _c(COL_PRESSED if pressed else COL_FILL, a))
	draw_arc(_secondary_centre, r, 0.0, TAU, 40, _c(COL_LINE, a), maxf(2.0 * _pt, 1.0), true)
	_draw_button_face(Broadcast.glyph("utility", utility_glyph_id()), _secondary_label.to_upper(),
		_secondary_centre, r, a, Broadcast.LABEL_PT)


## The weapon glyph is named for the PART id (glyph_weapon_horizontal_spinner.svg), and
## this node only knows the weapon's `kind` ("spinner"), so the two are matched through
## the catalogue rather than through a second hand written table that could drift from it.
## Falls back to the kind, which is right for the ids that are already the kind (flipper,
## lifter, crusher, axe, saw, ram).
static var _weapon_glyph_ids: Dictionary = {}


func weapon_glyph_id() -> String:
	if _weapon_glyph_ids.is_empty():
		var parts: Variant = PartsCatalogue.parts().get("weapon", {})
		if parts is Dictionary:
			for id: String in (parts as Dictionary).keys():
				var kind := str(((parts as Dictionary)[id] as Dictionary).get("kind", ""))
				if not kind.is_empty() and not _weapon_glyph_ids.has(kind):
					_weapon_glyph_ids[kind] = id
	return str(_weapon_glyph_ids.get(_weapon_kind, _weapon_kind))


## The utility glyph's id in the asset manifest, from whatever the button is doing now.
## A self righting bot works its srimech; there is no glyph for a pivot, and the button
## says the word instead.
func utility_glyph_id() -> String:
	return "srimech" if _inverted else "pivot"


## A button's face: the glyph when agent V1 has drawn it, and the word when there is no
## file yet. A missing glyph must never leave a blank disc, which is the state the owner
## already could not read.
func _draw_button_face(glyph: Texture2D, word: String, centre: Vector2, radius: float,
		alpha: float, word_pt: float) -> void:
	if glyph != null:
		var side := radius * 2.0 * GLYPH_FRACTION
		var rect := Rect2(centre - Vector2(side, side) * 0.5, Vector2(side, side))
		draw_texture_rect(glyph, rect, false, _c(COL_TEXT, alpha))
		return
	_draw_label(word, centre, word_pt * _pt, alpha * _alpha)


func _draw_label(text: String, centre: Vector2, font_size: float, alpha: float = 1.0) -> void:
	var font := Broadcast.font_label()
	if font == null:
		font = get_theme_default_font()
	if font == null:
		return
	var px := maxi(int(round(font_size)), int(round(Broadcast.TYPE_FLOOR_PT * _pt)))
	var origin := centre + Vector2(0.0, px * 0.35)
	Broadcast.draw_text(self, font, origin, text, px, Color(COL_TEXT, COL_TEXT.a * alpha),
		HORIZONTAL_ALIGNMENT_CENTER, maxi(int(round(2.0 * _pt)), 1))
