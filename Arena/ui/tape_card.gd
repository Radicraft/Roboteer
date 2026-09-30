class_name TapeCardOverlay extends CanvasLayer
## The tale of the tape on screen (wave D walk-outs, docs/wave-d-walkout-notes.md).
##
## FULL: the card for a machine walking out of its gate, a sheet of blueprint paper on the
## right of the picture (the machine is framed on the left): what it is called, who built
## it, its mass, drive and weapon, two or three whole-machine numbers, the head to head, and
## a STRENGTH and a WEAKNESS line. COMPACT: the house bot's card when it comes out of its
## corner mid-fight, smaller, top left under the player's name, no numbers.
##
## Blueprint direction A (docs/look/menus-blueprint.html, the menus' own plate): a square,
## upright sheet of blueprint blue with its graph paper, white type, Blueprint faces (Saira
## Stencil One, Saira Semi Condensed, B612 Mono for numbers). No edge, stroke, bar, skew or
## coloured rule (owner rule 2026-09-21): dividers are the neutral 1 px rule between sections.
##
## Presentation only, PROCESS_MODE_ALWAYS (it animates while the simulation is held).

const REF_SIZE_PT := Vector2(1206.0, 556.0)
## Blueprint plate: rgba(14, 58, 140, 0.9), the menus' `--plate`.
const PLATE := Color(0.0549, 0.2275, 0.5490, 0.92)
const GRID_MINOR := Color(1, 1, 1, 0.06)
const GRID_MAJOR := Color(1, 1, 1, 0.12)
const DIM := Color(1, 1, 1, 0.66)
const RULE := Color(1, 1, 1, 0.13)
const DANGER := Color(1.0, 0.478, 0.4)       # #FF7A66, readable on the blue
## The grid is 10 iOS pt, in the arena's reference units.
const GRID_STEP := 10.0 * Broadcast.PT_PER_IOS

const MARGIN := 22.0
const FULL_W := 452.0
const COMPACT_W := 360.0
const PAD := 18.0

var _safe := {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
var _canvas: Control = null
var _card: Dictionary = {}
var _compact := false
## 0 off the right edge, 1 home.
var _slide := 0.0
var _want := 0.0
var _hold_s := -1.0


func _ready() -> void:
	layer = 61
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.name = "TapeCanvas"
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_on_draw)
	add_child(_canvas)


func set_safe_area(px: Dictionary) -> void:
	for key in ["left", "top", "right", "bottom"]:
		_safe[key] = float(px.get(key, 0.0))


## Put a card up. `hold_s` > 0 takes it down by itself after that long (the house bot's).
func show_card(card: Dictionary, compact: bool = false, hold_s: float = -1.0) -> void:
	var swap := _want > 0.5 and _slide > 0.5 and not _card.is_empty()
	_card = card.duplicate(true)
	_compact = compact
	_want = 1.0
	_hold_s = hold_s
	if swap:
		_slide = minf(_slide, 0.55)
	_dirty()


func hide_card() -> void:
	_want = 0.0
	_hold_s = -1.0
	_dirty()


## Straight off, no exit (a skip, the end of the intro).
func clear() -> void:
	_want = 0.0
	_slide = 0.0
	_hold_s = -1.0
	_card = {}
	_dirty()


func card_visible() -> bool:
	return _want > 0.5 and not _card.is_empty()


func card() -> Dictionary:
	return _card if card_visible() else {}


func is_compact() -> bool:
	return _compact


## The card's rectangle on screen right now, in viewport pixels (tests: it must fit).
func card_rect() -> Rect2:
	if _canvas == null or _card.is_empty():
		return Rect2()
	var size := _canvas.get_viewport().get_visible_rect().size if _canvas.get_viewport() != null else REF_SIZE_PT
	var layout := _layout(size, _pt(size))
	return layout["rect"]


func _process(delta: float) -> void:
	if _hold_s > 0.0 and _slide >= 0.999:
		_hold_s -= delta
		if _hold_s <= 0.0:
			hide_card()
	var speed := 1.0 / (Broadcast.ENTER_S if _want > _slide else Broadcast.EXIT_S)
	var next := move_toward(_slide, _want, delta * speed)
	if next != _slide:
		_slide = next
		_dirty()


func _dirty() -> void:
	if _canvas != null:
		_canvas.queue_redraw()


func _pt(size: Vector2) -> float:
	return maxf(minf(size.x / REF_SIZE_PT.x, size.y / REF_SIZE_PT.y), 0.1)


# ---------------------------------------------------------------- layout

## Every row of the card as a list of draw steps, measured at `pt`, and the card's rectangle.
func _layout(size: Vector2, pt: float) -> Dictionary:
	var w := (COMPACT_W if _compact else FULL_W) * pt
	w = minf(w, size.x * (0.40 if not _compact else 0.34))
	var pad := PAD * pt
	var inner := w - pad * 2.0
	var rows: Array = []      # [kind, data, height]
	var label_px := _px(13.0, pt)
	var name_px := _px(40.0 if not _compact else 30.0, pt)
	var sub_px := _px(17.0, pt)
	var body_px := _px(18.0 if not _compact else 16.0, pt)
	var val_px := _px(18.0, pt)
	var display := Broadcast.font_display()
	var ui := Broadcast.font_label()
	var body := Broadcast.font_body()
	rows.append(["label", str(_card.get("label", "")), label_px * 1.35])
	# The name shrinks to fit the width, never below 70 %.
	var nm := str(_card.get("name", "")).to_upper()
	var npx := name_px
	while npx > int(name_px * 0.7) and Broadcast.text_width(display, nm, npx) > inner:
		npx -= 1
	rows.append(["name", [nm, npx], npx * 1.02])
	var who := str(_card.get("roboteer", ""))
	if who != "" and not _compact:
		rows.append(["sub", who, sub_px * 1.45])
	if not _compact:
		rows.append(["gap", null, 6.0 * pt])
		rows.append(["rule", null, 12.0 * pt])
		var spec := [["MASS", str(_card.get("mass", "")), true], ["DRIVE", str(_card.get("drive", "")), false],
			["WEAPON", str(_card.get("weapon", "")), false]]
		rows.append(["cells", spec, label_px * 1.3 + val_px * 1.3])
		var stats: Array = []
		for s in (_card.get("stats", []) as Array).slice(0, 3):
			stats.append([str((s as Dictionary).get("label", "")), str((s as Dictionary).get("value", "")), true])
		if not stats.is_empty():
			rows.append(["gap", null, 6.0 * pt])
			rows.append(["cells", stats, label_px * 1.3 + val_px * 1.3])
		var record := str(_card.get("record", ""))
		if record != "":
			rows.append(["gap", null, 6.0 * pt])
			rows.append(["record", record, maxf(label_px, val_px) * 1.4])
	if not _compact:
		rows.append(["gap", null, 4.0 * pt])
		rows.append(["rule", null, 12.0 * pt])
	else:
		rows.append(["gap", null, 4.0 * pt])
	for pair in [["STRENGTH", "strength", DIM], ["WEAKNESS", "weakness", DANGER]]:
		var text := str(_card.get(pair[1], ""))
		if text == "":
			continue
		var lines := _wrap(body, text, body_px, inner)
		rows.append(["line_label", [pair[0], pair[2]], label_px * 1.3])
		rows.append(["lines", lines, body_px * 1.22 * float(lines.size()) + 6.0 * pt])
	var h := pad * 2.0
	for r in rows:
		h += float(r[2])
	var left: float
	var top: float
	if _compact:
		# Mid-fight: under the player's name plate at the top LEFT. The right side already has
		# the house bot's name under the opponent's plate, and the buttons below it.
		left = float(_safe["left"]) + MARGIN * pt
		top = float(_safe["top"]) + 84.0 * pt
	else:
		# Centred in the height above the skip hint, on the right.
		left = size.x - float(_safe["right"]) - MARGIN * pt - w
		var avail := size.y - float(_safe["top"]) - float(_safe["bottom"]) - 70.0 * pt
		top = float(_safe["top"]) + maxf((avail - h) * 0.5, MARGIN * pt * 0.5)
	return {"rect": Rect2(Vector2(left, top), Vector2(w, h)), "rows": rows, "pad": pad,
		"inner": inner, "label_px": label_px, "sub_px": sub_px, "body_px": body_px, "val_px": val_px,
		"fonts": [display, ui, body, Broadcast.font_numerals()]}


static func _px(v: float, pt: float) -> int:
	return maxi(int(round(v * pt)), 9)


## Greedy word wrap to `width` pixels.
static func _wrap(font: Font, text: String, px: int, width: float) -> Array:
	var out: Array = []
	var line := ""
	for word in text.split(" ", false):
		var trial := word if line == "" else line + " " + word
		if line != "" and Broadcast.text_width(font, trial, px) > width:
			out.append(line)
			line = word
		else:
			line = trial
	if line != "":
		out.append(line)
	return out


# ---------------------------------------------------------------- draw

func _on_draw() -> void:
	if _card.is_empty() or _slide <= 0.001:
		return
	var vp := _canvas.get_viewport()
	if vp == null:
		return
	var size := vp.get_visible_rect().size
	var pt := _pt(size)
	var lay := _layout(size, pt)
	var rect: Rect2 = lay["rect"]
	var k := 1.0 - pow(1.0 - clampf(_slide, 0.0, 1.0), 4.0)
	# In from the edge it belongs to: the walk-out card from the right, the house bot's from the left.
	if _compact:
		rect.position.x -= (1.0 - k) * (rect.size.x + MARGIN * pt + float(_safe["left"]))
	else:
		rect.position.x += (1.0 - k) * (rect.size.x + MARGIN * pt + float(_safe["right"]))
	var alpha := clampf(_slide * 1.6, 0.0, 1.0)
	_draw_plate(rect, pt, alpha)
	var fonts: Array = lay["fonts"]
	var display: Font = fonts[0]
	var ui: Font = fonts[1]
	var body: Font = fonts[2]
	var mono: Font = fonts[3]
	var pad := float(lay["pad"])
	var inner := float(lay["inner"])
	var x := rect.position.x + pad
	var y := rect.position.y + pad
	var label_px := int(lay["label_px"])
	var val_px := int(lay["val_px"])
	var white := Color(1, 1, 1, alpha)
	var dim := Color(DIM, DIM.a * alpha)
	for r in lay["rows"]:
		var kind := str(r[0])
		var h := float(r[2])
		match kind:
			"label":
				Broadcast.draw_text(_canvas, ui, Vector2(x, y + label_px), str(r[1]), label_px, dim)
			"name":
				var nm: Array = r[1]
				Broadcast.draw_text(_canvas, display, Vector2(x, y + int(nm[1]) * 0.86), str(nm[0]), int(nm[1]), white)
			"sub":
				Broadcast.draw_text(_canvas, ui, Vector2(x, y + int(lay["sub_px"])), str(r[1]), int(lay["sub_px"]),
					Color(1, 1, 1, 0.86 * alpha))
			"rule":
				var ry := roundf(y + h * 0.5)
				_canvas.draw_line(Vector2(x, ry), Vector2(x + inner, ry), Color(RULE, RULE.a * alpha), maxf(pt, 1.0))
			"cells":
				var cells: Array = r[1]
				var cw := inner / float(maxi(cells.size(), 1))
				for i in cells.size():
					var c: Array = cells[i]
					var cx := x + cw * float(i)
					Broadcast.draw_text(_canvas, ui, Vector2(cx, y + label_px), str(c[0]), label_px, dim)
					# Saira for the numbers too: B612 Mono opens a gap after "." (owner call owed).
					var vfont: Font = ui
					var v := str(c[1]) if bool(c[2]) else str(c[1]).to_upper()
					var vpx := val_px
					while vpx > int(val_px * 0.7) and Broadcast.text_width(vfont, v, vpx) > cw - 6.0 * pt:
						vpx -= 1
					Broadcast.draw_text(_canvas, vfont, Vector2(cx, y + label_px * 1.3 + vpx * 1.02), v, vpx, white)
			"record":
				Broadcast.draw_text(_canvas, ui, Vector2(x, y + label_px * 1.15), "HEAD TO HEAD", label_px, dim)
				var lw := Broadcast.text_width(ui, "HEAD TO HEAD", label_px) + 12.0 * pt
				var rec := str(r[1]).to_upper()
				var rpx := val_px
				while rpx > int(val_px * 0.7) and Broadcast.text_width(ui, rec, rpx) > inner - lw:
					rpx -= 1
				Broadcast.draw_text(_canvas, ui, Vector2(x + lw, y + label_px * 1.15), rec, rpx, white)
			"line_label":
				var pair: Array = r[1]
				var col: Color = pair[1]
				Broadcast.draw_text(_canvas, ui, Vector2(x, y + label_px), str(pair[0]), label_px, Color(col, col.a * alpha))
			"lines":
				var body_px := int(lay["body_px"])
				var ly := y + body_px * 0.95
				for line in r[1]:
					Broadcast.draw_text(_canvas, body, Vector2(x, ly), str(line), body_px, white)
					ly += body_px * 1.22
		y += h


## The sheet: the plate and its graph paper, clipped to the plate. No edge.
func _draw_plate(rect: Rect2, pt: float, alpha: float) -> void:
	_canvas.draw_rect(rect, Color(PLATE, PLATE.a * alpha))
	var step := GRID_STEP * pt
	if step < 3.0:
		return
	var n := 0
	var gx := rect.position.x
	while gx < rect.end.x:
		var c := GRID_MAJOR if n % 5 == 0 else GRID_MINOR
		_canvas.draw_rect(Rect2(Vector2(roundf(gx), rect.position.y), Vector2(1.0, rect.size.y)), Color(c, c.a * alpha))
		gx += step
		n += 1
	n = 0
	var gy := rect.position.y
	while gy < rect.end.y:
		var c := GRID_MAJOR if n % 5 == 0 else GRID_MINOR
		_canvas.draw_rect(Rect2(Vector2(rect.position.x, roundf(gy)), Vector2(rect.size.x, 1.0)), Color(c, c.a * alpha))
		gy += step
		n += 1
