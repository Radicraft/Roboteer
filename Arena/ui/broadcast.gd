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
## #FFFFFF at 10 %. Kept for the old name only: no plate is outlined (owner rule).
const GLASS_EDGE := Color(1.0, 1.0, 1.0, 0.10)

# The blueprint plate (direction A, docs/look/menus-blueprint.html; Swift `Blueprint.plate`).
# Every plate the feed draws is this sheet since wave E (docs/wave-e-hud-notes.md): the icon's
# blue with its graph paper, upright, square cornered, no edge. The fight HUD's "light echo" of
# the menus is these plates; the bars, the ticker strip and the touch discs keep their own fills.

## rgba(14, 58, 140, 0.82): the HUD plate over the live arena (the mockup's `.hud .plate`).
const PLATE := Color(0.0549, 0.2275, 0.5490, 0.82)
## The same at 0.92: a sheet that holds a lot of reading (the walk-out card).
const PLATE_SOLID := Color(0.0549, 0.2275, 0.5490, 0.92)
## #B8352A, the blueprint danger plate (`--dangerbg`): POWER DOWN, ENDGAME, the stage stings,
## a hazard's intro card. White type on it.
const PLATE_DANGER := Color(0.7216, 0.2078, 0.1647, 0.88)
## #FF7A66, danger TYPE on a blue plate (`--danger`): the urgent clock, the knockout count.
## Plain `danger` (#E5483C) is too dark on the blue (2.2:1); this is 4:1 and up.
const DANGER_ON_PLATE := Color(1.0, 0.4784, 0.4)
## The graph paper: a 1 px line every 10 iOS pt, a brighter one every 50.
const GRID_MINOR := Color(1.0, 1.0, 1.0, 0.06)
const GRID_MAJOR := Color(1.0, 1.0, 1.0, 0.12)
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
# review's multiplier: display 0.8, the Saira UI face 0.94. Figures are the UI face with its
# tabular figures (wave D, docs/wave-d-figures-notes.md) at 0.87, the size at which they stand
# as tall as the B612 Mono figures they replaced.

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
## Numerals: Saira Semi Condensed 700 with tabular figures. 19 iOS pt.
const NUMERAL_PT := 26.0
## The fight clock's numerals, the same face. 29.5 iOS pt.
const CLOCK_PT := 41.0
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
## The graph paper's step, 10 iOS pt.
const GRID_STEP := 10.0 * PT_PER_IOS
## Where a lower third's leading bar used to be, 3 iOS pt. There is no bar (owner rule); the
## inset stays so the names and condition bars inside the plates do not move.
const BAR := 4.0
# There is no corner cut and no lean any more (wave E, owner rule: no skewed, slanted or cut
# accents). CUT and SKEW_DEG were deleted with the shapes that used them, so nothing can pick
# them up again.
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
## the same at 500, numerals the label file again with its tabular figures switched on
## (`NUMERAL_FEATURES`), so every figure lines up and none jitters as it counts, while the
## point, colon and comma keep their own narrow widths ("2:58", "89.5 kg", not "2: 58").
const FONT_FILES := {
	"display": "SairaStencilOne-Regular.ttf",
	"label": "SairaSemiCondensed-Bold.ttf",
	"body": "SairaSemiCondensed-Medium.ttf",
	"numerals": "SairaSemiCondensed-Bold.ttf",
}
## OpenType features the numerals role draws with: `tnum`, tabular (equal width) figures.
const NUMERAL_FEATURES := ["tnum"]

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


## Saira Semi Condensed 700 with tabular figures: the fight clock, the scrap bug and any
## other figure. Every digit is one width, so a counting number never jitters.
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
	if found != null and role == "numerals":
		var figures := FontVariation.new()
		figures.base_font = found
		var features := {}
		var ts := TextServerManager.get_primary_interface()
		for tag: String in NUMERAL_FEATURES:
			features[ts.name_to_tag(tag)] = 1
		figures.opentype_features = features
		found = figures
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

## A plate's outline: a plain upright rectangle, four points. No cut corner, no lean, no
## rounding (owner rule, wave E: the cut corner and the 12 degree lean read as "Claude design").
## `pt` is kept for the callers; nothing about the outline scales any more.
static func panel_points(rect: Rect2, _pt: float = 1.0) -> PackedVector2Array:
	var p := rect.position
	var s := rect.size
	return PackedVector2Array([p, p + Vector2(s.x, 0.0), p + s, p + Vector2(0.0, s.y)])


## THE plate: every panel, lower third, score bug, band and pill the feed draws comes through
## here. A blueprint sheet: `fill`, its graph paper, the soft top light, and `wash` (when it
## has any alpha) laid over the fill as a tint. No edge, rim, bar or hairline of any kind.
static func draw_plate(ci: CanvasItem, rect: Rect2, pt: float, alpha: float = 1.0,
		fill: Color = PLATE, wash: Color = Color(0, 0, 0, 0), grid: bool = true) -> void:
	if rect.size.x <= 0.5 or rect.size.y <= 0.5 or alpha <= 0.001:
		return
	var points := panel_points(rect)
	ci.draw_colored_polygon(points, Color(fill, fill.a * alpha))
	if wash.a > 0.001:
		ci.draw_colored_polygon(points, Color(wash, wash.a * alpha))
	if grid:
		draw_grid(ci, rect, pt, alpha)
	_draw_top_light(ci, points, alpha)


## The graph paper inside a plate, clipped to it. The first line sits one step IN from the top
## and left edges, never on them, so the paper never reads as a frame round the sheet; every
## fifth line is the brighter one.
static func draw_grid(ci: CanvasItem, rect: Rect2, pt: float, alpha: float = 1.0) -> void:
	var step := GRID_STEP * pt
	if step < 3.0:
		return
	var n := 1
	var gx := rect.position.x + step
	while gx < rect.end.x - 1.0:
		var c := GRID_MAJOR if n % 5 == 0 else GRID_MINOR
		ci.draw_rect(Rect2(Vector2(roundf(gx), rect.position.y), Vector2(1.0, rect.size.y)),
			Color(c, c.a * alpha))
		gx += step
		n += 1
	n = 1
	var gy := rect.position.y + step
	while gy < rect.end.y - 1.0:
		var c := GRID_MAJOR if n % 5 == 0 else GRID_MINOR
		ci.draw_rect(Rect2(Vector2(rect.position.x, roundf(gy)), Vector2(rect.size.x, 1.0)),
			Color(c, c.a * alpha))
		gy += step
		n += 1


## Panel: a plate. OWNER RULE (2026-09-21): no edge strokes, rims, bars or coloured hairlines
## on any plate; emphasis is fill, weight and light.
static func draw_panel(ci: CanvasItem, rect: Rect2, pt: float, alpha: float = 1.0,
		fill: Color = PLATE, wash: Color = Color(0, 0, 0, 0)) -> void:
	draw_plate(ci, rect, pt, alpha, fill, wash)


## Lower third: the same upright plate (wave E: no lean). No bar on its leading edge (owner
## rule, no line accents): `bar_colour`, when given, is washed into the fill instead.
## `leading_left` is kept for the callers' layout.
static func draw_lower_third(ci: CanvasItem, rect: Rect2, pt: float, _leading_left: bool,
		alpha: float = 1.0, fill: Color = PLATE, bar_colour: Color = Color(0, 0, 0, 0)) -> void:
	draw_plate(ci, rect, pt, alpha, fill,
		Color(bar_colour, bar_colour.a * 0.18) if bar_colour.a > 0.001 else Color(0, 0, 0, 0))


## Score bug: a small upright plate, numerals inside, a label above. The clock, the scrap and
## the tier badge. `rim` is no longer a rim (owner rule): it is a wash of that colour in the
## fill, at 16 %; pass a clear colour for a plain plate.
static func draw_score_bug(ci: CanvasItem, rect: Rect2, pt: float, alpha: float = 1.0,
		fill: Color = PLATE, rim: Color = Color(0, 0, 0, 0)) -> void:
	draw_plate(ci, rect, pt, alpha, fill,
		Color(rim, rim.a * 0.16) if rim.a > 0.001 else Color(0, 0, 0, 0))


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


## A pill for a coach callout or the intro's skip hint, sized by the caller (only the caller
## knows how wide the string came out). The same plate as everything else, without the graph
## paper (a pill is one short line of type and the grid only made it busy). Upright, no cut
## corner, no bevel, no skew, no edge (owner rule; wave D 2026-09-30 the "TAP TO SKIP" chip read
## as bevelled with the panel's cut corner on it).
static func draw_pill(ci: CanvasItem, rect: Rect2, pt: float, alpha: float = 1.0) -> void:
	draw_plate(ci, rect, pt, alpha, PLATE, Color(0, 0, 0, 0), false)


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

## The top light: white at 7 % along the top edge falling to nothing at the foot, drawn as
## per-vertex colour on the plate's own outline. No edge, no rim, no hairline (owner rule).
static func _draw_top_light(ci: CanvasItem, points: PackedVector2Array, alpha: float) -> void:
	if points.size() < 3:
		return
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
