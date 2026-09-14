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
const TIMER_PT := 40.0
const SCRAP_PT := 32.0
const NAMES_PT := 18.0
const KO_PT := 34.0
const READOUT_PT := 22.0
const COUNTDOWN_PT := 96.0
const RESULT_TITLE_PT := 58.0
const RESULT_WINNER_PT := 26.0
## Pad hints, shown where the on screen buttons are when a controller is driving.
const HINT_PT := 16.0

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


func show_ko_count(seconds_left: int, bot_name: String) -> void:
	_build()
	_ko.text = "%s\nKNOCKOUT COUNT %d" % [bot_name.to_upper(), maxi(seconds_left, 0)]
	_ko.visible = true


func hide_ko_count() -> void:
	_build()
	_ko.visible = false


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
	if c.has_signal("pad_present_changed") \
			and not c.is_connected("pad_present_changed", _on_pad_present_changed):
		c.connect("pad_present_changed", _on_pad_present_changed)
	if c.has_signal("secondary_label_changed") \
			and not c.is_connected("secondary_label_changed", _on_secondary_label_changed):
		c.connect("secondary_label_changed", _on_secondary_label_changed)
	if c.has_method("secondary_label"):
		_on_secondary_label_changed(str(c.call("secondary_label")))
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
	set_pad_hints(connected)


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
			_result_winner, _hint_primary, _hint_secondary]:
		var px := int(round(float(l.get_meta("size_pt", 20.0)) * _pt))
		l.add_theme_font_size_override("font_size", px)
		l.add_theme_constant_override("outline_size", maxi(int(round(px * 0.14)), 2))

	var pad := PAD_PT * _pt
	var left := float(_safe["left"]) + pad
	var right := float(_safe["right"]) + pad
	var top := float(_safe["top"]) + pad
	var bottom := float(_safe["bottom"]) + pad

	var timer_h := TIMER_PT * 1.3 * _pt
	_band(_names, top, timer_h, left, right)
	_band(_timer, top, timer_h, left, right)
	_band(_scrap, top, timer_h, left, right)

	var readout_h := READOUT_PT * 1.6 * _pt
	_band(_readout, s.y - bottom - readout_h, readout_h, left, right)

	# Centre furniture. The knockout count sits a little above the middle so it does
	# not land on top of the two bots at the default framing.
	var ko_h := KO_PT * 3.0 * _pt
	_band(_ko, s.y * 0.5 - ko_h * 0.5 - 40.0 * _pt, ko_h, left, right)
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


func _on_pad_present_changed(present: bool) -> void:
	set_pad_hints(present)


func _on_secondary_label_changed(label: String) -> void:
	_build()
	_hint_action_secondary = label.to_upper()
	_compose_hints()


func _refresh_pad() -> void:
	if _controls == null or not is_instance_valid(_controls):
		_controls = _find_controls()
	var present := not Input.get_connected_joypads().is_empty()
	if _controls != null and _controls.has_method("pad_present"):
		present = bool(_controls.call("pad_present"))
	set_pad_hints(present)


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
