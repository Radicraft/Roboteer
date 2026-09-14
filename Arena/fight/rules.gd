extends RefCounted
class_name FightRules
## Pure rule functions for the Stage 3 fight (docs/stage3-spec.md §8, brief-v3 §6).
##
## Nothing here touches the scene tree, the clock or the RNG. Every function is a
## static function of its arguments so `Arena/tests/rules_test.gd` can exercise the
## four win conditions and the judges' maths without a physics world.
##
## Scaling constants live in FightTypes (JUDGE_DAMAGE_FULL, JUDGE_AGGRESSION_FULL_S,
## JUDGE_CONTROL_FULL_S). Never redefine them here.

## The tally shape kept per bot by the fight orchestrator. Keys are the raw,
## unscaled facts; judge_scores() turns them into the 0..10 card.
##   damage_removed: condition points this bot has removed from its opponent
##   aggression_s:   seconds spent within AGGRESSION_RANGE_M of the opponent closing on it
##   weapon_hits:    weapon fires that landed (worth 1 second each, spec §8)
##   control_s:      seconds the opponent was airborne, inverted or on the spikes
##                   within CONTROL_CREDIT_S of this bot's last contact
static func empty_tally() -> Dictionary:
	return {"damage_removed": 0.0, "aggression_s": 0.0, "weapon_hits": 0, "control_s": 0.0}


const AGGRESSION_RANGE_M := 1.5
const AGGRESSION_CLOSING_MIN := 0.1     # m/s toward the opponent to count as closing
const CONTROL_RANGE_S := 2.0            # "within 2 s of your contact"
const CONTROL_RANGE_M := 2.0            # proximity that also counts as a contact touch
const TOUCH_CREDIT_S := 2.0             # hazard damage is credited to the last toucher inside this window
const WEAPON_HIT_WINDOW_S := 0.35       # a fire that produces damage this soon "made contact"
## A bot shoving another one is not immobile, it is just not getting anywhere. Inside
## this range, with this much stick, its knockout count freezes.
const PIN_RANGE_M := 1.0
const PIN_DRIVE_MIN := 0.2
## The HUD says nothing until the count has actually got somewhere.
const KO_SHOW_MIN_S := 1.0
const AIRBORNE_CLEARANCE_M := 0.12      # chassis above its spawn height by this much is airborne
const SPIKE_PATCH_HALF_M := 0.8         # the 1.6 x 1.6 m centre patch
const HEIGHT_BAND_FLOOR_MAX := 0.06
const HEIGHT_BAND_MID_MAX := 0.20


# ---------------------------------------------------------------- win condition 1: knockout

## Rolling knockout count. Movement resets it to zero, which is the whole rule.
##
## `pinned` is the one exception, and it freezes rather than resets: a bot locked nose to
## nose with the other one and still driving has not stopped fighting, so the count must
## not run, but nor has it broken free, so the count must not go back to zero either.
## Measured on the desktop QA build: a bot merely being pushed across the floor reached
## "KNOCKOUT COUNT 8" while its wheels were turning the whole time.
static func ko_count_next(current_s: float, immobile: bool, dt: float, pinned: bool = false) -> float:
	if not immobile:
		return 0.0
	if pinned:
		return current_s
	return current_s + dt


## Is this bot pinned rather than knocked out? Close to the opponent AND asking for drive.
##
## An inverted bot never counts as pinned. Spec §8 is explicit that "an inverted bot that
## cannot self-right counts down too", and an upside down bot spinning its wheels against
## the other one is exactly the case that rule exists for; exempting it would make a bot
## stuck on its back next to its opponent uncountable.
## Should the HUD be showing a knockout count at all?
##
## Two conditions, and both are about not lying to the player. A count that is FROZEN under
## the pin rule is not running, so showing it reads as "you are eight seconds from losing"
## when nothing is counting: on the desktop build the HUD flashed "TINRIBS KNOCKOUT COUNT
## 10" the instant the two bots clinched. And a count under a second is the half second
## immobility window plus noise, which flickers on every hard shove.
static func should_show_ko_count(count_s: float, advancing: bool) -> bool:
	return advancing and count_s >= KO_SHOW_MIN_S


static func is_pinned(distance_to_opponent: float, heading_length: float, inverted: bool) -> bool:
	if inverted:
		return false
	return distance_to_opponent <= PIN_RANGE_M and heading_length > PIN_DRIVE_MIN


static func is_knockout(count_s: float, ko_count_s: float) -> bool:
	return count_s >= ko_count_s


# ---------------------------------------------------------------- win condition 2: out of the arena

## Positional fallback for the arena's OOA sensor: outside the walls, or below the floor.
## The Area3D on layer 5 is authoritative when the arena scene is present; this keeps the
## rule true in headless tests and if the sensor is ever missed at high speed.
##
## `half_extent` is the arena's own half size, because not every arena is 10 m across: the
## Coliseum is 12, and hardcoding FightTypes.ARENA_SIZE declared a Coliseum bot standing at
## x = 5.5, comfortably inside its walls, out of the arena (agent A5, 2026-09-13). The
## default keeps every existing caller and every existing test correct.
static func is_out_of_arena(chassis_position: Vector3, half_extent: float = -1.0) -> bool:
	if chassis_position.y < FightTypes.OUT_OF_ARENA_Y:
		return true
	var half := half_extent if half_extent > 0.0 else FightTypes.ARENA_SIZE * 0.5
	return absf(chassis_position.x) > half or absf(chassis_position.z) > half


# ---------------------------------------------------------------- win condition 4: component kill

static func is_component_kill(condition: Dictionary) -> bool:
	return float(condition.get("core", 1.0)) <= 0.0


# ---------------------------------------------------------------- win condition 3: the judges

## Total condition points present in a condition() dictionary (the FightConfig "damage" shape).
static func condition_total(condition: Dictionary) -> float:
	var total := 0.0
	for wheel in (condition.get("wheels", []) as Array):
		total += float(wheel)
	total += float(condition.get("weapon", 0.0))
	var armour: Dictionary = condition.get("armour", {}) as Dictionary
	for key in ["front", "sides", "rear", "top"]:
		total += float(armour.get(key, 0.0))
	total += float(condition.get("drive", 0.0))
	total += float(condition.get("core", 0.0))
	return total


## Condition points removed between two snapshots of the same bot. Never negative.
static func condition_removed(start_condition: Dictionary, now_condition: Dictionary) -> float:
	return maxf(0.0, condition_total(start_condition) - condition_total(now_condition))


## The judges' card: three scores 0..10, whole numbers (bridge-spec v1 shows integers).
static func judge_scores(tally: Dictionary) -> Dictionary:
	return {
		"damage": _score(float(tally.get("damage_removed", 0.0)), FightTypes.JUDGE_DAMAGE_FULL),
		"aggression": _score(
			float(tally.get("aggression_s", 0.0)) + float(tally.get("weapon_hits", 0)),
			FightTypes.JUDGE_AGGRESSION_FULL_S),
		"control": _score(float(tally.get("control_s", 0.0)), FightTypes.JUDGE_CONTROL_FULL_S),
	}


## Unrounded card, used only to break a tie the rounded scores cannot.
static func judge_scores_raw(tally: Dictionary) -> Dictionary:
	return {
		"damage": _raw(float(tally.get("damage_removed", 0.0)), FightTypes.JUDGE_DAMAGE_FULL),
		"aggression": _raw(
			float(tally.get("aggression_s", 0.0)) + float(tally.get("weapon_hits", 0)),
			FightTypes.JUDGE_AGGRESSION_FULL_S),
		"control": _raw(float(tally.get("control_s", 0.0)), FightTypes.JUDGE_CONTROL_FULL_S),
	}


static func score_total(scores: Dictionary) -> float:
	return float(scores.get("damage", 0)) + float(scores.get("aggression", 0)) + float(scores.get("control", 0))


## Which of two tallies wins on the cards. Returns 0 for the first bot, 1 for the second.
## Spec §8: higher total wins; tie goes to damage, then to aggression. Two further
## fallbacks keep the answer deterministic rather than arbitrary: the unrounded totals,
## then config order (bot 0), which is the only stable thing left.
static func judges_winner_index(tally_a: Dictionary, tally_b: Dictionary) -> int:
	var a := judge_scores(tally_a)
	var b := judge_scores(tally_b)
	var order := [
		[score_total(a), score_total(b)],
		[float(a["damage"]), float(b["damage"])],
		[float(a["aggression"]), float(b["aggression"])],
		[score_total(judge_scores_raw(tally_a)), score_total(judge_scores_raw(tally_b))],
	]
	for pair in order:
		if pair[0] > pair[1]:
			return 0
		if pair[1] > pair[0]:
			return 1
	return 0


# ---------------------------------------------------------------- tally predicates

## Aggression: inside 1.5 m of the opponent AND closing on it.
static func is_aggressive(my_position: Vector3, my_velocity: Vector3, their_position: Vector3) -> bool:
	var to_them := their_position - my_position
	to_them.y = 0.0
	var distance := to_them.length()
	if distance > AGGRESSION_RANGE_M:
		return false
	if distance < 0.0001:
		return true     # overlapping bots are as close as aggression gets
	var flat_velocity := Vector3(my_velocity.x, 0.0, my_velocity.z)
	return flat_velocity.dot(to_them / distance) > AGGRESSION_CLOSING_MIN


## Control: the opponent is off its wheels or on the spikes, and I put it there
## (my last contact with it was less than CONTROL_RANGE_S ago).
static func is_controlling(
		opponent_airborne: bool, opponent_inverted: bool, opponent_on_spikes: bool,
		since_my_contact_s: float) -> bool:
	if since_my_contact_s > CONTROL_RANGE_S:
		return false
	return opponent_airborne or opponent_inverted or opponent_on_spikes


## True while the point sits over the centre spike patch.
static func is_on_spike_patch(position: Vector3) -> bool:
	return absf(position.x) <= SPIKE_PATCH_HALF_M and absf(position.z) <= SPIKE_PATCH_HALF_M


## Hazard attribution: "arena" damage is credited to the bot that touched the victim
## inside the last TOUCH_CREDIT_S, otherwise it is credited to nobody.
static func hazard_credit(last_toucher: String, since_touch_s: float) -> String:
	if last_toucher == "" or since_touch_s > TOUCH_CREDIT_S:
		return ""
	return last_toucher


# ---------------------------------------------------------------- readability

## Plain-word height band for the HUD readout (brief §2, the teaching affordance).
static func height_band(height_m: float) -> String:
	if height_m <= HEIGHT_BAND_FLOOR_MAX:
		return "floor"
	if height_m <= HEIGHT_BAND_MID_MAX:
		return "mid"
	return "high"


## "Your wedge: floor. Their flipper: mid." Plain sentences, no em dashes.
static func height_sentence(your_part: String, your_band: String, their_part: String, their_band: String) -> String:
	return "Your %s: %s. Their %s: %s." % [your_part, your_band, their_part, their_band]


## Banner text for a finished fight, by outcome type.
static func banner_for(outcome_type: String) -> String:
	match outcome_type:
		"ko":
			return "KNOCKOUT"
		"out_of_arena":
			return "OUT OF THE ARENA"
		"component_kill":
			return "CORE DESTROYED"
		"judges":
			return "JUDGES DECISION"
		_:
			return "FIGHT OVER"


# ---------------------------------------------------------------- internals

static func _raw(value: float, full: float) -> float:
	if full <= 0.0:
		return 0.0
	return clampf(value / full * 10.0, 0.0, 10.0)


static func _score(value: float, full: float) -> int:
	return int(round(_raw(value, full)))
