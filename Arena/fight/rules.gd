extends RefCounted
class_name FightRules
## Pure rule functions for the Stage 3 fight (docs/stage3-spec.md §8, brief-v3 §6).
##
## Nothing here touches the scene tree, the clock or the RNG. Every function is a
## static function of its arguments so `Arena/tests/rules_test.gd` can exercise the
## four win conditions and the judges' maths without a physics world.
##
## Scaling constants live in FightTypes (JUDGE_*_POINTS, JUDGE_*_FLOOR, JUDGE_SWEEP_LEAD).
## Never redefine them here.

## The tally shape kept per bot by the fight orchestrator. Keys are the raw,
## unscaled facts; judge_cards() turns two of them into the judges' split of ten points.
##   damage_removed: condition points this bot has removed from its opponent
##   aggression_s:   seconds spent within AGGRESSION_RANGE_M of the opponent closing on it
##   weapon_hits:    weapon fires that landed (worth 1 second each, spec §8)
##   control_s:      seconds the opponent was airborne, inverted or on the arena's RISEN
##                   spikes (and this bot was not on them too) within CONTROL_RANGE_S of
##                   this bot's last contact
##   lost_frac:      wave B judges: the fraction of its OWN starting condition this bot has
##                   lost, from every cause. The fight fills it (fill_damage_taken) just
##                   before it asks the judges; with the two below it is the damage criterion.
##   parts_out:      wave B judges: parts knocked out this fight (destroyed, or a dead drive)
##   vital_out:      wave B judges: of those, the weapon and the drive
##   payoff_s:       wave B pacing: control-seconds earned by the big moments (a shove
##                   into a live hazard, a hazard kill), PAYOFF_* below; scored as control
static func empty_tally() -> Dictionary:
	return {"damage_removed": 0.0, "aggression_s": 0.0, "weapon_hits": 0, "control_s": 0.0,
		"payoff_s": 0.0, "lost_frac": 0.0, "parts_out": 0, "vital_out": 0}


# ---------------------------------------------------------------- wave B pacing: payoffs
#
# The thing to chase (owner, 2026-09-27): flipping or shoving the other machine into a
# hazard, into the pit or out of the arena. A ring-out already ends the fight; the rest
# are scored here, heavily, as CONTROL (you put them there), on top of whatever damage the
# hazard did, which is credited to you anyway (TOUCH_CREDIT_S).
#
## A hazard visit is credited to the machine that was in physical contact with the victim
## (or landed a blow on it) this recently before the hazard bit.
const PAYOFF_CREDIT_S := 1.5
## Hazard damage on one machine closer together than this is one visit (one payoff).
const PAYOFF_VISIT_GAP_S := 1.5
## Control-seconds a credited hazard visit is worth: 8 of JUDGE_CONTROL_FULL_S (30), so a
## single shove onto the spikes is about 2.7 of the 10 control points.
const PAYOFF_HAZARD_S := 8.0
## And a hazard KILL (the visit takes a part off, or the core): 12 more, 20 in all.
const PAYOFF_KILL_S := 12.0
## One machine yields at most one hazard payoff in this long: the moment has to stay a
## moment (the first measure paid nine a fight in the Furnace, docs/qa/pacing.md).
const PAYOFF_VICTIM_COOLDOWN_S := 10.0


## Who gets the payoff for a hazard visit: the last machine in contact inside the window,
## never the victim itself, else nobody.
static func payoff_credit(last_contact: String, since_contact_s: float, victim: String) -> String:
	if last_contact == "" or last_contact == victim or since_contact_s > PAYOFF_CREDIT_S:
		return ""
	return last_contact


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
const SPIKE_PATCH_HALF_M := 0.8         # the Yard's 1.6 x 1.6 m centre patch (the default)
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


## A machine that is FIGHTING at close quarters is not knocked out, wherever its centre is
## (weapons gauntlet bug 2, 2026-09-25): a drill lance, a saw or a prod holds the two hulls
## 1.04 to 1.3 m apart while it works, past PIN_RANGE_M, and the attacker was counted out
## while winning. Inside ENGAGED_RANGE_M it is engaged when EITHER it is driving (the pin's
## PIN_DRIVE_MIN) with a part of it physically touching the opponent, OR it removed condition
## from them within ENGAGED_DAMAGE_S. Engaged freezes the count exactly as a pin does.
## Inverted never counts (see is_pinned). Every input is a simulation fact.
const ENGAGED_RANGE_M := 2.0
const ENGAGED_DAMAGE_S := 2.0

static func is_engaged(distance_to_opponent: float, heading_length: float, touching: bool,
		since_dealt_damage_s: float, inverted: bool) -> bool:
	if inverted or distance_to_opponent > ENGAGED_RANGE_M:
		return false
	if touching and heading_length > PIN_DRIVE_MIN:
		return true
	return since_dealt_damage_s <= ENGAGED_DAMAGE_S


static func is_knockout(count_s: float, ko_count_s: float) -> bool:
	return count_s >= ko_count_s


## Seconds after the countdown ends before the PLAYER's knockout count can start, if the
## player has not driven by then.
const PLAYER_KO_GRACE_S := 10.0

## Is the player's knockout count armed yet? (added 2026-09-14)
##
## Measured on a live device run: a player who had not yet worked out that there were any
## controls was under "KNOCKOUT COUNT" from the first second and lost without ever having
## moved, seven fights running. A count that starts before the player has touched anything
## is not a rule, it is a trap. So it arms as soon as the player asks for any drive at all,
## and in any case PLAYER_KO_GRACE_S after the countdown ends.
##
## `has_driven` is a fact about the RECORDED INPUT STREAM (any tick whose heading was not
## zero) and `fight_time_s` is the simulation clock, so this is a pure function of the
## replay log and arms on exactly the same tick in a fight and in its replay. The
## opponent's count is not affected: an AI that never moves has broken down.
static func ko_count_armed(has_driven: bool, fight_time_s: float) -> bool:
	return has_driven or fight_time_s >= PLAYER_KO_GRACE_S


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


## The judges (wave B judges, 2026-09-27; docs/wave-b-judges-notes.md "How the judges
## score"). Owner, on the phone: "i virtually had no damage one game but the judges decided
## the opponent won". The old card scored each machine ALONE against absolute scales, and
## damage topped out at 2.5 condition points, so both machines had 10 for damage in most
## fights and the decision fell to control seconds. The card is now a split of ten points
## between the two machines, criterion by criterion, and every criterion is relative:
##
##   DAMAGE      5 points  who lost less of their own machine (every cause: blows, hazards,
##                         the house bot), with a part knocked out counting a further
##                         tenth of a machine and the weapon or drive two tenths. The
##                         heaviest: when one machine took more than twice what the
##                         other did (7 to 3) it takes all five, which no sweep of the
##                         other two can overturn.
##   CONTROL     3 points  seconds the other machine was on its back, in the air or on the
##                         risen spikes because of you, plus hazard payoffs (8 s a shove
##                         into a live hazard, 20 s for a hazard kill).
##   AGGRESSION  2 points  seconds driving in on the other machine at close range, plus one
##                         for every weapon blow that landed.
##
## Highest total wins. A tie goes to the bigger damage lead, then control, then aggression,
## then the first machine (the only stable thing left).

## The damage measure of one tally: condition lost plus the parts knocked out
## (FightTypes.JUDGE_PART_OUT / JUDGE_VITAL_OUT).
static func damage_taken(tally: Dictionary) -> float:
	return float(tally.get("lost_frac", 0.0)) \
		+ FightTypes.JUDGE_PART_OUT * float(tally.get("parts_out", 0)) \
		+ FightTypes.JUDGE_VITAL_OUT * float(tally.get("vital_out", 0))


## Fills a tally's damage keys from the machine's condition at the start and now. A part
## that was already out when the fight started (condition carries between matches) is not
## knocked out again. Pure: condition in, numbers out, so a replay fills the same ones.
static func fill_damage_taken(tally: Dictionary, start: Dictionary, now: Dictionary) -> void:
	tally["lost_frac"] = damage_fraction(start, now)
	var before: Array = []
	for row in parts_lost(start):
		before.append(str((row as Dictionary)["part"]))
	var parts := 0
	var vital := 0
	for row in parts_lost(now):
		var part := str((row as Dictionary)["part"])
		if before.has(part):
			continue
		parts += 1
		if part == "weapon" or part == "drive":
			vital += 1
	tally["parts_out"] = parts
	tally["vital_out"] = vital


## One criterion's lead for `mine` over `theirs`, -1..1: the difference over the total, the
## total floored so that two small numbers make a small lead.
static func judge_lead(mine: float, theirs: float, floor_value: float) -> float:
	var total := maxf(maxf(mine, 0.0) + maxf(theirs, 0.0), floor_value)
	if total <= 0.0:
		return 0.0
	return clampf((maxf(mine, 0.0) - maxf(theirs, 0.0)) / total, -1.0, 1.0)


## A criterion's points for the side with this lead: half the pool each at no lead, all of
## it at `sweep` (JUDGE_SWEEP_LEAD, or JUDGE_DAMAGE_SWEEP_LEAD for damage) or more.
static func judge_points(lead: float, pool: float,
		sweep: float = FightTypes.JUDGE_SWEEP_LEAD) -> float:
	var share := 0.5 + 0.5 * clampf(lead / sweep, -1.0, 1.0)
	return pool * share


## The same, to one decimal, rounded so that the two machines' points in a column always
## add up to the column: the leader's share is rounded, the other gets the rest.
static func judge_points_shown(lead: float, pool: float,
		sweep: float = FightTypes.JUDGE_SWEEP_LEAD) -> float:
	if lead >= 0.0:
		return snappedf(judge_points(lead, pool, sweep), 0.1)
	return snappedf(pool - snappedf(judge_points(-lead, pool, sweep), 0.1), 0.1)


## The raw measures a tally carries, per criterion.
static func _control_of(tally: Dictionary) -> float:
	return float(tally.get("control_s", 0.0)) + float(tally.get("payoff_s", 0.0))


static func _aggression_of(tally: Dictionary) -> float:
	return float(tally.get("aggression_s", 0.0)) + float(tally.get("weapon_hits", 0))


## Damage lead of `me` over `them`: they lost more of their machine than I did of mine.
## A tally without `lost_frac` (a caller that predates it) falls back on the condition
## points each machine removed from the other, over ten (about one machine).
static func damage_lead(me: Dictionary, them: Dictionary) -> float:
	if me.has("lost_frac") and them.has("lost_frac"):
		return judge_lead(damage_taken(them), damage_taken(me), FightTypes.JUDGE_DAMAGE_FLOOR)
	return judge_lead(float(me.get("damage_removed", 0.0)) / 10.0,
		float(them.get("damage_removed", 0.0)) / 10.0, FightTypes.JUDGE_DAMAGE_FLOOR)


static func control_lead(me: Dictionary, them: Dictionary) -> float:
	return judge_lead(_control_of(me), _control_of(them), FightTypes.JUDGE_CONTROL_FLOOR_S)


static func aggression_lead(me: Dictionary, them: Dictionary) -> float:
	return judge_lead(_aggression_of(me), _aggression_of(them), FightTypes.JUDGE_AGGRESSION_FLOOR_S)


## The judges' card for `me` against `them`: {damage, control, aggression}, each to one
## decimal. `me`'s card and `them`'s card add up to 5 / 3 / 2 in every column.
static func judge_scores(me: Dictionary, them: Dictionary = {}) -> Dictionary:
	var foe := them if not them.is_empty() else empty_tally()
	return {
		"damage": judge_points_shown(damage_lead(me, foe), FightTypes.JUDGE_DAMAGE_POINTS,
			FightTypes.JUDGE_DAMAGE_SWEEP_LEAD),
		"aggression": judge_points_shown(aggression_lead(me, foe), FightTypes.JUDGE_AGGRESSION_POINTS),
		"control": judge_points_shown(control_lead(me, foe), FightTypes.JUDGE_CONTROL_POINTS),
	}


## Both cards at once, [card_a, card_b].
static func judge_cards(tally_a: Dictionary, tally_b: Dictionary) -> Array:
	return [judge_scores(tally_a, tally_b), judge_scores(tally_b, tally_a)]


## A Rumble machine is judged against the field: the mean of everyone else's tally.
static func field_tally(tallies: Array, except_index: int) -> Dictionary:
	var out := {"damage_removed": 0.0, "aggression_s": 0.0, "weapon_hits": 0.0,
		"control_s": 0.0, "payoff_s": 0.0, "lost_frac": 0.0, "parts_out": 0.0, "vital_out": 0.0}
	var n := 0
	for i in tallies.size():
		if i == except_index:
			continue
		n += 1
		var t: Dictionary = tallies[i] as Dictionary
		for key in out.keys():
			out[key] = float(out[key]) + float(t.get(key, 0.0))
	if n > 0:
		for key in out.keys():
			out[key] = float(out[key]) / float(n)
	return out


static func score_total(scores: Dictionary) -> float:
	return snappedf(float(scores.get("damage", 0)) + float(scores.get("aggression", 0))
		+ float(scores.get("control", 0)), 0.1)


## Which of two tallies wins on the cards. Returns 0 for the first bot, 1 for the second.
## The higher total on the printed cards wins, so the card the player reads always agrees
## with the decision. A tie goes to the bigger damage lead, then control, then aggression
## (the unrounded leads), and last to the first machine, which keeps it deterministic.
static func judges_winner_index(tally_a: Dictionary, tally_b: Dictionary) -> int:
	var cards := judge_cards(tally_a, tally_b)
	var total_a := score_total(cards[0])
	var total_b := score_total(cards[1])
	if total_a > total_b + 0.001:
		return 0
	if total_b > total_a + 0.001:
		return 1
	for lead in [damage_lead(tally_a, tally_b), control_lead(tally_a, tally_b),
			aggression_lead(tally_a, tally_b)]:
		if float(lead) > 0.0001:
			return 0
		if float(lead) < -0.0001:
			return 1
	return 0


## The decision in plain words, for the result screen and the log: which criteria each
## machine took. "Won on damage and control. Lost on aggression."
static func judges_reason(card_mine: Dictionary, card_theirs: Dictionary) -> String:
	var won: Array = []
	var lost: Array = []
	for key in ["damage", "control", "aggression"]:
		var a := float(card_mine.get(key, 0.0))
		var b := float(card_theirs.get(key, 0.0))
		if a > b + 0.001:
			won.append(key)
		elif b > a + 0.001:
			lost.append(key)
	var parts: Array = []
	if not won.is_empty():
		parts.append("Won on %s." % _and_list(won))
	if not lost.is_empty():
		parts.append("Lost on %s." % _and_list(lost))
	if parts.is_empty():
		return "Level on every card."
	return " ".join(parts)


static func _and_list(items: Array) -> String:
	if items.size() == 1:
		return str(items[0])
	return ", ".join(items.slice(0, items.size() - 1)) + " and " + str(items.back())


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


## True while the point sits over a spike patch: the arena's OWN patch (its centre and its
## full width), never an assumed one. `extent` 0 or less means the arena has no spikes,
## and nothing is ever on them. The defaults are the Yard's centre patch.
## (Wave B judges: every arena used to count the middle 1.6 m as "on the spikes", so two
## machines clinched in the middle of the Furnace both scored control.)
static func is_on_spike_patch(position: Vector3, centre: Vector3 = Vector3.ZERO,
		extent: float = SPIKE_PATCH_HALF_M * 2.0) -> bool:
	if extent <= 0.0:
		return false
	var half := extent * 0.5
	return absf(position.x - centre.x) <= half and absf(position.z - centre.z) <= half


## Is the opponent on the spikes in a way that is CONTROL for me? The spikes are up (a
## retracted or sleeping patch is floor), they are on it, and I am not on it with them: two
## machines clinched on the patch did not put each other there.
static func spikes_control(foe_on_patch: bool, me_on_patch: bool, spikes_up: bool) -> bool:
	return spikes_up and foe_on_patch and not me_on_patch


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


# ---------------------------------------------------------------- wave P: the scrap ledger
#
# brief v5 sections 3 and 9.3. A career fight carries `rules.scrap`
# ({base, damage_full, survivor, survivor_min, flawless}) and the arena tallies the four
# lines from CONDITION, never from the bolt shower: the bolts are the show, the ledger is
# the state. Everything here is a pure function of two condition dictionaries, so a replay
# of a fight produces exactly the same ledger and nothing is drawn from the rng.
#
# An empty rules dictionary means "no career scrap in this fight" (a quick fight, a side
# event, the test arena, the ladder), and every helper answers zero for it, which is what
# keeps the legacy bolt scrap exactly what it was.

## Human labels for the condition keys: the words a player reads in the match report.
## Wheel keys come from the drive module (`DriveBase.condition_keys`): four wheel rows give
## wheel_fl/fr/rl/rr, six add wheel_ml/mr, tracks give track_l and track_r.
const PART_LABELS := {
	"weapon": "Weapon",
	"drive": "Drive",
	"core": "Core",
	"armour_front": "Front armour",
	"armour_sides": "Side armour",
	"armour_rear": "Rear armour",
	"armour_top": "Top armour",
	"track_l": "Left track",
	"track_r": "Right track",
	"wheel_fl": "Front left wheel",
	"wheel_fr": "Front right wheel",
	"wheel_ml": "Middle left wheel",
	"wheel_mr": "Middle right wheel",
	"wheel_rl": "Rear left wheel",
	"wheel_rr": "Rear right wheel",
}

## The two words `parts_lost` uses for `state`. A part at zero condition is destroyed; a
## part still on the machine that has stopped answering is disabled (brief v5 section 5,
## "parts destroyed or disabled").
const STATE_DESTROYED := "destroyed"
const STATE_DISABLED := "disabled"

## The faults `Bot.weapon_fault()` reports, both of which stop the weapon without taking
## its condition to zero.
const WEAPON_FAULTS := ["jammed", "cooked"]

const EMPTY_BREAKDOWN := {"base": 0, "damage": 0, "survivor": 0, "flawless": 0, "total": 0}


## Fraction of a bot's condition that has been removed, 0..1. The denominator is what it
## STARTED the fight with, because condition carries between matches (brief v5 section 5):
## a machine that goes in at 60 % and is left at 30 % has had half of what it had taken
## off it, and its opponent is paid for half.
static func damage_fraction(start_condition: Dictionary, now_condition: Dictionary) -> float:
	var start_total := condition_total(start_condition)
	if start_total <= 0.0:
		return 0.0
	return clampf(1.0 - condition_total(now_condition) / start_total, 0.0, 1.0)


## The damage line: `damage_full` x the fraction of the OPPONENT's condition removed.
static func damage_bonus(rules: Dictionary, foe_start: Dictionary, foe_now: Dictionary) -> int:
	if rules.is_empty():
		return 0
	return int(round(float(rules.get("damage_full", 0.0))
		* damage_fraction(foe_start, foe_now)))


## The survivor line: paid when a bot's OWN condition at the bell is still at least
## `survivor_min` of what it started with.
static func survivor_bonus(rules: Dictionary, start_condition: Dictionary,
		now_condition: Dictionary) -> int:
	if rules.is_empty():
		return 0
	var start_total := condition_total(start_condition)
	if start_total <= 0.0:
		return 0
	var floor_total := float(rules.get("survivor_min", 0.7)) * start_total
	if condition_total(now_condition) >= floor_total:
		return int(round(float(rules.get("survivor", 0.0))))
	return 0


## The flawless line: won the fight and nothing reached zero. Not "took no damage": a
## machine can come home dented and still have lost no part.
static func flawless_bonus(rules: Dictionary, won: bool, now_condition: Dictionary) -> int:
	if rules.is_empty() or not won:
		return 0
	if any_part_zero(now_condition):
		return 0
	return int(round(float(rules.get("flawless", 0.0))))


## Is any wheel or track, the weapon, the drive, the core or an armour face at zero?
static func any_part_zero(condition: Dictionary) -> bool:
	for wheel in (condition.get("wheels", []) as Array):
		if float(wheel) <= 0.0:
			return true
	if float(condition.get("weapon", 1.0)) <= 0.0:
		return true
	var armour: Dictionary = condition.get("armour", {}) as Dictionary
	for face in ["front", "sides", "rear", "top"]:
		if float(armour.get(face, 1.0)) <= 0.0:
			return true
	if float(condition.get("drive", 1.0)) <= 0.0:
		return true
	return float(condition.get("core", 1.0)) <= 0.0


## The four scrap lines and their total, for one bot.
##
## `at_bell` false is the live tally and is the whole of the difference between the running
## number and the banked one: the HUD's scrap bug shows base plus the damage so far, and
## the survivor and flawless lines are decided when the bell rings.
static func scrap_breakdown(rules: Dictionary, own_start: Dictionary, own_now: Dictionary,
		foe_start: Dictionary, foe_now: Dictionary, won: bool,
		at_bell: bool = true) -> Dictionary:
	if rules.is_empty():
		return EMPTY_BREAKDOWN.duplicate()
	var base := int(round(float(rules.get("base", 0.0))))
	var damage := damage_bonus(rules, foe_start, foe_now)
	var survivor := survivor_bonus(rules, own_start, own_now) if at_bell else 0
	var flawless := flawless_bonus(rules, won, own_now) if at_bell else 0
	return {
		"base": base,
		"damage": damage,
		"survivor": survivor,
		"flawless": flawless,
		"total": base + damage + survivor + flawless,
	}


## Every part this bot lost, in the order the match report reads them out: the weapon, the
## drive, the wheels, the armour faces, the core.
##
## `wheel_keys` is the drive module's condition keys, in the same order as
## `condition["wheels"]`; `weapon_fault` is `Bot.weapon_fault()` ("" for a healthy weapon,
## and "" as well for a machine with no weapon fitted, which has nothing to lose).
static func parts_lost(condition: Dictionary, wheel_keys: Array = [],
		weapon_fault: String = "") -> Array:
	var out: Array = []

	var weapon := float(condition.get("weapon", 1.0))
	if weapon <= 0.0:
		out.append(_lost_row("weapon", STATE_DESTROYED))
	elif WEAPON_FAULTS.has(weapon_fault):
		out.append(_lost_row("weapon", STATE_DISABLED))

	# A dead drive is `disabled`, not `destroyed`: the motors have stopped but nothing has
	# come off the machine, and the report's words have to match what the player can see.
	if float(condition.get("drive", 1.0)) <= 0.0:
		out.append(_lost_row("drive", STATE_DISABLED))

	var wheels: Array = condition.get("wheels", []) as Array
	for i in range(wheels.size()):
		if float(wheels[i]) > 0.0:
			continue
		var key := str(wheel_keys[i]) if i < wheel_keys.size() else "wheel_%d" % i
		out.append(_lost_row(key, STATE_DESTROYED))

	var armour: Dictionary = condition.get("armour", {}) as Dictionary
	for face in ["front", "sides", "rear", "top"]:
		if float(armour.get(face, 1.0)) <= 0.0:
			out.append(_lost_row("armour_" + face, STATE_DESTROYED))

	if float(condition.get("core", 1.0)) <= 0.0:
		out.append(_lost_row("core", STATE_DESTROYED))

	return out


## The words for one condition key. An unknown key becomes readable rather than raw, so a
## wheel row nothing has a label for still reads as words ("wheel_x4" -> "Wheel X4").
static func part_label(part_key: String) -> String:
	if PART_LABELS.has(part_key):
		return str(PART_LABELS[part_key])
	return part_key.replace("_", " ").capitalize()


## `hits` for the result: what each bot landed, and what it took from the others. In a two
## bot fight "taken" is exactly the opponent's landed count; in a Rumble it is the sum of
## everyone else's, which is the closest true thing without per pair bookkeeping.
static func hits_from_tallies(tallies: Array, ids: Array) -> Dictionary:
	var out: Dictionary = {}
	var count := mini(tallies.size(), ids.size())
	for i in range(count):
		var landed := int((tallies[i] as Dictionary).get("weapon_hits", 0))
		var taken := 0
		for j in range(count):
			if j != i:
				taken += int((tallies[j] as Dictionary).get("weapon_hits", 0))
		out[str(ids[i])] = {"landed": landed, "taken": taken}
	return out


# ---------------------------------------------------------------- internals

static func _lost_row(part_key: String, state: String) -> Dictionary:
	return {"part": part_key, "label": part_label(part_key), "state": state}

