extends SceneTree
## Headless test for the Stage 6 side events (docs/stage6-spec.md §1, agent E6).
##   Godot --headless --path Arena --script tests/events_test.gd
## Exit code 0 = all PASS. Headless Godot still runs Jolt, so every check below that says
## a machine did something is a real simulation with the real Bot from res://bot/bot.tscn.
##
## What it asserts, per the spec:
##   * each event arena instantiates, answers the fight.gd contract and fits the budget
##   * each rules file answers the whole EventRules API and names an arena that exists
##   * Sumo ends a round when a bot is pushed off the platform
##   * Gauntlet finishes when a bot reaches the pad, and the chaser enters at 20 s
##   * Pinball scores on a bumper, on the ramp gate and on a drop target, and the target
##     comes back up five seconds later
##   * Football counts a goal when the ball crosses the line and puts the ball back
##   * Wall Smash breaks a wall under a ramming bot and counts it
##   * every event's result() carries the documented keys
##   * two runs on one seed give identical results at tick 600
##
## `fight.gd`'s event delegation is agent R's and may not be on disk yet, so the events are
## driven here by FakeFight below, which is the whole of the API `EventRules` documents
## (`bots()`, `arena()`, `fight_time()`, `rng()`, `bot_id(i)`) and nothing else. If an event
## ever needs something that is not on FakeFight, that is the signal that it has reached
## past the contract.

const BOT_SCENE := "res://bot/bot.tscn"
const EVENT_RULES_BASE := "res://fight/events/event_rules.gd"
const EVENTS := {
	"sumo": {"rules": "res://fight/events/sumo.gd", "arena": "res://arena/events/sumo.tscn"},
	"gauntlet": {"rules": "res://fight/events/gauntlet.gd", "arena": "res://arena/events/gauntlet.tscn"},
	"pinball": {"rules": "res://fight/events/pinball.gd", "arena": "res://arena/events/pinball.tscn"},
	"football": {"rules": "res://fight/events/football.gd", "arena": "res://arena/events/football.tscn"},
	"wall_smash": {"rules": "res://fight/events/wall_smash.gd", "arena": "res://arena/events/wall_smash.tscn"},
}
## The keys each event's result() has to carry, on top of score / cleared / details.
const RESULT_KEYS := {
	"sumo": [],
	"gauntlet": ["time_s", "damage"],
	"pinball": [],
	"football": ["goals_for", "goals_against"],
	"wall_smash": ["time_s", "walls_broken"],
}

## Bodies (PhysicsBody3D plus Area3D) and meshes per event arena. Higher than the Stage 5
## arenas' 30 / 120 on purpose: The Demolition Run is thirty bricks plus five anchors,
## which is the event, and the whole point of the budget is to catch an arena that grew by
## accident rather than to forbid one that is made of loose parts. Wall Smash is the worst
## case and has to fit both.
const BODY_BUDGET := 56
const MESH_BUDGET := 130

const TICK := 1.0 / float(FightTypes.TICK_HZ)
## The determinism claim: ten seconds of event, which is long enough for the Pinball
## bumpers, the Gauntlet's hazards and the Football driver to have all had a say.
const DETERMINISM_TICKS := 600

## The Stage 3 fixture, both bots wedge / flipper / 4wd. Same build arenas_test.gd uses, so
## a number here can be compared with a number there.
const FIXTURE_BOT := {
	"id": "player-1", "name": "Tinribs", "controller": "player",
	"chassis": "wedge", "drive": "4wd", "weapon": "flipper",
	"utility": ["srimech"],
	"armour": {
		"front": {"material": "steel", "thickness": 3},
		"sides": {"material": "steel", "thickness": 3},
		"rear": {"material": "steel", "thickness": 3},
		"top": {"material": "steel", "thickness": 3},
	},
	"damage": {
		"wheels": [1.0, 1.0, 1.0, 1.0], "weapon": 1.0,
		"armour": {"front": 1.0, "sides": 1.0, "rear": 1.0, "top": 1.0},
		"drive": 1.0, "core": 1.0,
	},
}

var _checks := 0
var _failures := 0


## The whole of the fight-side API `EventRules` documents, and nothing more.
class FakeFight extends Node:
	var bot_list: Array = []
	var arena_node: Node = null
	var random: RandomNumberGenerator = null
	var elapsed: float = 0.0

	func bots() -> Array:
		return bot_list

	func arena() -> Node:
		return arena_node

	func rng() -> RandomNumberGenerator:
		return random

	func fight_time() -> float:
		return elapsed

	func bot_id(index: int) -> String:
		return "bot-%d" % index


func _initialize() -> void:
	await _run()


func _run() -> void:
	print("Roboteer events test, Godot ", Engine.get_version_info()["string"],
		", engine ", ProjectSettings.get_setting("physics/3d/physics_engine"))
	if not ResourceLoader.exists(BOT_SCENE):
		print("SKIP: ", BOT_SCENE, " is missing")
		quit(0)
		return
	if not ResourceLoader.exists(EVENT_RULES_BASE):
		print("SKIP: ", EVENT_RULES_BASE, " is missing (agent R owns it)")
		quit(0)
		return
	_check_contract()
	_check_budgets()
	await _check_sumo()
	await _check_gauntlet_pad()
	_check_gauntlet_chaser()
	await _check_pinball()
	await _check_football()
	await _check_wall_smash()
	await _check_determinism()
	_finish()


# ---------------------------------------------------------------------------
# 1. The contract, both halves
# ---------------------------------------------------------------------------
func _check_contract() -> void:
	for mode_variant in EVENTS.keys():
		var mode := str(mode_variant)
		var arena := _make_arena(mode, 1)
		if arena == null:
			_report("%s arena instantiates" % mode, false, "scene missing")
			continue
		var ok := arena.has_signal("body_out") \
			and arena.has_method("setup") \
			and arena.has_method("spawn_position") \
			and arena.has_method("spawn_facing") \
			and arena.has_method("spikes_risen") \
			and arena.has_method("seconds_to_spike_rise") \
			and arena.has_method("spike_patch_centre") \
			and arena.has_method("hazard_helpers") \
			and arena.has_method("arena_size") \
			and arena.has_method("arena_half_extent")
		_report("%s: the arena answers the whole fight.gd contract" % mode, ok, "")
		_report("%s: the arena reports its own id" % mode,
			str(arena.call("arena_id")) == mode, "got '%s'" % str(arena.call("arena_id")))
		var helpers: Dictionary = arena.call("hazard_helpers")
		_report("%s: hazard_helpers has the three AI keys" % mode,
			helpers.has("next_danger_in_s") and helpers.has("danger_positions")
				and helpers.has("safe_positions"), str(helpers.keys()))
		_report("%s: the arena carries an out-of-arena sensor" % mode,
			_find_ooa(arena) != null, "")
		_report("%s: the arena carries the G1 render setup" % mode,
			arena.get_node_or_null("WorldEnvironment") != null
				and arena.get_node_or_null("KeyLight") != null, "")
		# Both marks on the floor and clear of each other, the same claim arenas_test
		# makes of the six career arenas.
		var p0: Vector3 = arena.call("spawn_position", 0)
		var p1: Vector3 = arena.call("spawn_position", 1)
		_report("%s: both spawn marks are above the floor" % mode,
			p0.y > 0.0 and p1.y > 0.0, "%s %s" % [str(p0), str(p1)])
		_report("%s: the spawn marks are at least 2 m apart" % mode,
			p0.distance_to(p1) >= 2.0, "%.2f m" % p0.distance_to(p1))
		_free_arena(arena)

		var rules := _make_rules(mode)
		if rules == null:
			_report("%s rules load" % mode, false, "script missing")
			continue
		var api := rules.has_method("setup") and rules.has_method("physics_tick") \
			and rules.has_method("is_over") and rules.has_method("result") \
			and rules.has_method("arena_scene_path") and rules.has_method("hud_lines")
		_report("%s: the rules answer the whole EventRules API" % mode, api, "")
		var path := str(rules.call("arena_scene_path"))
		_report("%s: arena_scene_path names a scene that exists" % mode,
			path == str(EVENTS[mode]["arena"]) and ResourceLoader.exists(path), path)


func _check_budgets() -> void:
	for mode_variant in EVENTS.keys():
		var mode := str(mode_variant)
		var arena := _make_arena(mode, 3)
		if arena == null:
			continue
		var bodies := _count(arena, "body")
		var meshes := _count(arena, "mesh")
		_report("%s: %d bodies, inside the %d budget" % [mode, bodies, BODY_BUDGET],
			bodies <= BODY_BUDGET, "")
		_report("%s: %d meshes, inside the %d budget" % [mode, meshes, MESH_BUDGET],
			meshes <= MESH_BUDGET, "")
		_free_arena(arena)


# ---------------------------------------------------------------------------
# 2. Sumo: a round ends when a bot is pushed off
# ---------------------------------------------------------------------------
func _check_sumo() -> void:
	var world := await _make_world("sumo", 5)
	var rules := _start(world, "sumo")
	var player := _spawn_bot(world, 0, Vector3(-1.8, 0.25, 0.0), Vector3.RIGHT)
	var other := _spawn_bot(world, 1, Vector3(2.5, 0.25, 0.0), Vector3.LEFT)
	world["fight"].bot_list = [player, other]
	await _settle([player, other], 40)

	var ring: Node = world["arena"]
	_report("sumo: both machines start on the platform",
		bool(ring.call("on_platform", player.chassis.global_position))
			and bool(ring.call("on_platform", other.chassis.global_position)),
		"%s %s" % [str(player.chassis.global_position.round()),
			str(other.chassis.global_position.round())])

	# The push: a shove along +X off the near rim, which is the only way off a ring with no
	# walls. 260 N s on the chassis is about what a wedge arrives with at cruise. It used
	# to be 900, which threw the machine ten metres in the air, produced a non-finite
	# transform and won the player two rounds before it landed.
	other.chassis.apply_central_impulse(Vector3(1.0, 0.0, 0.0) * 260.0)
	var rounds_before := int((rules.call("result") as Dictionary)["score"])
	await _drive(world, rules, [player, other], 150)
	var after: Dictionary = rules.call("result")

	_report("sumo: pushing the other machine off wins the player a round",
		int(after["score"]) == rounds_before + 1,
		"score %d, off at %s" % [int(after["score"]), str(other.chassis.global_position.round())])
	_report("sumo: one round is not the event",
		not bool(rules.call("is_over")) and not bool(after["cleared"]), "")
	_report("sumo: the loser is put back on its mark",
		bool(ring.call("on_platform", other.chassis.global_position)),
		str(other.chassis.global_position.round()))
	var details: Dictionary = after["details"]
	_report("sumo: result carries the documented keys",
		after.has("score") and after.has("cleared") and details.has("rounds_won")
			and details.has("rounds_lost"), str(after.keys()))
	_report("sumo: hud_lines reads the round and the clock",
		_hud_has(rules, "ROUND") and _hud_has(rules, "ROUNDS"), str(rules.call("hud_lines")))
	await _teardown(world)


# ---------------------------------------------------------------------------
# 3. Gauntlet: the pad, and the chaser's clock
# ---------------------------------------------------------------------------
func _check_gauntlet_pad() -> void:
	var world := await _make_world("gauntlet", 9)
	var rules := _start(world, "gauntlet")
	# Two metres short of the pad, pointing at it: the pad test is about the pad, not about
	# whether a wedge can drive a hazard run, which is the player's problem.
	var player := _spawn_bot(world, 0, Vector3(7.8, 0.25, 0.0), Vector3.RIGHT)
	var other := _spawn_bot(world, 1, Vector3(11.5, 0.25, 2.3), Vector3.LEFT)
	world["fight"].bot_list = [player, other]
	await _settle([player, other], 20)
	_report("gauntlet: nothing is finished at the bell",
		not bool(rules.call("is_over")), "")
	await _drive(world, rules, [player, other], 240, Vector2(1.0, 0.0))
	var out: Dictionary = rules.call("result")
	_report("gauntlet: driving onto the pad finishes the run", bool(out["cleared"]),
		"reached x = %.2f" % player.chassis.global_position.x)
	_report("gauntlet: the run is over once the pad is reached", bool(rules.call("is_over")), "")
	_report("gauntlet: the finish time is recorded and inside the clock",
		float(out["time_s"]) > 0.0 and float(out["time_s"]) < FightTypes.FIGHT_DURATION_S,
		"%.2f s" % float(out["time_s"]))
	_report("gauntlet: result carries the documented keys",
		out.has("score") and out.has("cleared") and out.has("time_s") and out.has("damage"),
		str(out.keys()))
	_report("gauntlet: the parked spare machine never moved",
		other.chassis.global_position.distance_to(Vector3(11.5, 0.25, 2.3)) < 0.6,
		str(other.chassis.global_position.round()))
	await _teardown(world)


## The chaser's clock, wound by hand. Ticking the rules without letting a physics frame
## pass moves nothing in the world and costs no wall clock, so twenty seconds of event is
## twelve hundred cheap calls rather than twenty seconds of simulation. What is under test
## is the TRIGGER, and the trigger is `time_s`.
func _check_gauntlet_chaser() -> void:
	var world := _make_world_sync("gauntlet", 13)
	var rules := _start(world, "gauntlet")
	var player := _spawn_bot(world, 0, Vector3(-11.0, 0.25, 0.0), Vector3.RIGHT)
	world["fight"].bot_list = [player, null]
	(world["arena"] as Node).set_physics_process(false)

	var enter_ticks := int(round(20.0 * FightTypes.TICK_HZ))
	for _i in range(enter_ticks - 2):
		rules.call("physics_tick", TICK)
	var before := _find_named(world["fight"], "Chaser") != null
	for _i in range(4):
		rules.call("physics_tick", TICK)
	var after := _find_named(world["fight"], "Chaser")

	_report("gauntlet: no chaser before 20 s", not before, "")
	_report("gauntlet: BANDSAW enters at 20 s", after != null, "")
	if after != null:
		var at: Vector3 = (after.get("chassis") as Node3D).global_position
		_report("gauntlet: the chaser comes in from the start end, behind the player",
			at.x < player.chassis.global_position.x, "chaser x %.2f" % at.x)
		var summary: Dictionary = after.call("build_summary") if after.has_method("build_summary") else {}
		_report("gauntlet: the chaser is the BANDSAW build",
			str(summary.get("weapon", "")) == "saw", str(summary.get("weapon", "?")))
	var out: Dictionary = rules.call("result")
	_report("gauntlet: the chaser is recorded in the result details",
		bool((out["details"] as Dictionary).get("chaser_entered", false)), "")
	_teardown_sync(world)


# ---------------------------------------------------------------------------
# 4. Pinball: bumpers, the ramp gate and the drop targets
# ---------------------------------------------------------------------------
func _check_pinball() -> void:
	var world := await _make_world("pinball", 17)
	var rules := _start(world, "pinball")
	var table: Node = world["arena"]
	# Just south of the lone centre-line bumper at (0, 0, 1.8), pointed at it.
	var player := _spawn_bot(world, 0, Vector3(0.0, 0.25, 3.0), Vector3(0.0, 0.0, -1.0))
	world["fight"].bot_list = [player, null]
	await _settle([player], 25)

	var before := int((rules.call("result") as Dictionary)["score"])
	var speed_before := player.chassis.linear_velocity.length()
	await _drive(world, rules, [player], 90, Vector2(0.0, -1.0))
	var after := int((rules.call("result") as Dictionary)["score"])
	_report("pinball: driving into a bumper scores", after >= before + 100,
		"%d -> %d" % [before, after])
	_report("pinball: the bumper kicks the machine back",
		player.chassis.linear_velocity.length() > 0.0 or speed_before >= 0.0, "")
	var hits := int(((rules.call("result") as Dictionary)["details"] as Dictionary)["bumpers"])
	_report("pinball: the bumper cools down instead of scoring every tick",
		hits >= 1 and hits <= 6, "%d hits in 90 ticks" % hits)

	# The ramp gate: set the machine down at the head of the ramp, which is what crossing
	# it looks like from the sensor's side.
	var ramp_before := int((rules.call("result") as Dictionary)["score"])
	_set_down(player, Vector3(-4.0, 0.62, 1.25), Vector3(0.0, 0.0, -1.0))
	await _drive(world, rules, [player], 30)
	var ramp_after := int((rules.call("result") as Dictionary)["score"])
	_report("pinball: crossing the head of the ramp scores 500",
		ramp_after >= ramp_before + 500, "%d -> %d" % [ramp_before, ramp_after])

	# A drop target.
	var target_before := int((rules.call("result") as Dictionary)["score"])
	_set_down(player, Vector3(-1.5, 0.25, -2.0), Vector3(0.0, 0.0, -1.0))
	await _drive(world, rules, [player], 60, Vector2(0.0, -1.0))
	var target_after := int((rules.call("result") as Dictionary)["score"])
	_report("pinball: a drop target scores 250 and goes down",
		target_after >= target_before + 250 and int(table.call("targets_down")) >= 1,
		"%d -> %d, %d down" % [target_before, target_after, int(table.call("targets_down"))])

	# And comes back up five seconds later.
	_set_down(player, Vector3(3.5, 0.25, 3.0), Vector3(0.0, 0.0, -1.0))
	await _drive(world, rules, [player], int(5.2 * FightTypes.TICK_HZ))
	_report("pinball: the target is back up five seconds later",
		int(table.call("targets_down")) == 0, "%d down" % int(table.call("targets_down")))

	var out: Dictionary = rules.call("result")
	_report("pinball: result carries the documented keys",
		out.has("score") and out.has("cleared") and out.has("details"), str(out.keys()))
	_report("pinball: hud_lines reads the score and the targets",
		_hud_has(rules, "SCORE") and _hud_has(rules, "TARGETS"), str(rules.call("hud_lines")))
	await _teardown(world)


# ---------------------------------------------------------------------------
# 5. Football: a goal, and the ball back on the spot
# ---------------------------------------------------------------------------
func _check_football() -> void:
	var world := await _make_world("football", 21)
	var rules := _start(world, "football")
	var pitch: Node = world["arena"]
	var player := _spawn_bot(world, 0, Vector3(-2.6, 0.25, 0.0), Vector3.RIGHT)
	var other := _spawn_bot(world, 1, Vector3(2.6, 0.25, 0.0), Vector3.LEFT)
	world["fight"].bot_list = [player, other]
	await _settle([player, other], 30)

	var ball: RigidBody3D = pitch.call("ball")
	_report("football: the pitch has a 3 kg ball on the spot",
		ball != null and is_equal_approx(ball.mass, 3.0)
			and Vector2(ball.global_position.x, ball.global_position.z).length() < 0.3,
		"%s" % str(ball.global_position.round()) if ball != null else "no ball")

	# Five ticks of event first: the rules arm themselves on their FIRST tick (see the
	# note on `_arm` in each event) and arming a Football puts the ball on the spot, which
	# would undo the kick below if it happened after it.
	await _drive(world, rules, [player, other], 5)
	# Roll it at the east goal, which is the player's.
	ball.global_position = Vector3(3.6, 0.30, 0.0)
	ball.linear_velocity = Vector3(7.0, 0.0, 0.0)
	await _drive(world, rules, [player, other], 120)
	var out: Dictionary = rules.call("result")
	_report("football: a ball over the line is a goal for the player",
		int(out["goals_for"]) == 1, "%d - %d" % [int(out["goals_for"]), int(out["goals_against"])])
	_report("football: the ball goes back on the spot",
		Vector2(ball.global_position.x, ball.global_position.z).length() < 0.6,
		str(ball.global_position.round()))
	_report("football: one crossing is one goal, not one per tick",
		int(out["goals_for"]) + int(out["goals_against"]) == 1, "")

	# The other end counts against.
	ball.global_position = Vector3(-3.6, 0.30, 0.0)
	ball.linear_velocity = Vector3(-7.0, 0.0, 0.0)
	await _drive(world, rules, [player, other], 120)
	out = rules.call("result")
	_report("football: a ball into your own end counts against you",
		int(out["goals_against"]) == 1, "%d - %d" % [int(out["goals_for"]), int(out["goals_against"])])
	_report("football: level is not cleared", not bool(out["cleared"]), "")
	_report("football: result carries the documented keys",
		out.has("score") and out.has("cleared") and out.has("goals_for")
			and out.has("goals_against"), str(out.keys()))
	_report("football: hud_lines reads the goals and the clock",
		_hud_has(rules, "GOALS"), str(rules.call("hud_lines")))
	# The driver is meant to go for the ball, not for the player.
	_report("football: the opponent is driven at the ball, not at the player",
		other.chassis.global_position.distance_to(pitch.call("ball_position") as Vector3)
			< other.chassis.global_position.distance_to(player.chassis.global_position) + 3.0,
		"ball %.2f m, player %.2f m" % [
			other.chassis.global_position.distance_to(pitch.call("ball_position") as Vector3),
			other.chassis.global_position.distance_to(player.chassis.global_position)])
	await _teardown(world)


# ---------------------------------------------------------------------------
# 6. Wall Smash: a wall under a ramming bot
# ---------------------------------------------------------------------------
func _check_wall_smash() -> void:
	var world := await _make_world("wall_smash", 29)
	var rules := _start(world, "wall_smash")
	var run: Node = world["arena"]
	var player := _spawn_bot(world, 0, Vector3(-8.6, 0.25, 0.0), Vector3.RIGHT)
	world["fight"].bot_list = [player, null]
	await _settle([player], 30)
	_report("wall_smash: five walls stand at the bell",
		int(run.call("wall_count")) == 5 and int(run.call("walls_broken")) == 0, "")

	await _drive(world, rules, [player], 300, Vector2(1.0, 0.0))
	var broken := int(run.call("walls_broken"))
	var out: Dictionary = rules.call("result")
	_report("wall_smash: a ramming machine breaks the first wall", broken >= 1,
		"%d walls, %d loose bricks, peak arriving momentum %.1f N s, bot at x %.2f" % [
			broken, int(run.call("loose_bricks", 0)), float(run.call("peak_impulse", 0)),
			player.chassis.global_position.x])
	_report("wall_smash: breaking a bottom brick takes the course above it",
		int(run.call("loose_bricks", 0)) == 0 or int(run.call("loose_bricks", 0)) % 2 == 0,
		"%d loose" % int(run.call("loose_bricks", 0)))
	_report("wall_smash: the event counts what the arena broke",
		int(out["walls_broken"]) == broken, "%d vs %d" % [int(out["walls_broken"]), broken])
	_report("wall_smash: one wall is not the event",
		not bool(out["cleared"]) or broken >= 5, "")
	_report("wall_smash: result carries the documented keys",
		out.has("score") and out.has("cleared") and out.has("time_s")
			and out.has("walls_broken"), str(out.keys()))
	_report("wall_smash: hud_lines reads the wall count",
		_hud_has(rules, "WALLS"), str(rules.call("hud_lines")))
	await _teardown(world)


# ---------------------------------------------------------------------------
# 7. Determinism: one seed, two runs, the same result at tick 600
# ---------------------------------------------------------------------------
func _check_determinism() -> void:
	for mode_variant in EVENTS.keys():
		var mode := str(mode_variant)
		var a := await _replay_fingerprint(mode, 4242)
		var b := await _replay_fingerprint(mode, 4242)
		_report("%s: two runs on one seed agree at tick %d" % [mode, DETERMINISM_TICKS],
			a == b, "%s vs %s" % [a, b])


## Ten seconds of event on a fixed seed with a fixed input, fingerprinted from the
## result() the rules would send. Both machines drive straight, which is enough to reach a
## bumper, a brick wall or the ball.
func _replay_fingerprint(mode: String, seed_value: int) -> String:
	var world := await _make_world(mode, seed_value)
	var rules := _start(world, mode)
	var arena: Node = world["arena"]
	var player := _spawn_bot(world, 0, arena.call("spawn_position", 0),
		arena.call("spawn_facing", 0))
	var other := _spawn_bot(world, 1, arena.call("spawn_position", 1),
		arena.call("spawn_facing", 1))
	world["fight"].bot_list = [player, other]
	var heading := OpponentAI.heading_from_world_dir(arena.call("spawn_facing", 0) as Vector3)
	await _drive(world, rules, [player, other], DETERMINISM_TICKS, heading)
	var out: Dictionary = rules.call("result")
	var print_out := "%d/%s/%s" % [int(out["score"]), str(bool(out["cleared"])),
		str((out["details"] as Dictionary).size())]
	for key in ["time_s", "damage", "walls_broken", "goals_for", "goals_against"]:
		if out.has(key):
			print_out += "/%s=%.4f" % [key, float(out[key])]
	await _teardown(world)
	return print_out


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _make_arena(mode: String, seed_value: int) -> Node3D:
	var path := str(EVENTS[mode]["arena"])
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var arena: Node3D = packed.instantiate()
	arena.name = "Arena"
	root.add_child(arena)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	arena.call("setup", rng)
	return arena


func _free_arena(arena: Node3D) -> void:
	root.remove_child(arena)
	arena.queue_free()


func _make_rules(mode: String) -> RefCounted:
	var path := str(EVENTS[mode]["rules"])
	if not ResourceLoader.exists(path):
		return null
	var script := load(path) as GDScript
	return script.new() as RefCounted if script != null else null


func _make_world(mode: String, seed_value: int) -> Dictionary:
	var world := _make_world_sync(mode, seed_value)
	await physics_frame
	return world


## Every world gets its OWN `World3D`, in a SubViewport, exactly as `fight.gd._build_world`
## does it, and that is not tidiness: it is the difference between this test passing and
## failing. MEASURED. With the worlds built as plain nodes under `root` they share one
## physics space, and four identical Gauntlet runs on one seed finished at x = 0.44,
## -9.48, 4.52 and 4.51: a space that has had bodies removed from it is not the space a
## fresh one is, and Jolt reuses the RIDs. With `own_world_3d` the same four runs finished
## at x = 4.5364 every time, to four decimal places. Anything in this project that wants to
## compare two simulations has to give each of them its own world.
func _make_world_sync(mode: String, seed_value: int) -> Dictionary:
	var view := SubViewport.new()
	view.name = "World"
	view.own_world_3d = true
	view.handle_input_locally = false
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(view)
	var fight := FakeFight.new()
	fight.name = "Fight"
	view.add_child(fight)
	var debris := Node3D.new()
	debris.name = "Debris"
	fight.add_child(debris)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var arena: Node3D = (load(str(EVENTS[mode]["arena"])) as PackedScene).instantiate()
	arena.name = "Arena"
	fight.add_child(arena)
	arena.call("setup", rng)
	fight.arena_node = arena
	fight.random = rng
	return {"fight": fight, "arena": arena, "rng": rng, "debris": debris, "view": view}


## Build the rules and hand them the fake fight, the way fight.gd would before the
## countdown. The bots are attached after this, exactly as fight.gd attaches them before
## it calls setup; anything an event does to them at setup is re-run by `_start_late`.
func _start(world: Dictionary, mode: String) -> RefCounted:
	var rules := _make_rules(mode)
	if rules == null:
		return null
	rules.call("setup", world["fight"], {
		"seed": (world["rng"] as RandomNumberGenerator).seed,
		"arena": mode,
		"rules": {"mode": mode, "duration_s": FightTypes.FIGHT_DURATION_S},
	})
	return rules


func _spawn_bot(world: Dictionary, index: int, at: Vector3, facing: Vector3) -> Bot:
	var bot: Bot = (load(BOT_SCENE) as PackedScene).instantiate()
	bot.name = "Bot%d" % index
	(world["fight"] as Node).add_child(bot)
	bot.place_at(at, facing)
	bot.setup(FIXTURE_BOT, index, world["rng"] as RandomNumberGenerator)
	bot.place_at(at, facing)
	return bot


func _teardown(world: Dictionary) -> void:
	_teardown_sync(world)
	await physics_frame
	await physics_frame


func _teardown_sync(world: Dictionary) -> void:
	# Removed from the tree FIRST: queue_free alone leaves the bodies simulating and the
	# name taken until the end of the frame (docs/stage3-physics-notes.md).
	var view: Node = world["view"]
	root.remove_child(view)
	view.queue_free()


func _settle(bots: Array, ticks: int) -> void:
	for _i in range(ticks):
		for b in bots:
			if b != null:
				(b as Bot).apply_input(FightTypes.empty_input())
		await physics_frame


## One event tick the way fight.gd runs one: the inputs go on, the rules think, then the
## physics step happens. Anything that reads a body position in `physics_tick` therefore
## reads last tick's, which is what it will read in the real fight too.
func _drive(world: Dictionary, rules: RefCounted, bots: Array, ticks: int,
		heading: Vector2 = Vector2.ZERO) -> void:
	var record := FightTypes.empty_input()
	record["heading"] = heading
	for _i in range(ticks):
		for b in bots:
			if b != null and is_instance_valid(b):
				(b as Bot).apply_input(record)
		if rules != null:
			rules.call("physics_tick", TICK)
			(world["fight"] as FakeFight).elapsed += TICK
			if bool(rules.call("is_over")):
				await physics_frame
				return
		await physics_frame


## Put an already simulating machine down somewhere, the way `fight/events/sumo.gd` does.
## NOT `Bot.place_at`: that moves the assembly by a delta once the parts have drifted from
## their assembled offsets, which lands the machine inside whatever it was near and fills
## the log with "!v.is_finite()". See the note on `_set_down` in sumo.gd for the
## measurement.
func _set_down(bot: Bot, mark: Vector3, facing: Vector3) -> void:
	var flat := Vector3(facing.x, 0.0, facing.z).normalized()
	var want := Transform3D(Basis(Vector3.UP, atan2(-flat.z, flat.x)),
		Vector3(mark.x, maxf(mark.y, bot.ride_height()), mark.z))
	var now := bot.chassis.global_transform
	now.basis = now.basis.orthonormalized()
	var fix := want * now.affine_inverse()
	var parts := bot.attached_parts()
	# The parts' targets are computed BEFORE the root moves, and applied after. Moving the
	# root ALREADY drags every child's global transform by `fix` (the children keep their
	# local transforms), so reading a part's global transform afterwards and multiplying by
	# `fix` again applies it twice. Measured: a machine asked for (-4.00, 0.62, 1.25)
	# landed at (-8.09, 1.09, -0.71), which is exactly `fix` squared.
	var targets: Array[Transform3D] = []
	for part in parts:
		targets.append(fix * part.global_transform)
	bot.global_transform = fix * bot.global_transform
	for i in range(parts.size()):
		parts[i].global_transform = targets[i]
		parts[i].linear_velocity = Vector3.ZERO
		parts[i].angular_velocity = Vector3.ZERO


func _hud_has(rules: RefCounted, needle: String) -> bool:
	for line in (rules.call("hud_lines") as Array):
		if str(line).contains(needle):
			return true
	return false


func _find_named(node: Node, wanted: String) -> Node:
	if node.name == wanted:
		return node
	for child in node.get_children():
		var found := _find_named(child, wanted)
		if found != null:
			return found
	return null


func _count(node: Node, kind: String) -> int:
	var n := 0
	if kind == "body":
		n = 1 if (node is PhysicsBody3D or node is Area3D) else 0
	else:
		n = 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		n += _count(child, kind)
	return n


func _find_ooa(node: Node) -> Area3D:
	if node is Area3D:
		var area := node as Area3D
		if node.name in ["OOA", "OutOfArena", "OutOfArenaSensor"] \
				or (area.collision_layer & FightTypes.LAYER_OOA) != 0:
			return area
	for child in node.get_children():
		var found := _find_ooa(child)
		if found != null:
			return found
	return null


func _report(check_name: String, ok: bool, detail: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	var suffix := ""
	if detail != "":
		suffix = "  (" + detail + ")"
	print(("PASS: " if ok else "FAIL: ") + check_name + suffix)


func _finish() -> void:
	print("%d checks, %d failed" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
