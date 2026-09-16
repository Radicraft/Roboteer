class_name FightCommentary extends RefCounted
## The commentary and the endgame cues (brief v4 §10 item 2, agent G6).
##
## It turns rules events into seven short lines and hands them to the HUD, and it fires
## the endgame horn and the music cue when the round turns. Nothing else.
##
## PRESENTATION, and the rule is absolute: this object may be deleted, never constructed,
## or fed nothing at all, and the fight must come out bit for bit the same. So it holds
## no fight state anybody else reads, draws from no random generator, and every hook into
## it from `fight.gd` records a fact and returns. The timing, the edge detection and the
## lines themselves happen in `step()`, which runs on the presentation frame.
##
##     var c := FightCommentary.new()
##     c.bind(hud, audio_mix)
##     c.reset("drop_zone", 2)
##     c.note_damage(info)                  # from the damage drain
##     c.note_pin(0, true)                  # from the pin check
##     c.step(delta, {"state": "fighting", "inverted": [...], "readiness": [...]})
##
## The lines are capitals and short because they are read out of the corner of an eye by
## somebody with both thumbs busy. Nothing here names a machine: a name doubles the
## length of the line and the player already knows whose bot just went over.

const OpponentAIScript := preload("res://ai/opponent_ai.gd")

const LINE_BIG_HIT := "BIG HIT"
const LINE_PINNED := "PINNED"
const LINE_IN_THE_ZONE := "IN THE ZONE"
const LINE_PIT_OPEN := "PIT OPEN"
const LINE_HOUSE_BOT_OUT := "HOUSE BOT OUT"
const LINE_FLIPPED := "FLIPPED"
const LINE_SPINNING_UP := "SPINNING UP"

## Every line this object can say, in the brief's order. The test walks it.
const LINES := [LINE_BIG_HIT, LINE_PINNED, LINE_IN_THE_ZONE, LINE_PIT_OPEN,
	LINE_HOUSE_BOT_OUT, LINE_FLIPPED, LINE_SPINNING_UP]

## What counts as a BIG HIT, and it is NOT a number invented here: it is the severity at
## which the FX layer already switches to the heavy impact sample and the big spark burst
## (`FightFx.IMPACT_HEAVY_SEVERITY`). A line that fired on hits the game was calling light
## would disagree with what the player just heard.
##
## Measured over whole AI vs AI fights (Arena/tests/_g6_severity_probe.gd, 2026-09-16) so
## the rate is known rather than hoped for:
##
##   flipper vs flipper   52 damage events, max severity 0.126  -> no BIG HIT
##   axe vs axe           24 damage events, max severity 0.111  -> no BIG HIT
##   spinner vs spinner    4 damage events, 2 of them 1.000     -> 2, both real
##
## That is the intended shape. A flipper fight's drama is the flip, and it has its own
## line; a spinner landing a bar on an armour plate is the hit worth shouting about. If
## the owner wants more of them, this constant is the one dial and nothing else moves.
const BIG_HIT_SEVERITY := FightFx.IMPACT_HEAVY_SEVERITY
## A blow that takes a part off is a big hit whatever the number says.
const BIG_HIT_ON_DETACH := true

## A pin has to HOLD before it is a pin. `Rules.is_pinned` is an instantaneous test and
## it flickers as two machines grind against each other; half a second of it is a shove
## that has become a hold.
const PIN_HOLD_S := 0.6

## A spinner is "up" at this fraction of full spin, and does not get to say so again until
## it has dropped back to the readiness the AI itself treats as spun down
## (`OpponentAI.READY_DROP`), so one bar taking hits cannot chatter.
const SPIN_READY := 0.98
const SPIN_REARM := OpponentAIScript.READY_DROP

## The same line may not be said again this soon. Separate from the HUD's one-line-every-
## two-seconds rule, which is about the screen; this is about the writing. "BIG HIT"
## three times in six seconds is not commentary, it is a stuck key.
const REPEAT_S := {
	LINE_BIG_HIT: 6.0,
	LINE_PINNED: 8.0,
	LINE_IN_THE_ZONE: 8.0,
	LINE_FLIPPED: 5.0,
	LINE_SPINNING_UP: 12.0,
	# The round turns once and the corner opens once, so these two are once a fight.
	LINE_PIT_OPEN: 1.0e9,
	LINE_HOUSE_BOT_OUT: 1.0e9,
}
const REPEAT_DEFAULT_S := 6.0

## The only arena with a pit to open (brief v4 §2). Every other arena escalates in a way
## that has no line of its own in the brief's list.
const PIT_ARENA := "drop_zone"

const STATE_FIGHTING := "fighting"

var hud: Node = null
## The audio director (`AudioMix`), or anything with `play_endgame_horn` and `set_endgame`.
var audio: Object = null
var arena_id: String = ""
## Off in the test arena, in a Rumble and in the side events: none of them has an endgame,
## and the test arena is a workshop, not a broadcast.
var enabled: bool = true

var _now: float = 0.0
var _last_said: Dictionary = {}          ## line -> the _now it was last said at
var _said: Array[String] = []            ## everything said this fight, for the test
var _pinned: Array[bool] = []
var _pinned_since: Array[float] = []
var _pin_said: Array[bool] = []
var _inverted: Array[bool] = []
var _spin_armed: Array[bool] = []
var _zone_on: bool = false
var _endgame_done: bool = false


func bind(hud_node: Node, audio_node: Object) -> void:
	hud = hud_node
	audio = audio_node


## A new fight. `bots` is how many machines are in it.
func reset(arena: String, bots: int = 2) -> void:
	arena_id = arena
	_now = 0.0
	_last_said.clear()
	_said.clear()
	_zone_on = false
	_endgame_done = false
	var n := maxi(bots, 1)
	_pinned = []
	_pinned_since = []
	_pin_said = []
	_inverted = []
	_spin_armed = []
	for i in n:
		_pinned.append(false)
		_pinned_since.append(-1.0)
		_pin_said.append(false)
		_inverted.append(false)
		_spin_armed.append(false)
	if hud != null and is_instance_valid(hud) and hud.has_method("clear_commentary"):
		hud.call("clear_commentary")
	# A fight that starts is a fight that is not in its endgame, whatever the last one
	# left on the Ambience bus.
	_set_audio_endgame(false)


# ---------------------------------------------------------------- the hooks
#
# Every one of these is called from an EXISTING event point in fight.gd. They record and
# return; none of them may take a decision the simulation could notice.

## A damage_event, from the presentation drain of `_pending_fx`.
func note_damage(info: Dictionary) -> void:
	var severity := float(info.get("severity", 0.0))
	var detached := BIG_HIT_ON_DETACH and bool(info.get("detached", false))
	if severity >= BIG_HIT_SEVERITY or detached:
		_say(LINE_BIG_HIT)


## The pin rule's answer for one machine this tick (`Rules.is_pinned`). The hold is timed
## in step(), so this is one array write.
func note_pin(index: int, pinned: bool) -> void:
	if index < 0 or index >= _pinned.size():
		return
	_pinned[index] = pinned


## The player's machine went into (or came out of) the house bot's corner. G2's
## `_update_zone_warning` already edge-detects this, so the line is on the way in only.
func note_zone(on: bool, _zone_name: String = "") -> void:
	if on and not _zone_on:
		_say(LINE_IN_THE_ZONE)
	_zone_on = on


## The house bot has left its mark: released at the endgame, or sent in by the idle rule.
func note_house_bot_out() -> void:
	_say(LINE_HOUSE_BOT_OUT)


## `fight.gd`'s `phase_changed`. The endgame is the only phase with anything to say.
func on_phase_changed(phase: String) -> void:
	if phase != FightTypes.PHASE_ENDGAME or _endgame_done:
		return
	_endgame_done = true
	# The cues first: the horn belongs to the moment, not to the line about it.
	_endgame_audio()
	if arena_id == PIT_ARENA:
		_say(LINE_PIT_OPEN)


# ---------------------------------------------------------------- the frame

## One presentation frame. `facts` is read only and every key is optional:
##   state      "countdown" | "fighting" | "result"
##   inverted   Array[bool], one per machine
##   readiness  Array[float], one per machine, 0..1
##   spinning   Array[bool], whether that machine's weapon spins up at all
func step(delta: float, facts: Dictionary = {}) -> void:
	_now += delta
	if str(facts.get("state", "")) != STATE_FIGHTING:
		return
	_step_pins()
	_step_flips(facts.get("inverted", []) as Array)
	_step_spin(facts.get("readiness", []) as Array, facts.get("spinning", []) as Array)


func _step_pins() -> void:
	for i in _pinned.size():
		if not bool(_pinned[i]):
			_pinned_since[i] = -1.0
			_pin_said[i] = false
			continue
		if _pinned_since[i] < 0.0:
			_pinned_since[i] = _now
		if not bool(_pin_said[i]) and _now - float(_pinned_since[i]) >= PIN_HOLD_S:
			_pin_said[i] = true
			_say(LINE_PINNED)


func _step_flips(inverted: Array) -> void:
	for i in mini(inverted.size(), _inverted.size()):
		var now_inverted := bool(inverted[i])
		if now_inverted and not bool(_inverted[i]):
			_say(LINE_FLIPPED)
		_inverted[i] = now_inverted


func _step_spin(readiness: Array, spinning: Array) -> void:
	for i in mini(readiness.size(), _spin_armed.size()):
		if i < spinning.size() and not bool(spinning[i]):
			continue
		var r := float(readiness[i])
		if r >= SPIN_READY and not bool(_spin_armed[i]):
			_spin_armed[i] = true
			_say(LINE_SPINNING_UP)
		elif r <= SPIN_REARM:
			_spin_armed[i] = false


# ---------------------------------------------------------------- introspection (tests)

## Every line said this fight, in order.
func said() -> Array[String]:
	return _said


func said_count(line: String) -> int:
	var n := 0
	for s in _said:
		if s == line:
			n += 1
	return n


func endgame_fired() -> bool:
	return _endgame_done


func clock() -> float:
	return _now


# ---------------------------------------------------------------- internals

func _say(line: String) -> void:
	if not enabled or line.is_empty():
		return
	var gap := float(REPEAT_S.get(line, REPEAT_DEFAULT_S))
	if _now - float(_last_said.get(line, -1.0e9)) < gap:
		return
	_last_said[line] = _now
	_said.append(line)
	if hud != null and is_instance_valid(hud) and hud.has_method("push_commentary"):
		hud.call("push_commentary", line)
	# WAVE F (agent F2), and this is the only line of this file it touches. The crowd
	# reacts at the same instants the ticker does, off the same edge detection, so the
	# roar and the caption can never disagree about what just happened. The audio
	# director decides WHICH lines earn a reaction (AudioMix.SWELL_FOR_LINE: BIG HIT and
	# FLIPPED, and nothing else) and how often, so no policy lives here. Guarded to the
	# last call, like `_endgame_audio` below: the FX subtree is deletable by design.
	if audio != null and is_instance_valid(audio) and audio.has_method("crowd_reaction"):
		audio.call("crowd_reaction", line)


## The horn and the music cue. Guarded to the last call: the audio director is the FX
## subtree's, and the FX subtree is deletable by design (docs/audio-notes.md).
func _endgame_audio() -> void:
	if not enabled:
		return
	if audio != null and is_instance_valid(audio) and audio.has_method("play_endgame_horn"):
		audio.call("play_endgame_horn")
	_set_audio_endgame(true)


func _set_audio_endgame(on: bool) -> void:
	if audio != null and is_instance_valid(audio) and audio.has_method("set_endgame"):
		audio.call("set_endgame", on)
