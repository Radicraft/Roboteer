extends SceneTree
## Headless unit test for the opponent AI (docs/stage3-spec.md §9).
##   Godot --headless --path Arena --script tests/ai_test.gd
##
## The bots are small fakes rather than the real Bot scene, so this passes before P's
## work lands and stays fast: the AI only ever reads `chassis` and `is_inverted()`.

const OpponentAIScript := preload("res://ai/opponent_ai.gd")
const BossAIScript := preload("res://ai/boss_ai.gd")
const NoviceScript := preload("res://ai/novice_driver.gd")
const BuildRulesScript := preload("res://bot/build_rules.gd")

const SEED := 987654321

# --- the acceptance sweep (brief v4 §4) ----------------------------------------------
const SWEEP_FIGHTS := 100
## A full three minute round (brief v4 §2), because that is the fight the tiers are
## judged over and a fifteen second one is a coin toss: the better driver's edge is a hit
## or two a minute, and over fifteen seconds that is inside the noise. Fights end early on
## a knockout, so most of these are over in about a minute of arena time.
const SWEEP_TICKS := 10800
const SIM_REACH_M := 0.95           # chassis centre to chassis centre: contact
## The weapon's EFFECTIVE bite, narrower than the 45 degrees OpponentAI is willing to
## fire inside: a driver with a 25 degree aim error presses the button believing it is on
## target and hits nothing, which is what an aim error costs.
const SIM_CONE_DEG := 30.0
const SIM_HIT := 0.075              # condition removed by one clean square hit
## Even a glancing hit inside the bite does most of the damage; where it lands matters
## far more than how square it was, which is why working for a flank is worth it.
const SIM_STRAIGHT_FLOOR := 0.6
const SIM_FACE_WEIGHT := 0.8        # 0.2 on their nose, 1.0 on their side, 1.8 on the back
const SIM_PUSH_M := 0.7             # chassis centres closer than this are in contact
const SIM_HAZARD_R := 0.9
const SIM_HAZARD_DPS := 0.25
## Every arena in the game has something live in it (brief v4 §2), so the acceptance
## fights have one too: hazard awareness is one of the six things a tier IS.
const SIM_ARENA_HAZARD := [Vector3.ZERO]


class FakeBot extends Node3D:
	var chassis: RigidBody3D = null
	## The judges' card is keyed by bot id (brief v4 §4's last twenty seconds).
	var bot_id := ""
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


## A machine in the toy arena the acceptance sweep fights in: a position, a nose, a
## finite turn rate and a condition that comes apart. It answers everything OpponentAI
## reads off a Bot (`chassis`, `weapon_kind`, `weapon_readiness`, `condition`,
## `is_inverted`, `bot_id`) and nothing else, because nothing else is read.
class SimBot extends Node3D:
	const SPEED := 3.0              # m/s, the same for both machines: this is about driving
	const TURN := 6.0               # rad/s
	const HALF := FightTypes.ARENA_SIZE * 0.5 - 0.5

	var chassis: RigidBody3D = null
	var bot_id := ""
	var weapon_kind_value := "flipper"
	var weapon_reach_value := 0.45
	var weapon_readiness_value := 1.0
	var health := 1.0
	var at := Vector3.ZERO
	var facing := Vector3.RIGHT

	func _init() -> void:
		chassis = RigidBody3D.new()
		chassis.freeze = true
		chassis.gravity_scale = 0.0
		add_child(chassis)

	func weapon_kind() -> String:
		return weapon_kind_value

	func weapon_reach() -> float:
		return weapon_reach_value

	func weapon_readiness() -> float:
		return weapon_readiness_value

	func is_inverted() -> bool:
		return false

	## The same shape FightRules.condition_total reads, scaled by what is left.
	func condition() -> Dictionary:
		var left := maxf(health, 0.0)
		return {
			"wheels": [left, left, left, left], "weapon": left, "drive": left, "core": left,
			"armour": {"front": left, "sides": left, "rear": left, "top": left},
		}

	func reset(origin: Vector3) -> void:
		health = 1.0
		at = origin
		facing = Vector3.RIGHT
		_write()

	func face(target: Vector3) -> void:
		var to := Vector3(target.x - at.x, 0.0, target.z - at.z)
		if to.length() > 0.0001:
			facing = to.normalized()
		_write()

	## One tick of an arcade drive: turn toward the heading at a finite rate, then move
	## along the nose by however much of the throttle survives the turn.
	func step(heading: Vector2, dt: float) -> void:
		if heading.length() < 0.0001:
			return
		var want := heading.normalized()
		var nose := Vector2(facing.x, facing.z).normalized()
		var turn := clampf(nose.angle_to(want), -TURN * dt, TURN * dt)
		nose = nose.rotated(turn)
		var throttle := clampf(nose.dot(want), 0.0, 1.0) * clampf(heading.length(), 0.0, 1.0)
		var moved := Vector2(at.x, at.z) + nose * (SPEED * throttle * dt)
		at = Vector3(clampf(moved.x, -HALF, HALF), 0.25, clampf(moved.y, -HALF, HALF))
		facing = Vector3(nose.x, 0.0, nose.y)
		_write()

	## Shoved by the other machine: moved without turning.
	func shove(by: Vector2) -> void:
		at = Vector3(clampf(at.x + by.x, -HALF, HALF), 0.25, clampf(at.z + by.y, -HALF, HALF))
		_write()

	func _write() -> void:
		chassis.global_transform = Transform3D(
			Basis(Vector3.UP, atan2(-facing.z, facing.x)), at)


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

	# brief v4 §4: the tiers, the temperaments and the behaviours they gate.
	_test_skill_table()
	_test_reaction_and_aim(me, foe)
	_test_srimech_speed(me, foe)
	_test_wall_pin(me, foe)
	_test_hazard_shove(me, foe)
	_test_weapon_counters(me, foe)
	_test_zone_and_house_bot(me, foe)
	_test_showboat_switch(me, foe)
	_test_skill_determinism(me, foe)
	await _test_sweep()

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


# ================================================================ brief v4 §4
#
# Skill tiers x temperaments. Everything below this line is the playtest brief's AI: the
# five tiers in section 4's table, the five personalities, the behaviours they gate, and
# the headless sweep that says whether the ladder is actually a ladder.


# ---------------------------------------------------------------- the tier table

func _test_skill_table() -> void:
	_check(OpponentAIScript.SKILL_IDS.size() == 5, "there are five skill tiers")
	for id in OpponentAIScript.SKILL_IDS:
		_check(OpponentAIScript.SKILLS.has(id), "the tier table has a row for %s" % id)
	_check(OpponentAIScript.TEMPERAMENT_IDS.size() == 5, "there are five temperaments")
	for id in OpponentAIScript.TEMPERAMENT_IDS:
		_check(OpponentAIScript.TEMPERAMENTS.has(id), "the temperament table has %s" % id)

	# The table is a ladder: every rung is quicker and straighter than the one below it.
	var last_reaction := 99.0
	var last_aim := 99.0
	for id in OpponentAIScript.SKILL_IDS:
		var row: Dictionary = OpponentAIScript.SKILLS[id]
		_check(float(row["reaction_s"]) < last_reaction,
			"%s reacts faster than the tier below it (%.2f s)" % [id, float(row["reaction_s"])])
		_check(float(row["aim_deg"]) < last_aim,
			"%s aims straighter than the tier below it (%.0f deg)" % [id, float(row["aim_deg"])])
		last_reaction = float(row["reaction_s"])
		last_aim = float(row["aim_deg"])

	# The exact numbers the brief's table names, so an edit to one is a decision.
	_check(is_equal_approx(float((OpponentAIScript.SKILLS["scrapyard"] as Dictionary)["reaction_s"]), 0.6)
		and is_equal_approx(float((OpponentAIScript.SKILLS["masters"] as Dictionary)["reaction_s"]), 0.12),
		"Scrapyard reacts in 0.6 s and Masters in 0.12 s, as the brief's table says")
	_check(not bool((OpponentAIScript.SKILLS["regional"] as Dictionary)["pin"])
		and bool((OpponentAIScript.SKILLS["national"] as Dictionary)["pin"]),
		"the wall pin arrives at National, not before")
	_check(not bool((OpponentAIScript.SKILLS["national"] as Dictionary)["shove"])
		and bool((OpponentAIScript.SKILLS["championship"] as Dictionary)["shove"]),
		"the hazard shove arrives at Championship")
	_check(bool((OpponentAIScript.SKILLS["masters"] as Dictionary)["bait"])
		and not bool((OpponentAIScript.SKILLS["championship"] as Dictionary)["bait"]),
		"only Masters baits")

	# An id nobody recognises is a Regional brawler rather than a crash.
	var fallback := OpponentAIScript.new(_rng(), OpponentAIScript.MODE_NORMAL, "nonsense", "silly")
	_check(fallback.skill == OpponentAIScript.SKILL_REGIONAL
		and fallback.temperament == OpponentAIScript.TEMPERAMENT_BRAWLER,
		"an unknown tier or temperament falls back to a Regional brawler")
	# A filler (no temperament of its own) draws one from the shared rng, at construction.
	var drawn := OpponentAIScript.new(_rng(), OpponentAIScript.MODE_NORMAL,
		OpponentAIScript.SKILL_REGIONAL, "")
	var drawn_again := OpponentAIScript.new(_rng(), OpponentAIScript.MODE_NORMAL,
		OpponentAIScript.SKILL_REGIONAL, "")
	_check(drawn.temperament in OpponentAIScript.TEMPERAMENT_IDS,
		"a filler draws a real temperament (%s)" % drawn.temperament)
	_check(drawn.temperament == drawn_again.temperament,
		"and the same seed draws the same one, so the fight replays")


# ---------------------------------------------------------------- reaction and aim

## The two numbers that separate the tiers. A reaction delay is "it aims where they were",
## so a Scrapyard driver chasing a moving target points further behind it than a Masters
## driver does; an aim error is "it steers wide of what it meant".
func _test_reaction_and_aim(me: FakeBot, foe: FakeBot) -> void:
	var lag := {}
	for id in OpponentAIScript.SKILL_IDS:
		var ai := OpponentAIScript.new(_rng(), OpponentAIScript.MODE_NORMAL, id,
			OpponentAIScript.TEMPERAMENT_BRAWLER)
		me.set_inverted(false)
		me.place(Vector3(0, 0.25, 3.0), Vector3(0, 0, -1))
		# The opponent runs across our nose at 3 m/s, which is what a human does.
		var at := Vector3(-2.0, 0.25, 0.0)
		var error := 0.0
		var samples := 0
		for tick in 240:
			foe.place(at, Vector3(1, 0, 0))
			ai.think(me, foe, _ctx(tick))
			at.x += 3.0 / 60.0
			if tick >= 60:
				# How far behind the truth this driver's picture of them is.
				error += (at - ai.get("_believed")).length()
				samples += 1
		lag[id] = error / maxf(float(samples), 1.0)
	_check(float(lag["scrapyard"]) > float(lag["masters"]) * 3.0,
		"a Scrapyard driver's picture of a running opponent lags %.2f m against Masters' %.2f m"
			% [float(lag["scrapyard"]), float(lag["masters"])])
	var ordered := true
	var previous := 99.0
	for id in OpponentAIScript.SKILL_IDS:
		if float(lag[id]) >= previous:
			ordered = false
		previous = float(lag[id])
	_check(ordered, "and every tier up the ladder lags less than the one below it")

	# Aim error, measured where the wanted direction is not a matter of opinion: standing
	# on the spike patch as it rises, every tier wants exactly "away", so whatever else
	# comes out is the jitter and the tier's aim error and nothing else.
	var wide := {}
	for id in OpponentAIScript.SKILL_IDS:
		var ai := OpponentAIScript.new(_rng(), OpponentAIScript.MODE_NORMAL, id,
			OpponentAIScript.TEMPERAMENT_BRAWLER)
		var worst := 0.0
		for tick in 900:
			foe.place(Vector3(-2.5, 0.25, 0), Vector3(1, 0, 0))
			me.place(Vector3(0.6, 0.25, 0.0), Vector3(-1, 0, 0))
			var ctx := _ctx(tick)
			ctx["spike_rise_in_s"] = 0.4         # away is exactly +X
			var heading: Vector2 = ai.think(me, foe, ctx)["heading"]
			if heading.length() < 0.0001:
				continue
			worst = maxf(worst, absf(rad_to_deg(heading.normalized().angle_to(Vector2(1, 0)))))
		wide[id] = worst
	_check(float(wide["scrapyard"]) > float(wide["masters"]) + 10.0,
		"a Scrapyard driver steers up to %.0f deg wide of what it meant, Masters %.0f deg"
			% [float(wide["scrapyard"]), float(wide["masters"])])
	var aim_ordered := true
	var widest := 0.0
	for id in [OpponentAIScript.SKILL_MASTERS, OpponentAIScript.SKILL_CHAMPIONSHIP,
			OpponentAIScript.SKILL_NATIONAL, OpponentAIScript.SKILL_REGIONAL,
			OpponentAIScript.SKILL_SCRAPYARD]:
		if float(wide[id]) < widest:
			aim_ordered = false
		widest = float(wide[id])
	_check(aim_ordered, "and every tier down the ladder steers wider than the one above it")
	# The jitter adds at most atan(0.15), about 8.5 degrees, on top of the tier's error.
	_check(float(wide["masters"]) <= 5.0 + 9.0,
		"Masters is never wilder than its 5 deg plus the jitter (%.0f deg)"
			% float(wide["masters"]))


func _test_srimech_speed(me: FakeBot, foe: FakeBot) -> void:
	var presses := {}
	for id in [OpponentAIScript.SKILL_SCRAPYARD, OpponentAIScript.SKILL_MASTERS]:
		var ai := OpponentAIScript.new(_rng(), OpponentAIScript.MODE_NORMAL, id,
			OpponentAIScript.TEMPERAMENT_BRAWLER)
		me.place(Vector3(1.0, 0.25, 1.0), Vector3(0, 0, -1))
		foe.place(Vector3(-1.0, 0.25, -1.0), Vector3(0, 0, 1))
		me.set_inverted(true)
		var count := 0
		var drove := false
		for tick in 600:
			var inp := ai.think(me, foe, _ctx(tick))
			if inp["secondary"]:
				count += 1
			elif inp["heading"].length() > 0.0001 and tick < 40:
				# Before the first press has had time to fail there is nothing to do but
				# press: it drives nowhere. (After two failed ones it rocks in reverse to
				# get off whatever is holding it, which is a fix from Stage 3.)
				drove = true
		presses[id] = count
		_check(not drove, "%s: an inverted bot drives nowhere, it presses the srimech" % id)
	me.set_inverted(false)
	_check(int(presses["masters"]) > int(presses["scrapyard"]),
		"a Masters srimech comes back quicker than a Scrapyard one (%d presses against %d)"
			% [int(presses["masters"]), int(presses["scrapyard"])])


# ---------------------------------------------------------------- the wall pin

func _test_wall_pin(me: FakeBot, foe: FakeBot) -> void:
	var half := FightTypes.ARENA_SIZE * 0.5
	me.set_inverted(false)
	foe.set_inverted(false)
	# Them on the north wall, us nose on them a metre off it.
	var foe_at := Vector3(0, 0.25, -(half - 0.4))
	var my_at := Vector3(0, 0.25, -(half - 1.4))

	var regional := OpponentAIScript.new(_rng(), OpponentAIScript.MODE_NORMAL,
		OpponentAIScript.SKILL_REGIONAL, OpponentAIScript.TEMPERAMENT_BULLY)
	var national := OpponentAIScript.new(_rng(), OpponentAIScript.MODE_NORMAL,
		OpponentAIScript.SKILL_NATIONAL, OpponentAIScript.TEMPERAMENT_BULLY)
	for tick in 600:
		foe.place(foe_at, Vector3(0, 0, 1))
		me.place(my_at, Vector3(0, 0, -1))
		regional.think(me, foe, _ctx(tick))
		national.think(me, foe, _ctx(tick))
	_check(int(regional.get("pin_ticks")) == 0,
		"a Regional driver does not know what a wall is for (%d pin ticks)"
			% int(regional.get("pin_ticks")))
	_check(int(national.get("pin_ticks")) > 0,
		"a National driver pins them against it (%d ticks of 600)"
			% int(national.get("pin_ticks")))
	# The pin rule (FightRules.is_pinned) bites at four seconds, so no single hold may
	# run that long: it lets go at three and stays off them for a moment.
	_check(int(national.get("pin_ticks")) <= int(OpponentAIScript.PIN_HOLD_TICKS) * 3,
		"and it lets go and comes back rather than holding one four second pin (%d ticks)"
			% int(national.get("pin_ticks")))
	var longest := _longest_pin(OpponentAIScript.SKILL_NATIONAL, me, foe, foe_at, my_at)
	_check(longest <= int(OpponentAIScript.PIN_HOLD_TICKS),
		"the longest single pin is %d ticks, inside the three seconds the rule allows"
			% longest)

	# In open floor there is nothing to pin against and it fights normally.
	var open_floor := OpponentAIScript.new(_rng(), OpponentAIScript.MODE_NORMAL,
		OpponentAIScript.SKILL_MASTERS, OpponentAIScript.TEMPERAMENT_BULLY)
	for tick in 300:
		foe.place(Vector3(0, 0.25, 0), Vector3(0, 0, 1))
		me.place(Vector3(0, 0.25, 1.1), Vector3(0, 0, -1))
		open_floor.think(me, foe, _ctx(tick))
	_check(int(open_floor.get("pin_ticks")) == 0,
		"nothing is pinned in the middle of the floor (%d pin ticks)"
			% int(open_floor.get("pin_ticks")))


## The longest unbroken run of pinning ticks a driver holds.
func _longest_pin(skill: String, me: FakeBot, foe: FakeBot, foe_at: Vector3,
		my_at: Vector3) -> int:
	var ai := OpponentAIScript.new(_rng(), OpponentAIScript.MODE_NORMAL, skill,
		OpponentAIScript.TEMPERAMENT_BULLY)
	var longest := 0
	var run := 0
	var last := 0
	for tick in 900:
		foe.place(foe_at, Vector3(0, 0, 1))
		me.place(my_at, Vector3(0, 0, -1))
		ai.think(me, foe, _ctx(tick))
		var now := int(ai.get("pin_ticks"))
		if now > last:
			run += 1
			longest = maxi(longest, run)
		else:
			run = 0
		last = now
	return longest


# ---------------------------------------------------------------- the hazard shove

func _test_hazard_shove(me: FakeBot, foe: FakeBot) -> void:
	me.set_inverted(false)
	foe.set_inverted(false)
	# Us behind them, a live hazard 1.6 m beyond them on the same line.
	var my_at := Vector3(0, 0.25, 1.0)
	var foe_at := Vector3(0, 0.25, 0.0)
	var hazard := Vector3(0, 0.0, -1.6)

	var counts := {}
	for id in [OpponentAIScript.SKILL_NATIONAL, OpponentAIScript.SKILL_CHAMPIONSHIP]:
		var ai := OpponentAIScript.new(_rng(), OpponentAIScript.MODE_NORMAL, id,
			OpponentAIScript.TEMPERAMENT_BULLY)
		for tick in 240:
			foe.place(foe_at, Vector3(0, 0, -1))
			me.place(my_at, Vector3(0, 0, -1))
			var ctx := _ctx(tick)
			ctx["hazard"] = {"danger_positions": [hazard]}
			ctx["hazards"] = [hazard]
			ai.think(me, foe, ctx)
		counts[id] = int(ai.get("shove_ticks"))
	_check(int(counts["national"]) == 0,
		"a National driver does not shove (%d ticks)" % int(counts["national"]))
	_check(int(counts["championship"]) > 0,
		"a Championship driver behind them pushes them onto the hazard (%d of 240 ticks)"
			% int(counts["championship"]))

	# With the hazard behind US instead there is nothing to push them onto.
	var wrong_side := OpponentAIScript.new(_rng(), OpponentAIScript.MODE_NORMAL,
		OpponentAIScript.SKILL_CHAMPIONSHIP, OpponentAIScript.TEMPERAMENT_BULLY)
	for tick in 240:
		foe.place(foe_at, Vector3(0, 0, -1))
		me.place(my_at, Vector3(0, 0, -1))
		var ctx := _ctx(tick)
		ctx["hazard"] = {"danger_positions": [Vector3(0, 0, 2.6)]}
		wrong_side.think(me, foe, ctx)
	_check(int(wrong_side.get("shove_ticks")) == 0,
		"and it does not push them away from one (%d ticks)"
			% int(wrong_side.get("shove_ticks")))


# ---------------------------------------------------------------- counter-build reading

func _test_weapon_counters(me: FakeBot, foe: FakeBot) -> void:
	me.set_inverted(false)
	foe.set_inverted(false)
	me.weapon_kind_value = "flipper"
	me.weapon_reach_value = 0.45
	me.weapon_readiness_value = 1.0

	# Every pair below is the SAME tier against a machine that declares its weapon and one
	# that declares nothing, so the only thing that differs is the reading. (A build you
	# have not been shown cannot be read, which is also why the rest of this file, whose
	# fakes declare nothing, fights exactly as it did before the tiers landed.)
	var tier := OpponentAIScript.SKILL_NATIONAL

	# vs a spinner: never down the nose of the spin.
	foe.weapon_kind_value = "spinner"
	foe.weapon_reach_value = 0.55
	foe.weapon_readiness_value = 1.0
	var read_spinner := _straight_in_ticks(tier, me, foe)
	foe.weapon_kind_value = ""
	foe.weapon_reach_value = 0.0
	var unread := _straight_in_ticks(tier, me, foe)
	_check(read_spinner < unread,
		"against a spinner it works round instead of charging the nose (%d ticks straight in against %d unscouted)"
			% [read_spinner, unread])

	# vs a flipper: thirty degrees off the nose, never down it.
	foe.weapon_kind_value = "flipper"
	foe.weapon_reach_value = 0.45
	var off_nose := _approach_offset_deg(tier, me, foe)
	foe.weapon_kind_value = ""
	foe.weapon_reach_value = 0.0
	var down_the_nose := _approach_offset_deg(tier, me, foe)
	_check(off_nose >= 15.0 and off_nose <= 45.0,
		"against a flipper it comes in about thirty degrees off the nose (%.0f deg)" % off_nose)
	_check(off_nose > down_the_nose + 10.0,
		"where an unscouted build is driven straight at (%.0f deg)" % down_the_nose)

	# vs a crusher: never stop moving. A saw latches onto anything else and holds; against
	# a crusher it keeps working instead of parking in the jaws.
	me.weapon_kind_value = "saw"
	me.weapon_reach_value = 0.2
	foe.weapon_kind_value = "crusher"
	foe.weapon_reach_value = 0.4
	var against_crusher := _latched_ticks(tier, me, foe)
	foe.weapon_kind_value = "saw"
	foe.weapon_reach_value = 0.2
	var against_saw := _latched_ticks(tier, me, foe)
	_check(against_crusher < against_saw,
		"against a crusher the saw never stops moving, where against anything else it latches on (%d ticks parked against %d)"
			% [against_crusher, against_saw])

	me.weapon_kind_value = ""
	me.weapon_reach_value = 0.0
	foe.weapon_kind_value = ""
	foe.weapon_reach_value = 0.0
	foe.weapon_readiness_value = 1.0


## How many of 240 ticks this driver spends driving straight down the opponent's nose
## from the standoff ring, held square on.
func _straight_in_ticks(skill: String, me: FakeBot, foe: FakeBot) -> int:
	var ai := OpponentAIScript.new(_rng(), OpponentAIScript.MODE_NORMAL, skill,
		OpponentAIScript.TEMPERAMENT_BRAWLER)
	var straight := 0
	for tick in 240:
		foe.place(Vector3(0, 0.25, 0), Vector3(0, 0, 1))     # nose pointed at us
		me.place(Vector3(0, 0.25, 1.3), Vector3(0, 0, -1))
		if ai.think(me, foe, _ctx(tick))["heading"].normalized().dot(Vector2(0, -1)) > 0.9:
			straight += 1
	return straight


## The average angle off the line to the opponent this driver approaches at, from an open
## flank at the edge of its engage range.
func _approach_offset_deg(skill: String, me: FakeBot, foe: FakeBot) -> float:
	var ai := OpponentAIScript.new(_rng(), OpponentAIScript.MODE_NORMAL, skill,
		OpponentAIScript.TEMPERAMENT_BRAWLER)
	var total := 0.0
	var samples := 0
	for tick in 240:
		foe.place(Vector3(0, 0.25, 0), Vector3(0, 0, -1))    # facing away: the flank is open
		me.place(Vector3(0, 0.25, 1.3), Vector3(0, 0, -1))
		var heading: Vector2 = ai.think(me, foe, _ctx(tick))["heading"]
		if heading.length() < 0.0001:
			continue
		total += absf(rad_to_deg(heading.normalized().angle_to(Vector2(0, -1))))
		samples += 1
	return total / maxf(float(samples), 1.0)


## How many of 240 ticks a saw spends parked square on the opponent, holding the cut.
func _latched_ticks(skill: String, me: FakeBot, foe: FakeBot) -> int:
	var ai := OpponentAIScript.new(_rng(), OpponentAIScript.MODE_NORMAL, skill,
		OpponentAIScript.TEMPERAMENT_BRAWLER)
	var parked := 0
	for tick in 240:
		foe.place(Vector3(0, 0.25, 0), Vector3(0, 0, 1))
		me.place(Vector3(0, 0.25, 0.6), Vector3(0, 0, -1))
		if ai.think(me, foe, _ctx(tick))["heading"].normalized().dot(Vector2(0, -1)) > 0.95:
			parked += 1
	return parked


# ---------------------------------------------------------------- the zone and the house bot

func _test_zone_and_house_bot(me: FakeBot, foe: FakeBot) -> void:
	me.set_inverted(false)
	foe.set_inverted(false)
	# G2's corner zone, 2.2 m square in the +X -Z corner, with us standing in it and the
	# opponent deeper inside it: a driver that cannot see the zone follows them in.
	var zone := Rect2(2.6, -4.8, 2.2, 2.2)
	var inside := Vector3(3.2, 0.25, -3.2)
	var deeper := Vector3(4.3, 0.25, -4.3)

	var blind := OpponentAIScript.new(_rng(), OpponentAIScript.MODE_NORMAL,
		OpponentAIScript.SKILL_REGIONAL, OpponentAIScript.TEMPERAMENT_BRAWLER)
	var aware := OpponentAIScript.new(_rng(), OpponentAIScript.MODE_NORMAL,
		OpponentAIScript.SKILL_NATIONAL, OpponentAIScript.TEMPERAMENT_BRAWLER)
	var leaving := 0
	var blind_leaving := 0
	for tick in 120:
		foe.place(deeper, Vector3(-1, 0, 1))
		me.place(inside, Vector3(1, 0, -1))
		var ctx := _ctx(tick)
		ctx["zone_rect"] = zone
		# Out of that corner is -X and +Z: back toward the middle of the floor.
		if aware.think(me, foe, ctx)["heading"].x < -0.3:
			leaving += 1
		if blind.think(me, foe, ctx)["heading"].x < -0.3:
			blind_leaving += 1
	_check(leaving >= 100,
		"a National driver gets out of the house bot's corner (%d of 120 ticks driving out)"
			% leaving)
	_check(blind_leaving <= 20,
		"a Regional driver stays in there fighting, because it does not know the corner is anybody's (%d of 120 ticks leaving)"
			% blind_leaving)
	_check(int(aware.get("dodge_ticks")) > int(blind.get("dodge_ticks")),
		"and the zone is counted as a dodge, not as a fight")

	# The released house bot in the endgame: route around it, not through it.
	var house := Vector3(0, 0.25, -1.2)
	var bent := 0.0
	var through := 0.0
	var champion := OpponentAIScript.new(_rng(), OpponentAIScript.MODE_NORMAL,
		OpponentAIScript.SKILL_CHAMPIONSHIP, OpponentAIScript.TEMPERAMENT_BRAWLER)
	var regional := OpponentAIScript.new(_rng(), OpponentAIScript.MODE_NORMAL,
		OpponentAIScript.SKILL_REGIONAL, OpponentAIScript.TEMPERAMENT_BRAWLER)
	for tick in 120:
		foe.place(Vector3(0, 0.25, -3.0), Vector3(0, 0, 1))
		me.place(Vector3(0, 0.25, 0.0), Vector3(0, 0, -1))
		var ctx := _ctx(tick)
		ctx["phase"] = FightTypes.PHASE_ENDGAME
		ctx["house_bot_position"] = house
		bent = maxf(bent, absf(champion.think(me, foe, ctx)["heading"].normalized().x))
		through = maxf(through, absf(regional.think(me, foe, ctx)["heading"].normalized().x))
	_check(bent > through,
		"in the endgame a Championship driver bends around the released house bot (%.2f of the heading sideways against %.2f)"
			% [bent, through])

	# In the open phase the house bot is on its mark and nothing is routed around.
	var open_phase := OpponentAIScript.new(_rng(), OpponentAIScript.MODE_NORMAL,
		OpponentAIScript.SKILL_CHAMPIONSHIP, OpponentAIScript.TEMPERAMENT_BRAWLER)
	var open_bend := 0.0
	for tick in 120:
		foe.place(Vector3(0, 0.25, -3.0), Vector3(0, 0, 1))
		me.place(Vector3(0, 0.25, 0.0), Vector3(0, 0, -1))
		var ctx := _ctx(tick)
		ctx["phase"] = FightTypes.PHASE_OPEN
		ctx["house_bot_position"] = house
		open_bend = maxf(open_bend, absf(open_phase.think(me, foe, ctx)["heading"].normalized().x))
	_check(open_bend < bent,
		"and leaves it alone in the open phase, when it is still on its mark (%.2f)" % open_bend)


# ---------------------------------------------------------------- the last twenty seconds

func _test_showboat_switch(me: FakeBot, foe: FakeBot) -> void:
	me.set_inverted(false)
	foe.set_inverted(false)
	me.bot_id = "mine"
	foe.bot_id = "theirs"

	var behind := OpponentAIScript.new(_rng(), OpponentAIScript.MODE_NORMAL,
		OpponentAIScript.SKILL_NATIONAL, OpponentAIScript.TEMPERAMENT_TECHNICIAN)
	var ahead := OpponentAIScript.new(_rng(), OpponentAIScript.MODE_NORMAL,
		OpponentAIScript.SKILL_NATIONAL, OpponentAIScript.TEMPERAMENT_TECHNICIAN)
	var behind_in := 0
	var ahead_in := 0
	for tick in 300:
		foe.place(Vector3(0, 0.25, 0), Vector3(0, 0, 1))      # nose on us: no flank at all
		me.place(Vector3(0, 0.25, 1.4), Vector3(0, 0, -1))
		var losing := _ctx(tick)
		losing["time_left_s"] = 12.0
		losing["judge_points"] = {"mine": 8.0, "theirs": 17.0}
		var winning := _ctx(tick)
		winning["time_left_s"] = 12.0
		winning["judge_points"] = {"mine": 17.0, "theirs": 8.0}
		if behind.think(me, foe, losing)["heading"].normalized().dot(Vector2(0, -1)) > 0.8:
			behind_in += 1
		if ahead.think(me, foe, winning)["heading"].normalized().dot(Vector2(0, -1)) > 0.8:
			ahead_in += 1
	_check(int(behind.get("showboat_ticks")) == 300,
		"behind on the card with twelve seconds left, it fights like a showboat (%d of 300 ticks)"
			% int(behind.get("showboat_ticks")))
	_check(int(ahead.get("showboat_ticks")) == 0,
		"ahead on the card, it keeps doing what was working")
	_check(behind_in > ahead_in,
		"and it over-commits for the judges rather than waiting for the angle (%d ticks driving in against %d)"
			% [behind_in, ahead_in])

	# Not in the first two and a half minutes, however far behind it is.
	var early := OpponentAIScript.new(_rng(), OpponentAIScript.MODE_NORMAL,
		OpponentAIScript.SKILL_NATIONAL, OpponentAIScript.TEMPERAMENT_TECHNICIAN)
	for tick in 120:
		foe.place(Vector3(0, 0.25, 0), Vector3(0, 0, 1))
		me.place(Vector3(0, 0.25, 1.4), Vector3(0, 0, -1))
		var ctx := _ctx(tick)
		ctx["time_left_s"] = 95.0
		ctx["judge_points"] = {"mine": 2.0, "theirs": 22.0}
		early.think(me, foe, ctx)
	_check(int(early.get("showboat_ticks")) == 0,
		"with ninety five seconds left it is still fighting its own fight")
	me.bot_id = ""
	foe.bot_id = ""


# ---------------------------------------------------------------- determinism, per tier

## The replay contract, with the new state in it: the belief, the pin clocks and the
## temperament draw are all functions of the seed and the tick, and nothing else.
func _test_skill_determinism(me: FakeBot, foe: FakeBot) -> void:
	for pair in [[OpponentAIScript.SKILL_MASTERS, OpponentAIScript.TEMPERAMENT_BULLY],
			[OpponentAIScript.SKILL_SCRAPYARD, OpponentAIScript.TEMPERAMENT_SHOWBOAT],
			[OpponentAIScript.SKILL_CHAMPIONSHIP, ""]]:
		var first := _tier_sequence(me, foe, str(pair[0]), str(pair[1]), SEED)
		var second := _tier_sequence(me, foe, str(pair[0]), str(pair[1]), SEED)
		var other := _tier_sequence(me, foe, str(pair[0]), str(pair[1]), SEED + 3)
		_check(first == second,
			"%s / %s replays bit for bit from the same seed" % [str(pair[0]), str(pair[1])])
		_check(first != other,
			"and fights differently from another seed")


func _tier_sequence(me: FakeBot, foe: FakeBot, skill: String, temperament: String,
		seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var ai := OpponentAIScript.new(rng, OpponentAIScript.MODE_NORMAL, skill, temperament)
	me.set_inverted(false)
	me.place(Vector3(3.2, 0.25, 3.2), Vector3(-1, 0, -1))
	var position := Vector3(3.2, 0.25, 3.2)
	var rows: Array = []
	for tick in 600:
		var angle := float(tick) * 0.01
		foe.place(Vector3(cos(angle) * 2.0, 0.25, sin(angle) * 2.0),
			Vector3(-sin(angle), 0, cos(angle)))
		var ctx := _ctx(tick)
		ctx["zone_rect"] = Rect2(2.6, -4.8, 2.2, 2.2)
		ctx["phase"] = FightTypes.PHASE_ENDGAME
		ctx["house_bot_position"] = Vector3(3.7, 0.25, -3.7)
		var inp := ai.think(me, foe, ctx)
		rows.append(FightTypes.replay_row(tick, inp))
		var heading: Vector2 = inp["heading"]
		var world := Vector3(heading.x, 0.0, heading.y)
		if world.length() > 0.0001:
			position += world.normalized() * 0.02
			me.place(position, world)
	return rows


# ---------------------------------------------------------------- the acceptance sweep

## brief v4 §4's acceptance numbers, fought in a small kinematic arena rather than the
## physics one: a hundred three-bot-length fights per pairing is two minutes of headless
## GDScript, where a hundred real fights would be an hour.
##
## What the toy keeps from the real thing: the drive is a heading, the bots turn at a
## finite rate, a weapon only bites inside its reach and inside the nose cone, a hit on
## the back of a machine is worth more than a hit on its front, the walls are where the
## walls are, and both drivers share one rng in fight.gd's fixed order (player, then
## opponent). What it drops: the physics, the parts, the flips. It is a test of DRIVING,
## which is what a skill tier is.
func _test_sweep() -> void:
	var a := SimBot.new()
	var b := SimBot.new()
	root.add_child(a)
	root.add_child(b)
	await process_frame

	var masters := _sweep(a, b, OpponentAIScript.SKILL_MASTERS,
		OpponentAIScript.SKILL_SCRAPYARD)
	print("SWEEP Masters vs Scrapyard: %d wins, %d losses, %d draws of %d"
		% [int(masters["wins"]), int(masters["losses"]), int(masters["draws"]), SWEEP_FIGHTS])
	_check(int(masters["wins"]) >= 85,
		"Masters beats Scrapyard in %d of %d seeded fights (the brief asks for 85)"
			% [int(masters["wins"]), SWEEP_FIGHTS])

	var novice := _sweep(a, b, "novice", OpponentAIScript.SKILL_SCRAPYARD)
	print("SWEEP Novice vs Scrapyard: %d wins, %d losses, %d draws of %d"
		% [int(novice["wins"]), int(novice["losses"]), int(novice["draws"]), SWEEP_FIGHTS])
	_check(int(novice["wins"]) >= 60,
		"the novice driver beats Scrapyard in %d of %d (the brief asks for 60)"
			% [int(novice["wins"]), SWEEP_FIGHTS])

	# The ladder is a ladder all the way up, not just at the ends.
	var rungs := {}
	for id in OpponentAIScript.SKILL_IDS:
		if id == OpponentAIScript.SKILL_SCRAPYARD:
			continue
		var result := _sweep(a, b, id, OpponentAIScript.SKILL_SCRAPYARD, 20)
		rungs[id] = int(result["wins"])
	print("SWEEP against Scrapyard over 20 fights: %s" % str(rungs))
	_check(int(rungs["regional"]) <= int(rungs["national"])
		and int(rungs["national"]) <= int(rungs["masters"]),
		"every tier beats Scrapyard at least as often as the tier below it (%s)" % str(rungs))

	# No tier from National up drives itself into a live hazard more than once a fight.
	var hazard_counts := {}
	for id in OpponentAIScript.SKILL_IDS:
		hazard_counts[id] = _hazard_sweep(a, b, id)
	print("SWEEP worst hazard entries in one fight: %s" % str(hazard_counts))
	for id in [OpponentAIScript.SKILL_NATIONAL, OpponentAIScript.SKILL_CHAMPIONSHIP,
			OpponentAIScript.SKILL_MASTERS]:
		_check(int(hazard_counts[id]) <= 1,
			"%s drives into a live hazard at most once in a fight (worst %d)"
				% [id, int(hazard_counts[id])])
	_check(int(hazard_counts["scrapyard"]) > int(hazard_counts["masters"]),
		"where a Scrapyard driver walks into it %d times, which is what the tier is"
			% int(hazard_counts["scrapyard"]))

	# Every temperament fights measurably differently, so a regression shows up here.
	var prints: Dictionary = _temperament_prints(a, b)
	for id in OpponentAIScript.TEMPERAMENT_IDS:
		print("SWEEP %-12s %s" % [id, str(prints[id])])
	var seen := []
	var distinct := true
	for id in OpponentAIScript.TEMPERAMENT_IDS:
		if prints[id] in seen:
			distinct = false
		seen.append(prints[id])
	_check(distinct, "all five temperaments leave a different mark on the same fight")
	_check(int((prints["bully"] as Array)[0]) > int((prints["technician"] as Array)[0])
			and int((prints["bully"] as Array)[0]) > int((prints["opportunist"] as Array)[0]),
		"the bully pins more than the technician or the opportunist (%d against %d and %d)"
			% [int((prints["bully"] as Array)[0]), int((prints["technician"] as Array)[0]),
				int((prints["opportunist"] as Array)[0])])
	_check(int((prints["opportunist"] as Array)[2]) > int((prints["brawler"] as Array)[2]),
		"the opportunist retreats where the brawler never does (%d ticks against %d)"
			% [int((prints["opportunist"] as Array)[2]), int((prints["brawler"] as Array)[2])])
	_check(int((prints["showboat"] as Array)[3]) > int((prints["technician"] as Array)[3]),
		"the showboat spends more of the fight inside a metre than the technician (%d against %d)"
			% [int((prints["showboat"] as Array)[3]), int((prints["technician"] as Array)[3])])

	a.queue_free()
	b.queue_free()


## `fights` seeded fights of one skill against another. The first driver is the one whose
## wins are counted; "novice" builds the scripted novice instead of an OpponentAI.
func _sweep(a: SimBot, b: SimBot, left: String, right: String,
		fights: int = SWEEP_FIGHTS) -> Dictionary:
	var out := {"wins": 0, "losses": 0, "draws": 0}
	for i in fights:
		var result := _duel_sim(a, b, left, right, SEED + i * 101, SIM_ARENA_HAZARD)
		match int(result["winner"]):
			0: out["wins"] = int(out["wins"]) + 1
			1: out["losses"] = int(out["losses"]) + 1
			_: out["draws"] = int(out["draws"]) + 1
	return out


## The worst number of times a driver of this tier drove into the live hazard in the
## middle of the floor, over five seeded fights.
func _hazard_sweep(a: SimBot, b: SimBot, skill: String) -> int:
	var worst := 0
	for i in 5:
		var result := _duel_sim(a, b, skill, OpponentAIScript.SKILL_REGIONAL,
			SEED + i * 37, [Vector3.ZERO])
		worst = maxi(worst, int(result["hazard_entries"]))
	return worst


## One fixed fight per temperament, all at Championship (where every behaviour is
## available) against a Championship brawler, both spawned along the same wall and with a
## live hazard on the floor, so that walls, hazards and damage are all on the table. The returned
## array is the fingerprint: [pins, shoves, retreats, ticks inside a metre].
func _temperament_prints(a: SimBot, b: SimBot) -> Dictionary:
	var out := {}
	for id in OpponentAIScript.TEMPERAMENT_IDS:
		var result := _duel_sim(a, b, OpponentAIScript.SKILL_CHAMPIONSHIP,
			OpponentAIScript.SKILL_CHAMPIONSHIP, SEED + 5, [Vector3(1.2, 0.0, 1.2)], id,
			SWEEP_TICKS, [Vector3(4.2, 0.25, -1.8), Vector3(4.2, 0.25, 1.8)])
		out[id] = result["print"]
	return out


## One fight in the toy arena. Driver A is built from `left`, driver B from `right`, both
## from ONE rng in fight.gd's order. Returns the winner (0, 1 or -1 for a draw), how many
## times A drove into a live hazard, and A's behaviour counters.
func _duel_sim(a: SimBot, b: SimBot, left: String, right: String, seed_value: int,
		hazards: Array, left_temperament: String = OpponentAIScript.TEMPERAMENT_BRAWLER,
		ticks: int = SWEEP_TICKS, spawn_pair: Array = []) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	# The spawn is drawn BEFORE the drivers are built, exactly as fight.gd draws the
	# arena's setup before it builds them, so the order of the stream is the fight's.
	var spread := rng.randf_range(0.0, TAU)
	var radius := rng.randf_range(2.6, 3.6)
	if spawn_pair.size() == 2:
		# A fixed pair instead of the seeded circle: used to put both machines on the same
		# wall, where wall work is on the table for every temperament.
		a.reset(spawn_pair[0] as Vector3)
		b.reset(spawn_pair[1] as Vector3)
	else:
		a.reset(Vector3(cos(spread) * radius, 0.25, sin(spread) * radius))
		b.reset(Vector3(-cos(spread) * radius, 0.25, -sin(spread) * radius))
	a.face(b.at)
	b.face(a.at)

	var driver_a: Object = null
	if left == "novice":
		driver_a = NoviceScript.new()
	else:
		driver_a = OpponentAIScript.new(rng, OpponentAIScript.MODE_NORMAL, left,
			left_temperament)
	var driver_b: Object = OpponentAIScript.new(rng, OpponentAIScript.MODE_NORMAL, right,
		OpponentAIScript.TEMPERAMENT_BRAWLER)

	var dt := 1.0 / float(FightTypes.TICK_HZ)
	var entries := 0
	var was_in := false
	for tick in ticks:
		var ctx := {"tick": tick, "spike_centre": Vector3.ZERO, "spike_rise_in_s": 999.0}
		if not hazards.is_empty():
			ctx["hazard"] = {"danger_positions": hazards}
			ctx["hazards"] = hazards
		# The fixed order fight.gd uses: the first driver thinks, then the second.
		var input_a: Dictionary = driver_a.think(a, b, ctx)
		var input_b: Dictionary = driver_b.think(b, a, ctx)
		a.step(input_a["heading"], dt)
		b.step(input_b["heading"], dt)
		_sim_contact(a, b)
		if bool(input_a["fire"]):
			b.health -= _sim_damage(a, b)
		if bool(input_b["fire"]):
			a.health -= _sim_damage(b, a)
		for at in hazards:
			var in_now := Vector2(a.at.x - (at as Vector3).x,
				a.at.z - (at as Vector3).z).length() <= SIM_HAZARD_R
			if in_now:
				a.health -= SIM_HAZARD_DPS * dt
				if not was_in:
					entries += 1
			was_in = in_now
			if Vector2(b.at.x - (at as Vector3).x, b.at.z - (at as Vector3).z).length() \
					<= SIM_HAZARD_R:
				b.health -= SIM_HAZARD_DPS * dt
		if a.health <= 0.0 or b.health <= 0.0:
			break

	var winner := -1
	if a.health > b.health + 0.001:
		winner = 0
	elif b.health > a.health + 0.001:
		winner = 1
	var counters: Array = [0, 0, 0, 0]
	if driver_a is OpponentAI:
		counters = [int(driver_a.get("pin_ticks")), int(driver_a.get("shove_ticks")),
			int(driver_a.get("retreat_ticks")), int(driver_a.get("close_ticks"))]
	return {"winner": winner, "hazard_entries": entries, "print": counters,
		"health": [a.health, b.health]}


## Contact, as much of it as a sim with no physics needs: whichever machine is driving
## into the other one shoves it along. It is what makes a wall pin possible at all, and
## what puts a shoved machine onto a hazard.
func _sim_contact(a: SimBot, b: SimBot) -> void:
	var gap_v := Vector2(b.at.x - a.at.x, b.at.z - a.at.z)
	var gap := gap_v.length()
	if gap > SIM_PUSH_M or gap < 0.0001:
		return
	var line := gap_v.normalized()
	var push := (SIM_PUSH_M - gap) * 0.5
	var a_nose := Vector2(a.facing.x, a.facing.z).normalized()
	var b_nose := Vector2(b.facing.x, b.facing.z).normalized()
	b.shove(line * push * maxf(a_nose.dot(line), 0.0))
	a.shove(-line * push * maxf(b_nose.dot(-line), 0.0))


## One tick of one weapon. It bites only inside its reach and inside the nose cone, it is
## worth more the straighter it lands, and a hit on the back of a machine is worth more
## than one on the armour at the front: which is why the tiers that work for a flank win.
func _sim_damage(attacker: SimBot, victim: SimBot) -> float:
	var to_victim := Vector2(victim.at.x - attacker.at.x, victim.at.z - attacker.at.z)
	var gap := to_victim.length()
	if gap > SIM_REACH_M or gap < 0.0001:
		return 0.0
	var line := to_victim.normalized()
	var nose := Vector2(attacker.facing.x, attacker.facing.z).normalized()
	var cone := cos(deg_to_rad(SIM_CONE_DEG))
	var aim := nose.dot(line)
	if aim < cone:
		return 0.0
	var straightness := SIM_STRAIGHT_FLOOR \
		+ (1.0 - SIM_STRAIGHT_FLOOR) * (aim - cone) / (1.0 - cone)
	# 1.0 = they are looking straight at us (their wedge and their thick plate), -1.0 =
	# we are on their back.
	var face := Vector2(victim.facing.x, victim.facing.z).normalized().dot(-line)
	return SIM_HIT * straightness * maxf(1.0 - SIM_FACE_WEIGHT * face, 0.05)


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
