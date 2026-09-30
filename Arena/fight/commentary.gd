class_name FightCommentary extends RefCounted
## The commentary and the endgame cues (brief v4 §10 item 2; wave D "show night").
##
## Wave G gave the fight seven capital-letter ticker words. Wave D gives it a voice, in text
## (owner, 30 Sept: no spoken voice yet): a few hundred ORIGINAL lines in
## `commentary_lines.json`, keyed to real fight events, naming both machines and the part
## that came off, with mock outrage when a house bot misbehaves. It still fires the endgame
## horn and the music cue when the round turns.
##
## PRESENTATION, and the rule is absolute: this object may be deleted, never constructed,
## or fed nothing at all, and the fight must come out bit for bit the same. So it holds no
## fight state anybody else reads, and every hook into it from `fight.gd` records a fact and
## returns. Its randomness (which line of several) is its OWN 32-bit xorshift, seeded from
## the fight seed; it never touches Godot's global generator or the fight's generator, so
## the fight's seeded sequence cannot move (tests/commentary_test.gd, determinism_test.gd).
##
## THE API (other agents call this):
##
##     commentary.call_event("house_late_hit", {"house_bot": "GRUDGE", "victim": "Tinribs"})
##
## `key` is one of the keys in commentary_lines.json. `ctx` may carry attacker, victim,
## house_bot, part, arena, weapon, seconds, margin, and flags (see each key's "doc" in the
## JSON). Aliases: winner -> attacker, loser -> victim, machine / name -> attacker. A line
## only fires when every fact it names is present and every flag it needs is true, so a
## "flipped" line never runs on a machine that is the right way up. It returns the line it
## chose (or "" when the key is cooling down, unknown, or nothing matches); whether that
## line reaches the ticker is the pacing's call (below). `line_for(key, ctx)` picks a line
## without saying it, for a card that wants the words (the tale of the tape).
##
## PACING (owner brief): at most one line every ~2 s, big moments pre-empt filler, silence
## is fine, a lull of 8 s draws a jibe. One line on screen, one waiting; a waiting line
## older than its key's `life` is dropped, never shown late.

signal line_said(key: String, text: String, at: float)

const OpponentAIScript := preload("res://ai/opponent_ai.gd")
const LINES_PATH := "res://fight/commentary_lines.json"

## The owner's call is sentence case for the personality lines (docs/look/commentary.html
## shows both). False puts every line in capitals like the wave G ticker.
const SENTENCE_CASE := true

## What counts as a BIG HIT, and it is NOT a number invented here: it is the severity at
## which the FX layer switches to the heavy impact sample (`FightFx.IMPACT_HEAVY_SEVERITY`).
const BIG_HIT_SEVERITY := FightFx.IMPACT_HEAVY_SEVERITY
## First blood is the first bot-on-bot damage event at least this heavy (a scrape is not
## blood).
const FIRST_BLOOD_SEVERITY := 0.02
## A pin has to HOLD before it is a pin; `Rules.is_pinned` flickers.
const PIN_HOLD_S := 0.6
## Spun up at this fraction, spun down at the AI's own line.
const SPIN_READY := 0.98
const SPIN_REARM := OpponentAIScript.READY_DROP
## The weapon kinds that SPIN (the flamethrower's readiness is its fuel, not a speed, so
## wave G's "SPINNING UP" on a flamethrower was a line that did not match its event).
const SPIN_KINDS := ["spinner", "drum", "fbs"]
const SPIN_UP_KINDS := ["spinner", "drum", "fbs", "saw"]
## A flip is credited to the other machine when it touched the victim this recently.
const FLIP_CREDIT_S := 1.5
## A machine must STAY upside down this long before it is "flipped": a machine rolled over
## and straight back onto its wheels in the same moment was never upside down to anyone
## watching, and a line saying so a second later would be a line about nothing.
const FLIP_HOLD_S := 0.3
## Hazard damage with nobody in contact for this long is self-inflicted.
const SELF_HAZARD_S := 3.0
## A stall: no contact and no blow for this long.
const STALL_S := 8.0
const STALL_APART_M := 3.0
## A comeback: a machine at least this far behind on condition that draws level.
const COMEBACK_DEFICIT := 0.2
## Wedge under: the other machine's chassis this far above where it spawned, upright.
const WEDGE_LIFT_M := 0.06
const WEDGE_TOUCH_S := 0.2
## A spin lost "after a hit" when that machine was in a blow this recently.
const SPIN_LOST_HIT_S := 0.6
## A judges' decision this close (out of 10 points) is close; the crowd boos it.
const VERDICT_CLOSE_MARGIN := 2.0

## Pacing. The minimum gap between two lines starting, how long a line stays (scaled by
## its length, so a long line gets the reading time a short one does not need), and how
## long a line must have been up before a bigger moment may replace it.
const MIN_GAP_S := 2.0
const HOLD_MIN_S := 1.8
const HOLD_MAX_S := 3.2
const HOLD_BASE_S := 0.9
const HOLD_PER_CHAR_S := 0.03
const PREEMPT_AFTER_S := 0.8
## A line said within this many lines is not said again while another will do.
const RECENT_LINES := 14

const P_FILLER := 0
const P_BIG := 2
const P_TOP := 3

const STATE_FIGHTING := "fighting"
const STATE_COUNTDOWN := "countdown"
const STATE_RESULT := "result"

## The only arena with a pit to open (brief v4 §2).
const PIT_ARENA := "drop_zone"
const ENFORCER_ID := "enforcer-1"

## The crowd swells with the ticker's biggest moments (AudioMix.SWELL_FOR_LINE keeps the
## wave G words, so this maps the new keys onto them).
const CROWD_FOR_KEY := {
	"big_hit": "BIG HIT", "part_off": "BIG HIT", "first_blood": "BIG HIT",
	"flipped": "FLIPPED",
}

const ARENA_NAMES := {
	"yard": "the Yard", "grinder": "the Grinder", "drop_zone": "Drop Zone",
	"furnace": "the Furnace", "crush": "the Crush", "coliseum": "the Coliseum",
}
const KNOWN_ARENAS := ["yard", "grinder", "drop_zone", "furnace", "crush", "coliseum"]

## The stage index -> key, matching fight.gd's STAGE_* numbering (1 hazards up, 2 wake,
## 4 final; 3 is the endgame, which has its own moment).
const STAGE_KEYS := {1: "stage_hazards", 2: "stage_wake", 4: "stage_final"}
## Payoff kind (fight.gd `_award_payoff`) -> key.
const PAYOFF_KEYS := {
	"spikes": "payoff_spikes", "grinder": "payoff_grinder", "flame": "payoff_fire",
	"ram": "payoff_crushed", "pit": "payoff_pit", "kill": "payoff_kill",
	"ring_out": "payoff_ring_out",
}

static var _data: Dictionary = {}

var hud: Node = null
## The audio director (`AudioMix`), or anything with `play_endgame_horn` and `set_endgame`.
var audio: Object = null
var arena_id: String = ""
## Off in the test arena, a Rumble and the side events (no broadcast there).
var enabled: bool = true

# --- who is fighting (from setup) ---
var _names: Array = ["", ""]
var _ids: Array = ["", ""]
var _weapon_names: Array = []
var _weapon_kinds: Array = []
var _chassis: Array = []
var _armour: Array = []
var _house_bot: String = ""
var _player_index: int = 0
var _info: Dictionary = {}

# --- the clock and the memory ---
var _now: float = 0.0
var _state: String = ""
var _voice_state: int = 0x2545F491
var _fired: Array[String] = []               ## every key accepted, in order (tests)
var _said: Array = []                        ## [{key, text, at, fight_s}] shown lines
var _cool_until: Dictionary = {}             ## cooldown key -> _now it frees
var _groups_done: Dictionary = {}
var _recent: Array[String] = []
var _last_text_for: Dictionary = {}

# --- pacing ---
var _cur_key: String = ""
var _cur_p: int = -1
var _cur_at: float = -1.0e9
var _cur_hold: float = 0.0
var _pending: Dictionary = {}                ## {key, ctx, p, at, life}

# --- per machine detection ---
var _pinned: Array = []
var _pinned_since: Array = []
var _pin_said: Array = []
var _inverted: Array = []
var _inverted_since: Array = []
var _flip_said: Array = []
var _flip_ctx: Array = []
var _spin_armed: Array = []
var _fault: Array = []
var _deficit_max: Array = []
var _touch_age: Array = []
var _last_blow_at: Array = []                ## _now of the last blow each machine was in
var _last_hit_by: Array = []                 ## raw attacker of the last damage on each
var _first_blood: bool = false
var _last_action_at: float = 0.0
var _fight_s: float = 0.0
var _time_left: float = 1.0e9
var _zone_on: bool = false
var _endgame_done: bool = false
var _prediction_done: bool = false


func bind(hud_node: Node, audio_node: Object) -> void:
	hud = hud_node
	audio = audio_node


## A new fight. `bots` is how many machines are in it.
func reset(arena: String, bots: int = 2) -> void:
	arena_id = arena
	_now = 0.0
	_state = ""
	_fired.clear()
	_said.clear()
	_cool_until.clear()
	_groups_done.clear()
	_recent.clear()
	_last_text_for.clear()
	_cur_key = ""
	_cur_p = -1
	_cur_at = -1.0e9
	_cur_hold = 0.0
	_pending = {}
	_first_blood = false
	_last_action_at = 0.0
	_fight_s = 0.0
	_time_left = 1.0e9
	_zone_on = false
	_endgame_done = false
	_prediction_done = false
	var n := maxi(bots, 1)
	_pinned = _fill(false, n)
	_pinned_since = _fill(-1.0, n)
	_pin_said = _fill(false, n)
	_inverted = _fill(false, n)
	_inverted_since = _fill(-1.0, n)
	_flip_said = _fill(false, n)
	_flip_ctx = _fill({}, n)
	_spin_armed = _fill(false, n)
	_fault = _fill("", n)
	_deficit_max = _fill(0.0, n)
	_touch_age = _fill(1.0e9, n)
	_last_blow_at = _fill(-1.0e9, n)
	_last_hit_by = _fill("", n)
	if hud != null and is_instance_valid(hud) and hud.has_method("clear_commentary"):
		hud.call("clear_commentary")
	_set_audio_endgame(false)


## Who is fighting, for the words. Every key is optional:
##   names, ids, weapons (display names), kinds (weapon kinds), chassis (ids),
##   armour (a number per machine, bigger is more), house_bot, seed, player_index,
##   records ([[wins, losses], ...]), meetings (times these two have met).
## Call after reset().
func setup(info: Dictionary) -> void:
	_info = info.duplicate(true)
	_names = (info.get("names", _names) as Array).duplicate()
	_ids = (info.get("ids", _ids) as Array).duplicate()
	_weapon_names = (info.get("weapons", []) as Array).duplicate()
	_weapon_kinds = (info.get("kinds", []) as Array).duplicate()
	_chassis = (info.get("chassis", []) as Array).duplicate()
	_armour = (info.get("armour", []) as Array).duplicate()
	_house_bot = str(info.get("house_bot", ""))
	_player_index = int(info.get("player_index", 0))
	_seed_voice(int(info.get("seed", 0)))


# ---------------------------------------------------------------- the API

## Something happened. See the header. Returns the chosen line, or "".
func call_event(key: String, ctx: Dictionary = {}) -> String:
	if not enabled:
		return ""
	var meta := _meta(key)
	if meta.is_empty():
		return ""
	var c := _normalise(ctx)
	var group := str(meta.get("group", ""))
	if group != "" and _groups_done.has(group):
		return ""
	var cool_key := key
	var per := str(meta.get("per", ""))
	if per != "":
		cool_key = "%s|%s" % [key, str(c.get(per, ""))]
	if _now < float(_cool_until.get(cool_key, -1.0e9)):
		return ""
	# Only a key with a line that fits the facts is an event at all. A key whose every
	# line needs a fact we do not have stays silent AND does not use up its cooldown.
	if _candidates(key, c).is_empty():
		return ""
	_cool_until[cool_key] = _now + float(meta.get("cool", 6.0))
	if group != "":
		_groups_done[group] = true
	_fired.append(key)
	_crowd(key)
	var p := int(meta.get("p", 1))
	if _can_show(p):
		return _show(key, c, p)
	if _pending.is_empty() or p >= int(_pending["p"]):
		_pending = {"key": key, "ctx": c, "p": p, "at": _now,
			"life": float(meta.get("life", 2.0))}
	return ""


## A line for `key` that fits `ctx`, without saying it or touching any cooldown. "" when
## none fits. For a card that wants the words (the tale of the tape, the prediction).
func line_for(key: String, ctx: Dictionary = {}) -> String:
	var c := _normalise(ctx)
	var pool := _candidates(key, c)
	if pool.is_empty():
		return ""
	return render(str((pool[_pick_index(pool)] as Dictionary)["t"]), c)


## The prediction's facts, from the setup: who the facts favour and why.
func prediction_context() -> Dictionary:
	var a := _player_index
	var b := _foe(a)
	var ctx := {"arena": _arena_name()}
	if _house_bot != "":
		ctx["house_bot"] = _house_bot
		ctx["house"] = true
	var records: Array = _info.get("records", []) as Array
	var rec_edge := -1
	if records.size() >= 2 and records[a] is Array and records[b] is Array:
		var ra: Array = records[a] as Array
		var rb: Array = records[b] as Array
		if ra.size() >= 2 and rb.size() >= 2:
			var sa := int(ra[0]) - int(ra[1])
			var sb := int(rb[0]) - int(rb[1])
			if sa >= sb + 2:
				rec_edge = a
			elif sb >= sa + 2:
				rec_edge = b
	var arm_edge := -1
	if _armour.size() >= 2:
		var aa := float(_armour[a])
		var ab := float(_armour[b])
		if aa >= ab * 1.25 and aa > 0.0:
			arm_edge = a
		elif ab >= aa * 1.25 and ab > 0.0:
			arm_edge = b
	var fav := rec_edge if rec_edge >= 0 else arm_edge
	var first := fav if fav >= 0 else a
	var second := _foe(first)
	ctx["attacker"] = _name(first)
	ctx["victim"] = _name(second)
	ctx["weapon"] = _weapon_name(first)
	if fav >= 0:
		ctx["favourite"] = true
		ctx["record_edge"] = rec_edge == fav
		ctx["armour_edge"] = arm_edge == fav
	else:
		ctx["even"] = true
	var ka := _kind(first)
	var kb := _kind(second)
	if ka != "" and ka == kb:
		ctx["same_weapon"] = true
	if ka in SPIN_KINDS and kb in ["flipper", "lifter"]:
		ctx["spin_vs_lift"] = true
	if int(_info.get("meetings", 0)) > 0:
		ctx["rematch"] = true
	return ctx


# ---------------------------------------------------------------- the hooks from fight.gd

## A damage_event, from the presentation drain of `_pending_fx`, with its RAW attacker
## ("arena", the house bot's id, a machine id, or the victim's own id for a cooked core).
func note_damage(info: Dictionary) -> void:
	var vi := _ids.find(str(info.get("victim", "")))
	if vi < 0 or vi >= _last_hit_by.size():
		return
	var raw := str(info.get("attacker", ""))
	var ai := _ids.find(raw)
	var severity := float(info.get("severity", 0.0))
	var detached := bool(info.get("detached", false))
	var part := str(info.get("part", ""))
	var source := str(info.get("source", ""))
	_last_hit_by[vi] = raw
	var by_bot := ai >= 0 and ai != vi and ai < _last_blow_at.size()
	if by_bot and severity > 0.0:
		_last_action_at = _now
		_last_blow_at[vi] = _now
		_last_blow_at[ai] = _now
	var ctx := {"victim": _name(vi)}
	if by_bot:
		ctx["attacker"] = _name(ai)
		ctx["weapon"] = _weapon_name(ai)
		_kind_flags(ctx, ai)
	elif raw == ENFORCER_ID:
		ctx["house"] = true
		ctx["house_bot"] = _house_bot
		ctx["attacker"] = _house_bot
		_last_blow_at[vi] = _now
	elif raw == "arena":
		ctx["hazard"] = true
	if source in ["burn", "flame", "fire", "heat"]:
		ctx["src_burn"] = true

	var part_words := part_name(part)
	if detached and part_words != "":
		ctx["part"] = part_words
		ctx["part_wheel"] = part.begins_with("wheel") or part.begins_with("track")
		ctx["part_armour"] = part.begins_with("armour_")
		ctx["part_top"] = part == "armour_top"
		ctx["part_face"] = part.begins_with("armour_") and part != "armour_top"
		if by_bot:
			_first_blood = true
		call_event("part_off", ctx)
		return
	if by_bot and not _first_blood and severity >= FIRST_BLOOD_SEVERITY:
		_first_blood = true
		call_event("first_blood", ctx)
		return
	if raw == "arena":
		if float(_touch_age[vi]) > SELF_HAZARD_S and severity > 0.0:
			call_event("hazard_self", {"victim": _name(vi), "arena": _arena_name()})
		return
	if severity >= BIG_HIT_SEVERITY and (by_bot or raw == ENFORCER_ID):
		call_event("big_hit", ctx)


## The pin rule's answer for one machine this tick (`Rules.is_pinned`), timed in step().
func note_pin(index: int, pinned: bool) -> void:
	if index < 0 or index >= _pinned.size():
		return
	_pinned[index] = pinned


## The player's machine went into (or came out of) the house bot's corner.
func note_zone(on: bool, zone_name: String = "") -> void:
	if on and not _zone_on:
		var house := _house_bot if _house_bot != "" else zone_name
		call_event("in_the_zone", {"victim": _name(_player_index), "house_bot": house})
	_zone_on = on


## The house bot has left its mark: `idle` when the inactivity rule sent it in, otherwise
## the endgame release. The HUD names it under the opponent's third whether or not the
## line itself gets the ticker.
func note_house_bot_out(idle: bool = false) -> void:
	if hud != null and is_instance_valid(hud) and hud.has_method("set_house_bot"):
		hud.call("set_house_bot", _house_bot, true)
	call_event("house_bot_out", {"house_bot": _house_bot, "idle": idle, "endgame": not idle})


## `fight.gd`'s `phase_changed`. The endgame is the only phase with anything to say.
func on_phase_changed(phase: String) -> void:
	if phase != FightTypes.PHASE_ENDGAME or _endgame_done:
		return
	_endgame_done = true
	_endgame_audio()
	if arena_id == PIT_ARENA:
		call_event("pit_open", {"arena": _arena_name()})
	elif _house_bot == "":
		# With a house bot in the corner, its release IS the endgame's news, and it has
		# the bigger line (house_bot_out); two lines for one moment would queue one late.
		call_event("endgame", {"arena": _arena_name()})


## A pacing stage (fight.gd `_present_stage`): 1 hazards up, 2 the wake word, 4 final.
func note_stage(stage_index: int, word: String = "") -> void:
	var key := str(STAGE_KEYS.get(stage_index, ""))
	if key == "":
		return
	var ctx := {"arena": _arena_name(), "word": word.capitalize()}
	ctx["arena=" + arena_id] = true
	if not arena_id in KNOWN_ARENAS:
		ctx["arena_other"] = true
	call_event(key, ctx)


## A payoff (fight.gd `_present_payoff`): {kind, by, victim} with machine ids.
func note_payoff(info: Dictionary) -> void:
	var kind := str(info.get("kind", ""))
	var key := str(PAYOFF_KEYS.get(kind, "payoff_hazard"))
	var by := _ids.find(str(info.get("by", "")))
	var vi := _ids.find(str(info.get("victim", "")))
	if vi < 0:
		return
	var ctx := {"victim": _name(vi), "arena": _arena_name()}
	if by >= 0 and by != vi:
		ctx["attacker"] = _name(by)
	else:
		ctx["self"] = true
	call_event(key, ctx)


## The result (fight.gd `_finish`): outcome "ko" | "component_kill" | "judges" |
## "out_of_arena"; `margin` the judges' points between the cards.
func note_result(outcome: String, winner: int, loser: int, margin: float = 0.0) -> void:
	var ctx := {"attacker": _name(winner), "victim": _name(loser), "arena": _arena_name()}
	match outcome:
		"ko":
			ctx["inverted"] = loser >= 0 and loser < _inverted.size() and bool(_inverted[loser])
			call_event("knockout", ctx)
		"component_kill":
			var last := str(_last_hit_by[loser]) \
				if loser >= 0 and loser < _last_hit_by.size() else ""
			ctx["self"] = loser >= 0 and loser < _ids.size() and last == str(_ids[loser])
			ctx["hazard"] = last == "arena"
			call_event("core_destroyed", ctx)
		"judges":
			ctx["margin"] = snappedf(margin, 0.1)
			call_event("judges", ctx)
			call_event("verdict_close" if margin <= VERDICT_CLOSE_MARGIN else "verdict_clear", ctx)
		_:
			pass    # a ring-out has already said its payoff


# ---------------------------------------------------------------- the frame

## One presentation frame. `facts` is read only and every key is optional:
##   state      "countdown" | "fighting" | "result"
##   intro      true while the intro flyover holds the countdown
##   time, time_left   fight seconds, seconds left on the clock
##   inverted   Array[bool]      readiness  Array[float]    fault  Array[String]
##   spinning   Array[bool] (legacy; the kinds from setup win when present)
##   condition  Array[float] 0..1 of what each machine started with
##   touch_age  Array[float] seconds since each machine last touched the other
##   lifted     Array[float] metres its chassis is above where it spawned
##   distance   metres between the two
func step(delta: float, facts: Dictionary = {}) -> void:
	_now += delta
	var state := str(facts.get("state", ""))
	var was := _state
	_state = state
	_fight_s = float(facts.get("time", _fight_s))
	if facts.has("touch_age"):
		var ages: Array = facts["touch_age"] as Array
		for i in mini(ages.size(), _touch_age.size()):
			_touch_age[i] = float(ages[i])

	if state == STATE_COUNTDOWN and not bool(facts.get("intro", false)) and not _prediction_done:
		_prediction_done = true
		call_event("prediction", prediction_context())
	if state == STATE_FIGHTING and was == STATE_COUNTDOWN:
		_last_action_at = _now
		call_event("fight_start", {"attacker": _name(_player_index),
			"victim": _name(_foe(_player_index)), "arena": _arena_name()})

	if state == STATE_FIGHTING:
		_step_pins()
		_step_flips(facts.get("inverted", []) as Array)
		_step_spin(facts.get("readiness", []) as Array, facts.get("spinning", []) as Array)
		_step_faults(facts.get("fault", []) as Array)
		_step_comeback(facts.get("condition", []) as Array)
		_step_wedge(facts.get("lifted", []) as Array, facts.get("inverted", []) as Array)
		_step_clock(float(facts.get("time_left", _time_left)))
		_step_stall(float(facts.get("distance", 0.0)))
	_pace()


func _step_pins() -> void:
	for i in _pinned.size():
		if not bool(_pinned[i]):
			_pinned_since[i] = -1.0
			_pin_said[i] = false
			continue
		if float(_pinned_since[i]) < 0.0:
			_pinned_since[i] = _now
		if not bool(_pin_said[i]) and _now - float(_pinned_since[i]) >= PIN_HOLD_S:
			_pin_said[i] = true
			_last_action_at = _now
			call_event("pinned", {"attacker": _name(_foe(i)), "victim": _name(i)})


func _step_flips(inverted: Array) -> void:
	for i in mini(inverted.size(), _inverted.size()):
		var now_inverted := bool(inverted[i])
		if now_inverted and not bool(_inverted[i]):
			# The rising edge: who did it is decided NOW, while the contact is fresh.
			_inverted_since[i] = _now
			_flip_said[i] = false
			var ctx := {"victim": _name(i)}
			var foe := _foe(i)
			if float(_touch_age[i]) <= FLIP_CREDIT_S and foe >= 0:
				ctx["attacker"] = _name(foe)
				_kind_flags(ctx, foe)
			elif str(_last_hit_by[i]) == ENFORCER_ID \
					and _now - float(_last_blow_at[i]) < FLIP_CREDIT_S:
				ctx["house"] = true
				ctx["house_bot"] = _house_bot
			else:
				ctx["self"] = true
			_flip_ctx[i] = ctx
		elif now_inverted and not bool(_flip_said[i]) \
				and _now - float(_inverted_since[i]) >= FLIP_HOLD_S:
			_flip_said[i] = true
			_last_action_at = _now
			call_event("flipped", _flip_ctx[i] as Dictionary)
		elif not now_inverted and bool(_inverted[i]) and bool(_flip_said[i]) \
				and _now - float(_inverted_since[i]) >= 0.5:
			call_event("self_right", {"victim": _name(i)})
		_inverted[i] = now_inverted


func _step_spin(readiness: Array, spinning: Array) -> void:
	for i in mini(readiness.size(), _spin_armed.size()):
		var kind := _kind(i)
		var spins := (kind in SPIN_UP_KINDS) if kind != "" \
			else (i < spinning.size() and bool(spinning[i]))
		if not spins:
			continue
		var r := float(readiness[i])
		if r >= SPIN_READY and not bool(_spin_armed[i]):
			_spin_armed[i] = true
			var ctx := {"attacker": _name(i), "weapon": _weapon_name(i)}
			_kind_flags(ctx, i)
			call_event("spinning_up", ctx)
		elif r <= SPIN_REARM and bool(_spin_armed[i]):
			_spin_armed[i] = false
			if i < _fault.size() and str(_fault[i]) != "":
				continue      # a dead weapon has its own line
			var lost := {"attacker": _name(i), "victim": _name(_foe(i)),
				"weapon": _weapon_name(i),
				"after_hit": _now - float(_last_blow_at[i]) <= SPIN_LOST_HIT_S}
			_kind_flags(lost, i)
			call_event("spin_lost", lost)


func _step_faults(faults: Array) -> void:
	for i in mini(faults.size(), _fault.size()):
		var f := str(faults[i])
		if f != str(_fault[i]):
			var ctx := {"victim": _name(i), "weapon": _weapon_name(i),
				"player": i == _player_index}
			if f == "jammed":
				call_event("weapon_jammed", ctx)
			elif f == "cooked":
				call_event("weapon_cooked", ctx)
		_fault[i] = f


func _step_comeback(condition: Array) -> void:
	if condition.size() < 2:
		return
	for i in mini(condition.size(), _deficit_max.size()):
		var foe := _foe(i)
		if foe < 0 or foe >= condition.size():
			continue
		var deficit := float(condition[foe]) - float(condition[i])
		if deficit > float(_deficit_max[i]):
			_deficit_max[i] = deficit
		if float(_deficit_max[i]) >= COMEBACK_DEFICIT and deficit <= 0.0:
			_deficit_max[i] = -1.0e9          # once per machine
			call_event("comeback", {"attacker": _name(i), "victim": _name(foe)})


func _step_wedge(lifted: Array, inverted: Array) -> void:
	for a in mini(_chassis.size(), _names.size()):
		if str(_chassis[a]) != "wedge":
			continue
		var v := _foe(a)
		if v < 0 or v >= lifted.size() or a >= lifted.size() or v >= _touch_age.size():
			continue
		var upright := v >= inverted.size() or not bool(inverted[v])
		if upright and float(lifted[v]) >= WEDGE_LIFT_M and float(lifted[a]) < WEDGE_LIFT_M \
				and float(_touch_age[v]) <= WEDGE_TOUCH_S:
			call_event("wedge_under", {"attacker": _name(a), "victim": _name(v)})


func _step_clock(time_left: float) -> void:
	if _time_left > 10.0 and time_left <= 10.0 and time_left > 0.0:
		call_event("last_ten", {"attacker": _name(_player_index),
			"victim": _name(_foe(_player_index))})
	_time_left = time_left


func _step_stall(distance: float) -> void:
	for age in _touch_age:
		if float(age) < 0.25:
			_last_action_at = _now
			return
	var quiet := _now - _last_action_at
	if quiet < STALL_S or _now - _cur_at < STALL_S * 0.5:
		return
	call_event("stall", {"attacker": _name(_player_index),
		"victim": _name(_foe(_player_index)), "apart": distance > STALL_APART_M,
		"seconds": str(int(quiet))})
	# Said, waiting or cooling down, the lull has been noticed: the next jibe needs a new one.
	_last_action_at = _now


# ---------------------------------------------------------------- pacing

func _can_show(p: int) -> bool:
	if _cur_key == "":
		return true
	var up := _now - _cur_at
	if up >= maxf(MIN_GAP_S, _cur_hold):
		return true
	if up < PREEMPT_AFTER_S:
		return false
	# A big moment takes the ticker from filler, and a payoff or a result from anything
	# less than a payoff or a result.
	return p >= _cur_p + 2 or (p >= P_TOP and _cur_p < P_TOP)


func _pace() -> void:
	if _pending.is_empty():
		return
	if _now - float(_pending["at"]) > float(_pending["life"]):
		_pending = {}
		return
	var p := int(_pending["p"])
	if not _still_true(str(_pending["key"]), _pending["ctx"] as Dictionary):
		_pending = {}
		return
	if _can_show(p):
		var pend := _pending
		_pending = {}
		_show(str(pend["key"]), pend["ctx"] as Dictionary, p)


## A line that waited must still be true when it goes up: "X is upside down!" about a
## machine that has since righted itself is exactly the licensed games' mistake.
func _still_true(key: String, ctx: Dictionary) -> bool:
	var v := _names.find(str(ctx.get("victim", "")))
	if v < 0:
		return true
	match key:
		"flipped":
			return v < _inverted.size() and bool(_inverted[v])
		"self_right":
			return v < _inverted.size() and not bool(_inverted[v])
		"pinned":
			return v < _pinned.size() and bool(_pinned[v])
	return true


func _show(key: String, ctx: Dictionary, p: int) -> String:
	var pool := _candidates(key, ctx)
	if pool.is_empty():
		return ""
	var entry: Dictionary = pool[_pick_index(pool)]
	var text := render(str(entry["t"]), ctx)
	if not SENTENCE_CASE:
		text = text.to_upper()
	_cur_key = key
	_cur_p = p
	_cur_at = _now
	_cur_hold = hold_for(text)
	_recent.append(str(entry["t"]))
	while _recent.size() > RECENT_LINES:
		_recent.pop_front()
	_last_text_for[key] = str(entry["t"])
	_said.append({"key": key, "text": text, "at": snappedf(_now, 0.01),
		"fight_s": snappedf(_fight_s, 0.01)})
	if hud != null and is_instance_valid(hud):
		if hud.has_method("say_commentary"):
			hud.call("say_commentary", text, _cur_hold, key == "prediction")
		elif hud.has_method("push_commentary"):
			hud.call("push_commentary", text)
	line_said.emit(key, text, _fight_s)
	return text


## How long a line of this length stays up.
static func hold_for(text: String) -> float:
	return clampf(HOLD_BASE_S + HOLD_PER_CHAR_S * float(text.length()), HOLD_MIN_S, HOLD_MAX_S)


# ---------------------------------------------------------------- the lines

static func data() -> Dictionary:
	if not _data.is_empty():
		return _data
	var text := FileAccess.get_file_as_string(LINES_PATH)
	var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
	_data = parsed as Dictionary if parsed is Dictionary else {"keys": {}}
	return _data


static func keys() -> Array:
	return (data().get("keys", {}) as Dictionary).keys()


static func _meta(key: String) -> Dictionary:
	return (data().get("keys", {}) as Dictionary).get(key, {}) as Dictionary


## Every line of `key` whose facts are all true of `ctx`, as {t, if, w}.
static func _candidates(key: String, ctx: Dictionary) -> Array:
	var out: Array = []
	for line_variant in (_meta(key).get("lines", []) as Array):
		var entry := entry_of(line_variant)
		if fits(entry, ctx):
			out.append(entry)
	return out


## A line as {t, if, w}, whether the JSON wrote it as a plain string or an object.
static func entry_of(line_variant: Variant) -> Dictionary:
	if line_variant is Dictionary:
		return line_variant as Dictionary
	return {"t": str(line_variant)}


## True when every placeholder in the line has a fact and every guard holds.
static func fits(entry: Dictionary, ctx: Dictionary) -> bool:
	for token_variant in (entry.get("if", []) as Array):
		if not _guard(str(token_variant), ctx):
			return false
	for field in placeholders(str(entry.get("t", ""))):
		if str(ctx.get(field, "")).strip_edges() == "":
			return false
	return true


static func _guard(token: String, ctx: Dictionary) -> bool:
	var negate := token.begins_with("!")
	var t := token.substr(1) if negate else token
	var ok := false
	var eq := t.find("=")
	if eq > 0:
		ok = str(ctx.get(t.substr(0, eq), "")) == t.substr(eq + 1) or _truthy(ctx.get(t, false))
	else:
		ok = _truthy(ctx.get(t, false))
	return ok != negate


static func _truthy(v: Variant) -> bool:
	if v is bool:
		return v
	if v is String:
		return not (v as String).is_empty()
	if v is int or v is float:
		return float(v) != 0.0
	return v != null


static func placeholders(text: String) -> Array:
	var out: Array = []
	var at := text.find("{")
	while at >= 0:
		var end := text.find("}", at)
		if end < 0:
			break
		var field := text.substr(at + 1, end - at - 1)
		if not field in out:
			out.append(field)
		at = text.find("{", end)
	return out


## The template with its facts filled in, each sentence starting with a capital.
static func render(template: String, ctx: Dictionary) -> String:
	var text := template
	for field in placeholders(template):
		var value := str(ctx.get(field, ""))
		text = text.replace("{%s}'s" % field, possessive(value))
		text = text.replace("{%s}" % field, value)
	return sentence_caps(text)


## "Tinribs'" rather than "Tinribs's"; "Clatterbox's" as ever.
static func possessive(value: String) -> String:
	if value.ends_with("s") or value.ends_with("S"):
		return value + "'"
	return value + "'s"


static func sentence_caps(text: String) -> String:
	var out := ""
	var cap_next := true
	for i in text.length():
		var ch := text.substr(i, 1)
		if cap_next and ch != " ":
			out += ch.to_upper()
			cap_next = false
			continue
		out += ch
		if ch == "." or ch == "!" or ch == "?":
			cap_next = i + 1 < text.length() and text.substr(i + 1, 1) == " "
	return out


## Weighted choice among the pool, never the line this key said last while there is
## another, and nothing said in the last RECENT_LINES lines while anything else will do.
func _pick_index(pool: Array) -> int:
	var allowed: Array[int] = []
	for i in pool.size():
		if not str((pool[i] as Dictionary)["t"]) in _recent:
			allowed.append(i)
	if allowed.is_empty():
		for i in pool.size():
			if not str((pool[i] as Dictionary)["t"]) in _last_text_for.values():
				allowed.append(i)
	if allowed.is_empty():
		for i in pool.size():
			allowed.append(i)
	var total := 0
	for i in allowed:
		total += maxi(int((pool[i] as Dictionary).get("w", 10)), 1)
	var roll := _next_voice() % maxi(total, 1)
	for i in allowed:
		roll -= maxi(int((pool[i] as Dictionary).get("w", 10)), 1)
		if roll < 0:
			return i
	return allowed[allowed.size() - 1]


## The commentary's own generator: 32-bit xorshift on a plain int. Deliberately NOT a
## RandomNumberGenerator and never the global one, so nothing here can move the fight.
func _seed_voice(seed_value: int) -> void:
	# Neighbouring fight seeds (11, 22, 33) must not open on the same line, so the seed is
	# mixed (a murmur-style finaliser) before the xorshift starts.
	var x := (seed_value ^ 0x5EEDC0DE) & 0xFFFFFFFF
	x = (x * 0x9E3779B1) & 0xFFFFFFFF
	x ^= x >> 16
	x = (x * 0x85EBCA6B) & 0xFFFFFFFF
	x ^= x >> 13
	_voice_state = x if x != 0 else 0x2545F491
	for i in 4:
		_next_voice()


func _next_voice() -> int:
	var x := _voice_state
	x ^= (x << 13) & 0xFFFFFFFF
	x ^= x >> 17
	x ^= (x << 5) & 0xFFFFFFFF
	_voice_state = x & 0xFFFFFFFF
	return _voice_state


# ---------------------------------------------------------------- words for things

## A detached part's name for a line ("" when it has no honest name).
static func part_name(part: String) -> String:
	match part:
		"armour_front": return "front armour"
		"armour_sides": return "side armour"
		"armour_rear": return "rear armour"
		"armour_top": return "top armour"
		"track_l": return "left track"
		"track_r": return "right track"
	if part.begins_with("wheel_") and part.length() == 8:
		var row := str({"f": "front", "m": "middle", "r": "rear"}.get(part.substr(6, 1), ""))
		var side := str({"l": "left", "r": "right"}.get(part.substr(7, 1), ""))
		if row != "" and side != "":
			return "%s %s wheel" % [row, side]
	if part.begins_with("wheel"):
		return "wheel"
	return ""


func _normalise(ctx: Dictionary) -> Dictionary:
	var c := ctx.duplicate()
	if not c.has("attacker"):
		for alias in ["winner", "machine", "name"]:
			if c.has(alias):
				c["attacker"] = c[alias]
				break
	if not c.has("victim") and c.has("loser"):
		c["victim"] = c["loser"]
	if not c.has("arena"):
		c["arena"] = _arena_name()
	if not c.has("house_bot") and _house_bot != "":
		c["house_bot"] = _house_bot
	for k in ["attacker", "victim", "house_bot", "part", "arena", "weapon"]:
		if c.has(k):
			c[k] = str(c[k]).strip_edges()
	if c.has("weapon"):
		c["weapon"] = str(c["weapon"]).to_lower()
	for k in ["attacker", "victim", "house_bot"]:
		var v := str(c.get(k, ""))
		if v != "":
			c["%s=%s" % [k, v]] = true
	return c


func _kind_flags(ctx: Dictionary, index: int) -> void:
	var kind := _kind(index)
	if kind == "":
		return
	ctx["wk"] = kind
	ctx["wk=" + kind] = true
	if kind in SPIN_KINDS:
		ctx["spin_weapon"] = true


func _name(index: int) -> String:
	if index < 0 or index >= _names.size():
		return ""
	return str(_names[index])


func _weapon_name(index: int) -> String:
	if index < 0 or index >= _weapon_names.size():
		return ""
	return str(_weapon_names[index]).to_lower()


func _kind(index: int) -> String:
	if index < 0 or index >= _weapon_kinds.size():
		return ""
	return str(_weapon_kinds[index])


## The other machine in a two-machine fight (commentary is off in a Rumble).
func _foe(index: int) -> int:
	return 1 if index == 0 else 0


func _arena_name() -> String:
	return str(ARENA_NAMES.get(arena_id, arena_id.capitalize()))


static func _fill(value: Variant, n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append(value)
	return out


# ---------------------------------------------------------------- introspection (tests)

## Every line said this fight, in order: [{key, text, at, fight_s}].
func said() -> Array:
	return _said


## Every key accepted as an event this fight (said or not), in order.
func fired() -> Array[String]:
	return _fired


func fired_count(key: String) -> int:
	var n := 0
	for k in _fired:
		if k == key:
			n += 1
	return n


func said_count(key: String) -> int:
	var n := 0
	for s in _said:
		if str((s as Dictionary)["key"]) == key:
			n += 1
	return n


func pending_key() -> String:
	return str(_pending.get("key", ""))


func endgame_fired() -> bool:
	return _endgame_done


func clock() -> float:
	return _now


# ---------------------------------------------------------------- audio

func _crowd(key: String) -> void:
	var word := str(CROWD_FOR_KEY.get(key, ""))
	if word == "":
		return
	if audio != null and is_instance_valid(audio) and audio.has_method("crowd_reaction"):
		audio.call("crowd_reaction", word)


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
