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
## #35D6F0. Selection sweep fill, fill bars and accent words. Never an edge (owner rule).
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

# The Blueprint type system (01 of docs/look/fonts-options.html). The faces are wider than
# the Barlow Condensed they replaced, so every size below is the old one times the type
# review's multiplier: display and numbers 0.8, the Saira UI face 0.94.

## Display, Saira Stencil One, CAPS. 44 iOS pt in Barlow, 35 in the stencil.
const DISPLAY_PT := 48.0
## Title, Saira Stencil One, CAPS. 28 iOS pt in Barlow, 22 in the stencil.
const TITLE_PT := 31.0
## Button, Saira Semi Condensed 700, CAPS. 16 iOS pt.
const BUTTON_PT := 22.0
## Label, Saira Semi Condensed 700, CAPS. 11.5 iOS pt, and the legibility floor is 11.
const LABEL_PT := 16.0
## Body, Saira Semi Condensed 500, sentence case. 14 iOS pt.
const BODY_PT := 20.0
## Numerals, B612 Mono 700 (fixed pitch). 17.5 iOS pt.
const NUMERAL_PT := 24.0
## The fight clock's numerals, B612 Mono. 27 iOS pt.
const CLOCK_PT := 38.0
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

## The Blueprint faces (SIL OFL 1.1, one `OFL-<family>.txt` per family beside them in
## `Arena/assets/fonts`, credits in docs/third-party-fonts.md). These are the files that are
## really there; a build that somehow has none of them falls back
## to the engine's own face rather than drawing nothing, and `fonts_found()` says which
## way it went.
const FONT_DIR := "res://assets/fonts"
const THEME_PATH := "res://ui/broadcast_theme.tres"

## The face per role. Display is Saira Stencil One, label Saira Semi Condensed 700, body
## the same at 500, numerals B612 Mono 700.
const FONT_FILES := {
	"display": "SairaStencilOne-Regular.ttf",
	"label": "SairaSemiCondensed-Bold.ttf",
	"body": "SairaSemiCondensed-Medium.ttf",
	"numerals": "B612Mono-Bold.ttf",
}

static var _fonts: Dictionary = {}
static var _theme: Theme = null
static var _glyphs: Dictionary = {}


## Saira Stencil One: the display and title faces, the slams, the countdown and KO.
static func font_display() -> Font:
	return _font("display")


## Saira Semi Condensed 700: labels and buttons.
static func font_label() -> Font:
	return _font("label")


## Saira Semi Condensed 500: body sentences.
static func font_body() -> Font:
	return _font("body")


## B612 Mono 700: the fight clock, the scrap bug and any other figure. Fixed pitch, so a
## counting number never jitters.
static func font_numerals() -> Font:
	return _font("numerals")


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


## Panel: `glass` fill with a soft top light. OWNER RULE (2026-09-21): no edge strokes,
## rims, bars or coloured hairlines on any plate; emphasis is fill, weight and light.
static func draw_panel(ci: CanvasItem, rect: Rect2, pt: float, alpha: float = 1.0,
		fill: Color = GLASS) -> void:
	_draw_shape(ci, panel_points(rect, pt), pt, alpha, fill)


## Lower third: a panel skewed 12 degrees. No bar on its leading edge (owner rule, no line
## accents): `bar_colour`, when given, is washed into the fill instead, which is how the
## ENDGAME band still reads as urgent. `leading_left` is kept for the callers' layout.
static func draw_lower_third(ci: CanvasItem, rect: Rect2, pt: float, leading_left: bool,
		alpha: float = 1.0, fill: Color = GLASS, bar_colour: Color = Color(0, 0, 0, 0)) -> void:
	var bottom := rect.position.y + rect.size.y
	var points := skew(panel_points(rect, pt), bottom)
	_draw_shape(ci, points, pt, alpha, fill)
	if bar_colour.a > 0.001:
		ci.draw_colored_polygon(points, Color(bar_colour, bar_colour.a * 0.18 * alpha))


## Score bug: a small NON skewed plate. Numerals live inside it, a label above. Used for
## the clock, the scrap and the tier badge. `rim` is no longer a rim (owner rule): it is a
## wash of that colour in the fill, so an urgent clock still reads red.
static func draw_score_bug(ci: CanvasItem, rect: Rect2, pt: float, alpha: float = 1.0,
		fill: Color = GLASS, rim: Color = LINE) -> void:
	var points := panel_points(rect, pt)
	_draw_shape(ci, points, pt, alpha, fill)
	ci.draw_colored_polygon(points, Color(rim, rim.a * 0.16 * alpha))


## Rule: 1 px, never thicker, never a box. Only for a leader line or a neutral divider,
## never as an edge on a plate.
static func draw_rule(ci: CanvasItem, from: Vector2, to: Vector2, pt: float,
		alpha: float = 1.0, colour: Color = LINE_DIM) -> void:
	ci.draw_line(from, to, Color(colour, colour.a * alpha), maxf(1.0 * pt, 1.0), true)


## Ticker: a full width strip on `ink` at 90 %. No hairline along its top (owner rule).
static func draw_ticker(ci: CanvasItem, rect: Rect2, pt: float, alpha: float = 1.0,
		flash: float = 0.0) -> void:
	ci.draw_rect(rect, Color(INK, 0.90 * alpha))
	if flash > 0.001:
		ci.draw_rect(rect, Color(LINE, 0.28 * flash * alpha))


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


## A glass pill for a coach callout or the intro's skip hint, sized by the caller (only the
## caller knows how wide the string came out). A PLAIN upright rectangle: no cut corner, no
## bevel, no skew, no edge (owner rule, no skewed or stroked accents; wave D 2026-09-30, the
## "TAP TO SKIP" chip read as bevelled with the panel's cut corner on it). The top light stays.
static func draw_pill(ci: CanvasItem, rect: Rect2, _pt: float, alpha: float = 1.0) -> void:
	var p := rect.position
	var s := rect.size
	_draw_shape(ci, PackedVector2Array([p, p + Vector2(s.x, 0.0), p + s, p + Vector2(0.0, s.y)]),
		_pt, alpha, GLASS_LIVE)


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


## A glass disc, the touch furniture's panel, in the one round shape the system allows (a
## thumb is round). No rim (owner rule): a lit inner disc gives it its body. `rim` is kept
## for the callers and ignored.
static func draw_disc(ci: CanvasItem, centre: Vector2, radius: float, pt: float,
		alpha: float = 1.0, fill: Color = GLASS_LIVE, rim: Color = LINE) -> void:
	ci.draw_circle(centre, radius, Color(fill, fill.a * alpha))
	draw_disc_light(ci, centre, radius, alpha)


## The light on a disc: a paler disc offset up, so the control reads as a raised object.
static func draw_disc_light(ci: CanvasItem, centre: Vector2, radius: float,
		alpha: float = 1.0) -> void:
	ci.draw_circle(centre - Vector2(0.0, radius * 0.12), radius * 0.8,
		Color(1.0, 1.0, 1.0, 0.06 * alpha))


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
	if points.size() < 3:
		return
	# The top light: white at 7 % along the top edge falling to nothing at the foot, drawn
	# as per-vertex colour on the same outline, so it follows the cut and the skew. No edge,
	# no rim, no hairline (owner rule, 2026-09-21).
	var top := INF
	var foot := -INF
	for p: Vector2 in points:
		top = minf(top, p.y)
		foot = maxf(foot, p.y)
	var span := maxf(foot - top, 1.0)
	var colours := PackedColorArray()
	for p: Vector2 in points:
		var t := clampf((p.y - top) / span, 0.0, 1.0)
		colours.append(Color(1.0, 1.0, 1.0, 0.07 * (1.0 - t) * alpha))
	ci.draw_polygon(points, colours)

