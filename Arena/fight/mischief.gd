class_name FightMischief extends RefCounted
## House bot mischief, AFTER THE RESULT ONLY (wave D, docs/wave-d-marshal-notes.md; owner
## decision 30 Sept 2026, docs/aaa/decisions-2026-09-30.md): during the finish beat after a
## knockout or a kill, the house bot drives to the beaten machine and shoves it into the
## arena's nearest hazard (the finishing ritual). About one fight in four it also lands a
## late hit after the bell; the Marshal flies in and cards it and it backs off.
##
## WHY IT CANNOT CHANGE THE FIGHT. It is planned inside `_finish`, AFTER the FightResult has
## been built (the replay inputs, the damage, the scrap and the judges are all in it) and it
## first moves on the RESULT state's WAIT_TICKS-th tick, well after the result has gone to
## the shell and after the one RESULT row the determinism goldens hash. Both machines are
## `stop_for_result`ed by then, so no damage can land on either (bot.gd refuses damage on a
## stopped machine) and nothing scores after the bell anyway. Only the HOUSE BOT is woken
## up; it is not a competitor and is in no tally. tests/mischief_test.gd fights the same
## fight with the mischief forced on, off and late, and proves the result (every key but the
## two wall clock stamps), the replay inputs and the hash rows identical.
##
## It never happens to the player's machine when the player won: the target is always the
## LOSER, and fight.gd refuses to plan one with no loser.
##
## Pure: it takes positions and returns an input record, so it draws nothing from the
## fight's rng and the test drives it without a physics world. Which kind a fight gets is a
## hash of the fight's seed, so a replay plays the same mischief the fight did.

const KIND_NONE := ""
const KIND_RITUAL := "ritual"
const KIND_LATE := "late"
## One fight in LATE_ONE_IN gets the late hit.
const LATE_ONE_IN := 4

const PHASE_WAIT := "wait"
const PHASE_APPROACH := "approach"
const PHASE_SHOVE := "shove"
const PHASE_HIT := "hit"
const PHASE_BACK := "back"
const PHASE_DONE := "done"

## RESULT ticks before the house bot moves: the slow motion on the loser plays first, and
## the hashed RESULT row is long gone.
const WAIT_TICKS := 30
const APPROACH_MAX_TICKS := 150
const SHOVE_MAX_TICKS := 100
const HIT_TICKS := 40
const BACK_TICKS := 70
## It lines up this far behind the loser (on the far side from the hazard) before it pushes.
const BEHIND_M := 0.85
const ARRIVE_M := 0.45
## The shove is done when the loser is this close to the hazard's centre.
const DELIVERED_M := 0.55
## A winner this close to the approach line is driven round, never through.
const WINNER_CLEAR_M := 1.1
const DETOUR_M := 1.3
const THROTTLE := 0.9
const HIT_REACH_M := 1.05

## Extra finish beat seconds this mischief needs on top of fight.gd's FINISH_BEAT_S.
const EXTRA_S := {KIND_RITUAL: 3.0, KIND_LATE: 4.8}

var kind: String = KIND_NONE
var phase: String = PHASE_WAIT
var hazard: Vector3 = Vector3.ZERO
var ticks: int = 0
var _phase_ticks: int = 0
## Moments for the presentation, drained by fight.gd: "finish" (the shove starts),
## "delivered" (the loser reached the hazard), "late_hit", "back_off", "done".
var events: Array = []


## Which mischief a fight gets. `forced` ("off", "ritual", "late") is QA's override.
static func kind_for(seed_value: int, forced: String = "") -> String:
	match forced:
		"off", "none":
			return KIND_NONE
		KIND_RITUAL, KIND_LATE:
			return forced
	var h := absi(hash("house_mischief:%d" % seed_value))
	return KIND_LATE if h % LATE_ONE_IN == 0 else KIND_RITUAL


static func extra_seconds(which: String) -> float:
	return float(EXTRA_S.get(which, 0.0))


func _init(which: String = KIND_RITUAL, hazard_at: Vector3 = Vector3.ZERO) -> void:
	kind = which
	hazard = Vector3(hazard_at.x, 0.0, hazard_at.z)
	phase = PHASE_WAIT if which != KIND_NONE else PHASE_DONE


func active() -> bool:
	return phase != PHASE_DONE


## Is the house bot moving under the mischief this tick (anything but the wait and done)?
func driving() -> bool:
	return phase in [PHASE_APPROACH, PHASE_SHOVE, PHASE_HIT, PHASE_BACK]


## One RESULT tick. Returns the house bot's input record for this tick, or {} when it should
## be left alone (still waiting, or done). Positions are chassis positions.
func step(house: Vector3, loser: Vector3, winner: Vector3) -> Dictionary:
	ticks += 1
	_phase_ticks += 1
	var h := Vector3(house.x, 0.0, house.z)
	var l := Vector3(loser.x, 0.0, loser.z)
	var w := Vector3(winner.x, 0.0, winner.z)
	match phase:
		PHASE_WAIT:
			if ticks >= WAIT_TICKS:
				_enter(PHASE_APPROACH)
			return {}
		PHASE_APPROACH:
			var spot := push_spot(l, hazard)
			if h.distance_to(spot) <= ARRIVE_M or _phase_ticks >= APPROACH_MAX_TICKS:
				_enter(PHASE_SHOVE)
				events.append("finish")
				return _drive(_toward(h, l), false)
			return _drive(_toward(h, waypoint(h, spot, w)), false)
		PHASE_SHOVE:
			var delivered := l.distance_to(hazard) <= DELIVERED_M
			if delivered or _phase_ticks >= SHOVE_MAX_TICKS:
				if delivered:
					events.append("delivered")
				if kind == KIND_LATE:
					_enter(PHASE_HIT)
					events.append("late_hit")
				else:
					_enter(PHASE_BACK)
				return {}
			# drive through the loser along the line to the hazard
			var through := l + _toward(l, hazard) * 0.3
			return _drive(_toward(h, through), false)
		PHASE_HIT:
			if _phase_ticks >= HIT_TICKS:
				_enter(PHASE_BACK)
				events.append("back_off")
				return {}
			# face it and press the button: the late hit
			var near := h.distance_to(l) <= HIT_REACH_M
			var rec := _drive(_toward(h, l), true)
			rec["heading"] = (rec["heading"] as Vector2) * (0.35 if near else 0.8)
			return rec
		PHASE_BACK:
			if _phase_ticks >= BACK_TICKS:
				_enter(PHASE_DONE)
				events.append("done")
				return {"heading": Vector2.ZERO, "fire": false, "secondary": false}
			# away from the loser, and away from the winner if it is in the way
			var away := _toward(l, h)
			var from_w := h - w
			if from_w.length() < WINNER_CLEAR_M and from_w.length() > 0.01:
				away = (away + from_w.normalized()).normalized()
			return _drive(away, false)
	return {}


## Where to stand to push the loser into the hazard: behind it, on the far side.
static func push_spot(loser: Vector3, hazard_at: Vector3) -> Vector3:
	var from_hazard := Vector3(loser.x - hazard_at.x, 0.0, loser.z - hazard_at.z)
	if from_hazard.length() < 0.01:
		from_hazard = Vector3.RIGHT
	return Vector3(loser.x, 0.0, loser.z) + from_hazard.normalized() * BEHIND_M


## The next point to drive at: the push spot, or a detour round the winner when the winner
## sits near the straight line to it. The winner is never driven through.
static func waypoint(house: Vector3, spot: Vector3, winner: Vector3) -> Vector3:
	var line := spot - house
	var length := line.length()
	if length < 0.01:
		return spot
	var dir := line / length
	var along := clampf((winner - house).dot(dir), 0.0, length)
	var closest := house + dir * along
	var off := winner - closest
	if off.length() >= WINNER_CLEAR_M or along <= 0.0 or along >= length:
		return spot
	var side := dir.cross(Vector3.UP)
	if off.dot(side) > 0.0:
		side = -side          # go round on the side away from the winner
	return closest + side * DETOUR_M


func _enter(next: String) -> void:
	phase = next
	_phase_ticks = 0


static func _toward(from: Vector3, to: Vector3) -> Vector3:
	var d := Vector3(to.x - from.x, 0.0, to.z - from.z)
	return d.normalized() if d.length() > 0.001 else Vector3.ZERO


static func _drive(dir: Vector3, fire: bool) -> Dictionary:
	return {
		"heading": Vector2(dir.x, dir.z) * THROTTLE,
		"fire": fire,
		"secondary": false,
	}
