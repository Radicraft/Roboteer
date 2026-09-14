extends SceneTree
## Headless unit test for the opponent AI (docs/stage3-spec.md §9).
##   Godot --headless --path Arena --script tests/ai_test.gd
##
## The bots are small fakes rather than the real Bot scene, so this passes before P's
## work lands and stays fast: the AI only ever reads `chassis` and `is_inverted()`.

const OpponentAIScript := preload("res://ai/opponent_ai.gd")
const BossAIScript := preload("res://ai/boss_ai.gd")
const BuildRulesScript := preload("res://bot/build_rules.gd")

const SEED := 987654321


class FakeBot extends Node3D:
	var chassis: RigidBody3D = null
	## Stage 4: the AI reads the weapon through these. A bot with none of them is the
	## Stage 3 flipper, which is what the defaults have to be.
	var weapon_kind_value := ""
	var weapon_reach_value := 0.0
	var weapon_readiness_value := 1.0

	var _inverted := false

	func weapon_kind() -> String:
		return weapon_kind_value

	func weapon_reach() -> float:
		return weapon_reach_value

	func weapon_readiness() -> float:
		return weapon_readiness_value

	func _init() -> void:
		chassis = RigidBody3D.new()
		chassis.freeze = true
		chassis.gravity_scale = 0.0
		add_child(chassis)

	## The same yaw Bot.place_at uses, so the fake's nose is +X like the real one's.
	func place(origin: Vector3, facing: Vector3) -> void:
		var flat := Vector3(facing.x, 0.0, facing.z)
		if flat.length() < 0.0001:
			flat = Vector3.RIGHT
		flat = flat.normalized()
		chassis.global_transform = Transform3D(
			Basis(Vector3.UP, atan2(-flat.z, flat.x)), origin)

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
	_test_weapon_profiles(me, foe)
	_test_bosses(me, foe)
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


# ---------------------------------------------------------------- weapon profiles

## docs/stage4-spec.md §6: the AI fights differently per weapon kind, and it reads the
## kind, the reach and the readiness off the Bot rather than being told.
func _test_weapon_profiles(me: FakeBot, foe: FakeBot) -> void:
	for kind in ["flipper", "lifter", "drum", "spinner", "fbs", "saw", "crusher", "axe", "ram", "flame"]:
		_check(OpponentAIScript.PROFILES.has(kind), "there is a profile for %s" % kind)
	me.weapon_kind_value = ""
	me.weapon_reach_value = 0.0
	me.weapon_readiness_value = 1.0

	# A spinner will not commit until it is spun up, and gives ground when it spins down.
	me.weapon_kind_value = "spinner"
	me.weapon_reach_value = 0.55
	foe.place(Vector3(0, 0.25, 0), Vector3(0, 0, 1))
	me.place(Vector3(0, 0.25, 1.6), Vector3(0, 0, -1))
	var cold := OpponentAIScript.new(_rng())
	me.weapon_readiness_value = 0.1
	var pressed_cold := 0
	for tick in 60:
		if cold.think(me, foe, _ctx(tick))["fire"]:
			pressed_cold += 1
	# A bar only gains readiness while it is held, so holding it is what spins it up.
	# Gating the press on readiness is a deadlock: it would never spin at all.
	_check(pressed_cold == 60,
		"a spun down bar holds the button on, which is how it spins up (%d of 60)" % pressed_cold)
	me.weapon_readiness_value = 0.1
	me.place(Vector3(0, 0.25, 1.0), Vector3(0, 0, -1))
	var away: Vector2 = cold.think(me, foe, _ctx(61))["heading"]
	_check(away.dot(Vector2(0, 1)) > 0.5,
		"but it backs off to re-spin rather than driving in with a cold bar (%s)" % str(away))

	# Spun up and on a flank, it commits.
	me.weapon_readiness_value = 1.0
	me.place(Vector3(1.4, 0.25, 0), Vector3(-1, 0, 0))
	var hot := OpponentAIScript.new(_rng())
	var closed_hot := false
	for tick in 40:
		if hot.think(me, foe, _ctx(tick))["heading"].dot(Vector2(-1, 0)) > 0.7:
			closed_hot = true
	_check(closed_hot, "a spun up bar on a flank commits to the attack")

	# A saw latches: once it is on, it stays on and holds the button down.
	me.weapon_kind_value = "saw"
	me.weapon_reach_value = 0.2
	me.place(Vector3(0, 0.25, 0.6), Vector3(0, 0, -1))
	var saw := OpponentAIScript.new(_rng())
	var held := 0
	var toward := 0
	for tick in 60:
		var out := saw.think(me, foe, _ctx(tick))
		if out["fire"]:
			held += 1
		if out["heading"].dot(Vector2(0, -1)) > 0.5:
			toward += 1
	_check(held >= 55, "a saw holds the button on rather than tapping it (%d of 60)" % held)
	_check(toward >= 55, "a saw latches on instead of giving ground (%d of 60)" % toward)

	# A ram has nothing to fire and charges straight in from the ring.
	me.weapon_kind_value = "ram"
	me.weapon_reach_value = 0.0
	me.place(Vector3(0, 0.25, 2.0), Vector3(0, 0, -1))
	var ram := OpponentAIScript.new(_rng())
	var ram_fired := false
	var ram_straight := 0
	for tick in 60:
		var out := ram.think(me, foe, _ctx(tick))
		if out["fire"]:
			ram_fired = true
		if out["heading"].dot(Vector2(0, -1)) > 0.7:
			ram_straight += 1
	_check(not ram_fired, "a ram never fires: it has nothing to fire")
	_check(ram_straight >= 50, "a ram charges straight in (%d of 60)" % ram_straight)

	# A flame keeps its distance and sweeps rather than closing.
	me.weapon_kind_value = "flame"
	me.weapon_reach_value = 2.0
	me.place(Vector3(0, 0.25, 1.7), Vector3(0, 0, -1))
	var flame := OpponentAIScript.new(_rng())
	var flame_closed := 0
	for tick in 60:
		if flame.think(me, foe, _ctx(tick))["heading"].dot(Vector2(0, -1)) > 0.7:
			flame_closed += 1
	_check(flame_closed <= 15,
		"a flame holds its reach and sweeps instead of closing (%d of 60 closing)" % flame_closed)

	_test_re_engages(me, foe)

	# Back to the Stage 3 default for the rest of the suite.
	me.weapon_kind_value = ""
	me.weapon_reach_value = 0.0
	me.weapon_readiness_value = 1.0


## The flank gate is a preference, not a requirement. Against an opponent that keeps its
## nose on you the good angle may never come, and a bot that waits forever for a perfect
## entry never fights: measured at 202 ticks of 2900 spent inside 1 m. It has to give up
## looking and go in. Two seconds is the bar.
func _test_re_engages(me: FakeBot, foe: FakeBot) -> void:
	me.weapon_kind_value = "flipper"
	me.weapon_reach_value = 0.45
	me.weapon_readiness_value = 1.0
	var ai := OpponentAIScript.new(_rng())

	# Squared up on the ring, opponent nose on, so the flank angle is never good.
	var first_commit := -1
	var ticks := int(OpponentAIScript.COMMIT_AFTER_TICKS) + 60
	for tick in ticks:
		foe.place(Vector3(0, 0.25, 0), Vector3(0, 0, 1))
		me.place(Vector3(0, 0.25, 1.2), Vector3(0, 0, -1))
		var heading: Vector2 = ai.think(me, foe, _ctx(tick))["heading"]
		if heading.dot(Vector2(0, -1)) > 0.8 and first_commit < 0:
			first_commit = tick
	_check(first_commit >= 0,
		"a flipper bot held at a bad angle eventually drives in anyway")
	_check(first_commit >= 0 and first_commit <= int(OpponentAIScript.COMMIT_AFTER_TICKS) + 30,
		"and it does so within about two seconds of circling (tick %d of %d)"
			% [first_commit, int(OpponentAIScript.COMMIT_AFTER_TICKS)])

	# It still prefers the flank when one is going: given a good angle straight away it
	# commits at once rather than waiting out the patience timer.
	var quick := OpponentAIScript.new(_rng())
	foe.place(Vector3(0, 0.25, 0), Vector3(0, 0, -1))       # facing away
	me.place(Vector3(0, 0.25, 1.2), Vector3(0, 0, -1))
	var early: Vector2 = quick.think(me, foe, _ctx(1))["heading"]
	_check(early.dot(Vector2(0, -1)) > 0.8,
		"with a flank already open it commits on the first tick, not after two seconds")

	# The flipper ring is inside the range at which a fight actually happens.
	var standoff := float((OpponentAIScript.PROFILES["flipper"] as Dictionary)["standoff"])
	_check(standoff <= 1.2,
		"the flipper holds a close ring, so backing off does not become standing off (%.2f m)"
			% standoff)


# ---------------------------------------------------------------- the bosses

## brief §8 and docs/stage5-spec.md §4. Five enforcers, each a personality laid over the
## ordinary weapon driver, each recognisable from the stands by one rule.
func _test_bosses(me: FakeBot, foe: FakeBot) -> void:
	for id in BossAIScript.BOSSES:
		var build := BossAIScript.build_for(id, "boss-1")
		_check(str(build.get("id", "")) == "boss-1", "%s builds with the id it was asked for" % id)
		_check(str(build.get("chassis", "")) != "" and str(build.get("weapon", "")) != "",
			"%s has a chassis and a weapon" % id)
		var weight := float(BuildRulesScript.total_weight(build))
		var errors: Array = BuildRulesScript.validate(build)
		_check(errors.is_empty(),
			"%s is a legal build at %.1f kg (%s)" % [id, weight, ", ".join(errors)])
	_check(str(BossAIScript.build_for("nonsense", "boss-1").get("name", "")) != "",
		"an unknown boss id falls back to a real build rather than an empty one")

	# THRESHER does not chase. Past its leash it goes home to its gate.
	var thresher := BossAIScript.new(_rng(), BossAIScript.BOSS_THRESHER)
	thresher.gate = Vector3(4.3, 0.25, 0.0)
	me.weapon_kind_value = "crusher"
	me.place(Vector3(0, 0.25, 0), Vector3(1, 0, 0))
	foe.place(Vector3(0, 0.25, -5.0), Vector3(0, 0, 1))     # 5 m away, past the leash
	var home: Vector2 = thresher.think(me, foe, _ctx(1))["heading"]
	_check(home.x > 0.3, "THRESHER walks back to its gate instead of chasing (%s)" % str(home))
	foe.place(Vector3(1.0, 0.25, 0), Vector3(-1, 0, 0))     # inside the leash
	var close: Dictionary = thresher.think(me, foe, _ctx(2))
	_check(close["heading"].length() <= BossAIScript.THRESHER_THROTTLE + 0.01,
		"and it is slow even when it does move (%.2f)" % close["heading"].length())

	# GRUDGE withdraws rather than being caught dry at contact range.
	var grudge := BossAIScript.new(_rng(), BossAIScript.BOSS_GRUDGE)
	me.weapon_kind_value = "flame"
	me.weapon_reach_value = 2.0
	me.place(Vector3(0, 0.25, 1.5), Vector3(0, 0, -1))
	foe.place(Vector3(0, 0.25, 0), Vector3(0, 0, 1))
	me.weapon_readiness_value = 0.1                          # fuel nearly gone
	var dry: Dictionary = grudge.think(me, foe, _ctx(1))
	_check(not dry["fire"], "GRUDGE stops burning when the fuel is nearly gone")
	_check(dry["heading"].dot(Vector2(0, 1)) > 0.5, "and backs away rather than closing")
	me.weapon_readiness_value = 1.0
	_check(grudge.think(me, foe, _ctx(2))["fire"], "with fuel it burns")

	# BANDSAW herds toward a wall, then pins and cuts.
	var bandsaw := BossAIScript.new(_rng(), BossAIScript.BOSS_BANDSAW)
	me.weapon_kind_value = "saw"
	me.weapon_reach_value = 0.2
	me.weapon_readiness_value = 1.0
	foe.place(Vector3(0, 0.25, 0), Vector3(0, 0, 1))         # dead centre, walls far off
	me.place(Vector3(0, 0.25, 1.2), Vector3(0, 0, -1))
	var herd: Vector2 = bandsaw.think(me, foe, _ctx(1))["heading"]
	_check(herd.dot(Vector2(0, -1)) > 0.5,
		"BANDSAW drives past the target toward the wall, shoving it along (%s)" % str(herd))
	foe.place(Vector3(0, 0.25, -4.6), Vector3(0, 0, 1))      # already on the wall
	me.place(Vector3(0, 0.25, -3.4), Vector3(0, 0, -1))
	var pin: Dictionary = bandsaw.think(me, foe, _ctx(2))
	_check(pin["fire"] and pin["heading"].dot(Vector2(0, -1)) > 0.7,
		"and once they are on the wall it holds them there cutting")

	# ANVIL never shows its back.
	var anvil := BossAIScript.new(_rng(), BossAIScript.BOSS_ANVIL)
	me.weapon_kind_value = "axe"
	me.weapon_reach_value = 0.5
	me.place(Vector3(0, 0.25, 0), Vector3(1, 0, 0))          # nose +X
	foe.place(Vector3(-2.0, 0.25, 0), Vector3(1, 0, 0))      # directly behind it
	var turn: Dictionary = anvil.think(me, foe, _ctx(1))
	_check(turn["heading"].dot(Vector2(-1, 0)) > 0.7,
		"ANVIL turns to face an opponent that got behind it (%s)" % str(turn["heading"]))
	_check(not turn["fire"], "and does not swing at its own back")
	foe.place(Vector3(3.0, 0.25, 0), Vector3(-1, 0, 0))      # in front, but far
	var wait: Vector2 = anvil.think(me, foe, _ctx(2))["heading"]
	_check(wait.length() < 0.5, "and waits rather than chasing (%.2f)" % wait.length())

	# CINDER lines up so a throw sends them at the hazard.
	var cinder := BossAIScript.new(_rng(), BossAIScript.BOSS_CINDER)
	me.weapon_kind_value = "flipper"
	me.weapon_reach_value = 0.45
	foe.place(Vector3(2.0, 0.25, 0), Vector3(-1, 0, 0))
	me.place(Vector3(2.0, 0.25, 1.5), Vector3(0, 0, -1))
	var ctx := _ctx(1)
	ctx["hazards"] = [Vector3(0, 0, 0)]                       # the pit is at the origin
	var line_up: Vector2 = cinder.think(me, foe, ctx)["heading"]
	_check(line_up.x > 0.3,
		"CINDER works round to the far side of the target from the hazard (%s)" % str(line_up))
	_check(BossAIScript.nearest_hazard(Vector3(3, 0, 3), {"hazards": [Vector3(4, 0, 4), Vector3(-4, 0, -4)]})
			== Vector3(4, 0, 4), "and it picks the nearest hazard when there are several")

	# The wall helper the herding depends on.
	var half := FightTypes.ARENA_SIZE * 0.5
	_check(is_equal_approx(BossAIScript.nearest_wall_point(Vector3(0, 0, -4.0)).z, -half),
		"the nearest wall to a bot near the north wall is the north wall")
	_check(is_equal_approx(BossAIScript.nearest_wall_point(Vector3(4.0, 0, 0)).x, half),
		"and to a bot near the east wall, the east wall")

	me.weapon_kind_value = ""
	me.weapon_reach_value = 0.0
	me.weapon_readiness_value = 1.0


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
