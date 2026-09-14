extends "res://fight/events/event_rules.gd"
## SUMO (side event 1, docs/stage6-spec.md §1, brief §10 "push out of a ring").
##
## Best of three on a 6 m platform inside ninety seconds. A round ends the moment either
## machine is off the platform; the other one takes it. Two rounds clears the event and
## pays the blueprint, which Swift decides from `cleared` and nothing here knows about.
##
## Why it is scored in ROUNDS and not in pushes: a single push-out is one lucky corner, and
## the original's trial modes were all best-of formats. Three rounds inside one clock also
## means the clock is a real pressure (a cagey round costs you the third one) without ever
## being the thing that decides it: a 1-0 lead on the bell is a WIN, because leading when
## the time runs out is winning, and "not enough time to finish it" is not a draw anybody
## enjoys.
##
## Determinism: the only state is two integers and two floats, all written inside
## `physics_tick`. The off-platform test is arithmetic on a chassis position, not a signal,
## so a replay lands on the same tick the fight did.

const ARENA_SCENE := "res://arena/events/sumo.tscn"
const ROUNDS := 3
const ROUNDS_TO_WIN := 2
## After a reset, neither machine can lose for this long. Both are put back on their marks
## with the velocities zeroed, and a joint assembly takes a few ticks to settle: without
## the pause a bot that was mid-throw can register as off the platform on the first tick of
## the new round, which reads as the arena awarding a round to nobody.
const SETTLE_S := 1.2
## The same pause at the bell, so a machine that spawned badly is not lost before it moves.
const OPENING_SETTLE_S := 0.5
## Used only when the event is somehow run in an arena that is not The Ring.
const FALLBACK_RADIUS := 3.35

var _duration := FightTypes.FIGHT_DURATION_S
var _rounds_won := [0, 0]
var _round_index := 0
var _settle_until := OPENING_SETTLE_S
var _over := false
## One entry per finished round: 0 player, 1 opponent, -1 both off in the same tick.
var _round_winners: Array[int] = []


func setup(owner_fight: Node, event_config: Dictionary) -> void:
	super(owner_fight, event_config)
	var rules: Dictionary = event_config.get("rules", {}) as Dictionary
	_duration = float(rules.get("duration_s", FightTypes.FIGHT_DURATION_S))
	_rounds_won = [0, 0]
	_round_index = 0
	_round_winners = []
	_settle_until = OPENING_SETTLE_S
	_over = false


func arena_scene_path() -> String:
	return ARENA_SCENE


func physics_tick(delta: float) -> void:
	super(delta)
	if _over:
		return
	if time_s < _settle_until:
		return
	var list := bots()
	var off_0 := _is_off(list[0] if list.size() > 0 else null)
	var off_1 := _is_off(list[1] if list.size() > 1 else null)
	if not off_0 and not off_1:
		return
	if off_0 and off_1:
		_end_round(-1)
	elif off_0:
		_end_round(1)
	else:
		_end_round(0)


func is_over() -> bool:
	return _over or time_s >= _duration


func result() -> Dictionary:
	var won := int(_rounds_won[0])
	var lost := int(_rounds_won[1])
	return {
		"score": won,
		"cleared": won >= ROUNDS_TO_WIN,
		"details": {
			"rounds_won": won,
			"rounds_lost": lost,
			"rounds_played": _round_winners.size(),
			"round_winners": _round_winners.duplicate(),
			# Leading on the bell is a win of the EVENT but not a clear: the blueprint is
			# for taking two rounds. The shell shows this as "1 - 0, not cleared".
			"led_on_the_bell": won > lost and won < ROUNDS_TO_WIN,
		},
	}


func hud_lines() -> Array[String]:
	var shown := mini(_round_index + 1, ROUNDS)
	var lines: Array[String] = [
		"ROUND %d OF %d" % [shown, ROUNDS],
		"ROUNDS %d - %d" % [int(_rounds_won[0]), int(_rounds_won[1])],
		clock(_duration - time_s),
	]
	if time_s < _settle_until and _round_index > 0:
		lines.append("BACK TO YOUR MARKS")
	return lines


# --------------------------------------------------------------------------------------

func _is_off(bot: Node) -> bool:
	if bot == null:
		return false
	var at := bot_position(bot)
	var ring := arena()
	if ring != null and ring.has_method("on_platform"):
		return not bool(ring.call("on_platform", at))
	return Vector2(at.x, at.z).length() > FALLBACK_RADIUS or at.y < -0.06


func _end_round(winner: int) -> void:
	if winner >= 0:
		_rounds_won[winner] = int(_rounds_won[winner]) + 1
	_round_winners.append(winner)
	_round_index += 1
	if int(_rounds_won[0]) >= ROUNDS_TO_WIN or int(_rounds_won[1]) >= ROUNDS_TO_WIN \
			or _round_index >= ROUNDS:
		_over = true
		return
	_reset_round()


## Both machines back on their marks, in whatever condition they are in. Damage carries
## across rounds on purpose: a bot that spent round one being cut up should feel it in
## round two, or the event is three unrelated fights.
func _reset_round() -> void:
	var ring := arena()
	var list := bots()
	for i in range(mini(list.size(), 2)):
		var bot: Node = list[i]
		if bot == null or not bot.has_method("place_at"):
			continue
		var mark := Vector3(-1.8, 0.25, 0.0) if i == 0 else Vector3(1.8, 0.25, 0.0)
		var facing := Vector3.RIGHT if i == 0 else Vector3.LEFT
		if ring != null and ring.has_method("spawn_position"):
			mark = ring.call("spawn_position", i) as Vector3
			facing = ring.call("spawn_facing", i) as Vector3
		_set_down(bot, mark, facing)
		if bot.has_method("apply_input"):
			bot.call("apply_input", FightTypes.empty_input())
	_settle_until = time_s + SETTLE_S


## Put an assembled, already simulating machine down on a mark, level and facing the right
## way. NOT `Bot.place_at`, and that is a trap worth writing down.
##
## `place_at` sets the BOT NODE'S global transform and then pushes each part's node
## transform at the physics server. That is an absolute placement only while the parts are
## still sitting at the local offsets the assembler gave them. Once the machine has been
## simulating, each part's transform relative to the root is wherever the solver has put
## it, so setting the root moves the whole assembly by a DELTA instead of to a position.
## MEASURED: a machine shoved to x = 4.41 and then `place_at(1.8)`-ed from a mark of 2.5
## landed at 3.71, which is 4.41 minus 0.7, and was still off the platform, so the round
## reset awarded the next round to the same bot and the event ended 2-0 on one push.
## `fight.gd._replace_bot` (test mode's stray replacement) is built the same way and will
## have the same behaviour; flagged for agent R in docs/stage6-events-notes.md.
##
## So this computes the rigid transform that maps the CHASSIS onto the mark and applies it
## to every attached part and to the root. Everything moves together, so the joint frames
## are unchanged, and because the target basis is pure yaw the machine also comes back the
## right way up.
func _set_down(bot: Node, mark: Vector3, facing: Vector3) -> void:
	var chassis: Variant = bot.get("chassis")
	if not (chassis is RigidBody3D) or not (bot is Node3D):
		if bot.has_method("place_at"):
			bot.call("place_at", mark, facing)
		return
	var body: RigidBody3D = chassis
	var flat := Vector3(facing.x, 0.0, facing.z)
	if flat.length_squared() < 1e-6:
		flat = Vector3.RIGHT
	flat = flat.normalized()
	var ride := float(bot.call("ride_height")) if bot.has_method("ride_height") else 0.11
	var want := Transform3D(Basis(Vector3.UP, atan2(-flat.z, flat.x)),
		Vector3(mark.x, maxf(mark.y, ride), mark.z))
	var now := body.global_transform
	now.basis = now.basis.orthonormalized()
	var fix := want * now.affine_inverse()
	var parts: Array = bot.call("attached_parts") if bot.has_method("attached_parts") else []
	# The parts' targets are computed BEFORE the root moves, and applied after. Moving the
	# root ALREADY drags every child's global transform by `fix` (the children keep their
	# local transforms), so reading a part's global transform afterwards and multiplying by
	# `fix` again applies it twice. Measured: a machine asked for (-4.00, 0.62, 1.25)
	# landed at (-8.09, 1.09, -0.71), which is exactly `fix` squared.
	var targets: Array[Transform3D] = []
	for part_variant in parts:
		targets.append(fix * (part_variant as Node3D).global_transform)
	(bot as Node3D).global_transform = fix * (bot as Node3D).global_transform
	for i in range(parts.size()):
		var part: RigidBody3D = parts[i]
		if not is_instance_valid(part):
			continue
		part.global_transform = targets[i]
		part.linear_velocity = Vector3.ZERO
		part.angular_velocity = Vector3.ZERO
