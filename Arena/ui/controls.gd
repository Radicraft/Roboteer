class_name FightControls extends Control
## Fight touch routing: floating left stick, two right thumb buttons, camera gestures.
## Spec: docs/stage3-spec.md sections 10 and 14.
##
## Presentation node only. The rules layer samples `heading`, `consume_fire()` and
## `secondary` once per physics tick and never the other way round. Nothing here
## touches the simulation.
##
## Coordinates: every touch position is in this Control's local space, which with the
## project's canvas_items stretch is the design viewport. `heading` is screen space,
## +x right, +y down, length 0 to 1; the rules layer maps it into the world.

signal camera_pinch(factor: float)
signal camera_orbit(delta: Vector2)

## Design reference: an iPhone 17 in landscape is 1206 x 556 points. Everything below
## is quoted in those points and multiplied by `_pt`, so the layout holds at any
## viewport size or content scale (2412 x 1112 gives _pt = 2.0).
const REF_SIZE_PT := Vector2(1206.0, 556.0)

const STICK_ZONE_FRACTION := 0.45
const STICK_BASE_PT := 60.0
const STICK_KNOB_PT := 28.0
const STICK_THROW_PT := 60.0
const PRIMARY_DIAMETER_PT := 92.0
const SECONDARY_DIAMETER_PT := 68.0
const EDGE_MARGIN_PT := 24.0
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

## The arena keeps gold for bolts and scrap (docs/stage2-art-direction.md), so the
## controls are white on a dark wash and never introduce a second warm.
const COL_LINE := Color(1.0, 1.0, 1.0, 0.85)
const COL_FILL := Color(0.06, 0.09, 0.12, 0.35)
const COL_KNOB := Color(1.0, 1.0, 1.0, 0.55)
const COL_PIP_FULL := Color(1.0, 1.0, 1.0, 0.92)
const COL_PIP_SPENT := Color(1.0, 1.0, 1.0, 0.16)
const COL_PRESSED := Color(1.0, 1.0, 1.0, 0.28)
const COL_TEXT := Color(1.0, 1.0, 1.0, 0.95)
const COL_TEXT_OUTLINE := Color(0.03, 0.05, 0.07, 0.9)

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

var _layout_size: Vector2 = REF_SIZE_PT
var _primary_centre: Vector2 = Vector2.ZERO
var _secondary_centre: Vector2 = Vector2.ZERO
var _secondary_label: String = "Pivot"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if get_parent() != null:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_desktop = OS.has_feature("pc")
	if not resized.is_connected(_relayout):
		resized.connect(_relayout)
	_relayout()
	set_process(true)


# ---------------------------------------------------------------- public API

## True exactly once per tap of the primary button (or Space on desktop QA).
func consume_fire() -> bool:
	if not _fire_pending:
		return false
	_fire_pending = false
	return true


## Insets in viewport pixels: {"left": float, "top": float, "right": float, "bottom": float}.
func set_safe_area(px: Dictionary) -> void:
	for key in ["left", "top", "right", "bottom"]:
		_safe[key] = float(px.get(key, 0.0))
	_relayout()


## Relabels the secondary button and redraws the gas charge pips.
func set_state(inverted: bool, gas_charges: int) -> void:
	if inverted == _inverted and gas_charges == _gas_charges:
		return
	_inverted = inverted
	_gas_charges = maxi(gas_charges, 0)
	_secondary_label = "Self right" if inverted else "Pivot"
	queue_redraw()


## Off during LOADING, COUNTDOWN and RESULT. Releases every live touch.
func set_enabled(on: bool) -> void:
	if on == _enabled:
		return
	_enabled = on
	if not on:
		_release_all()
	queue_redraw()


func is_enabled() -> bool:
	return _enabled


# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	handle_event(event)


## Public so the headless test can feed synthetic events without a display server.
func handle_event(event: InputEvent) -> void:
	if not _enabled:
		return
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_on_drag(event as InputEventScreenDrag)
	elif event is InputEventMagnifyGesture:
		camera_pinch.emit((event as InputEventMagnifyGesture).factor)
	elif event is InputEventPanGesture:
		camera_orbit.emit((event as InputEventPanGesture).delta * PAN_GESTURE_TO_PX)
	elif event is InputEventKey and _desktop:
		_on_key(event as InputEventKey)


func _on_touch(event: InputEventScreenTouch) -> void:
	var pos := event.position
	var idx := event.index
	if event.pressed:
		if _hit(pos, _primary_centre, PRIMARY_DIAMETER_PT * 0.5) and _primary_index == -1:
			_primary_index = idx
			_fire_pending = true
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
		heading = offset.limit_length(1.0)
		queue_redraw()
		return
	if idx == _primary_index or idx == _secondary_index:
		return
	if not _cam_points.has(idx):
		return
	_cam_points[idx] = event.position
	if _cam_points.size() != 2:
		# One camera touch does nothing, by design (spec section 10).
		return
	var centroid := _camera_centroid()
	var dist := _camera_spread()
	if _cam_dist > 1.0 and dist > 1.0:
		camera_pinch.emit(dist / _cam_dist)
	var delta := centroid - _cam_centroid
	if delta.length_squared() > 0.0:
		camera_orbit.emit(delta)
	_cam_dist = dist
	_cam_centroid = centroid


func _on_key(event: InputEventKey) -> void:
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_SPACE:
		_fire_pending = true


func _process(delta: float) -> void:
	if not _desktop or not _enabled:
		return
	# Keyboard driving, QA only, and only while no touch stick is live.
	if _stick_index == -1:
		var v := Vector2.ZERO
		if Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			v.x -= 1.0
		if Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			v.x += 1.0
		if Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			v.y -= 1.0
		if Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			v.y += 1.0
		heading = v.limit_length(1.0)
	if _secondary_index == -1:
		secondary = Input.is_key_pressed(KEY_SHIFT)

	var orbit := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_Q):
		orbit.x -= KEY_ORBIT_PX_PER_S * delta
	if Input.is_physical_key_pressed(KEY_E):
		orbit.x += KEY_ORBIT_PX_PER_S * delta
	if Input.is_physical_key_pressed(KEY_R):
		orbit.y -= KEY_TILT_PX_PER_S * delta
	if Input.is_physical_key_pressed(KEY_F):
		orbit.y += KEY_TILT_PX_PER_S * delta
	if orbit.length_squared() > 0.0:
		camera_orbit.emit(orbit)

	var zoom := 0.0
	if Input.is_key_pressed(KEY_EQUAL):
		zoom += 1.0
	if Input.is_key_pressed(KEY_MINUS):
		zoom -= 1.0
	if zoom != 0.0:
		camera_pinch.emit(1.0 + KEY_ZOOM_PER_S * zoom * delta)


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
	heading = Vector2.ZERO
	secondary = false
	_fire_pending = false


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if not _enabled:
		return
	_draw_primary()
	_draw_secondary()
	if _stick_index != -1:
		_draw_stick()


func _draw_stick() -> void:
	var base_r := STICK_BASE_PT * _pt
	var knob_r := STICK_KNOB_PT * _pt
	var throw := STICK_THROW_PT * _pt
	draw_circle(_stick_origin, base_r, COL_FILL)
	draw_arc(_stick_origin, base_r, 0.0, TAU, 48, COL_LINE, 3.0 * _pt, true)
	var knob := _stick_origin + heading * throw
	draw_circle(knob, knob_r, COL_KNOB)
	draw_arc(knob, knob_r, 0.0, TAU, 32, COL_LINE, 2.0 * _pt, true)


func _draw_primary() -> void:
	var r := PRIMARY_DIAMETER_PT * 0.5 * _pt
	draw_circle(_primary_centre, r, COL_PRESSED if _primary_index != -1 else COL_FILL)
	draw_arc(_primary_centre, r, 0.0, TAU, 48, COL_LINE, 3.0 * _pt, true)
	_draw_label("FLIP", _primary_centre, 17.0 * _pt)
	_draw_pips(r)


## Gas charges as pips on a ring just outside the primary button.
func _draw_pips(button_r: float) -> void:
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
		var a := start + sweep * t
		var p := _primary_centre + Vector2(cos(a), sin(a)) * ring
		draw_circle(p, pip, COL_PIP_FULL if i < _gas_charges else COL_PIP_SPENT)


func _draw_secondary() -> void:
	var r := SECONDARY_DIAMETER_PT * 0.5 * _pt
	draw_circle(_secondary_centre, r, COL_PRESSED if _secondary_index != -1 else COL_FILL)
	draw_arc(_secondary_centre, r, 0.0, TAU, 40, COL_LINE, 3.0 * _pt, true)
	_draw_label(_secondary_label.to_upper(), _secondary_centre, 14.0 * _pt)


func _draw_label(text: String, centre: Vector2, font_size: float) -> void:
	var font := get_theme_default_font()
	if font == null:
		return
	var px := int(round(font_size))
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, px).x
	var origin := centre + Vector2(-w * 0.5, px * 0.35)
	draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px,
		maxi(int(round(3.0 * _pt)), 1), COL_TEXT_OUTLINE)
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, COL_TEXT)
