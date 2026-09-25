extends RefCounted
class_name OpponentAI
## A bot driver (docs/stage3-spec.md §9). Produces one BotInput dictionary per physics
## tick from the shared RandomNumberGenerator.
##
## fight.gd builds one of these for the opponent always, and a second one for the player
## bot when `debug.player_ai` is set (QA now, the async ladder's ghost builds later).
##
## Two layers, since wave F (docs/wave-f-f4-notes.md):
##
##   THE DECISION LAYER decides what this machine is TRYING to do this tick -- close,
##   hold the ring, work round to a flank, pin them on the wall, shove them onto
##   something, give ground, get off a hazard, press the srimech. That is wave G's work
##   (skill, temperament, wall pin, hazard shove, weapon counters, srimech, showboat) and
##   it is unchanged in kind.
##
##   THE MOVEMENT LAYER turns that intent into a heading with CONTEXT STEERING
##   (`ai/context_steering.gd`): an interest map from the intent, a danger map from every
##   live hazard, the walls, the house bot and its corner, and the opponent's weapon arc;
##   interest masked BY danger; the surviving slots summed; the result eased across ticks.
##
## The split is the whole point. The owner played wave G on the phone and said the enemy
## AI was "really stupid, driving straight into the spikes", and it was: avoidance was a
## vector added to the approach, so a strong enough wish to attack drove the machine
## through a hazard. Masking cannot do that. NO TIER MAY EVER LOOK STUPID (the owner's
## verdict, 2026-09-16): every tier avoids every hazard, every wall and the house bot
## unless it is pushed into one. A tier is beatable because it reacts late, aims wide,
## hesitates and presses less, never because it drives itself into a grinder.
##
## Deterministic by construction:
##   1. It draws from the rng at a FIXED cadence (once every JITTER_TICKS ticks, always,
##      in every mode) before any branching, so no decision can change how many numbers it
##      consumes.
##   2. It reads only positions, velocities and the bots' public API, never the clock,
##      never Engine.get_frames_drawn, never a second rng.
##   3. The steering is pure arithmetic over fixed-size arrays, and the only memory it
##      carries between ticks (the smoothed heading) is a function of the ticks before it.
##
## Frame conventions it assumes about the Bot API (see docs/stage3-rules-notes.md):
##   - `bot.chassis` is a Node3D-or-better whose `global_position` is the bot position.
##   - The bot's nose points along **+X** of `bot.chassis.global_transform.basis`. That is
##     not Godot's usual forward, it is the convention `Bot._drive` and `Bot.place_at`
##     actually use (`fwd = chassis.global_basis.x`), and the AI has to agree with the
##     drive or its aim is ninety degrees out.
##   - An input heading of Vector2(x, y) asks for world direction Vector3(x, 0, y).
##     heading_from_world_dir() is the single place that mapping lives.

const MODE_NORMAL := "normal"
const MODE_IDLE := "idle"
const MODE_CHARGE := "charge"
## Not a behaviour: "off" means no driver at all. `debug.player_ai` defaults to it, and
## fight.gd builds no OpponentAI for a bot whose driver is off.
const MODE_OFF := "off"

# --- the fight, at arm's length ------------------------------------------------------
## Ring the bot holds while it looks for an angle. Far enough out to turn freely, close
## enough to dart in before the opponent can square up.
const STANDOFF_M := 1.4
const STANDOFF_BAND_M := 0.35       # how sloppily the ring is held while circling
## An approach angle is good when the bot is more than this far off the opponent's nose.
## 50 degrees puts it on a front corner at worst, and on the side or rear at best.
const GOOD_ANGLE_DEG := 50.0
## Once committed to a dart, keep going until this angle is lost, so it does not dither
## on the way in.
const ABANDON_ANGLE_DEG := 78.0
const ABANDON_RANGE_M := 2.2
## A dart is a COMMITMENT, and for this long it cannot be talked out of on the angle
## alone. Wave G set the flag and then abandoned it on the very next tick whenever the
## opponent was still nose on (which is exactly when patience runs out and the driver
## goes in anyway), so "it gives up looking and commits" was one tick of heading that the
## machine never had time to act on: measured, and it is why a Regional driver looked
## like it was pacing rather than attacking. 0.6 s is about two metres of run in.
const DART_MIN_TICKS := 36

# --- the strike ----------------------------------------------------------------------
## Chassis centre to chassis centre reach. The bots are 0.9 m long, so 0.9 is nose on
## nose; the slack lets the flipper start its sweep as the wedge bites rather than after.
##
## This is deliberately NOT the old "front edge within 0.45 m of their chassis" test.
## That test inverts in a clinch: at 0.3 m apart the front edge is already PAST the
## opponent's centre, the vector from edge to chassis points backwards, and the facing
## check fails exactly when the bots are locked together. Measured: 2322 ticks inside 1 m
## over 45 seconds and not one shot fired.
const STRIKE_REACH_M := 0.9
const STRIKE_SLACK_M := 0.2
const STRIKE_ANGLE_DEG := 45.0
const CHARGE_FIRE_RANGE_M := 0.9
## After firing, give ground so a whole tank of gas is not dumped into one clinch.
const BACKOFF_M := 0.6
const BACKOFF_MAX_TICKS := 45       # 0.75 s, a hard stop in case the retreat is blocked
const FIRE_COOLDOWN_TICKS := 48     # 0.8 s, just over FightTypes.FLIPPER_COOLDOWN_S

# --- housekeeping --------------------------------------------------------------------
const FRONT_EDGE_M := 0.45          # nose offset from the chassis centre
const JITTER_TICKS := 30            # 0.5 s at 60 Hz
const JITTER_MAX := 0.15
const RECOVER_STILL_SPEED := 0.35   # m/s: "nearly still" before pressing the srimech
const RECOVER_RETRY_TICKS := 90
const RECOVER_GIVE_UP_PRESSES := 2
const REVERSE_TICKS := 45
## How long before the patch rises a machine standing on it starts leaving, and how far
## off the centre still counts as standing on it. MEASURED in the physics world, 2026-09-16:
## at wave G's 1.0 s and 1.2 m a Championship driver in a clinch over the middle of the
## Yard was still on the patch when it came up, twice in four 60 s fights, because a
## machine that is being shoved does not clear 0.8 m in a second, and at 1.6 s and 1.4 m a
## Scrapyard one still was. The arena itself only declares the patch live 1.5 s ahead
## (ArenaBase._danger_positions), so the driver has to read the clock earlier than the
## arena does -- and it has to start leaving from further out than the patch is wide,
## because a wedge takes half a second to turn round before it goes anywhere.
const SPIKE_AVOID_LEAD_S := 2.4
const SPIKE_AVOID_RANGE_M := 1.8

# --- weapon kinds (docs/stage4-spec.md §6) -------------------------------------------
## `WeaponBase.kind`, straight out of the catalogue. Everything the AI does differently
## per weapon is in PROFILES and nowhere else, so a new weapon needs one row, not a branch.
##   standoff    ring radius it holds while it looks for an angle, metres
##   engage      fire range as a multiple of the weapon's own reach, plus ENGAGE_SLACK_M
##   flank       needs a side or rear angle before it commits, or charges straight in
##   spin_up     will not engage below READY_ENGAGE readiness, disengages below READY_DROP
##   hold        the weapon wants to be held on (saws, flame, spinners) rather than tapped
##   latch       stays in the clinch instead of giving ground after a hit
##   orbit       circles at the standoff while engaged, rather than closing
const PROFILES := {
	"flipper": {"standoff": 1.15, "engage": 1.0, "flank": true, "spin_up": false,
		"hold": false, "latch": false, "orbit": false},
	"lifter": {"standoff": 1.05, "engage": 1.0, "flank": true, "spin_up": false,
		"hold": true, "latch": true, "orbit": false},
	"drum": {"standoff": 1.4, "engage": 1.0, "flank": true, "spin_up": true,
		"hold": true, "latch": false, "orbit": false},
	"spinner": {"standoff": 1.7, "engage": 1.1, "flank": true, "spin_up": true,
		"hold": true, "latch": false, "orbit": false},
	"fbs": {"standoff": 1.3, "engage": 1.2, "flank": false, "spin_up": true,
		"hold": true, "latch": false, "orbit": true},
	"saw": {"standoff": 1.0, "engage": 0.9, "flank": false, "spin_up": true,
		"hold": true, "latch": true, "orbit": false},
	"crusher": {"standoff": 1.0, "engage": 0.9, "flank": false, "spin_up": false,
		"hold": true, "latch": true, "orbit": false},
	"axe": {"standoff": 1.1, "engage": 0.7, "flank": false, "spin_up": false,
		"hold": false, "latch": false, "orbit": false},
	"ram": {"standoff": 0.0, "engage": 0.0, "flank": false, "spin_up": false,
		"hold": false, "latch": true, "orbit": false},
	"flame": {"standoff": 0.0, "engage": 1.0, "flank": false, "spin_up": false,
		"hold": true, "latch": false, "orbit": true},
	# --- wave P (D1): the kinds brief v5 section 9.5 adds ------------------------
	# A prod fights in the clinch and never gives ground: its whole weapon is a
	# touch, and its payoff is the stalled drive it leaves behind.
	"prod": {"standoff": 0.0, "engage": 0.9, "flank": false, "spin_up": false,
		"hold": true, "latch": true, "orbit": false},
	# An arc needs to be near, not on: it charges at its standoff, circles while it
	# waits, and will not commit on an empty coil.
	"arc": {"standoff": 0.9, "engage": 1.0, "flank": false, "spin_up": true,
		"hold": true, "latch": false, "orbit": true},
	# A drill is a saw that does not care what the plate is made of, so it fights
	# the saw's fight: get on them, stay on them.
	"drill": {"standoff": 1.0, "engage": 0.9, "flank": false, "spin_up": true,
		"hold": true, "latch": true, "orbit": false},
}
## PER WEAPON, when the kind's row is not the whole story (wave P, D1). Looked up
## by catalogue id first and falling back to PROFILES by kind, so a new weapon
## that fights like its kind still needs no row at all.
const PROFILES_BY_ID := {
	# Two discs on one arbor fight exactly as one disc does; the row is here so
	# every weapon on the ladder can be found by name.
	"twin_saw": {"standoff": 1.0, "engage": 0.9, "flank": false, "spin_up": true,
		"hold": true, "latch": true, "orbit": false},
	# The one weapon that fights where its wielder is not. It holds the length of
	# its own lob, throws fire onto that ring and circles it rather than driving
	# through its own patch; `engage` 0.8 of a 1.35 m reach means it shoots while
	# the other machine is still coming.
	"napalm_cannon": {"standoff": 1.25, "engage": 0.8, "flank": false,
		"spin_up": false, "hold": true, "latch": false, "orbit": true},
	# A vortex is a full body spinner that also throws, so it wants the same ring
	# and the same orbit, and rather more patience: it will not close below
	# READY_ENGAGE, and 3.2 s is a long wind-up to waste.
	"vortex_spinner": {"standoff": 1.35, "engage": 1.2, "flank": false,
		"spin_up": true, "hold": true, "latch": false, "orbit": true},
	"shock_prod": {"standoff": 0.0, "engage": 0.9, "flank": false, "spin_up": false,
		"hold": true, "latch": true, "orbit": false},
	"tesla_arc": {"standoff": 0.9, "engage": 1.0, "flank": false, "spin_up": true,
		"hold": true, "latch": false, "orbit": true},
	"drill_lance": {"standoff": 1.0, "engage": 0.9, "flank": false, "spin_up": true,
		"hold": true, "latch": true, "orbit": false},
}
const DEFAULT_KIND := "flipper"
const DEFAULT_REACH := 0.45         # the Stage 3 flipper
## Fire range is the weapon's reach times the profile's engage, plus this, measured
## chassis centre to chassis centre. The bots are 0.9 m long, so a 0.45 m reach weapon
## still has to fire from about a metre out.
const ENGAGE_SLACK_M := 0.65
const READY_ENGAGE := 0.85          # spun up enough to be worth closing with from cold
## Above this the bar is a weapon, so the bot STAYS ON the target: no ring, no waiting for
## a flank, no giving ground. Measured 2026-09-13: holding the ring whenever readiness was
## below READY_ENGAGE meant a spinner build spent 2.4 seconds of a 60 second fight inside
## a metre of its opponent, against the flipper build's 56.6, because a bar that loses a
## little spin on every hit is almost never at 0.85.
const READY_STAY := 0.5
const READY_DROP := 0.45            # spun down enough to be worth backing off to re-spin
## A weapon with no reach of its own (a ram) fights at contact.
const CONTACT_M := 0.95
## Circle for at most this long before going in anyway.
##
## The flank gate is a preference, not a requirement. Against an opponent that keeps its
## nose on you (a faster bot, or another AI doing the same thing) the angle may simply
## never come good, and a bot that waits forever for a perfect entry never fights at all:
## measured at 202 ticks of 2900 spent inside 1 m. Two seconds of looking, then commit.
const COMMIT_AFTER_TICKS := 120

# --- skill tiers (brief v4 §4) --------------------------------------------------------
## One row per career tier. The tier id IS the skill id, so the shell can send the tier
## it already knows (`bots[i].ai_skill`) and nothing has to translate.
##   reaction_s  how far behind the truth this driver's picture of the opponent runs
##   aim_deg     how far off its steering is, at worst, drawn from the shared rng
##   danger_s    how many seconds ahead it looks for danger (NOT what it knows is
##               dangerous: every tier knows everything is dangerous. This is how far in
##               front of itself it plans, so a Scrapyard driver notices a grinder about
##               a machine-length before it and a Masters driver was never going that way)
##   hesitate_s  how long it eases off after changing its mind
##   aggression  how hard it presses: commitment, ground given after a shot, ring held
##   pin/shove/bait   which of the wall behaviours it has
##   zone        whether it knows the house bot's corner is anybody's
##   endgame     whether it plans around the released house bot rather than merely
##               avoiding it (every tier avoids it; this one goes the long way round)
##   srimech     multiplier on the self-right retry cadence: below 1.0 is faster
##   reading     how much of the opponent's build it fights differently against
##   recovery_s / overshoot_m   the RECOVERY WINDOW (combat feel, owner decision 2026-09-24,
##               early tiers only): a committed dart that ends without touching them carries
##               on straight for overshoot_m, then turns back at hesitation throttle, for
##               recovery_s in all, rear exposed and not firing. Absent = no window
##               (Championship and Masters commit and recover like pros).
const SKILL_SCRAPYARD := "scrapyard"
const SKILL_REGIONAL := "regional"
const SKILL_NATIONAL := "national"
const SKILL_CHAMPIONSHIP := "championship"
const SKILL_MASTERS := "masters"
const SKILL_IDS := [SKILL_SCRAPYARD, SKILL_REGIONAL, SKILL_NATIONAL, SKILL_CHAMPIONSHIP,
	SKILL_MASTERS]

const READ_NONE := "none"
const READ_WEAPON := "weapon"
const READ_WEAPON_ARMOUR := "weapon+armour"
const READ_FULL := "full"

const SKILLS := {
	SKILL_SCRAPYARD: {"reaction_s": 0.6, "aim_deg": 25.0, "danger_s": 0.6,
		"hesitate_s": 0.55, "aggression": 0.55,
		"pin": false, "shove": false, "bait": false, "zone": false, "endgame": false,
		"srimech": 1.7, "reading": READ_NONE, "recovery_s": 0.8, "overshoot_m": 1.0},
	SKILL_REGIONAL: {"reaction_s": 0.45, "aim_deg": 18.0, "danger_s": 0.8,
		"hesitate_s": 0.32, "aggression": 0.70,
		"pin": false, "shove": false, "bait": false, "zone": false, "endgame": false,
		"srimech": 1.0, "reading": READ_WEAPON, "recovery_s": 0.6, "overshoot_m": 0.75},
	SKILL_NATIONAL: {"reaction_s": 0.3, "aim_deg": 12.0, "danger_s": 1.0,
		"hesitate_s": 0.16, "aggression": 0.82,
		"pin": true, "shove": false, "bait": false, "zone": true, "endgame": false,
		"srimech": 1.0, "reading": READ_WEAPON_ARMOUR, "recovery_s": 0.4, "overshoot_m": 0.5},
	SKILL_CHAMPIONSHIP: {"reaction_s": 0.2, "aim_deg": 8.0, "danger_s": 1.25,
		"hesitate_s": 0.06, "aggression": 0.92,
		"pin": true, "shove": true, "bait": false, "zone": true, "endgame": true,
		"srimech": 0.6, "reading": READ_FULL},
	SKILL_MASTERS: {"reaction_s": 0.12, "aim_deg": 5.0, "danger_s": 1.5,
		"hesitate_s": 0.0, "aggression": 1.0,
		"pin": true, "shove": true, "bait": true, "zone": true, "endgame": true,
		"srimech": 0.6, "reading": READ_FULL},
}

# --- temperaments (brief v4 §4) -------------------------------------------------------
## The rival's `personality` line, turned into numbers. Every one is a multiplier on
## behaviour the driver already had, so a temperament can never remove a safety rule:
##   standoff  the ring it holds, times the weapon profile's
##   commit    how long it looks for a flank before going in anyway, times COMMIT_AFTER
##   backoff   how long it gives ground after a shot, times BACKOFF_MAX (0 = never)
##   pin       how eagerly it takes a wall pin, and how briefly it rests between them
##   shove     how far out it will line an opponent up on a hazard
##   retreat   how hurt it has to be before it disengages (0 = it never does)
##   pounce    charges an inverted opponent instead of working for an angle
const TEMPERAMENT_BRAWLER := "brawler"
const TEMPERAMENT_TECHNICIAN := "technician"
const TEMPERAMENT_BULLY := "bully"
const TEMPERAMENT_OPPORTUNIST := "opportunist"
const TEMPERAMENT_SHOWBOAT := "showboat"
const TEMPERAMENT_IDS := [TEMPERAMENT_BRAWLER, TEMPERAMENT_TECHNICIAN, TEMPERAMENT_BULLY,
	TEMPERAMENT_OPPORTUNIST, TEMPERAMENT_SHOWBOAT]

const TEMPERAMENTS := {
	TEMPERAMENT_BRAWLER: {"standoff": 1.0, "commit": 0.5, "backoff": 0.5, "pin": 1.0,
		"shove": 1.0, "retreat": 0.0, "pounce": false},
	TEMPERAMENT_TECHNICIAN: {"standoff": 1.25, "commit": 1.6, "backoff": 1.2, "pin": 0.5,
		"shove": 0.8, "retreat": 0.45, "pounce": false},
	TEMPERAMENT_BULLY: {"standoff": 0.95, "commit": 0.8, "backoff": 0.3, "pin": 1.8,
		"shove": 1.6, "retreat": 0.2, "pounce": false},
	TEMPERAMENT_OPPORTUNIST: {"standoff": 1.15, "commit": 1.2, "backoff": 1.4, "pin": 0.4,
		"shove": 0.6, "retreat": 1.0, "pounce": true},
	TEMPERAMENT_SHOWBOAT: {"standoff": 0.85, "commit": 0.3, "backoff": 0.0, "pin": 0.8,
		"shove": 1.0, "retreat": 0.0, "pounce": true},
}
## A driver built with this (or with "") draws its temperament from the shared rng at
## construction: career fillers get one for the fight, rivals are told theirs.
const TEMPERAMENT_DRAW := "random"

# --- the new behaviours ---------------------------------------------------------------
## An opponent this close to a wall can be pinned against it.
const PIN_WALL_M := 0.95
const PIN_RANGE_M := 1.35           # and we have to be this close to start one
const PIN_HOLD_TICKS := 180         # 3 s: the pin rule bites at 4 s, so let go first
const PIN_REST_TICKS := 90          # 1.5 s off before another one
## A hazard this far in front of the opponent, with us behind them, is worth a shove.
const HAZARD_SHOVE_M := 2.5
const SHOVE_LINE_DOT := 0.6         # how squarely lined up on it the push has to be
const SHOVE_RANGE_M := 1.4          # and how close to them we have to be to push at all
const HAZARD_AVOID_M := 1.1         # a live hazard this close to us is driven away from
const ZONE_MARGIN_M := 0.45         # how far outside the corner zone to stay
## Counter-build reading (brief v4 §4): what to do about the weapon they are carrying.
const COUNTER_SPIN_ANGLE_DEG := 70.0    # a spinner is approached well off its nose
## How much longer a driver waits for that angle before giving up and going in anyway.
const COUNTER_PATIENCE := 2.5
## A flipper is approached thirty degrees off its nose, as a point that far to one side
## of it at contact range rather than as a heading that never lands.
const COUNTER_FLIPPER_DEG := 30.0
## The opponent's picture only lags: a jump bigger than this is a teleport (a spawn, a
## test fixture) and is believed at once rather than eased into.
const TELEPORT_M := 0.5
## Last twenty seconds: if the judges' tally is behind, fight like a showboat.
const SHOWBOAT_WINDOW_S := 20.0
## Below this much of the machine left, a temperament that retreats disengages.
const RETREAT_CONDITION := 0.55

# --- the movement layer: context steering (docs/wave-f-f4-notes.md) -------------------
## What a machine covers in a second at full throttle, near enough. Used only to turn the
## tier's danger lookahead from seconds into the metres the steering probes along.
## Measured in the Yard: a 4wd wedge from a standing start does about 3 m in its first
## second and holds a little over that.
const AI_SPEED_M_S := 3.0
## THE FLOOR THE OWNER'S VERDICT COMES DOWN TO. Whatever the tier's lookahead, a hazard
## within a metre is probed for and is therefore full danger. A Scrapyard driver plans
## badly; it does not drive into a grinder that is already under its nose.
const DANGER_FLOOR_M := 1.0
## A timed hazard (the spike patch) is treated as live this long before it rises, on top
## of the tier's lookahead: standing on a patch that is about to come up is the same
## mistake as driving onto a risen one, and it is the one the owner actually saw.
const HAZARD_LEAD_S := 2.0
## THE HOLE THE OWNER FELL DOWN, and it took the physics test to find it.
##
## `ArenaBase` publishes the spike patch as dangerous while `_spikes_up` OR while the
## countdown reads under 1.5 s. Those two are read a tick apart: `seconds_to_spike_rise()`
## uses the arena's CURRENT tick counter, `_spikes_up` is set from the PREVIOUS tick's
## height, and the patch has to travel for a quarter second before it counts as up. So at
## the instant the cycle wraps there are about nine ticks in which the countdown has
## already jumped from "now" to "in 5.8 seconds" and the patch is not up yet, and the
## arena reports nothing dangerous anywhere. Measured 2026-09-16 in the Yard: a driver
## that had been giving the patch a wide berth read that gap, believed the middle of the
## floor was free for the next six seconds, drove back in, and was standing on the patch
## when the spikes came through it. Twice in one 60 s fight. That IS the bug the owner
## reported off his phone.
##
## The driver therefore latches: once the countdown has been under SPIKE_WRAP_S, the patch
## stays live for SPIKE_HOLD_TICKS whatever the arena says next. Which is also how a human
## driver behaves -- they have just come up, stay off them -- and it needs nothing from
## the arena that the arena does not already publish.
const SPIKE_WRAP_S := 0.3
const SPIKE_HOLD_TICKS := 100       # 1.67 s: the 1.2 s up phase plus its travel and a beat
## How close to a wall a machine starts steering along it rather than into it. Roughly a
## chassis and a half, so the nose never reaches the wall before the steering has turned.
const WALL_MARGIN_M := 1.0
## Relative danger weights. A live hazard and the house bot are absolute; a wall only
## costs you the fight, and their weapon arc is a place you would rather not be.
const DANGER_HAZARD := 1.0
const DANGER_HOUSE_BOT := 1.0
const DANGER_ZONE := 0.85
const DANGER_WALL := 0.7
const DANGER_ARC := 0.5
## How wide a berth the released house bot gets. It cannot be knocked out, so it is not an
## opponent, it is terrain.
const HOUSE_BOT_RADIUS_M := 1.1
## How much of the new heading is taken each tick. 0.35 settles in about six ticks (a
## tenth of a second), which is fast enough to dodge and slow enough that the machine
## reads as steering rather than as flickering between slots.
const STEER_SMOOTH := 0.35
## Getting off something live is not a change of mind, it is a flinch: no tier hesitates
## over it and every tier snaps. Anything slower and the smoothing itself would be the new
## way a machine drives into the spikes.
const STEER_SMOOTH_ESCAPE := 0.8
## Throttle while hesitating. Not a stop -- a machine that stops dead reads as broken --
## but visibly easing off.
const HESITATE_THROTTLE := 0.40

## What the decision layer hands the movement layer. One at a time, never blended: the
## whole reason context steering works is that ONE intent writes the interest map and the
## danger map is free to veto any part of it.
const INTENT_NONE := "none"
const INTENT_ESCAPE := "escape"       # get off / away from something live
const INTENT_PIN := "pin"             # hold them on the wall
const INTENT_SHOVE := "shove"         # push them onto something live
const INTENT_RETREAT := "retreat"     # give ground, we are coming apart
const INTENT_RESPIN := "respin"       # back off and let the bar come up
const INTENT_BACKOFF := "backoff"     # gave a shot, give ground
const INTENT_CLOSE := "close"         # go and hit them
const INTENT_RING := "ring"           # hold the standoff and look for an angle
const INTENT_RECOVER := "recover"     # a missed dart: overshoot, then turn back slowly
## The intents during which the opponent's weapon arc is danger. While we are going in to
## hit them, their arc is the price of the hit and the steering must not talk us out of it.
const ARC_AWARE_INTENTS := [INTENT_ESCAPE, INTENT_RETREAT, INTENT_RESPIN, INTENT_BACKOFF,
	INTENT_RING]

var mode: String = MODE_NORMAL
## The tier this driver fights at, and the personality it fights with. Both are read from
## the fight config (`bots[i].ai_skill`, `bots[i].temperament`) by fight.gd.
var skill: String = SKILL_REGIONAL
var temperament: String = TEMPERAMENT_BRAWLER

# --- telemetry: counters the headless sweep in tests/ai_test.gd reads --------------
var pin_ticks := 0
var shove_ticks := 0
var retreat_ticks := 0
var dodge_ticks := 0
var fire_ticks := 0
var close_ticks := 0
var showboat_ticks := 0

var _rng: RandomNumberGenerator = null
var _jitter: Vector2 = Vector2.ZERO
var _fire_ready_tick: int = 0
var _failed_flips: int = 0
var _secondary_ready_tick: int = 0
var _reverse_until_tick: int = -1
var _was_inverted: bool = false
## +1 or -1: which way round the opponent this bot is working. Held until the other side
## is clearly better, so it does not oscillate across the opponent's nose.
var _flank_sign: int = 1
var _darting: bool = false
## The tick a dart may first be reconsidered on. See DART_MIN_TICKS.
var _dart_until_tick: int = -1
var _backoff_until_tick: int = -1
var _backoff_from_range: float = 0.0
## The tick circling started, or -1 when it is not circling.
var _circling_since_tick: int = -1
## The recovery window (see SKILLS recovery_s). Set when a dart ends without contact.
var _dart_touched: bool = false
var _recover_until_tick: int = -1
var _recover_from: Vector3 = Vector3.ZERO
var _recover_dir: Vector3 = Vector3.ZERO
var recover_ticks := 0

# --- skill and temperament state ------------------------------------------------------
var _skill: Dictionary = SKILLS[SKILL_REGIONAL]
var _temper: Dictionary = TEMPERAMENTS[TEMPERAMENT_BRAWLER]
## The temperament actually being fought with this tick: the driver's own, or showboat
## once the last twenty seconds are on and the judges have it behind.
var _active: Dictionary = TEMPERAMENTS[TEMPERAMENT_BRAWLER]
## ±1 of the aim error, redrawn on the jitter cadence so the draw count per tick is fixed.
var _aim_offset: float = 0.0
## What this driver BELIEVES about the opponent. It lags the truth by the tier's reaction
## time, which is the whole of what a reaction delay is: the bot aims where they were.
var _believed: Vector3 = Vector3.ZERO
var _believed_forward: Vector3 = Vector3.RIGHT
var _last_seen: Vector3 = Vector3.ZERO
var _belief_ready: bool = false
var _pin_until_tick: int = -1
var _pin_rest_until_tick: int = -1
## Until when the spike patch is believed live whatever the arena's clock says next. See
## SPIKE_WRAP_S.
var _spike_live_until_tick: int = -1

# --- the movement layer's memory -------------------------------------------------------
## The heading this driver actually steered last tick, and whether there is one yet. The
## smoothing eases from it; on the first tick of a fight there is nothing to ease from.
var _steered: Vector2 = Vector2.ZERO
var _steer_ready: bool = false
## What it was trying to do last tick, and until when it is easing off after changing its
## mind. Both are functions of the ticks before them, so both replay.
var _intent: String = INTENT_NONE
var _hesitate_until_tick: int = -1
## The arena is a 10 m square unless the context says otherwise or a machine is seen
## outside one (the Coliseum is 12 m and fight.gd does not publish the extent: see
## docs/wave-f-f4-notes.md). Growing it from what has been seen is deterministic, and it
## is never smaller than the Yard, so a wall is never modelled further out than it is
## in any arena the AI has actually been driven in.
var _half_extent: float = FightTypes.ARENA_SIZE * 0.5


func _init(rng: RandomNumberGenerator, ai_mode: String = MODE_NORMAL,
		ai_skill: String = SKILL_REGIONAL,
		ai_temperament: String = TEMPERAMENT_BRAWLER) -> void:
	_rng = rng
	mode = ai_mode if ai_mode in [MODE_NORMAL, MODE_IDLE, MODE_CHARGE] else MODE_NORMAL
	skill = ai_skill if SKILLS.has(ai_skill) else SKILL_REGIONAL
	_skill = SKILLS[skill] as Dictionary
	# A filler with no temperament of its own draws one, HERE, from the shared rng: a
	# fixed point in the fight's setup, so the fight still replays bit for bit.
	if (ai_temperament == "" or ai_temperament == TEMPERAMENT_DRAW) and _rng != null:
		temperament = TEMPERAMENT_IDS[_rng.randi() % TEMPERAMENT_IDS.size()]
	else:
		temperament = ai_temperament if TEMPERAMENTS.has(ai_temperament) \
			else TEMPERAMENT_BRAWLER
	_temper = TEMPERAMENTS[temperament] as Dictionary
	_active = _temper


## Map a world direction to the stick heading both bots consume.
static func heading_from_world_dir(direction: Vector3) -> Vector2:
	var flat := Vector2(direction.x, direction.z)
	if flat.length() < 0.0001:
		return Vector2.ZERO
	return flat.normalized()


## One tick of thought: decide the intent, then steer it.
##   me, foe: Bot instances (or duck-typed fakes exposing chassis / is_inverted()).
##   ctx: everything fight.gd publishes, all of it optional --
##     tick, spike_centre, spike_rise_in_s        the Yard's patch and its clock
##     hazard / hazards                           the arena's own read of what is live
##     house_bot_position, zone_rect, phase       G2's enforcer and the corner it guards
##     time_left_s, judge_points                  the last twenty seconds
##     arena_half_extent                          where the walls are, when anyone says
##                                                (see docs/wave-f-f4-notes.md)
func think(me: Object, foe: Object, ctx: Dictionary) -> Dictionary:
	var tick := int(ctx.get("tick", 0))

	# The rng is drawn at a fixed cadence in EVERY mode, before any branching, so the
	# number of draws over a fight depends only on the tick count.
	if tick % JITTER_TICKS == 0:
		_jitter = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * JITTER_MAX
		# The aim error is the third draw and is taken in every mode for the same reason
		# the jitter is: the number of draws over a fight must not depend on a decision.
		_aim_offset = _rng.randf_range(-1.0, 1.0)

	if me == null or foe == null or mode == MODE_IDLE:
		return FightTypes.empty_input()

	# The spike latch, updated once per tick at a fixed point and from the context only,
	# so it is a function of the fight and replays with it.
	if float(ctx.get("spike_rise_in_s", 999.0)) <= SPIKE_WRAP_S:
		_spike_live_until_tick = tick + SPIKE_HOLD_TICKS

	var my_position := _position(me)
	var forward := _flat(_forward(me))

	if mode == MODE_CHARGE:
		return _charge(my_position, _position(foe), forward, tick)

	# --- the picture of the opponent, running as far behind the truth as the tier is
	# slow. Everything below reads the BELIEF, never the opponent's real position: a
	# reaction delay is exactly "it aims where they were", and it is what makes a
	# Scrapyard driver miss a moving human that a Masters driver does not.
	_update_belief(_position(foe), _flat(_forward(foe)))
	var foe_position := _believed

	# --- the last twenty seconds: behind on the judges' tally, fight like a showboat
	_active = _temper
	if float(ctx.get("time_left_s", 999.0)) <= SHOWBOAT_WINDOW_S \
			and _behind_on_points(me, foe, ctx):
		_active = TEMPERAMENTS[TEMPERAMENT_SHOWBOAT] as Dictionary
		showboat_ticks += 1

	# --- recover: inverted bots do nothing else until they are back on their wheels
	var inverted := _is_inverted(me)
	if not inverted:
		_failed_flips = 0
		_reverse_until_tick = -1
	elif not _was_inverted:
		_failed_flips = 0
	_was_inverted = inverted
	if inverted:
		_darting = false
		return _recover(me, forward, tick)

	var to_foe := _flat(foe_position - my_position)
	var range_m := to_foe.length()
	var to_foe_dir := to_foe.normalized() if range_m > 0.0001 else forward

	var profile := _profile(me)
	var reach := _weapon_reach(me)
	var ready := _weapon_readiness(me)
	var engage_m := maxf(reach * float(profile["engage"]) + ENGAGE_SLACK_M, CONTACT_M) \
		if float(profile["engage"]) > 0.0 else CONTACT_M
	var standoff := float(profile["standoff"])
	if standoff <= 0.0:
		# A flame keeps its own reach; a ram has no standoff at all and just charges.
		standoff = maxf(reach * 0.9, CONTACT_M) if float(profile["engage"]) > 0.0 else 0.0
	standoff *= float(_active["standoff"])

	if range_m <= 1.0:
		close_ticks += 1
	_note_extent(my_position, foe_position, ctx)

	# =================================================================== decision layer
	# ONE intent, decided in wave G's order, expressed as a world direction this machine
	# would like to go. Nothing below returns a heading: the movement layer owns that, so
	# that every one of these -- the pin, the shove, the dart, the retreat -- is steered
	# around the hazards rather than driven blindly down its own line.
	var intent := INTENT_NONE
	var want := Vector3.ZERO
	var fire := false
	var was_darting := _darting
	if _darting and my_position.distance_to(_position(foe)) <= CONTACT_M:
		_dart_touched = true

	# --- avoid: something live is under us or about to be. Every tier, every hazard.
	var escape := _escape(my_position, forward, ctx, tick)
	if escape != Vector3.ZERO:
		intent = INTENT_ESCAPE
		want = escape
		_darting = false
		dodge_ticks += 1
	# --- the wall pin: hold them on the wall for three seconds and let go, because the
	# pin rule bites at four and a pin that ends in a penalty is not a pin.
	elif _pinning(my_position, foe_position, range_m, tick):
		intent = INTENT_PIN
		want = to_foe_dir
		fire = true
		pin_ticks += 1
		_darting = false
	# --- the hazard shove: behind them with something live in front of them, push
	elif _shoving(foe_position, to_foe_dir, range_m, ctx):
		intent = INTENT_SHOVE
		want = to_foe_dir
		fire = true
		shove_ticks += 1
		_darting = false
	# --- retreat: a temperament that knows when it is losing disengages to repair its
	# angle rather than trading with a machine that is beating it.
	elif _retreating(me, foe, range_m, standoff):
		intent = INTENT_RETREAT
		want = -to_foe_dir
		retreat_ticks += 1
		_darting = false
	else:
		# --- strike, decided before the movement so it can fire on the way in
		fire = _should_fire(me, profile, range_m, engage_m, ready, to_foe_dir, forward, tick)
		# A spun up bar has no reason to give ground: it is not reloading, and every tick
		# it is off the target is a tick the bar is slowing down for nothing.
		var stay_on := bool(profile["spin_up"]) and ready >= READY_STAY
		if fire:
			fire_ticks += 1
		if fire and not bool(profile["hold"]) and not stay_on:
			# A one shot weapon taps and gives ground; a held one stays on the target. How
			# long it gives ground for is the temperament, and how hard the tier presses.
			_fire_ready_tick = tick + FIRE_COOLDOWN_TICKS
			var backoff_ticks := int(round(float(BACKOFF_MAX_TICKS)
				* float(_active["backoff"]) * _give_ground_scale()))
			if not bool(profile["latch"]) and backoff_ticks > 0:
				_backoff_until_tick = tick + backoff_ticks
				_backoff_from_range = range_m
				_darting = false
		if stay_on:
			_backoff_until_tick = -1
		# Far enough away again: the ground has been given, stop giving it.
		if tick < _backoff_until_tick and range_m >= _backoff_from_range + BACKOFF_M:
			_backoff_until_tick = -1

		# --- a missed dart: pay for it (early tiers only). Before the re-spin and the
		# back-off, after every safety rule above: the danger map still steers it.
		if tick < _recover_until_tick:
			intent = INTENT_RECOVER
			fire = false
			recover_ticks += 1
			if _flat(my_position - _recover_from).length() < float(_skill.get("overshoot_m", 0.0)):
				want = _recover_dir
			else:
				want = to_foe_dir
				_hesitate_until_tick = maxi(_hesitate_until_tick, _recover_until_tick)
		# --- disengage to re-spin: a spun down bar is a handle, not a weapon
		elif bool(profile["spin_up"]) and ready < READY_DROP and range_m < standoff:
			intent = INTENT_RESPIN
			want = -to_foe_dir
			_darting = false
		# --- back off: give ground after a shot rather than grinding the gas away
		elif tick < _backoff_until_tick:
			intent = INTENT_BACKOFF
			want = -to_foe_dir
		else:
			var move := _manoeuvre(my_position, foe_position, _believed_forward,
				range_m, to_foe_dir, profile, standoff, engage_m, ready, tick, foe)
			intent = str(move["intent"])
			want = move["want"] as Vector3

	# A dart that ended with no contact, and not because something more important took
	# over (a hazard, a pin, a shove, a retreat) or because it fired: that is a miss.
	if was_darting and not _darting:
		if not _dart_touched and not fire and intent in [INTENT_CLOSE, INTENT_RING] \
				and float(_skill.get("recovery_s", 0.0)) > 0.0:
			_start_recovery(my_position, forward, tick)
		_dart_touched = false
	elif not _darting:
		_dart_touched = false

	# =================================================================== movement layer
	return _input(_jittered(_steer(intent, want, my_position, foe, ctx, range_m, tick)),
		fire, false)


## Open the recovery window: carry on the way the dart was going (the overshoot), then turn.
func _start_recovery(my_position: Vector3, forward: Vector3, tick: int) -> void:
	_recover_until_tick = tick + int(round(float(_skill["recovery_s"]) * float(FightTypes.TICK_HZ)))
	_recover_from = my_position
	_recover_dir = forward if forward.length_squared() > 1e-6 else Vector3.RIGHT


## True while this driver is paying for a missed dart. For tells and tests; read only.
func is_recovering(tick: int) -> bool:
	return tick < _recover_until_tick


# ---------------------------------------------------------------- the movement layer

## Context steering, once per tick (Andrew Fray, GDC 2015; see ai/context_steering.gd for
## the algorithm and why a masked map beats a sum of forces).
##
## The intent writes ONE interest lobe. Everything that could hurt writes the danger map:
## every live hazard, the walls, the house bot and its corner, and -- when we are not
## going in to hit them -- the arc the opponent's weapon sweeps. Danger masks interest,
## the best survivor is taken, and the result is eased into last tick's heading so the
## machine reads as a driver steering rather than as sixteen numbers being re-sorted.
func _steer(intent: String, want: Vector3, my_position: Vector3, foe: Object,
		ctx: Dictionary, range_m: float, tick: int) -> Vector2:
	# A change of mind costs this driver a beat of throttle. Only the throttle: an earlier
	# cut slowed the STEERING during the beat too, and measured that it made the weaker
	# tier better, because holding a heading through a clinch is committed pushing rather
	# than a handicap. That is one of the four things a low tier is now made of.
	if intent != _intent:
		if _intent != INTENT_NONE and intent != INTENT_ESCAPE:
			var beat := int(round(float(_skill["hesitate_s"]) * float(FightTypes.TICK_HZ)))
			if beat > 0:
				_hesitate_until_tick = tick + beat
		_intent = intent
	var escaping := intent == INTENT_ESCAPE
	if escaping:
		_hesitate_until_tick = -1
	var hesitating := tick < _hesitate_until_tick

	var interest := ContextSteering.new_map()
	ContextSteering.add_interest(interest, want)

	var danger := ContextSteering.new_map()
	var lookahead := maxf(float(_skill["danger_s"]) * AI_SPEED_M_S, DANGER_FLOOR_M)
	# We cannot drive through the machine we are pushing. When the intent is to be ON
	# them the probe stops at them, or a Championship driver lining an opponent up on a
	# grinder reads the grinder BEHIND THEM as its own danger and lets them go, which is
	# the one place a longer lookahead makes a driver worse rather than better.
	if intent == INTENT_PIN or intent == INTENT_SHOVE or intent == INTENT_CLOSE:
		lookahead = maxf(minf(lookahead, range_m), DANGER_FLOOR_M)

	for entry in _danger_points(ctx, tick):
		ContextSteering.add_point_danger(danger, my_position, entry as Vector3,
			lookahead, DANGER_HAZARD)
	ContextSteering.add_wall_danger(danger, my_position, _half_extent, WALL_MARGIN_M,
		DANGER_WALL)
	# The released house bot is terrain, not an opponent: it cannot be knocked out, so no
	# tier drives through it. A tier that can read the endgame gives it a wider berth
	# still, which is the difference between surviving it and planning around it.
	var house: Variant = ctx.get("house_bot_position", null)
	if house is Vector3 \
			and str(ctx.get("phase", FightTypes.PHASE_OPEN)) == FightTypes.PHASE_ENDGAME:
		var clearance := HOUSE_BOT_RADIUS_M * (1.6 if bool(_skill["endgame"]) else 1.0)
		ContextSteering.add_point_danger(danger, my_position, house as Vector3,
			maxf(lookahead, DANGER_FLOOR_M), DANGER_HOUSE_BOT, clearance)
	# The corner is a keep-out rather than a hazard: only a driver that knows whose corner
	# it is stays out of it.
	if bool(_skill["zone"]):
		var zone: Variant = ctx.get("zone_rect", null)
		if zone is Rect2:
			ContextSteering.add_rect_danger(danger, my_position,
				(zone as Rect2).grow(ZONE_MARGIN_M), lookahead, DANGER_ZONE)
	if foe != null and intent in ARC_AWARE_INTENTS:
		ContextSteering.add_arc_danger(danger, my_position, _believed, _believed_forward,
			_weapon_reach(foe), lookahead, DANGER_ARC)

	# Last tick's direction settles ties, so the machine keeps the side of an obstacle it
	# has already committed to rather than flip-flopping across it.
	var chosen := ContextSteering.choose(interest, danger,
		Vector3(_steered.x, 0.0, _steered.y))
	var heading := heading_from_world_dir(chosen) * clampf(chosen.length(), 0.0, 1.0)
	if hesitating:
		heading *= HESITATE_THROTTLE
	_steered = ContextSteering.smooth(_steered, heading,
		STEER_SMOOTH_ESCAPE if escaping else STEER_SMOOTH, _steer_ready)
	_steer_ready = true
	return _steered


## Everything that is live RIGHT NOW, as world points. The arena's own read
## (`hazard_helpers().danger_positions`) plus the spike patch, which has a clock of its
## own on the context and is the hazard the owner watched a machine drive into.
##
## The patch counts as live from HAZARD_LEAD_S before it rises ON TOP OF the tier's
## lookahead, because standing on a patch that is about to come up is the same mistake as
## driving onto a risen one.
func _danger_points(ctx: Dictionary, tick: int) -> Array:
	var out: Array = []
	var centre: Variant = ctx.get("spike_centre", null)
	if centre is Vector3 and (tick < _spike_live_until_tick \
			or float(ctx.get("spike_rise_in_s", 999.0)) \
				<= float(_skill["danger_s"]) + HAZARD_LEAD_S):
		out.append(centre as Vector3)
	for entry in _live_hazards(ctx):
		out.append(entry)
	return out


## The arena is a 10 m square unless we are told otherwise or we watch a machine drive
## outside one. fight.gd does not put the arena's extent on the context (the arenas do
## know it: `arena_half_extent()`; see docs/wave-f-f4-notes.md), so this is how the driver
## comes to believe in the Coliseum's bigger floor without anyone editing fight.gd.
## Deterministic: it is a function of the positions, which are a function of the seed.
func _note_extent(my_position: Vector3, foe_position: Vector3, ctx: Dictionary) -> void:
	var told: Variant = ctx.get("arena_half_extent", null)
	if told != null and float(told) > 0.0:
		_half_extent = maxf(FightTypes.ARENA_SIZE * 0.5, float(told))
		return
	for at in [my_position, foe_position]:
		var reach := maxf(absf((at as Vector3).x), absf((at as Vector3).z)) + 0.6
		_half_extent = maxf(_half_extent, reach)


## Aggression: how hard this driver presses, and the three places that shows.
##
## It must only ever COST the weaker tier. Wave F's first cut had a low tier hold a wider
## ring and wait longer for a flank, and measured it made the Scrapyard driver BETTER
## (it beat a Regional one 19 of 20), because patience and distance are tactics, not
## handicaps. What a weak driver actually does is break off an attack half way in, give
## too much ground after a hit, and wait until it is almost touching before it dares press
## the button -- so it earns chances and does not convert them. None of that is stupid to
## watch, and none of it is pathing.
##
##   dart     how long it stays committed to a run-in before it can be talked out of it
##   ground   how long it gives ground after a shot instead of following up
##   window   how much of its weapon's range it will actually fire at

## The shortest a committed run-in can be, even at the timidest tier: below this the
## machine reads as dithering rather than as attacking.
const DART_MIN_FLOOR_TICKS := 18

func _dart_ticks() -> int:
	return maxi(int(round(float(DART_MIN_TICKS) * float(_skill["aggression"]))),
		DART_MIN_FLOOR_TICKS)


func _give_ground_scale() -> float:
	return 2.0 - float(_skill["aggression"])


## How far off the nose this driver will still press the button. A Masters driver holds
## fire until the opponent is in front of it; a weak one slaps the button at anything in
## the general direction, the wedge goes past them, and the cooldown is spent for nothing.
##
## Trigger discipline, not aim: the shot is taken at the same RANGE at every tier, which
## matters because the range at which a flipper is worth firing is a property of the
## flipper. What a tier changes is whether the machine was pointing at anything.
func _fire_cone_deg() -> float:
	return STRIKE_ANGLE_DEG * (1.0 + (1.0 - float(_skill["aggression"])) * 0.6)


# ---------------------------------------------------------------- movement

## Hold the ring, circle to a side or rear angle, then dart in, and a commitment flag so
## the dart is not re-decided every tick on the way in.
##
## The profile changes three things and nothing else: whether an angle is required before
## committing (`flank`), whether the bot orbits at the ring instead of closing (`orbit`,
## the full body spinner and the flame), and whether it waits to be spun up (`spin_up`).
##
## Since wave F this returns an INTENT and a world direction rather than a heading:
## {"intent": INTENT_CLOSE or INTENT_RING, "want": Vector3}. The movement layer turns it
## into steering, so every line below is a wish rather than an instruction, and any of
## them can be overruled by something live on the floor.
func _manoeuvre(my_position: Vector3, foe_position: Vector3, foe_forward: Vector3,
		range_m: float, to_foe_dir: Vector3, profile: Dictionary, standoff: float,
		engage_m: float, ready: float, tick: int, foe: Object = null) -> Dictionary:
	var bearing := _flat(my_position - foe_position)
	var bearing_dir := bearing.normalized() if bearing.length() > 0.0001 else -to_foe_dir
	# What their build is worth knowing about: the angle a spinner has to be taken from,
	# the thirty degrees off a flipper's nose, the crusher you never stop moving against.
	var counter := _counter_for(foe)
	# 1.0 = dead in front of them, -1.0 = dead behind them.
	var exposure := foe_forward.dot(bearing_dir) if foe_forward.length() > 0.0001 else -1.0
	# A bar above READY_STAY is a weapon and the bot fights with it: the standoff ring is
	# for a COLD bar, which is a handle. Hysteresis between READY_STAY (0.5) and READY_DROP
	# (0.45) keeps it from flickering in and out on every hit.
	var spins := bool(profile["spin_up"])
	var hot := (not spins) or ready >= READY_STAY
	# The angle worth waiting for is ours by default, and theirs when we can read their
	# build: a spinner has to be taken well off the nose of the spin or not at all.
	var wanted_angle := maxf(GOOD_ANGLE_DEG, float(counter["min_angle_deg"]))
	var needs_angle := bool(profile["flank"]) or float(counter["min_angle_deg"]) > 0.0
	var angle_ok := (not needs_angle) or exposure <= cos(deg_to_rad(wanted_angle))
	if spins and hot and float(counter["min_angle_deg"]) <= 0.0:
		angle_ok = true            # a spun up bar drives through the flank
	var spun_ok := (not spins) or hot
	# Reading the whole build: their bar is down, so the reload is the opening. Go now.
	if bool(counter["punish"]) and _weapon_readiness(foe) < READY_DROP:
		angle_ok = true
	# An upside down machine is not a fight, it is a free hit, and two temperaments take it.
	if bool(_active["pounce"]) and foe != null and _is_inverted(foe):
		angle_ok = true
	# Masters bait: their weapon is hot and ours is reloading, so give them nothing to
	# hit and make them come to us. One ring wider, no commitment.
	if bool(counter["bait"]) and tick < _fire_ready_tick \
			and _weapon_readiness(foe) >= READY_STAY:
		return _ring(_circle(bearing_dir, to_foe_dir, range_m, standoff * 1.3))

	# A latching weapon that is already on the target simply stays there. Unless what it
	# is latching onto is a crusher: a machine that stops moving in front of one is a
	# machine in its jaws, so it keeps working around them instead of parking.
	if bool(profile["latch"]) and range_m <= engage_m:
		_circling_since_tick = -1
		if bool(counter["no_latch"]):
			return _ring(_circle(bearing_dir, to_foe_dir, range_m, standoff))
		return _close(to_foe_dir)

	if _darting:
		if range_m > ABANDON_RANGE_M or (tick >= _dart_until_tick and needs_angle \
				and exposure > cos(deg_to_rad(ABANDON_ANGLE_DEG))):
			_darting = false
		else:
			_circling_since_tick = -1
			return _close(_approach(my_position, foe_position, to_foe_dir,
				counter, range_m, engage_m))

	# Orbiters (full body spinner, flame) never close past their working distance: their
	# weapon reaches out, so closing only gives the opponent a wedge under them.
	if bool(profile["orbit"]) and range_m <= standoff + STANDOFF_BAND_M:
		return _ring(_circle(bearing_dir, to_foe_dir, range_m, standoff))

	if standoff <= 0.0:
		# A ram has no ring: it lines up and charges.
		_circling_since_tick = -1
		return _close(to_foe_dir)

	if range_m > standoff + STANDOFF_BAND_M:
		_circling_since_tick = -1
		if spins and hot:
			# Spun up and out of range: go straight at them rather than out to the ring.
			return _close(to_foe_dir)
		var target := foe_position \
			+ _flank_direction(foe_forward, bearing_dir, float(counter["rear_bias"])) * standoff
		return _close(_flat(target - my_position))

	# Out of patience: a flank is worth waiting two seconds for and no longer, and how
	# patient this driver is at all is its temperament (a showboat barely looks). Spinning
	# up is not negotiable, though, because a cold bar is a handle.
	var commit_after := int(round(float(COMMIT_AFTER_TICKS) * float(_active["commit"])))
	if float(counter["min_angle_deg"]) > 0.0:
		# Patience against a spinner is not the same as patience against a wedge: going in
		# on the nose of a bar is how you lose a fight, so it waits a lot longer before it
		# gives up looking. Not forever, though, or it never fights at all.
		commit_after = int(round(float(commit_after) * COUNTER_PATIENCE))
	if _circling_since_tick >= 0 and tick - _circling_since_tick >= commit_after:
		angle_ok = true

	if angle_ok and spun_ok:
		if not _darting:
			_dart_until_tick = tick + _dart_ticks()
		_darting = true
		_circling_since_tick = -1
		return _close(_approach(my_position, foe_position, to_foe_dir,
			counter, range_m, engage_m))

	if _circling_since_tick < 0:
		_circling_since_tick = tick
	return _ring(_circle(bearing_dir, to_foe_dir, range_m, standoff))


## The two things _manoeuvre can decide, as the movement layer wants them. `close` is
## "go and hit them" and turns their weapon arc off in the danger map, because on the way
## in the arc is the price of the hit. `ring` is everything else, and keeps it on.
static func _close(want: Vector3) -> Dictionary:
	return {"intent": INTENT_CLOSE, "want": want}


static func _ring(want: Vector3) -> Dictionary:
	return {"intent": INTENT_RING, "want": want}


## Drive along the ring toward the chosen flank, correcting the radius as it goes.
func _circle(bearing_dir: Vector3, to_foe_dir: Vector3, range_m: float, standoff: float) -> Vector3:
	var tangent := bearing_dir.cross(Vector3.UP) * float(_flank_sign)
	var radius_error := range_m - standoff
	var correction := to_foe_dir * clampf(radius_error, -0.6, 0.6)
	var out := _flat(tangent + correction)
	return out.normalized() if out.length() > 0.0001 else to_foe_dir


## Which side of the opponent to work, as a world direction from their chassis. The sign
## is held until the other side is clearly better, so the bot commits to a lap instead of
## flip-flopping across the opponent's nose.
func _flank_direction(foe_forward: Vector3, bearing_dir: Vector3,
		rear_bias: float = 0.6) -> Vector3:
	if foe_forward.length() < 0.0001:
		return bearing_dir
	var right := foe_forward.cross(Vector3.UP).normalized()
	var side := 1 if bearing_dir.dot(right) >= 0.0 else -1
	# Only change sides when we are well past the midline, never on a knife edge.
	if side != _flank_sign and absf(bearing_dir.dot(right)) > 0.35:
		_flank_sign = side
	# Aim a little behind the opponent's shoulder: that is the angle worth having, and a
	# driver that can read armour aims deeper behind it when the back is the thin face.
	return (right * float(_flank_sign) * 0.8 - foe_forward * rear_bias).normalized()


# ---------------------------------------------------------------- the strike

## Fire when the opponent's chassis is inside this weapon's engage range and inside the
## nose cone, or when the Bot says the opponent is already sitting on our wedge.
##
## This is deliberately NOT the Stage 3 "front edge within 0.45 m of their chassis" test.
## That test inverts in a clinch: at 0.3 m apart the front edge is already PAST the
## opponent's centre, the vector from edge to chassis points backwards, and the facing
## check fails exactly when the bots are locked together. Measured: 2322 ticks inside 1 m
## over 45 seconds and not one shot fired.
func _should_fire(me: Object, profile: Dictionary, range_m: float, engage_m: float,
		ready: float, to_foe_dir: Vector3, forward: Vector3, tick: int) -> bool:
	if float(profile["engage"]) <= 0.0:
		return false            # a ram has nothing to fire
	if not _weapon_ready(me, tick, profile, _weapon_kind(me)):
		return false

	# A weapon that spins up only gains readiness WHILE IT IS HELD, so holding it is not a
	# decision about the opponent at all: it is what makes it a weapon. Gating the press on
	# readiness is a deadlock, and it was one (agent W1, 2026-09-13): `ready` never rose,
	# so the bar never spun, so a spinner in AI hands removed nothing while the same weapon
	# held down by a test took 0.81 condition off in four seconds. Spinners, drums, the
	# full body spinner and the saw now spin from the bell and keep spinning.
	#
	# READY_ENGAGE and READY_DROP still gate the MOVEMENT (see _manoeuvre and the
	# disengage in think): a cold bar is a handle, so the bot does not close with one, and
	# backs off to re-spin if it drops. They must never gate the press.
	if bool(profile["hold"]) and bool(profile["spin_up"]):
		return true

	if me.has_method("opponent_on_wedge") and bool(me.call("opponent_on_wedge")):
		return true
	if range_m > engage_m:
		return false
	if forward.length() < 0.0001:
		return false
	return forward.dot(to_foe_dir) >= cos(deg_to_rad(_fire_cone_deg()))


## Can this weapon be used at all this tick? Jam, ammunition and the tap cooldown, and
## nothing about the opponent.
##
## `flipper_ready()` and `gas_charges` are the FLIPPER's, and consulting them for every
## weapon was why a spinner never spun: `Bot.flipper_ready()` is false on a machine with no
## flipper, so `_should_fire` refused before it ever reached the spin-up rule, and the
## measured result was `fire` false for all 1974 ticks of a thirty second fight and a bar
## that sat at zero readiness the whole time (2026-09-14).
func _weapon_ready(me: Object, tick: int, profile: Dictionary, kind: String) -> bool:
	# A held weapon has no tap cooldown: the cooldown exists so a flipper does not empty
	# its gas into one clinch, and a saw has nothing to empty.
	if not bool(profile["hold"]) and tick < _fire_ready_tick:
		return false
	if me.has_method("weapon_jammed") and bool(me.call("weapon_jammed")):
		return false
	if kind == "flipper":
		var gas: Variant = me.get("gas_charges")
		if gas != null and int(gas) <= 0:
			return false
		if me.has_method("flipper_ready"):
			return bool(me.call("flipper_ready"))
	return true


# ---------------------------------------------------------------- other modes

func _charge(my_position: Vector3, foe_position: Vector3, forward: Vector3, tick: int) -> Dictionary:
	var to_foe := _flat(foe_position - my_position)
	var fire := false
	if tick >= _fire_ready_tick and to_foe.length() <= CHARGE_FIRE_RANGE_M:
		fire = true
		_fire_ready_tick = tick + FIRE_COOLDOWN_TICKS
	var direction := to_foe if to_foe.length() > 0.0001 else forward
	return _input(heading_from_world_dir(direction), fire, false)


func _recover(me: Object, forward: Vector3, tick: int) -> Dictionary:
	# After two failed srimech presses, drive in reverse to rock off whatever is holding us.
	if tick < _reverse_until_tick:
		return _input(heading_from_world_dir(-forward), false, false)
	if _failed_flips >= RECOVER_GIVE_UP_PRESSES:
		_reverse_until_tick = tick + REVERSE_TICKS
		_failed_flips = 0
		return _input(heading_from_world_dir(-forward), false, false)
	# Press the srimech only once the bot is nearly still: firing mid tumble wastes it.
	# How quickly it comes back for another go is the tier's srimech speed.
	if _speed(me) <= RECOVER_STILL_SPEED and tick >= _secondary_ready_tick:
		_secondary_ready_tick = tick \
			+ int(round(float(RECOVER_RETRY_TICKS) * float(_skill["srimech"])))
		_failed_flips += 1
		return _input(Vector2.ZERO, false, true)
	return FightTypes.empty_input()


# ---------------------------------------------------------------- skill behaviours

## The opponent's position and facing as this driver believes them to be: the truth,
## eased in over the tier's reaction time. A jump bigger than TELEPORT_M is not something
## a machine can do in a tick, so a spawn or a test fixture is believed at once.
func _update_belief(foe_position: Vector3, foe_forward: Vector3) -> void:
	var facing := foe_forward if foe_forward.length() > 0.0001 else Vector3.RIGHT
	if not _belief_ready or _last_seen.distance_to(foe_position) > TELEPORT_M:
		_believed = foe_position
		_believed_forward = facing.normalized()
		_belief_ready = true
		_last_seen = foe_position
		return
	var alpha := clampf(1.0 / maxf(float(_skill["reaction_s"]) * float(FightTypes.TICK_HZ),
		1.0), 0.0, 1.0)
	_believed = _believed.lerp(foe_position, alpha)
	var eased := _believed_forward.lerp(facing, alpha)
	_believed_forward = eased.normalized() if eased.length() > 0.0001 else facing.normalized()
	_last_seen = foe_position


## Somewhere to run to, or Vector3.ZERO for "nothing here is going to hurt us".
##
## This is the LAST line, not the first: the danger map has already been keeping the
## machine away from all of this for a second or more. What reaches here is a machine that
## has been shoved onto something, or spawned beside it, and the answer is the same at
## every tier -- get off it -- because NO TIER MAY EVER LOOK STUPID. The only thing still
## gated by skill is the house bot's corner, which is a keep-out rather than a hazard: a
## Scrapyard driver does not know whose corner that is, and nothing in it will hurt it.
func _escape(my_position: Vector3, forward: Vector3, ctx: Dictionary, tick: int) -> Vector3:
	# The spike patch is signposted, and every tier gets off it. The latch covers the
	# seconds AFTER the rise, when the arena's countdown has already wrapped round to the
	# next one and the spikes it published are standing in the floor (see SPIKE_WRAP_S).
	var spike_centre: Vector3 = ctx.get("spike_centre", Vector3.ZERO)
	var spike_rise_in_s := float(ctx.get("spike_rise_in_s", 999.0))
	var from_spikes := _flat(my_position - spike_centre)
	if (spike_rise_in_s <= SPIKE_AVOID_LEAD_S or tick < _spike_live_until_tick) \
			and from_spikes.length() <= SPIKE_AVOID_RANGE_M:
		return _away(from_spikes, forward)

	for entry in _live_hazards(ctx):
		var from_hazard := _flat(my_position - (entry as Vector3))
		if from_hazard.length() <= HAZARD_AVOID_M:
			return _away(from_hazard, forward)

	if bool(_skill["zone"]):
		var zone: Variant = ctx.get("zone_rect", null)
		if zone is Rect2:
			var here := Vector2(my_position.x, my_position.z)
			if (zone as Rect2).grow(ZONE_MARGIN_M).has_point(here):
				var centre := (zone as Rect2).get_center()
				var away_zone := Vector3(here.x - centre.x, 0.0, here.y - centre.y)
				if away_zone.length() <= 0.0001:
					# Standing on the middle of its mark: out of the corner is toward the
					# middle of the floor, which is always away from a corner zone.
					away_zone = -_flat(my_position)
				return _away(away_zone, forward)
	return Vector3.ZERO


## A normalised "that way", with the machine's own nose as the answer when "away" has no
## direction at all (dead centre of the thing we are standing on).
static func _away(from_it: Vector3, forward: Vector3) -> Vector3:
	if from_it.length() > 0.0001:
		return from_it.normalized()
	return forward.normalized() if forward.length() > 0.0001 else Vector3.RIGHT


## Everything the arena currently calls live. `hazard` is the whole helper dictionary
## from `ArenaBase.hazard_helpers()`; `hazards` is the flattened list fight.gd also puts
## on the context for CINDER. Either will do, and neither has to be there.
func _live_hazards(ctx: Dictionary) -> Array:
	var helpers: Variant = ctx.get("hazard", null)
	if helpers is Dictionary and (helpers as Dictionary).has("danger_positions"):
		var listed: Variant = (helpers as Dictionary)["danger_positions"]
		if listed is Array:
			return listed as Array
	var flat: Variant = ctx.get("hazards", [])
	return flat as Array if flat is Array else []


## Drive them into the wall and hold them there for three seconds, then let go: the pin
## rule (FightRules.is_pinned, four seconds) is a penalty, and a pin that ends in one is
## worse than no pin at all.
func _pinning(my_position: Vector3, foe_position: Vector3, range_m: float, tick: int) -> bool:
	if not bool(_skill["pin"]):
		return false
	var eagerness := float(_active["pin"])
	if _pin_until_tick > 0 and tick >= _pin_until_tick:
		_pin_until_tick = -1
		_pin_rest_until_tick = tick \
			+ int(round(float(PIN_REST_TICKS) / maxf(eagerness, 0.1)))
		return false
	if tick < _pin_rest_until_tick:
		return false
	var on_wall := _wall_distance(foe_position) <= PIN_WALL_M * eagerness
	if _pin_until_tick > tick:
		# Already pinning: hold it while they are still on the wall and still ours.
		if on_wall and range_m <= PIN_RANGE_M * eagerness + 0.4:
			return true
		_pin_until_tick = -1
		return false
	if on_wall and range_m <= PIN_RANGE_M * eagerness:
		_pin_until_tick = tick + PIN_HOLD_TICKS
		return true
	return false


## Behind them with something live in front of them: push. The hazard does the damage and
## the last toucher is credited with it, so this is the cheapest damage in the game.
func _shoving(foe_position: Vector3, to_foe_dir: Vector3, range_m: float,
		ctx: Dictionary) -> bool:
	if not bool(_skill["shove"]) or range_m > SHOVE_RANGE_M:
		return false
	var reach := HAZARD_SHOVE_M * float(_active["shove"])
	for entry in _live_hazards(ctx):
		var to_hazard := _flat((entry as Vector3) - foe_position)
		var gap := to_hazard.length()
		if gap > reach or gap < 0.05:
			continue
		if to_hazard.normalized().dot(to_foe_dir) >= SHOVE_LINE_DOT:
			return true
	return false


## Give ground when the machine is coming apart. How hurt it has to be is the
## temperament: an opportunist leaves early, a brawler never leaves at all. An inverted
## opponent is not something you retreat from, whatever the temperament says.
func _retreating(me: Object, foe: Object, range_m: float, standoff: float) -> bool:
	var appetite := float(_active["retreat"])
	if appetite <= 0.0:
		return false
	if range_m > standoff + STANDOFF_BAND_M:
		return false                # already out of it: nothing to retreat from
	if bool(_active["pounce"]) and foe != null and _is_inverted(foe):
		return false
	return _condition_fraction(me) < RETREAT_CONDITION * appetite


## What is worth knowing about the machine in front of us, at this tier's reading.
##   min_angle_deg  a spinner is taken from the side or the rear of the spin, never head on
##   offset_deg     a flipper is approached thirty degrees off its nose, never down it
##   no_latch       a crusher gets hold of anything that stops moving, so never stop
##   punish         their bar is down: the reload is the opening (full reading)
##   bait           make a hot weapon come to us while ours reloads (Masters)
##   rear_bias      how deep behind the shoulder to work, from their armour (National up)
func _counter_for(foe: Object) -> Dictionary:
	var out := {"min_angle_deg": 0.0, "offset_m": 0.0, "no_latch": false,
		"punish": false, "bait": false, "rear_bias": 0.6}
	var reading := str(_skill["reading"])
	if reading == READ_NONE or foe == null:
		return out
	# A build you have not been shown cannot be read: the counter only fires against a
	# machine that actually declares its weapon.
	var kind := _known_weapon_kind(foe)
	if kind == "":
		return out
	match kind:
		"spinner", "drum", "fbs":
			out["min_angle_deg"] = COUNTER_SPIN_ANGLE_DEG
			out["punish"] = reading == READ_FULL
			out["bait"] = bool(_skill["bait"])
		"flipper", "lifter":
			out["offset_m"] = tan(deg_to_rad(COUNTER_FLIPPER_DEG)) * CONTACT_M
		"crusher":
			out["no_latch"] = true
	if reading == READ_WEAPON_ARMOUR or reading == READ_FULL:
		if _weakest_face(foe) == "rear":
			out["rear_bias"] = 1.0
	return out


## The approach line: straight at them, or off the nose of a machine whose whole game is
## what happens on its centreline.
##
## The offset is a point beside them, NOT a rotation of the heading: a heading rotated
## thirty degrees every tick is a spiral that never arrives, where aiming half a chassis
## to one side of them converges on their front CORNER, which is what "thirty degrees off
## the nose" means when you get there (atan(0.55 / 0.9) is thirty degrees at contact).
func _approach(my_position: Vector3, foe_position: Vector3, to_foe_dir: Vector3,
		counter: Dictionary, range_m: float, engage_m: float) -> Vector3:
	var offset := float(counter["offset_m"])
	if offset < 0.001:
		return to_foe_dir
	if range_m <= engage_m:
		# Close enough to bite. The offset is how you LINE UP on a wedge, not how you hit
		# it: a bot that keeps sidestepping at contact range never lands anything.
		return to_foe_dir
	var side := to_foe_dir.cross(Vector3.UP)
	if side.length() < 0.0001:
		return to_foe_dir
	var target := foe_position + side.normalized() * offset * float(_flank_sign)
	var to_target := _flat(target - my_position)
	return to_target.normalized() if to_target.length() > 0.0001 else to_foe_dir


## Behind on the judges' tally? fight.gd puts `judge_points` (bot id -> points) on the
## context inside the last twenty seconds. Without it, damage is the biggest column on the
## card, so the machines themselves are the next best read.
func _behind_on_points(me: Object, foe: Object, ctx: Dictionary) -> bool:
	var points: Variant = ctx.get("judge_points", null)
	if points is Dictionary:
		var card := points as Dictionary
		var mine := float(card.get(_bot_id(me), 0.0))
		var theirs := float(card.get(_bot_id(foe), 0.0))
		if not is_equal_approx(mine, theirs):
			return mine < theirs
	return _condition_fraction(me) < _condition_fraction(foe) - 0.02


# ---------------------------------------------------------------- helpers

static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## How far a position is from the nearest arena wall. The Coliseum is bigger than this,
## which only makes a pin there slightly less eager: it is never wrong, only shy.
static func _wall_distance(position: Vector3) -> float:
	var half := FightTypes.ARENA_SIZE * 0.5
	return maxf(0.0, half - maxf(absf(position.x), absf(position.z)))


func _bot_id(bot: Object) -> String:
	if bot == null:
		return ""
	var id: Variant = bot.get("bot_id")
	return str(id) if id != null else ""


## 0..1 of the machine still there, from the same condition() dictionary the judges read.
func _condition_fraction(bot: Object) -> float:
	if bot == null or not bot.has_method("condition"):
		return 1.0
	var condition: Variant = bot.call("condition")
	if not (condition is Dictionary):
		return 1.0
	var parts := condition as Dictionary
	var slots := float((parts.get("wheels", []) as Array).size()) + 7.0
	return clampf(FightRules.condition_total(parts) / maxf(slots, 1.0), 0.0, 1.0)


## Which armour face has the least left on it, or "" when we cannot see.
func _weakest_face(bot: Object) -> String:
	if bot == null or not bot.has_method("condition"):
		return ""
	var condition: Variant = bot.call("condition")
	if not (condition is Dictionary):
		return ""
	var armour: Dictionary = (condition as Dictionary).get("armour", {}) as Dictionary
	var worst := ""
	var worst_value := INF
	for face in ["front", "sides", "rear", "top"]:
		if not armour.has(face):
			continue
		var value := float(armour[face])
		if value < worst_value:
			worst_value = value
			worst = face
	return worst


## The weapon kind the machine DECLARES, with no fallback: `_weapon_kind` answers "flipper"
## for anything it cannot read, which is the right default for driving our own machine and
## exactly the wrong one for reading somebody else's.
func _known_weapon_kind(bot: Object) -> String:
	if bot == null:
		return ""
	if bot.has_method("weapon_kind"):
		var kind := str(bot.call("weapon_kind"))
		if kind != "":
			return kind
	var weapon: Variant = bot.get("weapon")
	if weapon is Object and (weapon as Object).get("kind") != null:
		return str((weapon as Object).get("kind"))
	return ""


## Jitter (so it never looks scripted) and then the tier's aim error (so a Scrapyard
## driver steers a quarter turn wide of what it meant and a Masters driver does not).
## Both are drawn on the same fixed cadence, so neither can change the draw count.
func _jittered(heading: Vector2) -> Vector2:
	if heading.length() < 0.0001:
		return heading
	var out := heading + _jitter
	if out.length() > 1.0:
		out = out.normalized()
	var aim_deg := float(_skill["aim_deg"]) * _aim_offset
	if absf(aim_deg) > 0.001:
		out = out.rotated(deg_to_rad(aim_deg))
	return out


func _input(heading: Vector2, fire: bool, secondary: bool) -> Dictionary:
	return {"heading": heading, "fire": fire, "secondary": secondary}


func _position(bot: Object) -> Vector3:
	var chassis: Object = bot.get("chassis")
	if chassis == null:
		return Vector3.ZERO
	return (chassis as Node3D).global_position


## The nose direction. `Bot._drive` steers by `chassis.global_basis.x`, so that is the
## nose, and `Bot.place_at` yaws the same way. Measured 2026-09-13: a bot placed facing
## +X has basis.x = (1,0,0) and -basis.z = (0,0,-1).
func _forward(bot: Object) -> Vector3:
	var chassis: Object = bot.get("chassis")
	if chassis == null:
		return Vector3.RIGHT
	return (chassis as Node3D).global_transform.basis.x.normalized()


func _speed(bot: Object) -> float:
	var chassis: Object = bot.get("chassis")
	if chassis is RigidBody3D:
		return (chassis as RigidBody3D).linear_velocity.length()
	return 0.0


# --- what weapon is this? -------------------------------------------------------------
## Everything here is duck typed through `has_method` / `get`, with the Stage 3 flipper as
## the fallback, so the AI works against P2's Bot before and after `weapon_readiness()`
## lands and against W1/W2's weapons before and after they do.

func _profile(bot: Object) -> Dictionary:
	# The weapon's own row first (wave P), then its kind's, then the flipper's.
	var id := _weapon_id(bot)
	if id != "" and PROFILES_BY_ID.has(id):
		return PROFILES_BY_ID[id] as Dictionary
	var kind := _weapon_kind(bot)
	return PROFILES.get(kind, PROFILES[DEFAULT_KIND]) as Dictionary


## The catalogue id of the fitted weapon, or "" when the machine will not say.
## Duck typed like everything else here: the Bot writes `id` into the weapon's
## spec when it builds it, and a fake bot in a test need not have one at all.
func _weapon_id(bot: Object) -> String:
	var weapon: Variant = bot.get("weapon")
	if not (weapon is Object):
		return ""
	var spec: Variant = (weapon as Object).get("spec")
	if not (spec is Dictionary):
		return ""
	return str((spec as Dictionary).get("id", ""))


func _weapon_kind(bot: Object) -> String:
	if bot.has_method("weapon_kind"):
		return str(bot.call("weapon_kind"))
	var weapon: Variant = bot.get("weapon")
	if weapon is Object and (weapon as Object).get("kind") != null:
		var kind := str((weapon as Object).get("kind"))
		if kind != "":
			return kind
	return DEFAULT_KIND


func _weapon_reach(bot: Object) -> float:
	for method in ["weapon_reach", "reach"]:
		if bot.has_method(method):
			var value := float(bot.call(method))
			if value > 0.0:
				return value
	var weapon: Variant = bot.get("weapon")
	if weapon is Object and (weapon as Object).has_method("reach"):
		var value := float((weapon as Object).call("reach"))
		if value > 0.0:
			return value
	return DEFAULT_REACH


## 0 to 1. A weapon with no idea of readiness is always ready, which is the Stage 3
## flipper's behaviour and the right default for anything that does not spin up.
func _weapon_readiness(bot: Object) -> float:
	if bot.has_method("weapon_readiness"):
		return clampf(float(bot.call("weapon_readiness")), 0.0, 1.0)
	var weapon: Variant = bot.get("weapon")
	if weapon is Object and (weapon as Object).has_method("readiness"):
		return clampf(float((weapon as Object).call("readiness")), 0.0, 1.0)
	return 1.0


func _is_inverted(bot: Object) -> bool:
	if bot.has_method("is_inverted"):
		return bool(bot.call("is_inverted"))
	return false
