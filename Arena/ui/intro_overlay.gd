class_name IntroOverlay extends CanvasLayer
## The fight intro's words (wave B, docs/wave-b-intro-notes.md): one Broadcast lower third
## bottom left naming what the camera is looking at ("SPIKE PATCH" over "RISES EVERY SIX
## SECONDS"), and a small skip hint bottom right. Every colour, size and shape comes out of
## Arena/ui/broadcast.gd; no edge strokes, rims or line accents (owner rule 2026-09-21):
## a hazard card is told apart by a danger wash in its fill, nothing else.
##
## Presentation only, PROCESS_MODE_ALWAYS (it animates while the simulation is held).

const REF_SIZE_PT := Vector2(1206.0, 556.0)
const PAD_PT := 22.0
## The card's baseline sits this far above the bottom safe edge.
const LIFT_PT := 34.0
const SKIP_TEXT := "TAP TO SKIP"
const SKIP_TEXT_PAD := "ANY BUTTON TO SKIP"

var _safe := {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
var _canvas: Control = null
var _title := ""
var _sub := ""
var _danger := false
## -1 off the left edge, 0 home. Out goes back the way it came.
var _slide := -1.0
var _want := -1.0
var _alpha := 0.0
var _skip_on := false
var _skip_alpha := 0.0
var _skip_delay := 0.0


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.name = "IntroCanvas"
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_on_draw)
	add_child(_canvas)


func set_safe_area(px: Dictionary) -> void:
	for key in ["left", "top", "right", "bottom"]:
		_safe[key] = float(px.get(key, 0.0))


## A new card. If one is up it is swapped in place (the words change, the plate stays).
func show_card(title: String, sub: String, danger: bool) -> void:
	var was_up := _want >= 0.0 and _slide > -0.5
	_title = title
	_sub = sub
	_danger = danger
	_want = 0.0
	if not was_up:
		_slide = -1.0
	else:
		# Swapped in place: a short re-entry so the new words land rather than blink.
		_slide = minf(_slide, -0.3)
	_alpha = 1.0
	_dirty()


func hide_card() -> void:
	_want = -1.0
	_dirty()


func card_visible() -> bool:
	return _want >= 0.0 and _title != ""


func card_title() -> String:
	return _title if card_visible() else ""


func card_sub() -> String:
	return _sub if card_visible() else ""


func set_skip_hint(on: bool) -> void:
	_skip_on = on
	if on:
		_skip_delay = 0.5
	_dirty()


func skip_hint_visible() -> bool:
	return _skip_on


func _process(delta: float) -> void:
	var moved := false
	var speed := 1.0 / (Broadcast.ENTER_S if _want > _slide else Broadcast.EXIT_S)
	var next := move_toward(_slide, _want, delta * speed)
	if next != _slide:
		_slide = next
		moved = true
	if _skip_delay > 0.0:
		_skip_delay -= delta
	var skip_want := 1.0 if _skip_on and _skip_delay <= 0.0 else 0.0
	var s := move_toward(_skip_alpha, skip_want, delta * 4.0)
	if s != _skip_alpha:
		_skip_alpha = s
		moved = true
	if moved:
		_dirty()


func _dirty() -> void:
	if _canvas != null:
		_canvas.queue_redraw()


func _pt(size: Vector2) -> float:
	return maxf(minf(size.x / REF_SIZE_PT.x, size.y / REF_SIZE_PT.y), 0.1)


func _on_draw() -> void:
	var vp := _canvas.get_viewport()
	if vp == null:
		return
	var size := vp.get_visible_rect().size
	var pt := _pt(size)
	if _title != "" and _slide > -1.0:
		_draw_card(size, pt)
	if _skip_alpha > 0.01:
		_draw_skip(size, pt)


func _draw_card(size: Vector2, pt: float) -> void:
	var title_font := Broadcast.font_display()
	var sub_font := Broadcast.font_label()
	var title_px := maxi(int(round(Broadcast.TITLE_PT * pt)), 12)
	var sub_px := maxi(int(round(Broadcast.LABEL_PT * pt)), 9)
	var pad := Broadcast.PANEL_PAD * pt
	var title_w := Broadcast.text_width(title_font, _title, title_px)
	var sub_w := Broadcast.text_width(sub_font, _sub, sub_px)
	var h := pad * 1.6 + title_px * 0.9 + (sub_px * 1.35 if _sub != "" else 0.0)
	# An upright plate (wave E, owner rule: no lean, no cut corner), padded the same both sides.
	var w := maxf(title_w, sub_w) + pad * 2.0
	var left := float(_safe["left"]) + PAD_PT * pt
	var bottom := size.y - float(_safe["bottom"]) - LIFT_PT * pt
	var ease_k := 1.0 - pow(1.0 - clampf(_slide + 1.0, 0.0, 1.0), 4.0)
	var x := lerpf(-(w + left), left, ease_k)
	var rect := Rect2(Vector2(x, bottom - h), Vector2(w, h))
	# A hazard's card is the blueprint danger plate; every other card the blue one.
	Broadcast.draw_lower_third(_canvas, rect, pt, true, _alpha,
		Broadcast.PLATE_DANGER if _danger else Broadcast.PLATE)
	var tx := rect.position.x + pad
	var title_base := rect.position.y + pad * 0.8 + title_px * 0.82
	Broadcast.draw_text(_canvas, title_font, Vector2(tx, title_base), _title, title_px,
		Color(Broadcast.TYPE, _alpha))
	if _sub != "":
		Broadcast.draw_text(_canvas, sub_font, Vector2(tx, title_base + sub_px * 1.45),
			_sub, sub_px, Color(Broadcast.TYPE if _danger else Broadcast.TYPE_DIM, _alpha))


func _draw_skip(size: Vector2, pt: float) -> void:
	var font := Broadcast.font_label()
	var px := maxi(int(round(Broadcast.LABEL_PT * pt)), 9)
	var text := SKIP_TEXT_PAD if not Input.get_connected_joypads().is_empty() else SKIP_TEXT
	var w := Broadcast.text_width(font, text, px) + Broadcast.PANEL_PAD * pt * 1.4
	var h := px * 2.0
	var right := size.x - float(_safe["right"]) - PAD_PT * pt
	var bottom := size.y - float(_safe["bottom"]) - LIFT_PT * pt
	var rect := Rect2(Vector2(right - w, bottom - h), Vector2(w, h))
	Broadcast.draw_pill(_canvas, rect, pt, _skip_alpha)
	Broadcast.draw_text(_canvas, font, Vector2(rect.position.x + w * 0.5, rect.position.y + h * 0.5 + px * 0.36),
		text, px, Color(Broadcast.TYPE_DIM, _skip_alpha), HORIZONTAL_ALIGNMENT_CENTER)
