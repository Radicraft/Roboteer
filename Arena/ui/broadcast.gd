class_name Broadcast extends RefCounted
## The Broadcast design system, Godot half. docs/design-system.md sections 1 to 4.
##
## One place for the colours, the type and the drawn shapes of the fight feed. hud.gd and
## controls.gd draw nothing from raw numbers: every panel, lower third, score bug, rule,
## ticker and bar on screen comes out of this file, so the feed and the Swift screens can
## only drift if the token changes here.
##
## UNITS. The design system quotes points on a 402 pt tall phone. The arena's own design
## space is 1206 x 556 (FightHud.REF_SIZE_PT and FightControls.REF_SIZE_PT), which is the
## same screen 1.383 times over, so every size below is the design system's point value
## times PT_PER_IOS_PT. Drawing code then multiplies by the HUD's `_pt`, which is 1.0 at
## the design size and 2.0 on the phone.
##
## RENDERERS. Nothing here is a shader or a texture: every shape is draw_colored_polygon,
## draw_rect, draw_line or draw_string, so the feed is identical on Forward+ (device),
## gl_compatibility (simulator) and the dummy renderer (the headless suite).

## 556 / 402: the arena's design units per iOS point.
const PT_PER_IOS := 1.383

# ---------------------------------------------------------------- 1. tokens (colours)

## #07090C. Page and fight backdrop behind glass.
const INK := Color(0.0275, 0.0353, 0.0471)
## #0E1218 at 82 %. Panel fill.
const GLASS := Color(0.0549, 0.0706, 0.0941, 0.82)
## The same fill over the live arena, where the frame behind it is moving.
const GLASS_LIVE := Color(0.0549, 0.0706, 0.0941, 0.62)
## #FFFFFF at 10 %. The 1 px inner edge on every panel, top and left only.
const GLASS_EDGE := Color(1.0, 1.0, 1.0, 0.10)
## #35D6F0. Hairline rules, selection sweep, focus ring, the score bug rim.
const LINE := Color(0.2078, 0.8392, 0.9412)
## The same at 45 %: secondary rules and dividers.
const LINE_DIM := Color(0.2078, 0.8392, 0.9412, 0.45)
## #F4F6F8. Primary text.
const TYPE := Color(0.9569, 0.9647, 0.9725)
## #9CA6B2. Secondary text, labels, units.
const TYPE_DIM := Color(0.6118, 0.6510, 0.6980)
## #F0B23A. Scrap numbers and the purse. The only warm chrome colour.
const SCRAP := Color(0.9412, 0.6980, 0.2275)
## #E5483C. Damage, the zone warning, losing states, quit.
const DANGER := Color(0.8980, 0.2824, 0.2353)
## #5BE38F. Won states only, never chrome.
const WIN := Color(0.3569, 0.8902, 0.5608)

# ---------------------------------------------------------------- 1. tokens (type)

## Display, 800 italic, CAPS. 44 iOS pt.
const DISPLAY_PT := 60.0
## Title, 800 italic, CAPS. 28 iOS pt.
const TITLE_PT := 39.0
## Button, 700, CAPS. 17 iOS pt.
const BUTTON_PT := 23.0
## Label, 700, CAPS. 12 iOS pt, and the legibility floor is 11.
const LABEL_PT := 17.0
## Body, 500, sentence case. 15 iOS pt.
const BODY_PT := 21.0
## Numerals, 700 tabular. 22 iOS pt.
const NUMERAL_PT := 30.0
## The fight clock's numerals. 34 iOS pt.
const CLOCK_PT := 47.0
## Nothing labelled ever goes below this (the legibility floor, 11 iOS pt).
const TYPE_FLOOR_PT := 15.0

# ---------------------------------------------------------------- 1. tokens (spacing)

## The 4 pt grid.
const GRID := 5.5
## Panel padding, 12 iOS pt.
const PANEL_PAD := 17.0
## Gap between panels, 8 iOS pt.
const GAP := 11.0
## Screen gutter, 16 iOS pt, on top of the safe area.
const GUTTER := 22.0
## Corner cuts, 10 iOS pt. Every panel, the same angle.
const CUT := 14.0
## The lower third's lean, always to the right.
const SKEW_DEG := 12.0
## The leading bar on a lower third, 3 iOS pt.
const BAR := 4.0
## The ticker strip's height, 22 iOS pt.
const TICKER_H := 30.0
## The condition bar's thickness, 3 iOS pt.
const CONDITION_H := 4.0
## A condition bar below this is drawn in `danger`.
const CONDITION_DANGER := 0.25
## The zone warning's inner edge glow, 6 iOS pt.
const EDGE_GLOW := 8.0

# ---------------------------------------------------------------- motion

## A lower third enters from its own edge, and leaves faster than it arrives.
const ENTER_S := 0.25
const EXIT_S := 0.18
## The ENDGAME sting: slam in from the left, hold, leave right.
const SLAM_S := 0.12
const SLAM_HOLD_S := 1.2
const SLAM_OUT_S := 0.18
## Numbers (scrap, purse) count over this.
const COUNT_S := 0.4

# ---------------------------------------------------------------- the font

## Barlow Condensed, bundled by agent V1 (SIL OFL, `Arena/assets/fonts/OFL.txt`). These
## are the files that are really there; a build that somehow has none of them falls back
## to the engine's own face rather than drawing nothing, and `fonts_found()` says which
## way it went.
const FONT_DIR := "res://assets/fonts"
const THEME_PATH := "res://ui/broadcast_theme.tres"

## The face per role. Display is the 800 italic, label the 700, body the 500.
const FONT_FILES := {
	"display": "BarlowCondensed-ExtraBoldItalic.ttf",
	"label": "BarlowCondensed-Bold.ttf",
	"body": "BarlowCondensed-Medium.ttf",
}

static var _fonts: Dictionary = {}
static var _theme: Theme = null
static var _glyphs: Dictionary = {}


## 800 italic: the display and title faces, and the countdown.
static func font_display() -> Font:
	return _font("display")


## 700: labels, buttons and the tabular numerals.
static func font_label() -> Font:
	return _font("label")


## 500: body sentences.
static func font_body() -> Font:
	return _font("body")


## True when the real face was found for that role. The notes and the headless test read
## this rather than guessing.
static func fonts_found() -> Dictionary:
	var out := {}
	for role: String in FONT_FILES.keys():
		out[role] = _font(role) != null
	return out


static func _font(role: String) -> Font:
	if _fonts.has(role):
		return _fonts[role]
	var found: Font = null
	var path := "%s/%s" % [FONT_DIR, str(FONT_FILES.get(role, ""))]
	if ResourceLoader.exists(path):
		found = load(path) as Font
	_fonts[role] = found
	return found


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var built: Theme = null
	if ResourceLoader.exists(THEME_PATH):
		built = load(THEME_PATH) as Theme
	if built == null:
		# Only if the resource itself is gone: the tokens still have to reach the screen.
		built = Theme.new()
		built.default_font_size = int(LABEL_PT)
		built.set_color("font_color", "Label", TYPE)
		built.set_color("font_outline_color", "Label", INK)
		built.set_constant("outline_size", "Label", 0)
	if built.default_font == null:
		built.default_font = font_label()
	_theme = built
	return built


## A weapon or utility glyph from the asset manifest (docs/design-system.md section 6),
## single colour on a 64 px grid, so the caller modulates it to `type`. Null when there is
## no file for that one (the pivot), in which case the caller draws the word instead.
## `kind` is the PART id the file is named for, not the weapon's kind: see
## FightControls.weapon_glyph_id().
static func glyph(prefix: String, kind: String) -> Texture2D:
	var key := "%s_%s" % [prefix, kind]
	if _glyphs.has(key):
		return _glyphs[key]
	var found: Texture2D = null
	var path := "res://assets/ui/glyph_%s_%s.svg" % [prefix, kind]
	if ResourceLoader.exists(path):
		found = load(path) as Texture2D
	_glyphs[key] = found
	return found


## Tests and a fresh run in one process: forget the loaded font, theme and glyphs.
static func forget() -> void:
	_fonts.clear()
	_glyphs.clear()
	_theme = null


# ---------------------------------------------------------------- 2. shapes

## A panel's outline: a rectangle with ONE cut corner, top right, at CUT. Never a
## rounded rectangle.
static func panel_points(rect: Rect2, pt: float) -> PackedVector2Array:
	var p := rect.position
	var s := rect.size
	var c := minf(CUT * pt, minf(s.x, s.y) * 0.5)
	return PackedVector2Array([
		p,
		p + Vector2(s.x - c, 0.0),
		p + Vector2(s.x, c),
		p + Vector2(s.x, s.y),
		p + Vector2(0.0, s.y),
	])


## The same points sheared SKEW_DEG about the bottom edge, leaning right.
static func skew(points: PackedVector2Array, bottom: float, lean: float = 1.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	var t := tan(deg_to_rad(SKEW_DEG)) * lean
	for p: Vector2 in points:
		out.append(Vector2(p.x + (bottom - p.y) * t, p.y))
	return out


## Panel: `glass` fill, a `glassEdge` inner edge along the top and the left, and a `line`
## hairline along the bottom.
static func draw_panel(ci: CanvasItem, rect: Rect2, pt: float, alpha: float = 1.0,
		fill: Color = GLASS) -> void:
	_draw_shape(ci, panel_points(rect, pt), pt, alpha, fill)


## Lower third: a panel skewed 12 degrees with a 3 pt `line` bar on its leading edge.
## `leading_left` puts the bar on the left, which is where a left hand panel enters from;
## the right hand panels carry it on the right.
static func draw_lower_third(ci: CanvasItem, rect: Rect2, pt: float, leading_left: bool,
		alpha: float = 1.0, fill: Color = GLASS, bar_colour: Color = LINE) -> void:
	var bottom := rect.position.y + rect.size.y
	var points := skew(panel_points(rect, pt), bottom)
	_draw_shape(ci, points, pt, alpha, fill)
	var w := BAR * pt
	var bar := Rect2(rect.position, Vector2(w, rect.size.y))
	if not leading_left:
		bar.position.x = rect.position.x + rect.size.x - w
	var bar_points := skew(PackedVector2Array([
		bar.position,
		bar.position + Vector2(bar.size.x, 0.0),
		bar.position + bar.size,
		bar.position + Vector2(0.0, bar.size.y),
	]), bottom)
	ci.draw_colored_polygon(bar_points, Color(bar_colour, bar_colour.a * alpha))


## Score bug: a small NON skewed panel with a `line` rim. Numerals live inside it, a
## label above. Used for the clock, the scrap and the tier badge.
static func draw_score_bug(ci: CanvasItem, rect: Rect2, pt: float, alpha: float = 1.0,
		fill: Color = GLASS, rim: Color = LINE) -> void:
	var points := panel_points(rect, pt)
	ci.draw_colored_polygon(points, Color(fill, fill.a * alpha))
	_draw_outline(ci, points, Color(rim, rim.a * alpha), maxf(1.0 * pt, 1.0))


## Rule: 1 px `lineDim`, never thicker, never a box.
static func draw_rule(ci: CanvasItem, from: Vector2, to: Vector2, pt: float,
		alpha: float = 1.0, colour: Color = LINE_DIM) -> void:
	ci.draw_line(from, to, Color(colour, colour.a * alpha), maxf(1.0 * pt, 1.0), true)


## Ticker: a full width strip on `ink` at 90 %, with a `line` hairline along its top so
## it reads as a plate rather than as a shadow.
static func draw_ticker(ci: CanvasItem, rect: Rect2, pt: float, alpha: float = 1.0,
		flash: float = 0.0) -> void:
	ci.draw_rect(rect, Color(INK, 0.90 * alpha))
	if flash > 0.001:
		ci.draw_rect(rect, Color(LINE, 0.28 * flash * alpha))
	draw_rule(ci, rect.position, rect.position + Vector2(rect.size.x, 0.0), pt, alpha, LINE_DIM)


## A condition bar: a rule that empties. `fraction` 1 is undamaged, and anything under
## CONDITION_DANGER is drawn in `danger` whatever colour was asked for.
static func draw_condition(ci: CanvasItem, rect: Rect2, fraction: float, colour: Color,
		alpha: float = 1.0, right_to_left: bool = false) -> void:
	ci.draw_rect(rect, Color(LINE_DIM, 0.22 * alpha))
	var f := clampf(fraction, 0.0, 1.0)
	if f <= 0.001:
		return
	var use := DANGER if f < CONDITION_DANGER else colour
	var filled := Rect2(rect.position, Vector2(rect.size.x * f, rect.size.y))
	if right_to_left:
		filled.position.x = rect.position.x + rect.size.x - filled.size.x
	ci.draw_rect(filled, Color(use, use.a * alpha))


## A glass pill for a coach callout: the panel shape at the size of the words. Sized by
## the caller, because only the caller knows how wide the string came out.
static func draw_pill(ci: CanvasItem, rect: Rect2, pt: float, alpha: float = 1.0) -> void:
	_draw_shape(ci, panel_points(rect, pt), pt, alpha, GLASS_LIVE)


## The zone warning: a `danger` inner edge glow on the whole frame. Four bands per side,
## brightest at the edge, so it reads as a glow without a shader.
static func draw_edge_glow(ci: CanvasItem, rect: Rect2, pt: float, alpha: float,
		colour: Color = DANGER) -> void:
	var band := EDGE_GLOW * pt
	var steps := 4
	for i in steps:
		var t := float(i) / float(steps)
		var depth := band * (1.0 + t * 2.0)
		var a := alpha * (1.0 - t) * 0.5
		if a <= 0.002:
			continue
		var c := Color(colour, colour.a * a)
		var left := rect.position.x
		var top := rect.position.y
		var right := rect.position.x + rect.size.x
		var bottom := rect.position.y + rect.size.y
		ci.draw_rect(Rect2(Vector2(left, top), Vector2(right - left, depth)), c)
		ci.draw_rect(Rect2(Vector2(left, bottom - depth), Vector2(right - left, depth)), c)
		ci.draw_rect(Rect2(Vector2(left, top), Vector2(depth, bottom - top)), c)
		ci.draw_rect(Rect2(Vector2(right - depth, top), Vector2(depth, bottom - top)), c)


## A glass disc, the touch furniture's panel: the same fill and the same rim weights as a
## panel, in the one round shape the system allows (a thumb is round).
static func draw_disc(ci: CanvasItem, centre: Vector2, radius: float, pt: float,
		alpha: float = 1.0, fill: Color = GLASS_LIVE, rim: Color = LINE) -> void:
	ci.draw_circle(centre, radius, Color(fill, fill.a * alpha))
	ci.draw_arc(centre, radius, 0.0, TAU, 56, Color(rim, rim.a * alpha), maxf(1.5 * pt, 1.0), true)


# ---------------------------------------------------------------- text

## One string, from the tokens. `align` says which end of `at` the string sits on, and
## `at` is the BASELINE point, the same convention draw_string uses.
static func draw_text(ci: CanvasItem, font: Font, at: Vector2, text: String, px: int,
		colour: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, outline_px: int = 0) -> void:
	if font == null or text.is_empty():
		return
	var origin := at
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x
	match align:
		HORIZONTAL_ALIGNMENT_RIGHT:
			origin.x -= w
		HORIZONTAL_ALIGNMENT_CENTER:
			origin.x -= w * 0.5
		_:
			pass
	if outline_px > 0:
		ci.draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px,
			outline_px, Color(INK, 0.92 * colour.a))
	ci.draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, colour)


static func text_width(font: Font, text: String, px: int) -> float:
	if font == null:
		return 0.0
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x


# ---------------------------------------------------------------- internals

static func _draw_shape(ci: CanvasItem, points: PackedVector2Array, pt: float, alpha: float,
		fill: Color) -> void:
	ci.draw_colored_polygon(points, Color(fill, fill.a * alpha))
	if points.size() < 4:
		return
	var hair := maxf(1.0 * pt, 1.0)
	# The inner edge, top and left only.
	var edge := Color(GLASS_EDGE, GLASS_EDGE.a * alpha)
	ci.draw_line(points[0] + Vector2(0.0, hair * 0.5), points[1] + Vector2(0.0, hair * 0.5),
		edge, hair, true)
	ci.draw_line(points[0] + Vector2(hair * 0.5, 0.0),
		points[points.size() - 1] + Vector2(hair * 0.5, 0.0), edge, hair, true)
	# The `line` hairline along the bottom.
	ci.draw_line(points[points.size() - 2] - Vector2(0.0, hair * 0.5),
		points[points.size() - 1] - Vector2(0.0, hair * 0.5),
		Color(LINE, LINE.a * alpha), hair, true)


static func _draw_outline(ci: CanvasItem, points: PackedVector2Array, colour: Color,
		width: float) -> void:
	var loop := PackedVector2Array(points)
	loop.append(points[0])
	ci.draw_polyline(loop, colour, width, true)
