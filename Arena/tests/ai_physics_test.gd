extends SceneTree
## The opponent AI, measured IN THE PHYSICS WORLD (docs/wave-f-f4-notes.md).
##   Godot --headless --path Arena --script tests/ai_physics_test.gd
##
## Why this file exists. Wave G proved its skill tiers in a kinematic toy arena inside
## `ai_test.gd`: a heading, a turn rate and a circle for a hazard. The owner then played
## the build on his phone and said the enemy AI was "really stupid, driving straight into
## the spikes". Both things were true at once, because the toy has no Jolt, no wheels, no
## momentum and no wall to be shoved into, and a machine that never quite arrives where it
## steered is a machine that drives into things the toy said it avoided.
##
## So every number below comes from real arenas out of `Arena/arena/*.tscn`, real machines
## out of `res://bot/bot.tscn`, and the same world-spawning shape `physics_test.gd` and
## `events_test.gd` use. It is slower than the toy and it is the one that counts.
##
## THE BAR (the owner's verdict, 2026-09-16: no tier may ever look stupid):
##   * zero unpushed hazard entries at EVERY tier in the Yard
##   * at most one at every tier in the Grinder, whose two discs are always live and sit
##     where a shoved machine ends up
## and, so that "it avoids things" never quietly becomes "it does nothing":
##   * every tier still drives the floor, still gets in close, and still lands hits
##
## UNPUSHED is the whole measurement. A machine that is rammed onto a grinder has not made
## a mistake, it has been beaten, and counting that against the driver would only teach the
## test to reward a driver that never engages. So an entry counts only when the two
## machines have been out of contact for CONTACT_FREE_TICKS beforehand.

const BOT_SCENE := "res://bot/bot.tscn"
const OpponentAIScript := preload("res://ai/opponent_ai.gd")
const NoviceScript := preload("res://ai/novice_driver.gd")

## The two arenas the brief names, and how big the thing a `danger_positions()` entry
## stands for actually is in each (the helper publishes bare points, with no radius: see
## docs/wave-f-f4-notes.md). The Yard's patch is 1.6 m square, so 0.8 m; a grinder disc is
## 0.55 m, and 0.7 m allows for the wheel that reaches it before the chassis centre does.
## `live` names an arena getter that says whether the hazard is BITING right now, or "" for
## an arena whose hazards never stop. It matters: `danger_positions()` lists the Yard's
## patch from 1.5 s before it rises, so counting membership of that list as a hazard entry
## would count a machine that crossed the middle of the floor during the down phase and
## left in good time -- which is driving, not stupidity. What is being counted here is
## machines ON RISEN SPIKES and ON SPINNING DISCS.
const ARENAS := {
	"yard": {"scene": "res://arena/yard.tscn", "hazard_r": 0.80, "allowed": 0,
		"live": "spikes_risen"},
	"grinder": {"scene": "res://arena/grinder.tscn", "hazard_r": 0.70, "allowed": 1,
		"live": ""},
}

## 60 s of fight, as the brief asks. At 60 Hz that is 3600 real physics ticks with two
## real machines in them, which is about eight seconds of headless wall clock each.
const FIGHT_S := 60.0
const FIGHT_TICKS := int(FIGHT_S * 60.0)
## Two seeds per pairing. The kinematic sweep in ai_test.gd is where the statistics live
## (a hundred fights a pairing); this is where the truth lives, and it costs real time.
const SEEDS := [20260916, 771]

## Chassis centre to chassis centre: the machines are 0.9 m long, so this is contact plus
## the slack a shove needs.
const CONTACT_M := 1.15
## How long the machines have to have been apart for a hazard entry to be the driver's own
## fault. Half a second is long enough that a shove cannot still be carrying it and short
## enough that the driver does not get a free pass for the whole fight after one clinch.
const CONTACT_FREE_TICKS := 30
## How near a wall counts as wall time. About a chassis: close enough that the machine is
## working the boards rather than the floor.
const WALL_NEAR_M := 0.6

## Both machines are the Stage 3 wedge / flipper / 4wd, so the only difference between the
## two sides of any fight below is the driver. Same build arenas_test and physics_test use.
const FIXTURE_BOT := {
	"id": "bot", "name": "Tinribs", "controller": "ai",
	"chassis": "wedge", "drive": "4wd", "weapon": "flipper",
	"utility": ["srimech"],
	"armour": {
		"front": {"material": "steel", "thickness": 2},
		"sides": {"material": "steel", "thickness": 2},
		"rear": {"material": "steel", "thickness": 2},
		"top": {"material": "steel", "thickness": 2},
	},
	"damage": {
		"wheels": [1.0, 1.0, 1.0, 1.0], "weapon": 1.0,
		"armour": {"front": 1.0, "sides": 1.0, "rear": 1.0, "top": 1.0},
		"drive": 1.0, "core": 1.0,
	},
}

var _checks := 0
var _failures := 0


## Headless Godot steps physics in REAL TIME unless it is told not to: measured, forty
## 60 s fights took forty minutes of wall clock for seven minutes of CPU. `--fixed-fps`
## turns that off ("disables real-time synchronisation") and it also pins the delta to
## exactly 1/60, which is stricter than the default, not looser. The suite runner does not
## pass it, so this script runs itself once in a child process that does -- the same
## child-process shape physics_test.gd uses for its determinism sample.
const CHILD_FLAG := "--ai-physics-child"


func _initialize() -> void:
	if OS.get_cmdline_user_args().has(CHILD_FLAG):
		await _run()
	else:
		_run_in_child()


func _run_in_child() -> void:
	var out: Array = []
	var args := PackedStringArray([
		"--headless", "--fixed-fps", "60",
		"--path", ProjectSettings.globalize_path("res://"),
		"--script", "tests/ai_physics_test.gd", "--", CHILD_FLAG,
	])
	var code := OS.execute(OS.get_executable_path(), args, out, true)
	for line_variant in out:
		print(str(line_variant).strip_edges(false, true))
	if code != 0 and out.is_empty():
		print("FAIL  ai physics: the child process would not run (exit %d)" % code)
	quit(code)


func _run() -> void:
	print("Roboteer AI physics test, Godot ", Engine.get_version_info()["string"],
		", engine ", ProjectSettings.get_setting("physics/3d/physics_engine"),
		", ", Engine.physics_ticks_per_second, " Hz")
	if not ResourceLoader.exists(BOT_SCENE):
		print("SKIP: ", BOT_SCENE, " is missing")
		quit(0)
		return

	for arena_variant in ARENAS.keys():
		await _check_arena(str(arena_variant))
	_finish()


# ---------------------------------------------------------------------------
# The measurement
# ---------------------------------------------------------------------------
func _check_arena(arena_id: String) -> void:
	var profile: Dictionary = ARENAS[arena_id]
	var allowed := int(profile["allowed"])
	print("")
	print("--- %s ---------------------------------------------------------" % arena_id)
	print("  %-13s %-9s %6s %7s %7s %7s %6s %6s"
		% ["tier", "against", "hazard", "pushed", "driven", "walltime", "hits", "close"])

	var worst := {}
	var driven := {}
	var landed := {}
	for id in OpponentAIScript.SKILL_IDS:
		worst[id] = 0
		driven[id] = 0.0
		landed[id] = 0
		for against in ["novice", OpponentAIScript.SKILL_MASTERS]:
			for seed_value in SEEDS:
				var run := await _fight(arena_id, str(id), str(against), int(seed_value))
				print("  %-13s %-9s %6d %7d %7.1f %7.1f%% %6d %5.0f%%"
					% [id, against, int(run["hazard_unpushed"]), int(run["hazard_pushed"]),
						float(run["driven_m"]), float(run["wall_pct"]), int(run["hits"]),
						float(run["close_pct"])])
				worst[id] = maxi(int(worst[id]), int(run["hazard_unpushed"]))
				driven[id] = float(driven[id]) + float(run["driven_m"])
				landed[id] = int(landed[id]) + int(run["hits"])

	for id in OpponentAIScript.SKILL_IDS:
		_report("%s: %d unpushed hazard entries in %s, at most %d allowed"
			% [id, int(worst[id]), arena_id, allowed], int(worst[id]) <= allowed, "")
		# The other half of the bar: a driver that scores zero by parking in a corner has
		# not passed anything. Four 60 s fights, so 40 m is a machine that is barely idling.
		_report("%s: still drives the floor in %s (%.0f m over four fights)"
			% [id, arena_id, float(driven[id])], float(driven[id]) > 40.0, "")
		_report("%s: still lands hits in %s (%d over four fights)"
			% [id, arena_id, int(landed[id])], int(landed[id]) > 0, "")


## One seeded 60 s fight. `left` is the driver under test and every number returned is
## about it; `right` is whatever it is being made to fight.
func _fight(arena_id: String, left: String, right: String, seed_value: int) -> Dictionary:
	var profile: Dictionary = ARENAS[arena_id]
	var world := _make_world(str(profile["scene"]), seed_value)
	var arena: Node3D = world["arena"]
	var rng: RandomNumberGenerator = world["rng"]

	var me := _spawn_bot(world, 0, arena.call("spawn_position", 0) as Vector3,
		arena.call("spawn_facing", 0) as Vector3)
	var foe := _spawn_bot(world, 1, arena.call("spawn_position", 1) as Vector3,
		arena.call("spawn_facing", 1) as Vector3)
	# Let the machines settle on their wheels before anyone drives: a bot spawned in the
	# air and driven on tick one is a bot that skates, and none of these numbers would be
	# about the driver.
	for _i in range(30):
		me.apply_input(FightTypes.empty_input())
		foe.apply_input(FightTypes.empty_input())
		await physics_frame

	# The drivers are built AFTER the arena has drawn its hazard phase, which is the order
	# fight.gd builds them in, so this fight's stream is the fight's.
	var driver_me := _driver(rng, left)
	var driver_foe := _driver(rng, right)

	var hazard_r := float(profile["hazard_r"])
	var live_method := str(profile["live"])
	var half := float(arena.call("arena_half_extent"))
	var unpushed := 0
	var pushed := 0
	var was_in := false
	var apart_for := CONTACT_FREE_TICKS
	var driven_m := 0.0
	var wall_ticks := 0
	var close_ticks := 0
	var hits := 0
	var last_at: Vector3 = me.chassis.global_position
	var foe_left := FightRules.condition_total(foe.condition())

	for tick in FIGHT_TICKS:
		var ctx := _context(arena, tick, half)
		# fight.gd's fixed order: the first driver thinks, then the second.
		var input_me: Dictionary = driver_me.think(me, foe, ctx)
		var input_foe: Dictionary = driver_foe.think(foe, me, ctx)
		me.apply_input(input_me)
		foe.apply_input(input_foe)
		await physics_frame

		var at: Vector3 = me.chassis.global_position
		var their_at: Vector3 = foe.chassis.global_position
		driven_m += Vector2(at.x - last_at.x, at.z - last_at.z).length()
		last_at = at

		var gap := Vector2(at.x - their_at.x, at.z - their_at.z).length()
		if gap <= CONTACT_M:
			apart_for = 0
			close_ticks += 1
		else:
			apart_for += 1
		if maxf(0.0, half - maxf(absf(at.x), absf(at.z))) <= WALL_NEAR_M:
			wall_ticks += 1

		# Hazard entries, from the arena's OWN read of what is live this tick, so the Yard's
		# patch counts only while it is risen (or about to be) and the Grinder's discs
		# always do. Anything else would be the test inventing its own hazards.
		var in_now := false
		if live_method == "" or bool(arena.call(live_method)):
			for entry in _danger_positions(arena):
				var to_hazard: Vector3 = entry
				if Vector2(at.x - to_hazard.x, at.z - to_hazard.z).length() <= hazard_r:
					in_now = true
					break
		if in_now and not was_in:
			# Upside down is not driving. A machine that has been thrown onto a hazard has
			# been beaten, not fooled, and it cannot steer while it is on its back: the
			# driver is pressing the srimech, which is the right thing to be doing.
			if apart_for >= CONTACT_FREE_TICKS and not me.is_inverted():
				unpushed += 1
				# Say where and how, every time, because "the AI drove into the spikes" is
				# the report this whole file exists to answer and a bare count cannot.
				print("    ENTRY %s vs %s seed %d tick %d at (%.2f, %.2f) speed %.2f y %.2f%s, %d ticks since contact"
					% [left, right, seed_value, tick, at.x, at.z,
						me.chassis.linear_velocity.length(), at.y,
						" INVERTED" if me.is_inverted() else "", apart_for])
				print("      rise_in %.2f, arena called %d things dangerous, intent %s"
					% [float(ctx.get("spike_rise_in_s", -1.0)),
						(ctx.get("hazards", []) as Array).size(),
						str(driver_me.get("_intent"))])
			else:
				pushed += 1
		was_in = in_now

		var now_left := FightRules.condition_total(foe.condition())
		if now_left < foe_left - 0.0001:
			hits += 1
		foe_left = now_left

	var out := {
		"hazard_unpushed": unpushed,
		"hazard_pushed": pushed,
		"driven_m": driven_m,
		"wall_pct": 100.0 * float(wall_ticks) / float(FIGHT_TICKS),
		"close_pct": 100.0 * float(close_ticks) / float(FIGHT_TICKS),
		"hits": hits,
	}
	await _teardown(world)
	return out


## The context fight.gd builds, plus `arena_half_extent`, which fight.gd does not publish
## and which the driver would otherwise have to infer (docs/wave-f-f4-notes.md).
func _context(arena: Node3D, tick: int, half: float) -> Dictionary:
	var ctx := {
		"tick": tick,
		"spike_centre": arena.call("spike_patch_centre"),
		"spike_rise_in_s": float(arena.call("seconds_to_spike_rise")),
		"arena_half_extent": half,
		"phase": FightTypes.PHASE_OPEN,
		"time_left_s": FIGHT_S - float(tick) / 60.0,
	}
	var helpers: Variant = arena.call("hazard_helpers")
	if helpers is Dictionary:
		ctx["hazard"] = helpers
		ctx["hazards"] = (helpers as Dictionary).get("danger_positions", [])
	return ctx


func _danger_positions(arena: Node3D) -> Array:
	var helpers: Variant = arena.call("hazard_helpers")
	if not (helpers is Dictionary):
		return []
	var listed: Variant = (helpers as Dictionary).get("danger_positions", [])
	return listed as Array if listed is Array else []


func _driver(rng: RandomNumberGenerator, id: String) -> Object:
	if id == "novice":
		return NoviceScript.new()
	return OpponentAIScript.new(rng, OpponentAIScript.MODE_NORMAL, id,
		OpponentAIScript.TEMPERAMENT_BRAWLER)


# ---------------------------------------------------------------------------
# World helpers, the same shape physics_test.gd and events_test.gd use
# ---------------------------------------------------------------------------
func _make_world(scene_path: String, seed_value: int) -> Dictionary:
	var fight := Node3D.new()
	fight.name = "Fight"
	root.add_child(fight)
	var debris := Node3D.new()
	debris.name = "Debris"
	fight.add_child(debris)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var arena: Node3D = (load(scene_path) as PackedScene).instantiate()
	arena.name = "Arena"
	fight.add_child(arena)
	arena.call("setup", rng)

	return {"fight": fight, "arena": arena, "rng": rng, "debris": debris}


func _spawn_bot(world: Dictionary, index: int, at: Vector3, facing: Vector3) -> Bot:
	var bot: Bot = (load(BOT_SCENE) as PackedScene).instantiate()
	bot.name = "Bot%d" % index
	(world["fight"] as Node3D).add_child(bot)
	bot.place_at(at, facing)
	var config := FIXTURE_BOT.duplicate(true)
	config["id"] = "bot-%d" % index
	bot.setup(config, index, world["rng"] as RandomNumberGenerator)
	bot.place_at(at, facing)
	return bot


func _teardown(world: Dictionary) -> void:
	# Out of the tree FIRST: queue_free alone leaves the bodies simulating and the name
	# taken until the end of the frame, which is enough to make the next world start from
	# a different state (physics_test.gd, same comment, same reason).
	var fight: Node3D = world["fight"]
	root.remove_child(fight)
	fight.queue_free()
	await physics_frame
	await physics_frame


# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------
func _report(label: String, ok: bool, detail: String) -> void:
	_checks += 1
	var suffix := "" if detail == "" else " (%s)" % detail
	if ok:
		print("PASS  ", label, suffix)
	else:
		_failures += 1
		printerr("FAIL  ", label, suffix)
		print("FAIL  ", label, suffix)


func _finish() -> void:
	print("")
	if _failures == 0:
		print("PASS  ai physics: %d checks, 0 failures" % _checks)
		quit(0)
	else:
		print("FAIL  ai physics: %d checks, %d failures" % [_checks, _failures])
		quit(1)
