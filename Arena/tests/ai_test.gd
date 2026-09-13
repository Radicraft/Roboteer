extends SceneTree
## Headless unit test for the opponent AI (docs/stage3-spec.md §9).
##   Godot --headless --path Arena --script tests/ai_test.gd
##
## The bots are small fakes rather than the real Bot scene, so this passes before P's
## work lands and stays fast: the AI only ever reads `chassis` and `is_inverted()`.

const OpponentAIScript := preload("res://ai/opponent_ai.gd")

const SEED := 987654321


class FakeBot extends Node3D:
	var chassis: RigidBody3D = null

	var _inverted := false

	func _init() -> void:
		chassis = RigidBody3D.new()
		chassis.freeze = true
		chassis.gravity_scale = 0.0
		add_child(chassis)

	func place(origin: Vector3, facing: Vector3) -> void:
		var flat := Vector3(facing.x, 0.0, facing.z)
		if flat.length() < 0.0001:
			flat = Vector3.FORWARD
		chassis.global_transform = Transform3D(Basis(), origin).looking_at(
			origin + flat.normalized(), Vector3.UP)

	func set_inverted(value: bool) -> void:
		_inverted = value

	func is_inverted() -> bool:
		return _inverted


var _failures := 0
var _checks := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var me := FakeBot.new()
	var foe := FakeBot.new()
	root.add_child(me)
	root.add_child(foe)
	# root.add_child() during _initialize() does not enter the tree until the first
	# frame, and Node3D.global_transform needs the tree. Wait one frame.
	await process_frame

	_test_idle(me, foe)
	_test_approach(me, foe)
	_test_strike(me, foe)
	_test_charge(me, foe)
	_test_recover(me, foe)
	_test_spike_avoidance(me, foe)
	_test_determinism(me, foe)
	_test_ai_versus_ai(me, foe)
	_test_heading_mapping()

	_finish()


# ---------------------------------------------------------------- idle

func _test_idle(me: FakeBot, foe: FakeBot) -> void:
	var ai := OpponentAIScript.new(_rng(), OpponentAIScript.MODE_IDLE)
	me.place(Vector3(3.2, 0.25, 3.2), Vector3(-1, 0, -1))
	foe.place(Vector3(-3.2, 0.25, -3.2), Vector3(1, 0, 1))
	var moved := false
	for tick in 240:
		var inp := ai.think(me, foe, _ctx(tick))
		if inp["heading"] != Vector2.ZERO or inp["fire"] or inp["secondary"]:
			moved = true
	_check(not moved, "idle mode returns zero input for 240 ticks")


# ---------------------------------------------------------------- approach

func _test_approach(me: FakeBot, foe: FakeBot) -> void:
	var ai := OpponentAIScript.new(_rng())
	me.place(Vector3(3.2, 0.25, 3.2), Vector3(-1, 0, -1))
	foe.place(Vector3(-3.2, 0.25, -3.2), Vector3(1, 0, 1))
	var to_foe := Vector2(-3.2 - 3.2, -3.2 - 3.2).normalized()
	var toward := 0
	for tick in 120:
		var heading: Vector2 = ai.think(me, foe, _ctx(tick))["heading"]
		if heading.dot(to_foe) > 0.5:
			toward += 1
	_check(toward == 120, "approach heads toward the opponent on every tick (%d of 120)" % toward)

	var far_heading: Vector2 = ai.think(me, foe, _ctx(200))["heading"]
	_check(is_equal_approx(far_heading.length(), 1.0) or far_heading.length() > 0.85,
		"approach drives at full throttle (heading length %0.3f)" % far_heading.length())

	# The flank matters: from dead behind them it should still close, and it should not
	# aim at the exact centre of a bot that is facing away.
	foe.place(Vector3(0, 0.25, 0), Vector3(0, 0, -1))
	me.place(Vector3(0, 0.25, 4.0), Vector3(0, 0, -1))
	var rear_heading: Vector2 = ai.think(me, foe, _ctx(240))["heading"]
	_check(rear_heading.dot(Vector2(0, -1)) > 0.5,
		"from behind a fleeing bot the AI still closes on it")

	# Squared up nose to nose at the standoff ring it must NOT charge the front: it works
	# round to a side or rear angle first. That is the whole point of the rework.
	var ai2 := OpponentAIScript.new(_rng())
	foe.place(Vector3(0, 0.25, 0), Vector3(0, 0, 1))
	me.place(Vector3(0, 0.25, 1.4), Vector3(0, 0, -1))
	var straight_in := Vector2(0, -1)
	var circling := 0
	for tick in 60:
		if ai2.think(me, foe, _ctx(tick))["heading"].dot(straight_in) < 0.7:
			circling += 1
	_check(circling >= 50,
		"squared up at the ring it circles for an angle instead of charging the nose (%d of 60)"
			% circling)


# ---------------------------------------------------------------- strike

func _test_strike(me: FakeBot, foe: FakeBot) -> void:
	var ai := OpponentAIScript.new(_rng())
	foe.place(Vector3(0, 0.25, 0), Vector3(0, 0, 1))
	# Nose 0.45 m ahead of the chassis, so a 0.7 m gap puts the front edge 0.25 m away.
	me.place(Vector3(0, 0.25, 0.7), Vector3(0, 0, -1))
	var fired: bool = ai.think(me, foe, _ctx(1))["fire"]
	_check(fired, "the AI fires when its front edge is inside 0.45 m and it is facing them")

	_check(not ai.think(me, foe, _ctx(2))["fire"], "it does not fire again on the very next tick")
	var refired := false
	for tick in range(3, 3 + 120):
		if ai.think(me, foe, _ctx(tick))["fire"]:
			refired = true
			break
	_check(refired, "it fires again after the cooldown")

	var ai2 := OpponentAIScript.new(_rng())
	me.place(Vector3(0, 0.25, 2.5), Vector3(0, 0, -1))
	var fired_far := false
	for tick in 60:
		if ai2.think(me, foe, _ctx(tick))["fire"]:
			fired_far = true
	_check(not fired_far, "it does not fire from 2.5 m away")

	var ai3 := OpponentAIScript.new(_rng())
	me.place(Vector3(0, 0.25, 0.7), Vector3(0, 0, 1))   # facing away, same distance
	var fired_away := false
	for tick in 60:
		if ai3.think(me, foe, _ctx(tick))["fire"]:
			fired_away = true
	_check(not fired_away, "it does not fire with its back to them")

	# The bug this rework exists for: in a real clinch the bots end up much closer than
	# the flipper's nominal reach, and the old "front edge within 0.45 m of their chassis"
	# test inverted there (the front edge is already past them, so the aim check failed).
	# Measured before the fix: 2322 ticks inside 1 m over 45 s and not one shot.
	var ai4 := OpponentAIScript.new(_rng())
	me.place(Vector3(0, 0.25, 0.3), Vector3(0, 0, -1))
	_check(ai4.think(me, foe, _ctx(1))["fire"],
		"it fires when locked nose to nose at 0.3 m, which is where fights actually happen")

	# Gas is not dumped into one clinch: after a shot it gives ground before coming back.
	var ai5 := OpponentAIScript.new(_rng())
	me.place(Vector3(0, 0.25, 0.5), Vector3(0, 0, -1))
	_check(ai5.think(me, foe, _ctx(1))["fire"], "the backoff fixture fires on the first tick")
	var retreating := 0
	for tick in range(2, 20):
		if ai5.think(me, foe, _ctx(tick))["heading"].dot(Vector2(0, 1)) > 0.5:
			retreating += 1
	_check(retreating >= 10,
		"after firing it backs off rather than grinding on (%d of 18 ticks)" % retreating)


# ---------------------------------------------------------------- charge debug mode

func _test_charge(me: FakeBot, foe: FakeBot) -> void:
	var ai := OpponentAIScript.new(_rng(), OpponentAIScript.MODE_CHARGE)
	foe.place(Vector3(-3.2, 0.25, -3.2), Vector3(1, 0, 1))
	me.place(Vector3(3.2, 0.25, 3.2), Vector3(1, 0, 0))
	var straight := Vector2(-1, -1).normalized()
	var heading: Vector2 = ai.think(me, foe, _ctx(1))["heading"]
	_check(heading.distance_to(straight) < 0.001,
		"charge drives straight at the player with no jitter and no flanking")
	var never_secondary := true
	for tick in 300:
		if ai.think(me, foe, _ctx(tick))["secondary"]:
			never_secondary = false
	_check(never_secondary, "charge never presses the srimech")


# ---------------------------------------------------------------- recover

func _test_recover(me: FakeBot, foe: FakeBot) -> void:
	var ai := OpponentAIScript.new(_rng())
	me.place(Vector3(1.0, 0.25, 1.0), Vector3(0, 0, -1))
	foe.place(Vector3(-1.0, 0.25, -1.0), Vector3(0, 0, 1))
	me.set_inverted(true)
	var presses := 0
	var reversed_ticks := 0
	for tick in 400:
		var inp := ai.think(me, foe, _ctx(tick))
		if inp["secondary"]:
			presses += 1
		elif inp["heading"] != Vector2.ZERO:
			reversed_ticks += 1
	_check(presses > 0, "an inverted bot presses the srimech (%d presses in 400 ticks)" % presses)
	_check(presses < 20, "it does not mash the srimech every tick (%d presses)" % presses)
	_check(reversed_ticks > 0, "after failed flips it drives in reverse to rock off a wall")

	me.set_inverted(false)
	var recovered := ai.think(me, foe, _ctx(401))
	_check(not recovered["secondary"], "an upright bot stops pressing the srimech")


# ---------------------------------------------------------------- spike avoidance

func _test_spike_avoidance(me: FakeBot, foe: FakeBot) -> void:
	var ai := OpponentAIScript.new(_rng())
	me.set_inverted(false)
	# Opponent facing away, so the approach angle is good and the AI darts straight in.
	me.place(Vector3(0.6, 0.25, 0.0), Vector3(-1, 0, 0))
	foe.place(Vector3(-0.6, 0.25, 0.0), Vector3(-1, 0, 0))
	var calm: Dictionary = ai.think(me, foe, _ctx(1))
	_check(calm["heading"].x < 0.0, "with the spikes down it still drives at the opponent")

	var ctx := _ctx(2)
	ctx["spike_rise_in_s"] = 0.4
	var dodge: Dictionary = ai.think(me, foe, ctx)
	_check(dodge["heading"].x > 0.5,
		"with the spikes about to rise it steers away from the patch (heading %s)"
			% str(dodge["heading"]))
	_check(not dodge["fire"], "it does not fire while dodging the spikes")


# ---------------------------------------------------------------- determinism

func _test_determinism(me: FakeBot, foe: FakeBot) -> void:
	var first := _sequence(me, foe)
	var second := _sequence(me, foe)
	_check(first.size() == 600, "the determinism run produced 600 input records")
	_check(first == second, "the same seed produces an identical 600 tick input sequence")

	var different := _sequence(me, foe, SEED + 1)
	_check(first != different, "a different seed produces a different sequence")


## 600 ticks of AI input as plain comparable rows, from a bot that moves as it drives so
## the run exercises the flanking and the jitter rather than one frozen pose.
func _sequence(me: FakeBot, foe: FakeBot, seed_value: int = SEED) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var ai := OpponentAIScript.new(rng)
	me.set_inverted(false)
	me.place(Vector3(3.2, 0.25, 3.2), Vector3(-1, 0, -1))
	foe.place(Vector3(-3.2, 0.25, -3.2), Vector3(1, 0, 1))
	var position := Vector3(3.2, 0.25, 3.2)
	var rows: Array = []
	for tick in 600:
		var inp := ai.think(me, foe, _ctx(tick))
		rows.append(FightTypes.replay_row(tick, inp))
		# A cheap stand in for the drive: step along the heading and face it.
		var heading: Vector2 = inp["heading"]
		var world := Vector3(heading.x, 0.0, heading.y)
		if world.length() > 0.0001:
			position += world.normalized() * 0.02
			me.place(position, world)
		# Circle the opponent so the flank choice keeps changing.
		var angle := float(tick) * 0.01
		foe.place(Vector3(cos(angle) * 2.0, 0.25, sin(angle) * 2.0), Vector3(-sin(angle), 0, cos(angle)))
	return rows


# ---------------------------------------------------------------- AI against AI

## `debug.player_ai` puts a second OpponentAI on the PLAYER bot: QA now, and the shape the
## async ladder needs later (a ghost build driven by AI against the player).
##
## Both drivers share ONE rng, and fight.gd calls them in a fixed order every tick, player
## first. That order is part of the seed, so an AI against AI fight must replay exactly.
func _test_ai_versus_ai(me: FakeBot, foe: FakeBot) -> void:
	var first := _duel(me, foe)
	var second := _duel(me, foe)
	_check(first["player"].size() == 600 and first["opponent"].size() == 600,
		"the duel produced 600 input records for each bot")
	_check(first["player"] == second["player"],
		"the same seed drives the PLAYER bot identically over 600 ticks")
	_check(first["opponent"] == second["opponent"],
		"the same seed drives the OPPONENT bot identically over 600 ticks")
	_check(first["player"] != first["opponent"],
		"the two drivers are not simply producing the same input (they face each other)")

	var other := _duel(me, foe, SEED + 7)
	_check(first["player"] != other["player"], "a different seed drives the duel differently")

	# The draw order is what makes it reproducible: swapping it must change the result,
	# which is why fight.gd fixes it rather than leaving it to call order elsewhere.
	var swapped := _duel(me, foe, SEED, true)
	_check(swapped["player"] != first["player"],
		"drawing the opponent's jitter before the player's changes the fight, so the order matters")


## 600 ticks of both bots driven by AI from one shared rng, as fight.gd does it.
func _duel(me: FakeBot, foe: FakeBot, seed_value: int = SEED, opponent_first: bool = false) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var player_ai := OpponentAIScript.new(rng, OpponentAIScript.MODE_NORMAL)
	var opponent_ai := OpponentAIScript.new(rng, OpponentAIScript.MODE_NORMAL)
	me.set_inverted(false)
	foe.set_inverted(false)
	var player_pos := Vector3(-3.2, 0.25, -3.2)
	var opponent_pos := Vector3(3.2, 0.25, 3.2)
	me.place(player_pos, (opponent_pos - player_pos).normalized())
	foe.place(opponent_pos, (player_pos - opponent_pos).normalized())

	var out := {"player": [], "opponent": []}
	for tick in 600:
		var ctx := _ctx(tick)
		var player_input: Dictionary
		var opponent_input: Dictionary
		if opponent_first:
			opponent_input = opponent_ai.think(foe, me, ctx)
			player_input = player_ai.think(me, foe, ctx)
		else:
			player_input = player_ai.think(me, foe, ctx)
			opponent_input = opponent_ai.think(foe, me, ctx)
		(out["player"] as Array).append(FightTypes.replay_row(tick, player_input))
		(out["opponent"] as Array).append(FightTypes.replay_row(tick, opponent_input))
		player_pos = _step(me, player_pos, player_input)
		opponent_pos = _step(foe, opponent_pos, opponent_input)
	return out


func _step(bot: FakeBot, position: Vector3, input_record: Dictionary) -> Vector3:
	var heading: Vector2 = input_record["heading"]
	var world := Vector3(heading.x, 0.0, heading.y)
	if world.length() < 0.0001:
		return position
	var moved := position + world.normalized() * 0.03
	bot.place(moved, world)
	return moved


func _test_heading_mapping() -> void:
	_check(OpponentAIScript.heading_from_world_dir(Vector3(0, 0, -2)) == Vector2(0, -1),
		"a world direction maps to the stick heading as (x, z)")
	_check(OpponentAIScript.heading_from_world_dir(Vector3.ZERO) == Vector2.ZERO,
		"a zero direction is a zero heading")
	_check(is_equal_approx(OpponentAIScript.heading_from_world_dir(Vector3(3, 9, 4)).length(), 1.0),
		"the heading is normalised and ignores height")


# ---------------------------------------------------------------- harness

func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	return rng


func _ctx(tick: int) -> Dictionary:
	return {"tick": tick, "spike_centre": Vector3.ZERO, "spike_rise_in_s": 5.0}


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS  ", label)
	else:
		_failures += 1
		printerr("FAIL  ", label)
		print("FAIL  ", label)


func _finish() -> void:
	print("")
	if _failures == 0:
		print("PASS  ai: %d checks, 0 failures" % _checks)
		quit(0)
	else:
		print("FAIL  ai: %d checks, %d failures" % [_checks, _failures])
		quit(1)
