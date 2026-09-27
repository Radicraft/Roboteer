class_name FightHud extends CanvasLayer
## Fight HUD, the live feed of the Broadcast system (docs/design-system.md sections 1 to 4,
## brief-v4-playtest.md section 7). Spec for the behaviour: docs/stage3-spec.md section 10.
##
## The game presents itself as a televised championship, so the fight is the live feed: the
## clock is a score bug top centre with the phase word under it, each machine's name and
## condition is a lower third at the top corner it belongs to, scrap is a bug in the top
## right, commentary runs along the bottom in the ticker, and ENDGAME is a full-width slam.
## Every colour, size and shape comes out of `Arena/ui/broadcast.gd`; nothing here invents
## a number of its own.
##
## Behaviour is unchanged from wave G. Every public method, every node name under Root and
## every test contract is the same; only the drawing and the placement are new.
##
## Presentation only. Every animation is a Tween or a hand-stepped clock on the idle frame;
## nothing here is read back by the simulation. All children are built in code so the scene
## works whether it is instanced from hud.tscn or constructed with FightHud.new().

## Design reference, matching FightControls: an iPhone 17 landscape is 1206 x 556 pt. These
## are the arena's own design units; the design system's iOS points are 1.383 of them
## (Broadcast.PT_PER_IOS), which is why the type sizes below come from Broadcast.
##
## This is a RATIO, not a base canvas. `window/stretch/mode` is "disabled" (wave P, agent H,
## docs/wave-v-v4-notes.md section 1), so `get_visible_rect()` is the real device pixel rect
## and `_pt` is how many of those pixels one design point is worth: 2.1692 on an iPhone 17
## (2622 x 1206), where the old stretched canvas made it exactly 2.0 and then blew the whole
## frame up by 1.0846 on the way to the glass. Everything on the feed is quoted in these
## points and multiplied by `_pt`, so the change moved nothing: the same physical size, drawn
## at the phone's own resolution. It is also why the safe area, which Swift sends in DEVICE
## pixels and this file consumes unconverted, is now exact rather than 8.5 % too generous.
const REF_SIZE_PT := Vector2(1206.0, 556.0)

## The screen gutter, on top of the safe area.
const PAD_PT := Broadcast.GUTTER
## Kept clear in the top-right corner, measured in from the safe area, for the shell's
## own pause button (44 pt, 12 pt in from both edges). This is the design system's "pause
## glyph, top right": the shell draws it, the feed keeps the room.
const CORNER_RESERVE_PT := 64.0
## And the scrap bug keeps this much clear of the reserve, because digits sitting flush
## against the button still read as touching it.
const CORNER_CLEARANCE_PT := 12.0
## TEST ARENA: the shell draws its own Back / TEST ARENA / Reset row across the top, so
## the HUD starts below it and shows no clock (the spec says there is no clock there).
const TEST_BAND_PT := 60.0

const TIMER_PT := Broadcast.CLOCK_PT
const PHASE_PT := Broadcast.LABEL_PT
const SCRAP_PT := Broadcast.NUMERAL_PT
const NAMES_PT := Broadcast.LABEL_PT
const KO_PT := 34.0
## The line under a count running on the player's own machine.
const KO_PROMPT_PT := Broadcast.LABEL_PT
const READOUT_PT := Broadcast.BODY_PT
const COUNTDOWN_PT := 96.0
const RESULT_TITLE_PT := Broadcast.DISPLAY_PT
const RESULT_WINNER_PT := Broadcast.BUTTON_PT
## Pad hints, shown where the on screen buttons are when a controller is driving.
const HINT_PT := Broadcast.LABEL_PT
## The PAUSED mark: small and out of the way, because the shell draws the real overlay.
const PAUSED_PT := Broadcast.LABEL_PT

## The clock's score bug, and the scrap bug beside the reserved corner.
const CLOCK_BUG_PT := Vector2(168.0, 62.0)
const SCRAP_BUG_PT := Vector2(156.0, 58.0)
## Each machine's lower third.
const THIRD_PT := Vector2(330.0, 50.0)

## The phase word under the clock. "OPEN" in typeDim, "ENDGAME" in danger.
const PHASE_OPEN := "OPEN"
const PHASE_ENDGAME := "ENDGAME"

# ---------------------------------------------------------------- coach callouts
#
# How-to-play labels anchored to the real controls, for a first fight or the test
# arena. Draw only: the overlay never takes a touch, so nothing they sit on stops
# working. Each one fades the moment its input is first used, and they are all gone a
# few seconds into the fight whether or not anything was touched. Broadcast puts each
# one on a glass pill, so a callout never has to shout over the arena behind it.

const COACH_PT := Broadcast.LABEL_PT
## Seconds of FIGHTING after which every callout has gone, used or not.
const COACH_FIGHT_S := 8.0
const COACH_FADE_S := 0.35
## Gap between a callout and the control it points at.
const COACH_GAP_PT := 18.0
const COL_COACH := Broadcast.TYPE
const COL_COACH_LINE := Broadcast.LINE_DIM
## Phases the rules layer reports, so the HUD does not have to know State.
const COACH_COUNTDOWN := "countdown"
const COACH_FIGHTING := "fighting"

## Off-screen opponent arrow. While the camera is holding the player-priority floor the
## opponent can be outside the frame; this says which way, at the screen edge, with the
## name under it. In `type`, and it fades rather than blinking.
const ARROW_PT := 15.0
const ARROW_NAME_PT := Broadcast.LABEL_PT
const ARROW_INSET_PT := 26.0
const ARROW_FADE_S := 0.18

## "YOU" over the player's own machine through the countdown and the opening seconds of
## the fight, so nobody takes the opponent for their own bot (the owner did, 2026-09-16).
## A chevron pointing down at the chassis with the word above it, in `type`.
const TAG_PT := 15.0
const TAG_TEXT := "YOU"
const TAG_FADE_S := 0.25

## The tokens, under the names this file has always used for them.
const COL_TEXT := Broadcast.TYPE
const COL_DIM := Broadcast.TYPE_DIM
const COL_OUTLINE := Color(Broadcast.INK, 0.92)
const COL_URGENT := Broadcast.DANGER
## The knockout count is a losing state, so it is `danger`, not a second warm colour.
const COL_KO := Broadcast.DANGER
const COL_SCRAP := Broadcast.SCRAP
const COL_HINT := Broadcast.TYPE

## Controller kinds whose face buttons are a cross and a circle rather than A and B.
## Matched case insensitively as a substring, so "DualSense", "DualShock 4", "PS5" and
## "PlayStation Controller" all land on the same glyphs.
const PLAYSTATION_KINDS := ["dualsense", "dualshock", "playstation", "ps3", "ps4", "ps5"]
## The real symbols, with letter fallbacks for a font that has no glyph for them.
const GLYPH_CROSS := "✕"
const GLYPH_CIRCLE := "○"

## FightControls adds itself to this group, so the HUD can find the button geometry
## without the rules layer having to wire the two together.
const CONTROLS_GROUP := "roboteer_fight_controls"

## Numbers count over 0.4 s (design system section 3).
const ROLL_S := Broadcast.COUNT_S
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
var _chrome: Control
var _timer: Label
var _phase: Label
var _scrap: Label
var _names: Label
var _opponent: Label
var _house: Label
var _ko: Label
var _readout: Label
var _countdown: Label
var _result_title: Label
var _result_winner: Label
var _hint_primary: Label
var _hint_secondary: Label
## BOOST (wave B pacing): the third pad hint, on the boost button's spot.
var _hint_boost: Label
var _paused_label: Label
var _ko_prompt: Label

var _paused: bool = false
## The test arena: no clock, and everything below the shell's own top row.
var _test_mode: bool = false

## The phase word under the clock, and the two condition bars.
var _phase_word: String = PHASE_OPEN
var _condition: Dictionary = {"player": 1.0, "opponent": 1.0}
## The house bot's name sits under the opponent's lower third, in danger, while it is out.
var _house_name: String = ""
var _house_out: bool = false

## The rectangles the chrome draws and the labels sit in, worked out once per layout so
## the plate and the type can never disagree.
var _clock_rect: Rect2 = Rect2()
var _scrap_rect: Rect2 = Rect2()
var _player_rect: Rect2 = Rect2()
var _opponent_rect: Rect2 = Rect2()
var _ticker_rect: Rect2 = Rect2()
var _ko_rect: Rect2 = Rect2()
## Where the result banner's top sits, as a share of the screen height (B12): the lower
## third, clear of the wreck the camera centres.
const RESULT_BAND_TOP := 0.66
var _result_rect: Rect2 = Rect2()
var _readout_rect: Rect2 = Rect2()
var _endgame_rect: Rect2 = Rect2()

## Coach callouts.
var _coach_on: bool = false
var _coach_phase: String = ""
var _coach_fight_s: float = 0.0
var _coach_overlay: Control = null
## Per callout alpha, 1 fully drawn, 0 gone. Keys: drive, primary, camera.
var _coach_alpha: Dictionary = {"drive": 1.0, "primary": 1.0, "camera": 1.0, "boost": 1.0}
var _coach_used: Dictionary = {"drive": false, "primary": false, "camera": false,
	"boost": false}

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
## BOOST on a pad is the right shoulder: RB on an Xbox pad, R1 on a PlayStation one.
var _hint_boost_text: String = "RB BOOST"
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
	_names.text = _player_name
	_opponent.text = _opponent_name
	# The rules layer names the machines once per fight, so this is also where the round
	# goes back to OPEN: without it a second fight would start in ENDGAME red.
	_phase_word = ""
	set_phase(PHASE_OPEN)
	# And where everything the last fight left on the glass comes down. The one HUD lives
	# for the whole process, and the owner saw "OUT OF THE ARENA" and "CORE DESTROYED"
	# still up at the next bell (2026-09-16).
	hide_result()
	hide_ko_count()
	if has_method("hide_endgame_sting"):
		call("hide_endgame_sting")
	if has_method("clear_commentary"):
		call("clear_commentary")
	if has_method("set_zone_warning"):
		call("set_zone_warning", false, "")
	if has_method("set_house_bot"):
		call("set_house_bot", "", false)
	if has_method("set_condition"):
		call("set_condition", 1.0, 1.0)
	if has_method("set_player_tag"):
		call("set_player_tag", false, Vector2.ZERO)
	_chrome_dirty()


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
		_chrome_dirty()


## The phase word under the clock: "OPEN", or "ENDGAME" in danger. The sting sets it on
## its own, so a rules layer that never calls this still reads right.
func set_phase(word: String) -> void:
	var want := word.strip_edges().to_upper()
	if want.is_empty() or want == _phase_word:
		return
	_build()
	_phase_word = want
	_phase.text = want
	_phase.add_theme_color_override("font_color",
		COL_URGENT if want == PHASE_ENDGAME else COL_DIM)
	_chrome_dirty()


func phase_word() -> String:
	return _phase_word


## How much fight each machine has left, 0 to 1, for the condition bars in the lower
## thirds. The player's bar is `line`, the opponent's `typeDim`, and either goes `danger`
## under 25 %. Untouched they read full, which is what an unwired rules layer means.
func set_condition(player: float, opponent: float) -> void:
	var p := clampf(player, 0.0, 1.0)
	var o := clampf(opponent, 0.0, 1.0)
	if is_equal_approx(p, float(_condition["player"])) \
			and is_equal_approx(o, float(_condition["opponent"])):
		return
	_condition["player"] = p
	_condition["opponent"] = o
	_chrome_dirty()


## "player" or "opponent".
func condition(which: String) -> float:
	return float(_condition.get(which, 1.0))


## The house bot's name under the opponent's lower third, in danger, while it is out on
## the floor. The rules layer can call this directly; failing that the HUD picks the name
## up from the corner warning and the OUT from the commentary feed.
func set_house_bot(house_name: String, out: bool) -> void:
	_build()
	var want := house_name.strip_edges().to_upper()
	if not want.is_empty():
		_house_name = want
	_house_out = out
	_house.text = _house_name
	_house.visible = out and not _house_name.is_empty()
	_chrome_dirty()


func house_bot_out() -> bool:
	return _house_out


func house_bot_name() -> String:
	return _house_name


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
## own label because the count itself is danger red and a Label carries one colour.
func show_ko_count(seconds_left: int, bot_name: String, on_player: bool = false) -> void:
	_build()
	_ko.text = "%s\nKNOCKOUT COUNT %d" % [bot_name.to_upper(), maxi(seconds_left, 0)]
	_ko.visible = true
	_ko_prompt.visible = on_player
	_chrome_dirty()


func hide_ko_count() -> void:
	_build()
	_ko.visible = false
	_ko_prompt.visible = false
	_chrome_dirty()


## True while the "drive to stop the count" line is up.
func ko_prompt_visible() -> bool:
	return _ko_prompt != null and _ko_prompt.visible


## R builds the sentence, for example "Your wedge: floor. Their flipper: mid."
func set_height_readout(text: String) -> void:
	_build()
	_readout.text = text
	_chrome_dirty()


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
	_chrome_dirty()
	if not is_inside_tree():
		_result_title.modulate = Color(1, 1, 1, 1)
		_result_winner.modulate = Color(1, 1, 1, 1)
		return
	if _result_tween != null and _result_tween.is_valid():
		_result_tween.kill()
	# A lower third enters from the edge it belongs to: this one is the full width banner,
	# so it sweeps in from the left over ENTER_S and never scales.
	_set_result_slide(0.0)
	_result_tween = create_tween()
	_result_tween.set_parallel(true)
	_result_tween.tween_property(_result_title, "modulate:a", 1.0, Broadcast.ENTER_S)
	_result_tween.tween_method(_set_result_slide, 0.0, 1.0, Broadcast.ENTER_S) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_result_tween.tween_property(_result_winner, "modulate:a", 1.0, 0.25).set_delay(0.15)


func hide_result() -> void:
	_build()
	_result_title.visible = false
	_result_winner.visible = false
	_chrome_dirty()


## 0 while the result banner is still off the left edge, 1 when it has arrived.
var _result_slide: float = 1.0


func _set_result_slide(value: float) -> void:
	_result_slide = clampf(value, 0.0, 1.0)
	var dx := (1.0 - _result_slide) * -(_result_rect.size.x + _result_rect.position.x)
	if _result_title != null:
		_result_title.position.x = _result_title_home + dx
	_chrome_dirty()


var _result_title_home: float = 0.0


# ---------------------------------------------------------------- the endgame sting
# brief v4 §2: at 2:00 the HUD stamps ENDGAME across the screen. Design system section 3:
# a full-width lower third slams in from the left in 0.12 s, holds 1.2 s, exits right in
# 0.18 s, with a `line` flash across the ticker. Built on demand rather than in _build(),
# so the sting owns itself and the shared layout pass has nothing of it to know about.
const ENDGAME_PT := Broadcast.DISPLAY_PT
const ENDGAME_TEXT := "ENDGAME"
const ENDGAME_SLAM_S := Broadcast.SLAM_S
const ENDGAME_HOLD_S := Broadcast.SLAM_HOLD_S
const ENDGAME_FADE_S := Broadcast.SLAM_OUT_S
## How long the `line` flash takes to run off the ticker.
const TICKER_FLASH_S := 0.45

var _endgame: Label = null
var _endgame_tween: Tween
## -1 fully off the left edge, 0 home, +1 fully off the right edge.
var _endgame_slide: float = -1.0
var _ticker_flash: float = 0.0


## fight.gd calls this once, on the endgame tick.
func show_endgame_sting() -> void:
	_build()
	set_phase(PHASE_ENDGAME)
	var l := _endgame_label()
	l.text = ENDGAME_TEXT
	l.visible = true
	l.modulate = Color(1, 1, 1, 1)
	l.scale = Vector2.ONE
	_ticker_flash = 1.0
	if _endgame_tween != null and _endgame_tween.is_valid():
		_endgame_tween.kill()
	if not is_inside_tree():
		_set_endgame_slide(0.0)
		return
	_set_endgame_slide(-1.0)
	_endgame_tween = create_tween()
	_endgame_tween.tween_method(_set_endgame_slide, -1.0, 0.0, ENDGAME_SLAM_S) \
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_endgame_tween.tween_interval(ENDGAME_HOLD_S)
	# parallel() takes the NEXT tweener only, so the exit really does wait out the hold.
	# set_parallel(true) here would have put the exit in the same step as the interval and
	# the sting would have left as it arrived.
	_endgame_tween.tween_method(_set_endgame_slide, 0.0, 1.0, ENDGAME_FADE_S) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_endgame_tween.parallel().tween_property(l, "modulate:a", 0.0, ENDGAME_FADE_S)
	_endgame_tween.chain().tween_callback(func() -> void: l.visible = false)


## True while the stamp is on screen. The headless test reads it.
func endgame_sting_visible() -> bool:
	return _endgame != null and _endgame.visible and _endgame.modulate.a > 0.01


## Where the slam has got to: -1 off the left, 0 home, +1 gone right.
func endgame_slide() -> float:
	return _endgame_slide


func hide_endgame_sting() -> void:
	if _endgame_tween != null and _endgame_tween.is_valid():
		_endgame_tween.kill()
	if _endgame != null:
		_endgame.visible = false
	_chrome_dirty()


func _set_endgame_slide(value: float) -> void:
	_endgame_slide = clampf(value, -1.0, 1.0)
	if _endgame != null and is_instance_valid(_endgame):
		_endgame.position.x = _endgame_home_x + _endgame_slide * _endgame_travel()
	_chrome_dirty()


var _endgame_home_x: float = 0.0


func _endgame_travel() -> float:
	var s := _viewport_size()
	return s.x + _endgame_rect.size.x


func _endgame_label() -> Label:
	if _endgame == null:
		_endgame = _label("Endgame", ENDGAME_PT, COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER,
			Broadcast.font_display())
		_endgame.visible = false
	_place_endgame()
	return _endgame


## The full-width band it slams across, at whatever size the screen is now.
func _place_endgame() -> void:
	if _endgame == null:
		return
	_relayout()
	var px := maxi(int(round(ENDGAME_PT * _pt)), 12)
	_endgame.add_theme_font_size_override("font_size", px)
	_endgame.add_theme_constant_override("outline_size", 0)
	_band(_endgame, _endgame_rect.position.y, _endgame_rect.size.y,
		float(_safe["left"]) + PAD_PT * _pt, float(_safe["right"]) + PAD_PT * _pt)
	_endgame_home_x = _endgame.position.x
	_endgame.position.x = _endgame_home_x + _endgame_slide * _endgame_travel()


# ---------------------------------------------------------------- the ticker (agent G6)
#
# brief v4 §10 item 2: short capitals for the moments that matter, driven by rules events
# (`Arena/fight/commentary.gd`). Wave G showed them as ONE plain outlined line; wave V
# makes it the broadcast ticker along the bottom: a strip on `ink` at 90 %, label type,
# one line at a time, sliding in from the right edge.
#
# Three rules, and they are the whole design:
#
#   - never during the countdown. There is a 96 pt "3" in the middle of the screen and a
#     coach callout on every control; a commentary line there is noise on top of noise.
#   - never more than one line every 2 s. The line holds 1.6 s and fades in 0.25 s, so
#     consecutive lines never overlap and the eye always finishes one before the next.
#   - a line that has waited more than 2 s is DROPPED, not shown late. Commentary is
#     about what is happening; "BIG HIT" four seconds after the hit is a lie, and a
#     queue that never drops turns a scrappy ten seconds into a minute of backlog.
#
# The strip itself is drawn at the line's own alpha, so the ticker is on screen exactly
# while there is something to say. It crosses the bottom of the stick well for those two
# seconds; a plate that sat there all fight would cover a control the owner already had
# trouble finding.

const COMMENTARY_PT := Broadcast.LABEL_PT
const COMMENTARY_HOLD_S := 1.6
const COMMENTARY_FADE_S := 0.25
## Minimum gap between two lines appearing, measured from one appearing to the next.
const COMMENTARY_GAP_S := 2.0
## A queued line older than this is dropped rather than shown late.
const COMMENTARY_STALE_S := 2.0
## How long a new line takes to slide in from the right edge.
const TICKER_SLIDE_S := 0.28
## The commentary line that means the house bot is on the floor, so the feed can name it
## under the opponent's lower third without the rules layer having to say so twice.
const HOUSE_BOT_OUT_LINE := "HOUSE BOT OUT"

var _commentary: Label = null
## [{"text": String, "at": float}], oldest first.
var _commentary_queue: Array = []
var _commentary_now: float = 0.0
var _commentary_shown_at: float = -1000.0
var _commentary_alpha: float = 0.0
## 0 just promoted and off the right edge, 1 arrived.
var _commentary_slide: float = 1.0
var _commentary_home: Rect2 = Rect2()


## Say one line. Short capitals; the caller decides the words (commentary.gd owns them).
## Dropped outright during the countdown, queued otherwise.
func push_commentary(text: String) -> void:
	var line := text.strip_edges().to_upper()
	if line.is_empty():
		return
	if _coach_phase == COACH_COUNTDOWN:
		return
	_build()
	if line == HOUSE_BOT_OUT_LINE:
		set_house_bot(_house_name, true)
	_commentary_queue.append({"text": line, "at": _commentary_now})


## Drive the commentary clock by hand, for the headless test and for any caller that
## wants the timeline without waiting on real frames. Called every frame from _process.
func commentary_step(delta: float) -> void:
	_commentary_now += delta

	# Promote BEFORE pruning, so a line queued behind another and waiting out the gap is
	# shown on the frame the gap opens rather than being thrown away on it.
	var elapsed := _commentary_now - _commentary_shown_at
	if elapsed >= COMMENTARY_GAP_S and not _commentary_queue.is_empty():
		var entry: Dictionary = _commentary_queue.pop_front()
		_commentary_shown_at = _commentary_now
		_commentary_alpha = 1.0
		_commentary_slide = 0.0
		var l := _commentary_label()
		l.text = str(entry["text"])
		l.visible = true
		l.modulate = Color(1, 1, 1, 1)
		_apply_commentary_slide()
		_chrome_dirty()

	var i := 0
	while i < _commentary_queue.size():
		var queued: Dictionary = _commentary_queue[i]
		if _commentary_now - float(queued["at"]) > COMMENTARY_STALE_S:
			_commentary_queue.remove_at(i)
		else:
			i += 1

	# The slide in from the right edge. Presentation only: the timeline below is the one
	# wave G wrote and the one commentary_test measures.
	if _commentary_slide < 1.0:
		_commentary_slide = minf(_commentary_slide + delta / maxf(TICKER_SLIDE_S, 0.001), 1.0)
		_apply_commentary_slide()

	if _ticker_flash > 0.0:
		_ticker_flash = maxf(_ticker_flash - delta / maxf(TICKER_FLASH_S, 0.001), 0.0)
		_chrome_dirty()

	# Hold, then fade. Done by hand rather than with a Tween because the whole section
	# has to run headless, where there is no frame for a Tween to sit on.
	var age := _commentary_now - _commentary_shown_at
	var want := 1.0
	if age >= COMMENTARY_HOLD_S + COMMENTARY_FADE_S:
		want = 0.0
	elif age >= COMMENTARY_HOLD_S:
		want = 1.0 - (age - COMMENTARY_HOLD_S) / maxf(COMMENTARY_FADE_S, 0.001)
	if is_equal_approx(want, _commentary_alpha):
		return
	_commentary_alpha = clampf(want, 0.0, 1.0)
	if _commentary != null and is_instance_valid(_commentary):
		_commentary.modulate = Color(1, 1, 1, _commentary_alpha)
		_commentary.visible = _commentary_alpha > 0.004
	_chrome_dirty()


## The line on screen now, or "" when nothing is being said.
func commentary_text() -> String:
	if _commentary == null or _commentary_alpha <= 0.004:
		return ""
	return _commentary.text


func commentary_visible() -> bool:
	return _commentary_alpha > 0.004


func commentary_alpha() -> float:
	return _commentary_alpha


## 0 while the line is still arriving from the right edge, 1 once it is home.
func commentary_slide() -> float:
	return _commentary_slide


## How many lines are waiting. For the headless test.
func commentary_queued() -> int:
	return _commentary_queue.size()


## The ticker strip's rectangle in viewport pixels. For the headless test.
func ticker_rect() -> Rect2:
	_relayout()
	return _ticker_rect


## Forget everything, said and queued. R calls this when a fight starts.
func clear_commentary() -> void:
	_commentary_queue.clear()
	_commentary_now = 0.0
	_commentary_shown_at = -1000.0
	_commentary_alpha = 0.0
	_commentary_slide = 1.0
	_ticker_flash = 0.0
	_house_out = false
	if _house != null and is_instance_valid(_house):
		_house.visible = false
	if _commentary != null and is_instance_valid(_commentary):
		_commentary.visible = false
	_chrome_dirty()


func _commentary_label() -> Label:
	if _commentary == null:
		_commentary = _label("Commentary", COMMENTARY_PT, COL_TEXT, HORIZONTAL_ALIGNMENT_LEFT)
		_commentary.visible = false
	_place_commentary()
	return _commentary


## The line sits in the ticker strip along the bottom, inside the gutter.
func _place_commentary() -> void:
	if _commentary == null:
		return
	_relayout()
	var px := maxi(int(round(COMMENTARY_PT * _pt)), 10)
	_commentary.add_theme_font_size_override("font_size", px)
	_commentary.add_theme_constant_override("outline_size", 0)
	_commentary_home = Rect2(
		Vector2(float(_safe["left"]) + PAD_PT * _pt, _ticker_rect.position.y),
		Vector2(maxf(_ticker_rect.size.x - (float(_safe["left"]) + float(_safe["right"])
			+ PAD_PT * 2.0 * _pt), 1.0), _ticker_rect.size.y))
	_band(_commentary, _commentary_home.position.y, _commentary_home.size.y,
		float(_safe["left"]) + PAD_PT * _pt, float(_safe["right"]) + PAD_PT * _pt)
	_apply_commentary_slide()


## A new line enters from the right edge of the strip and settles at the left, which is
## the ticker's own motion rule. Horizontal only: the row it sits on never moves.
func _apply_commentary_slide() -> void:
	if _commentary == null or not is_instance_valid(_commentary):
		return
	var t := clampf(_commentary_slide, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - t, 3.0)
	var travel := _viewport_size().x - _commentary_home.position.x
	_commentary.position.x = _commentary_home.position.x + (1.0 - eased) * travel


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
	_hint_boost.visible = on
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
		_hint_boost_text = "R1 BOOST"
	else:
		_glyph_primary = "A"
		_glyph_secondary = "B"
		_hint_boost_text = "RB BOOST"
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
	var font: Font = null
	if _hint_primary != null:
		font = _hint_primary.get_theme_font("font")
		if font == null:
			font = _hint_primary.get_theme_default_font()
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
	if _hint_boost != null:
		_hint_boost.text = _hint_boost_text


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
	_chrome_dirty()


func is_paused() -> bool:
	return _paused


## The test arena has no clock (docs/stage3-spec.md section 6) and the shell owns the top
## TEST_BAND_PT of the screen for its own Back / TEST ARENA / Reset row, so the names and
## the scrap bug move below it.
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
	commentary_step(delta)
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


func _chrome_dirty() -> void:
	if _chrome != null and is_instance_valid(_chrome):
		_chrome.queue_redraw()


## Draws the callouts on the overlay, anchored to where FightControls really put its
## furniture. Label type in `type` on a glass pill, with a `lineDim` leader to the rim of
## the control it names.
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
		_coach_text(on, "DRIVE  SLIDE YOUR THUMB HERE", at, font_px, drive_alpha,
			HORIZONTAL_ALIGNMENT_LEFT)
		_coach_leader(on, at + Vector2(-gap * 0.4, 0.0), home, radius, drive_alpha, pt)

	var primary_alpha := float(_coach_alpha.get("primary", 0.0))
	if primary_alpha > 0.004:
		var centre: Vector2 = geometry.get("primary", Vector2.ZERO)
		var radius := float(geometry.get("primary_radius", 0.0))
		var verb := "HOLD"
		if _controls.has_method("primary_is_hold") and not bool(_controls.call("primary_is_hold")):
			verb = "TAP"
		# Above the button: its left side is the BOOST button now (wave B pacing). Clear of
		# the flipper's gas pips and the spin-up ring, which sit just outside it.
		var at := centre + Vector2(0.0, -radius - gap - 12.0 * pt)
		_coach_text(on, "%s  %s" % [_hint_action_primary, verb], at, font_px, primary_alpha,
			HORIZONTAL_ALIGNMENT_CENTER)
		_coach_leader(on, at + Vector2(0.0, gap * 0.4), centre, radius, primary_alpha, pt)

	# BOOST (wave B pacing): to the left of the boost button, pointing in.
	var boost_alpha := float(_coach_alpha.get("boost", 0.0))
	if boost_alpha > 0.004 and geometry.has("boost"):
		var centre: Vector2 = geometry.get("boost", Vector2.ZERO)
		var radius := float(geometry.get("boost_radius", 0.0))
		var at := centre + Vector2(-radius - gap, 0.0)
		_coach_text(on, "BOOST  TAP TO DASH", at, font_px, boost_alpha,
			HORIZONTAL_ALIGNMENT_RIGHT)
		_coach_leader(on, at + Vector2(gap * 0.4, 0.0), centre, radius, boost_alpha, pt)

	var camera_alpha := float(_coach_alpha.get("camera", 0.0))
	if camera_alpha > 0.004:
		# The free right middle band: outside the stick zone, above the two buttons.
		var at := Vector2(view.x * 0.72, view.y * 0.40)
		_coach_text(on, "CAMERA  DRAG TO LOOK, PINCH TO ZOOM", at, font_px, camera_alpha,
			HORIZONTAL_ALIGNMENT_CENTER)


## A small arrow at the screen edge pointing at an opponent that is off the frame, with
## its name under it, in `type`.
func _draw_offscreen_marker(on: Control) -> void:
	if _marker_alpha <= 0.004:
		return
	var font := _font_label(on)
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
	# The name is pushed back INSIDE the frame from the arrow, never off the edge.
	var origin := at - d * (r + 6.0 * _pt) + Vector2(0.0, px * 0.35)
	Broadcast.draw_text(on, font, origin, _marker_name, px,
		Color(COL_TEXT, _marker_alpha), HORIZONTAL_ALIGNMENT_CENTER,
		maxi(int(round(px * 0.25)), 2))


## A small chevron pointing down at the player's machine with YOU above it, in `type`.
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
	var font := _font_label(on)
	if font == null:
		return
	var px := int(round(TAG_PT * _pt))
	var origin := tip + Vector2(0.0, -r - 5.0 * _pt)
	Broadcast.draw_text(on, font, origin, TAG_TEXT, px, Color(COL_TEXT, _tag_alpha),
		HORIZONTAL_ALIGNMENT_CENTER, maxi(int(round(px * 0.25)), 2))


## One callout, on a glass pill. `at` is the anchor; align says which end sits on it.
func _coach_text(on: Control, text: String, at: Vector2, font_px: int, alpha: float,
		align: int) -> void:
	var font := _font_label(on)
	if font == null:
		return
	var w := Broadcast.text_width(font, text, font_px)
	var origin := at + Vector2(0.0, font_px * 0.35)
	match align:
		HORIZONTAL_ALIGNMENT_RIGHT:
			origin.x -= w
		HORIZONTAL_ALIGNMENT_CENTER:
			origin.x -= w * 0.5
		_:
			pass
	var pad := Broadcast.GAP * _pt
	var pill := Rect2(origin - Vector2(pad, font_px * 0.95),
		Vector2(w + pad * 2.0, font_px * 1.5))
	Broadcast.draw_pill(on, pill, _pt, alpha)
	Broadcast.draw_text(on, font, origin, text, font_px,
		Color(COL_COACH, COL_COACH.a * alpha), HORIZONTAL_ALIGNMENT_LEFT)


## A hairline from the callout to the rim of the control it names.
func _coach_leader(on: Control, from: Vector2, centre: Vector2, radius: float, alpha: float,
		pt: float) -> void:
	var to_centre := centre - from
	if to_centre.length() <= radius + 1.0:
		return
	var end := centre - to_centre.normalized() * radius
	Broadcast.draw_rule(on, from, end, pt, alpha, COL_COACH_LINE)


## Authoritative scrap total behind the rolling number.
func scrap_total() -> int:
	return _scrap_total


## Displayed scrap, rounded. Exposed for the headless test.
func scrap_displayed() -> int:
	return int(round(_scrap_shown))


# ---------------------------------------------------------------- the chrome

## Everything the feed DRAWS rather than types: the score bugs, the lower thirds, the
## condition bars, the ticker strip and the sting's band. Drawn under every label, from
## the rectangles `_relayout` worked out, so the plate and the type cannot disagree.
func _draw_chrome(on: Control) -> void:
	var font := _font_label(on)
	var label_px := maxi(int(round(Broadcast.LABEL_PT * _pt)), 9)

	# The clock, top centre, with the phase word under it.
	if _timer != null and _timer.visible:
		Broadcast.draw_score_bug(on, _clock_rect, _pt, 1.0, Broadcast.GLASS,
			COL_URGENT if _time_urgent else Broadcast.LINE)

	# The two machines' lower thirds, each entering from the corner it belongs to.
	Broadcast.draw_lower_third(on, _player_rect, _pt, true)
	Broadcast.draw_condition(on, _condition_rect(_player_rect), float(_condition["player"]),
		Broadcast.LINE)
	Broadcast.draw_lower_third(on, _opponent_rect, _pt, false)
	Broadcast.draw_condition(on, _condition_rect(_opponent_rect), float(_condition["opponent"]),
		Broadcast.TYPE_DIM, 1.0, true)

	# The scrap bug, beside the corner the shell's pause button owns.
	Broadcast.draw_score_bug(on, _scrap_rect, _pt, 1.0, Broadcast.GLASS, Broadcast.SCRAP)
	if font != null:
		Broadcast.draw_text(on, font,
			_scrap_rect.position + Vector2(Broadcast.PANEL_PAD * _pt, label_px * 1.25),
			"SCRAP", label_px, COL_DIM, HORIZONTAL_ALIGNMENT_LEFT)

	# The knockout count and the result banner get their own plate, because both land in
	# the middle of the frame with the whole arena behind them.
	if _ko != null and _ko.visible:
		# The count's plate reads as danger by a wash in its fill, not by a rule along its
		# foot (owner rule, no line accents).
		Broadcast.draw_panel(on, _ko_rect, _pt, 1.0, Broadcast.GLASS)
		on.draw_colored_polygon(Broadcast.panel_points(_ko_rect, _pt), Color(COL_KO, 0.16))
	if _result_title != null and _result_title.visible:
		var banner := _result_rect
		banner.position.x += (1.0 - _result_slide) * -(banner.size.x + banner.position.x)
		Broadcast.draw_lower_third(on, banner, _pt, true, _result_title.modulate.a)
	if _readout != null and not _readout.text.is_empty() and font != null:
		var rw := Broadcast.text_width(font, _readout.text,
			maxi(int(round(READOUT_PT * _pt)), 9))
		var pad := Broadcast.PANEL_PAD * _pt
		var plate := Rect2(
			Vector2(_readout_rect.position.x + _readout_rect.size.x * 0.5 - rw * 0.5 - pad,
				_readout_rect.position.y),
			Vector2(rw + pad * 2.0, _readout_rect.size.y))
		Broadcast.draw_panel(on, plate, _pt, 1.0, Broadcast.GLASS_LIVE)

	# The ENDGAME slam: a full-width lower third that arrives from the left.
	if _endgame != null and _endgame.visible:
		var band := _endgame_rect
		band.position.x += _endgame_slide * _endgame_travel()
		Broadcast.draw_lower_third(on, band, _pt, true, _endgame.modulate.a,
			Broadcast.GLASS, COL_URGENT)

	# The ticker, on screen exactly while there is a line to read, with the sting's flash
	# running across it.
	var ticker_alpha := maxf(_commentary_alpha, _ticker_flash)
	if ticker_alpha > 0.004:
		Broadcast.draw_ticker(on, _ticker_rect, _pt, ticker_alpha, _ticker_flash)


## The condition bar inside a lower third: full width less the leading bar and the pad,
## sitting on the panel's lower edge.
func _condition_rect(third: Rect2) -> Rect2:
	var pad := Broadcast.PANEL_PAD * _pt
	var bar := Broadcast.BAR * _pt
	var h := Broadcast.CONDITION_H * _pt
	return Rect2(
		Vector2(third.position.x + bar + pad, third.position.y + third.size.y - pad * 0.7 - h),
		Vector2(maxf(third.size.x - bar - pad * 2.0, 1.0), h))


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
		_scrap.text = "%d" % int(round(maxf(value, 0.0)))


func _flash() -> void:
	if not is_inside_tree() or _scrap == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_scrap.pivot_offset = Vector2(_scrap.size.x, _scrap.size.y * 0.5)
	_scrap.modulate = Color(1.7, 1.55, 1.1)
	_scrap.scale = Vector2(1.08, 1.08)
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
	_root.theme = Broadcast.theme()

	# The drawn chrome goes in FIRST, so every label sits on top of its own plate.
	_chrome = _root.get_node_or_null("Chrome") as Control
	if _chrome == null:
		var chrome := ChromeOverlay.new()
		chrome.name = "Chrome"
		chrome.hud = self
		_root.add_child(chrome)
		_chrome = chrome
	_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chrome.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.move_child(_chrome, 0)

	var label_face := Broadcast.font_label()
	var display_face := Broadcast.font_display()
	var body_face := Broadcast.font_body()

	_names = _label("Names", NAMES_PT, COL_TEXT, HORIZONTAL_ALIGNMENT_LEFT, label_face)
	_opponent = _label("Opponent", NAMES_PT, COL_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, label_face)
	_house = _label("HouseBot", NAMES_PT, COL_URGENT, HORIZONTAL_ALIGNMENT_RIGHT, label_face)
	_timer = _label("Timer", TIMER_PT, COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER, label_face)
	_phase = _label("Phase", PHASE_PT, COL_DIM, HORIZONTAL_ALIGNMENT_CENTER, label_face)
	_scrap = _label("Scrap", SCRAP_PT, COL_SCRAP, HORIZONTAL_ALIGNMENT_RIGHT, label_face)
	_ko = _label("KoCount", KO_PT, COL_KO, HORIZONTAL_ALIGNMENT_CENTER, display_face)
	_readout = _label("Readout", READOUT_PT, COL_DIM, HORIZONTAL_ALIGNMENT_CENTER, body_face)
	_countdown = _label("Countdown", COUNTDOWN_PT, COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER,
		display_face)
	_result_title = _label("ResultTitle", RESULT_TITLE_PT, COL_TEXT,
		HORIZONTAL_ALIGNMENT_CENTER, display_face)
	_result_winner = _label("ResultWinner", RESULT_WINNER_PT, COL_TEXT,
		HORIZONTAL_ALIGNMENT_CENTER, label_face)
	_hint_primary = _label("HintPrimary", HINT_PT, COL_HINT, HORIZONTAL_ALIGNMENT_CENTER,
		label_face)
	_hint_secondary = _label("HintSecondary", HINT_PT, COL_HINT, HORIZONTAL_ALIGNMENT_CENTER,
		label_face)
	_hint_boost = _label("HintBoost", HINT_PT, COL_HINT, HORIZONTAL_ALIGNMENT_CENTER,
		label_face)
	_ko_prompt = _label("KoPrompt", KO_PROMPT_PT, COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER,
		label_face)
	_ko_prompt.text = "DRIVE TO STOP THE COUNT"
	_ko_prompt.visible = false
	_paused_label = _label("Paused", PAUSED_PT, COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER,
		label_face)
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
	_coach_overlay.theme = Broadcast.theme()
	_coach_overlay.visible = _coach_on or _marker_alpha > 0.004 or _tag_alpha > 0.004
	set_process(true)

	_names.text = _player_name
	_opponent.text = _opponent_name
	_house.visible = false
	_phase.text = _phase_word
	# The round is three minutes (brief v4 §2, FightTypes.FIGHT_DURATION_S). This is only
	# the value on screen before the first set_time_left, but it must not read 1:30.
	_timer.text = "3:00"
	_scrap.text = "0"
	_readout.text = ""
	_hint_primary.text = _hint_primary_text
	_hint_secondary.text = _hint_secondary_text
	_hint_boost.text = _hint_boost_text
	_hint_primary.visible = _pad_hints
	_hint_secondary.visible = _pad_hints
	_hint_boost.visible = _pad_hints
	_ko.visible = false
	_countdown.visible = false
	_result_title.visible = false
	_result_winner.visible = false


func _label(node_name: String, size_pt: float, colour: Color, align: int,
		face: Font = null) -> Label:
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
	var use := face if face != null else Broadcast.font_label()
	if use != null:
		l.add_theme_font_override("font", use)
	return l


## Labels that sit on a plate carry no outline; the ones that float over the live arena
## keep a thin one, which is the design system's "add the wash if not" in the one place
## a wash would cover the fight.
const OUTLINED_LABELS := ["Countdown", "ResultTitle", "ResultWinner", "KoCount", "KoPrompt",
	"HintPrimary", "HintSecondary", "HintBoost"]


var _laying_out: bool = false


func _relayout() -> void:
	# _place_commentary and _place_endgame both ask for a layout before they place
	# themselves, and this function places both of them: without the guard that is a
	# stack overflow the first time a line of commentary appears.
	if _laying_out:
		return
	_laying_out = true
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

	for l: Label in [_names, _opponent, _house, _timer, _phase, _scrap, _ko, _readout,
			_countdown, _result_title, _result_winner, _hint_primary, _hint_secondary, _hint_boost,
			_paused_label, _ko_prompt]:
		var px := int(round(float(l.get_meta("size_pt", 20.0)) * _pt))
		l.add_theme_font_size_override("font_size", px)
		var outline := maxi(int(round(px * 0.14)), 2) if String(l.name) in OUTLINED_LABELS else 0
		l.add_theme_constant_override("outline_size", outline)

	var pad := PAD_PT * _pt
	var gap := Broadcast.GAP * _pt
	var panel_pad := Broadcast.PANEL_PAD * _pt
	var bar := Broadcast.BAR * _pt
	var left := float(_safe["left"]) + pad
	var right := float(_safe["right"]) + pad
	var top := float(_safe["top"]) + pad
	var bottom := float(_safe["bottom"]) + pad

	# In the test arena the shell owns the top band and there is no clock at all.
	var band_top := top + (TEST_BAND_PT * _pt if _test_mode else 0.0)
	_timer.visible = not _test_mode
	_phase.visible = not _test_mode

	# The clock, a score bug top centre, with the phase word under it.
	var bug := CLOCK_BUG_PT * _pt
	_clock_rect = Rect2(Vector2(s.x * 0.5 - bug.x * 0.5, top), bug)
	_place(_timer, _clock_rect)
	var phase_h := PHASE_PT * 1.5 * _pt
	_place(_phase, Rect2(Vector2(_clock_rect.position.x, _clock_rect.position.y + bug.y + 4.0 * _pt),
		Vector2(bug.x, phase_h)))
	var head_bottom := band_top
	if not _test_mode:
		head_bottom = _clock_rect.position.y + bug.y + phase_h + 4.0 * _pt
	# Just under the clock, so the mark reads with the timer it has stopped.
	_place(_paused_label, Rect2(Vector2(_clock_rect.position.x, head_bottom + 2.0 * _pt),
		Vector2(bug.x, PAUSED_PT * 1.5 * _pt)))

	# The player's lower third, top left, with its condition bar.
	var third := THIRD_PT * _pt
	_player_rect = Rect2(Vector2(left, band_top), third)
	_place(_names, Rect2(_player_rect.position + Vector2(bar + panel_pad, 4.0 * _pt),
		Vector2(third.x - bar - panel_pad * 2.0, NAMES_PT * 1.7 * _pt)))

	# The scrap bug, top right, keeping the shell's pause button corner clear. On the live
	# build the gold counter sat exactly there and read "SCRA"; CORNER_RESERVE_PT is
	# measured from the safe area, so it holds at any inset.
	var scrap_bug := SCRAP_BUG_PT * _pt
	var reserve_left := s.x - float(_safe["right"]) \
		- (CORNER_RESERVE_PT + CORNER_CLEARANCE_PT) * _pt
	_scrap_rect = Rect2(Vector2(reserve_left - scrap_bug.x, band_top), scrap_bug)
	_place(_scrap, Rect2(
		_scrap_rect.position + Vector2(panel_pad, scrap_bug.y * 0.34),
		Vector2(maxf(scrap_bug.x - panel_pad * 2.0, 1.0), scrap_bug.y * 0.58)))
	_scrap.pivot_offset = Vector2(_scrap.size.x, _scrap.size.y * 0.5)

	# The opponent's lower third sits under the bug, so nothing of it reaches the corner.
	_opponent_rect = Rect2(
		Vector2(s.x - right - third.x, band_top + scrap_bug.y + gap), third)
	_place(_opponent, Rect2(_opponent_rect.position + Vector2(panel_pad, 4.0 * _pt),
		Vector2(third.x - bar - panel_pad * 2.0, NAMES_PT * 1.7 * _pt)))
	# The house bot's name under it, in danger, while it is out.
	_place(_house, Rect2(
		Vector2(_opponent_rect.position.x + panel_pad,
			_opponent_rect.position.y + third.y + 2.0 * _pt),
		Vector2(third.x - panel_pad * 2.0, NAMES_PT * 1.6 * _pt)))

	# The ticker along the bottom, flush with the safe area, and the height readout on the
	# row above it.
	var ticker_h := Broadcast.TICKER_H * _pt
	_ticker_rect = Rect2(Vector2(0.0, s.y - float(_safe["bottom"]) - ticker_h),
		Vector2(s.x, ticker_h))
	var readout_h := READOUT_PT * 1.6 * _pt
	_readout_rect = Rect2(Vector2(left, _ticker_rect.position.y - gap - readout_h),
		Vector2(maxf(s.x - left - right, 1.0), readout_h))
	_place(_readout, _readout_rect)

	# Centre furniture. The knockout count sits a little above the middle so it does
	# not land on top of the two bots at the default framing.
	var ko_h := KO_PT * 3.0 * _pt
	var ko_top := s.y * 0.5 - ko_h * 0.5 - 40.0 * _pt
	_ko_rect = Rect2(Vector2(s.x * 0.5 - 260.0 * _pt, ko_top), Vector2(520.0 * _pt, ko_h))
	_band(_ko, ko_top, ko_h, left, right)
	_band(_ko_prompt, ko_top + ko_h, KO_PROMPT_PT * 1.8 * _pt, left, right)
	var cd_h := COUNTDOWN_PT * 1.4 * _pt
	_band(_countdown, s.y * 0.5 - cd_h * 0.5, cd_h, left, right)
	_countdown.pivot_offset = Vector2(_countdown.size.x * 0.5, _countdown.size.y * 0.5)
	var rt_h := RESULT_TITLE_PT * 1.5 * _pt
	var rw_h := RESULT_WINNER_PT * 1.8 * _pt
	# B12 (combat feel): the result is a LOWER third, never across the middle. The wreckage
	# orbit (and the finish beat's slow motion) centres the wreck on the frame, and a banner
	# across the centre covered exactly the thing it was framing (vortex_finish_sheet.jpg).
	# It sits in the band above the ticker, as low as the ticker allows.
	var result_top := minf(s.y * RESULT_BAND_TOP,
		_ticker_rect.position.y - gap - rt_h - 6.0 * _pt - rw_h)
	_result_rect = Rect2(Vector2(left, result_top),
		Vector2(maxf(s.x - left - right, 1.0), rt_h))
	_band(_result_title, _result_rect.position.y, rt_h, left, right)
	_result_title_home = _result_title.position.x
	_result_title.position.x = _result_title_home \
		+ (1.0 - _result_slide) * -(_result_rect.size.x + _result_rect.position.x)
	_band(_result_winner, result_top + rt_h + 6.0 * _pt, rw_h, left, right)

	# The ENDGAME band: full width, across the middle.
	var eg_h := ENDGAME_PT * 1.5 * _pt
	_endgame_rect = Rect2(Vector2(left, s.y * 0.5 - eg_h * 0.5),
		Vector2(maxf(s.x - left - right, 1.0), eg_h))
	if _endgame != null and is_instance_valid(_endgame):
		_band(_endgame, _endgame_rect.position.y, _endgame_rect.size.y, left, right)
		_endgame_home_x = _endgame.position.x
		_endgame.position.x = _endgame_home_x + _endgame_slide * _endgame_travel()
	if _commentary != null and is_instance_valid(_commentary):
		_place_commentary()

	# Pad hints sit exactly where the buttons they replace would be.
	var centres := _button_centres(s)
	var hint_h := HINT_PT * 2.0 * _pt
	var hint_w := 200.0 * _pt
	_place_centred(_hint_primary, centres["primary"], hint_w, hint_h)
	_place_centred(_hint_secondary, centres["secondary"], hint_w, hint_h)
	if centres.has("boost"):
		_place_centred(_hint_boost, centres["boost"], hint_w * 0.7, hint_h)
	_laying_out = false
	_chrome_dirty()


## How many viewport pixels one design point is worth on this screen. 2.1692 on an iPhone 17
## with the stretch disabled. Anything outside this file that wants to check a point-sized
## piece of the layout has to multiply by it.
func points() -> float:
	return _pt


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
		"boost": primary + FightControls.BOOST_OFFSET_PT * _pt,
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


## The label face a drawn string uses: the theme's, or the engine default when the
## Broadcast font has not been bundled.
func _font_label(on: Control) -> Font:
	var font := Broadcast.font_label()
	if font != null:
		return font
	return on.get_theme_default_font()


## Centres a label on a point, for furniture that is not a full width band.
func _place_centred(l: Label, centre: Vector2, width: float, height: float) -> void:
	_place(l, Rect2(Vector2(centre.x - width * 0.5, centre.y - height * 0.5),
		Vector2(width, height)))


## Places a label in an exact rectangle, anchored top left so `position` is where it says.
func _place(l: Label, rect: Rect2) -> void:
	l.set_anchors_preset(Control.PRESET_TOP_LEFT, false)
	l.anchor_left = 0.0
	l.anchor_right = 0.0
	l.anchor_top = 0.0
	l.anchor_bottom = 0.0
	l.offset_left = rect.position.x
	l.offset_right = rect.position.x + rect.size.x
	l.offset_top = rect.position.y
	l.offset_bottom = rect.position.y + rect.size.y


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


## The drawn chrome's canvas: every plate, bug, bar and strip in the feed. A Control only
## because _draw needs one; it is MOUSE_FILTER_IGNORE on a CanvasLayer that never handles
## input, and it is the first child of Root so every label sits on top of it.
class ChromeOverlay extends Control:
	var hud: FightHud = null

	func _draw() -> void:
		if hud != null and is_instance_valid(hud):
			hud._draw_chrome(self)


## The coach callouts' canvas. A Control only because _draw needs one; it is
## MOUSE_FILTER_IGNORE and sits on a CanvasLayer that never handles input, so it can
## never come between a thumb and the controls underneath it.
class CoachOverlay extends Control:
	var hud: FightHud = null

	func _draw() -> void:
		if hud != null and is_instance_valid(hud):
			hud._draw_coach(self)


# ---------------------------------------------------------------- the corner zone (G2)
#
# brief v4 §3: while the player's machine is standing in the house bot's corner, the
# frame flashes red and the house bot is named. Design system section 4: the warning is a
# `danger` inner edge glow on the whole frame, 6 pt, plus the name in the ticker. The
# first time it happens, the coach line says what the corner is for.
#
# It draws on its own overlay rather than on the coach one, so the warning is a section
# of this file and nothing else in it has to know the corner exists.

const ZONE_PULSE_S := 0.9
const ZONE_FADE_S := 0.18
const ZONE_EDGE_PT := Broadcast.EDGE_GLOW
const ZONE_COACH_PT := Broadcast.LABEL_PT
const ZONE_COACH_S := 4.5
const ZONE_COACH_TEXT := "CORNER ZONE. THE HOUSE BOT GUARDS IT."
const COL_ZONE := Broadcast.DANGER

var _zone_on: bool = false
var _zone_alpha: float = 0.0
var _zone_pulse: float = 0.0
var _zone_name: String = ""
var _zone_coach_s: float = -1.0
var _zone_overlay: Control = null


## The player's machine is in the house bot's corner, or has left it. `zone_name` is the
## house bot's name, which goes into the ticker so the warning says what is coming.
func set_zone_warning(on: bool, zone_name: String) -> void:
	_build()
	_ensure_zone_overlay()
	if not zone_name.is_empty():
		_zone_name = zone_name.to_upper()
		if _house_name.is_empty():
			_house_name = _zone_name
	if on == _zone_on:
		return
	_zone_on = on
	if on:
		_zone_pulse = 0.0
		if not _zone_name.is_empty():
			push_commentary("%s CORNER ZONE" % _zone_name)
	if _zone_overlay != null and is_instance_valid(_zone_overlay):
		_zone_overlay.visible = true
		_zone_overlay.queue_redraw()


## The one coach line the corner gets, held for a few seconds and faded. Called once by
## the rules layer, the first time the player stands in the corner with the coach on.
func show_zone_coach() -> void:
	_build()
	_ensure_zone_overlay()
	_zone_coach_s = 0.0
	if _zone_overlay != null and is_instance_valid(_zone_overlay):
		_zone_overlay.visible = true
		_zone_overlay.queue_redraw()


## True while the warning is drawn at all. For the headless test.
func zone_warning_visible() -> bool:
	return _zone_alpha > 0.004


func zone_warning_name() -> String:
	return _zone_name


func zone_coach_visible() -> bool:
	return _zone_coach_s >= 0.0 and _zone_coach_s < ZONE_COACH_S


## Drive the flash by hand, for the headless test and for any caller that wants the
## timeline without waiting on real frames.
func zone_step(delta: float) -> void:
	_zone_step(delta)


func _zone_step(delta: float) -> void:
	var target := 1.0 if _zone_on else 0.0
	var moved := false
	if not is_equal_approx(_zone_alpha, target):
		_zone_alpha = move_toward(_zone_alpha, target, delta / maxf(ZONE_FADE_S, 0.001))
		moved = true
	if _zone_alpha > 0.004:
		_zone_pulse = fposmod(_zone_pulse + delta, ZONE_PULSE_S)
		moved = true
	if _zone_coach_s >= 0.0 and _zone_coach_s < ZONE_COACH_S:
		_zone_coach_s += delta
		moved = true
	if not moved or _zone_overlay == null or not is_instance_valid(_zone_overlay):
		return
	_zone_overlay.visible = _zone_alpha > 0.004 or zone_coach_visible()
	_zone_overlay.queue_redraw()


func _ensure_zone_overlay() -> void:
	if _zone_overlay != null and is_instance_valid(_zone_overlay):
		return
	var existing := get_node_or_null("ZoneWarning") as Control
	if existing != null:
		_zone_overlay = existing
	else:
		var overlay := ZoneOverlay.new()
		overlay.name = "ZoneWarning"
		overlay.hud = self
		add_child(overlay)
		_zone_overlay = overlay
	_zone_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zone_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_zone_overlay.theme = Broadcast.theme()
	_zone_overlay.visible = _zone_alpha > 0.004 or zone_coach_visible()


## The warning: a `danger` inner edge glow on the whole frame inside the safe area,
## pulsing while the machine is in the corner. Drawn as plain rectangles rather than a
## shader or a texture, so it looks the same on Forward+, gl_compatibility and dummy.
func _draw_zone(on: Control) -> void:
	if _zone_alpha > 0.004:
		var pulse := 0.55 + 0.45 * sin(TAU * _zone_pulse / ZONE_PULSE_S)
		var size := on.size
		var frame := Rect2(Vector2(float(_safe["left"]), float(_safe["top"])),
			Vector2(size.x - float(_safe["left"]) - float(_safe["right"]),
				size.y - float(_safe["top"]) - float(_safe["bottom"])))
		Broadcast.draw_edge_glow(on, frame, _pt, _zone_alpha * pulse, COL_ZONE)
	if not zone_coach_visible():
		return
	# The coach line fades out over its last half second, like every other callout.
	var fade := clampf((ZONE_COACH_S - _zone_coach_s) / maxf(COACH_FADE_S, 0.001), 0.0, 1.0)
	var coach_px := int(round(ZONE_COACH_PT * _pt))
	_coach_text(on, ZONE_COACH_TEXT,
		Vector2(on.size.x * 0.5, on.size.y * 0.30), coach_px, fade,
		HORIZONTAL_ALIGNMENT_CENTER)


## The corner warning's canvas. Its own _process drives the flash, so the warning needs
## nothing from the HUD's frame loop and cannot disturb anything already drawn there.
class ZoneOverlay extends Control:
	var hud: FightHud = null

	func _process(delta: float) -> void:
		if hud != null and is_instance_valid(hud):
			hud._zone_step(delta)

	func _draw() -> void:
		if hud != null and is_instance_valid(hud):
			hud._draw_zone(self)
