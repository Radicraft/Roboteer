extends SceneTree
## Headless test for the Stage 5 arenas (docs/stage5-spec.md §3, agent A5).
##   Godot --headless --path Arena --script tests/arenas_test.gd
## Exit code 0 = all PASS. Headless Godot still runs Jolt, so every hazard check below is
## a real simulation with the real Bot from res://bot/bot.tscn.
##
## What it asserts, per the spec:
##   * every arena instantiates and exposes the fight.gd contract
##   * setup(rng) is deterministic: two builds on one seed produce the same 90 s hazard
##     timeline, and two DIFFERENT seeds do not (so the seed is actually being used)
##   * every hazard damages a bot parked on it and leaves a bot parked away from it alone
##   * the Drop Zone's pit is part of the out-of-arena sensor
##   * the Furnace's conveyor carries a body, and the Coliseum's discs turn one
##   * both spawn marks are on the floor, inside the walls and clear of every hazard
##   * body and mesh counts are inside budget

const BOT_SCENE := "res://bot/bot.tscn"
const ARENAS := {
	"yard": "res://arena/yard.tscn",
	"grinder": "res://arena/grinder.tscn",
	"drop_zone": "res://arena/drop_zone.tscn",
	"furnace": "res://arena/furnace.tscn",
	"crush": "res://arena/crush.tscn",
	"coliseum": "res://arena/coliseum.tscn",
}

## Budget per arena: physics bodies plus areas, and visual meshes. The Coliseum is the
## worst case (every hazard plus 32 banner meshes) and it has to fit inside both.
const BODY_BUDGET := 30
const MESH_BUDGET := 120

## 90 seconds of fight, the duration the determinism claim has to hold over.
const TIMELINE_TICKS := 90 * FightTypes.TICK_HZ
const TIMELINE_SAMPLE := 5

## The Stage 3 fixture (docs/bridge-spec.md), both bots wedge / flipper / 4wd.
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
var _ooa_bodies: Array = []


func _initialize() -> void:
	await _run()


func _run() -> void:
	print("Roboteer arenas test, Godot ", Engine.get_version_info()["string"],
		", engine ", ProjectSettings.get_setting("physics/3d/physics_engine"))
	if not ResourceLoader.exists(BOT_SCENE):
		print("SKIP: ", BOT_SCENE, " is missing")
		quit(0)
		return
	_check_contract()
	_check_budgets()
	_check_determinism()
	await _check_spawn_marks()
	await _check_grinder()
	await _check_furnace_flames()
	await _check_conveyor()
	await _check_crush()
	await _check_pit_is_out_of_arena()
	await _check_pit_opens()
	await _check_turntables()
	await _check_coliseum_spikes()
	_check_endgame_escalation()
	_finish()


# ---------------------------------------------------------------------------
# 1. The contract fight.gd reads
# ---------------------------------------------------------------------------
func _check_contract() -> void:
	for id_variant in ARENAS.keys():
		var id := str(id_variant)
		var arena := _make_arena(id, 1)
		if arena == null:
			_report("%s instantiates" % id, false, "scene missing")
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
		_report("%s exposes the whole fight.gd contract" % id, ok, "")
		_report("%s reports its own id" % id, str(arena.call("arena_id")) == id,
			"got '%s'" % str(arena.call("arena_id")))

		var helpers: Dictionary = arena.call("hazard_helpers")
		var helper_ok := helpers.has("next_danger_in_s") \
			and helpers.has("danger_positions") and helpers.has("safe_positions")
		_report("%s hazard_helpers has the three AI keys" % id, helper_ok, str(helpers.keys()))
		_report("%s offers somewhere safe to go" % id,
			(helpers.get("safe_positions", []) as Array).size() > 0, "")

		# Every arena finds its out-of-arena sensor the way fight.gd does.
		_report("%s carries an OOA Area3D on layer 5" % id,
			_find_ooa(arena) != null, "")
		# And G1's render setup, which is what makes it look like the same game.
		_report("%s carries the G1 render setup" % id,
			arena.get_node_or_null("WorldEnvironment") != null
			and arena.get_node_or_null("KeyLight") != null
			and arena.get_node_or_null("FillLight") != null
			and arena.get_node_or_null("FloorProbe") != null, "")
		_free_arena(arena)


func _check_budgets() -> void:
	for id_variant in ARENAS.keys():
		var id := str(id_variant)
		var arena := _make_arena(id, 1)
		if arena == null:
			continue
		var bodies := _count(arena, "body")
		var meshes := _count(arena, "mesh")
		_report("%s body count is inside budget" % id, bodies <= BODY_BUDGET,
			"%d bodies and areas, budget %d" % [bodies, BODY_BUDGET])
		_report("%s mesh count is inside budget" % id, meshes <= MESH_BUDGET,
			"%d meshes, budget %d" % [meshes, MESH_BUDGET])
		_free_arena(arena)


# ---------------------------------------------------------------------------
# 2. Determinism: the hazard timeline is the seed's, not the clock's
# ---------------------------------------------------------------------------
## The arena is driven by hand here rather than by the engine, so 90 seconds of hazard
## timeline costs no wall clock at all. Nothing else is stepped: with no bots in the
## world every hazard area is empty, so the tick reduces to exactly the state machine
## the determinism claim is about.
func _check_determinism() -> void:
	for id_variant in ARENAS.keys():
		var id := str(id_variant)
		var a := _timeline(id, 424242)
		var b := _timeline(id, 424242)
		var c := _timeline(id, 999983)
		_report("%s: one seed, two builds, identical 90 s timeline" % id, a == b,
			"%d chars of timeline" % a.length())
		if id == "grinder":
			# The Grinder's cut never stops, so its timeline is the same on any seed by
			# design; the seed only moves the disc's visual phase.
			_report("%s: the cut is always live, seed or no seed" % id, a == c, "")
		else:
			_report("%s: a different seed is a different timeline" % id, a != c, "")


func _timeline(id: String, seed_value: int) -> String:
	var arena := _make_arena(id, seed_value)
	if arena == null:
		return ""
	arena.set_physics_process(false)
	var out := PackedStringArray()
	for tick in range(TIMELINE_TICKS):
		arena.call("_physics_process", 1.0 / float(FightTypes.TICK_HZ))
		if tick % TIMELINE_SAMPLE == 0:
			out.append(_sample(arena))
	_free_arena(arena)
	return "".join(out)


## A compact per-tick fingerprint of every moving hazard part, read only through the
## public API so a subclass cannot pass this by accident.
func _sample(arena: Node) -> String:
	var helpers: Dictionary = arena.call("hazard_helpers")
	var s := "%d" % int(round(float(helpers.get("next_danger_in_s", 0.0)) * 10.0))
	s += "1" if bool(arena.call("spikes_risen")) else "0"
	if arena.has_method("pit_open"):
		s += "1" if bool(arena.call("pit_open")) else "0"
		s += "1" if bool(arena.call("warning_lit")) else "0"
	if arena.has_method("jets_firing"):
		s += "1" if bool(arena.call("jets_firing")) else "0"
	if arena.has_method("rams_extended"):
		s += "%d" % int(round(float(arena.call("rams_extended")) * 20.0))
	return s + ","


# ---------------------------------------------------------------------------
# 3. Spawn marks: on the floor, inside the walls, clear of every hazard
# ---------------------------------------------------------------------------
func _check_spawn_marks() -> void:
	for id_variant in ARENAS.keys():
		var id := str(id_variant)
		var world := await _make_world(id, 7)
		var arena: Node3D = world["arena"]
		var half := float(arena.call("arena_half_extent"))
		var inside := true
		for team in 2:
			var p: Vector3 = arena.call("spawn_position", team)
			if absf(p.x) > half - 0.6 or absf(p.z) > half - 0.6 or p.y <= 0.0:
				inside = false
		_report("%s: both spawn marks are inside the walls" % id, inside,
			"%s and %s in a %.1f m arena" % [str(arena.call("spawn_position", 0)),
				str(arena.call("spawn_position", 1)), half * 2.0])
		var apart := (arena.call("spawn_position", 0) as Vector3).distance_to(
			arena.call("spawn_position", 1) as Vector3)
		_report("%s: the spawn marks are at least 4 m apart" % id, apart >= 4.0,
			"%.2f m" % apart)

		# The honest version of "on the floor": drop both bots on their marks, let them
		# settle, and check they are upright, still there, undamaged and not out.
		_ooa_bodies.clear()
		arena.connect("body_out", _on_body_out)
		var bots: Array = []
		for team in 2:
			bots.append(_spawn_bot(world, team, arena.call("spawn_position", team),
				arena.call("spawn_facing", team)))
		var before := _total_condition(bots[0]) + _total_condition(bots[1])
		await _settle(bots, 90)
		var settled := true
		var detail := ""
		for b in bots:
			var bot: Bot = b
			var pos: Vector3 = bot.chassis.global_position
			if pos.y < 0.05 or pos.y > 1.0 or bot.is_inverted():
				settled = false
			detail += "%s " % str(pos.round())
		_report("%s: both bots settle upright on their marks" % id, settled, detail)
		_report("%s: no spawn mark is inside a hazard" % id,
			_total_condition(bots[0]) + _total_condition(bots[1]) >= before - 0.001
				and _ooa_bodies.is_empty(),
			"lost %.3f condition, %d OOA" % [
				before - _total_condition(bots[0]) - _total_condition(bots[1]),
				_ooa_bodies.size()])
		await _teardown(world)


# ---------------------------------------------------------------------------
# 4. The hazards, each one on a bot that is on it and a bot that is not
# ---------------------------------------------------------------------------
func _check_grinder() -> void:
	var world := await _make_world("grinder", 11)
	var arena: Node3D = world["arena"]
	var discs: Array = arena.call("grinder_positions")
	var on := _spawn_bot(world, 0, (discs[0] as Vector3) + Vector3.UP * 0.25, Vector3.RIGHT)
	var off := _spawn_bot(world, 1, Vector3(0.0, 0.25, 0.0), Vector3.LEFT)
	await _settle([on, off], 20)
	var on_before := _total_condition(on)
	var off_before := _total_condition(off)
	await _settle([on, off], 150)
	var touched := bool(arena.call("grinding"))
	_report("the grinder knows a bot is on it", touched, "")
	_report("a bot parked on a grinder is cut",
		_total_condition(on) < on_before - 0.01,
		"%.3f -> %.3f" % [on_before, _total_condition(on)])
	_report("a bot in the middle of the Grinder is untouched",
		is_equal_approx(_total_condition(off), off_before),
		"%.3f -> %.3f" % [off_before, _total_condition(off)])
	await _teardown(world)


func _check_furnace_flames() -> void:
	var world := await _make_world("furnace", 23)
	var arena: Node3D = world["arena"]
	# In the north jet's lane, and in the jet-free middle band.
	var in_jet := _spawn_bot(world, 0, Vector3(1.2, 0.25, -3.6), Vector3.RIGHT)
	var clear := _spawn_bot(world, 1, Vector3(2.2, 0.25, 0.4), Vector3.LEFT)
	await _settle([in_jet, clear], 30)
	# Wind the jet clock forward by hand so the test does not have to sit through up to
	# 12 seconds of a seeded gap. Nothing moves while it winds: the jets are off.
	_fast_forward(arena, 0.3)
	var jet_before := _total_condition(in_jet)
	var clear_before := _total_condition(clear)
	var fired := false
	var disrupted := false
	for _i in range(200):
		in_jet.apply_input(FightTypes.empty_input())
		clear.apply_input(FightTypes.empty_input())
		await physics_frame
		fired = fired or bool(arena.call("jets_firing"))
		disrupted = disrupted or in_jet.is_disrupted("drive")
	_report("the Furnace jets fire on their seeded timer", fired, "")
	_report("a bot in a flame jet burns",
		_total_condition(in_jet) < jet_before - 0.005,
		"%.3f -> %.3f" % [jet_before, _total_condition(in_jet)])
	_report("a second in the flame cuts the drive", disrupted, "")
	_report("a bot in the jet-free band is untouched",
		is_equal_approx(_total_condition(clear), clear_before),
		"%.3f -> %.3f" % [clear_before, _total_condition(clear)])
	await _teardown(world)


func _check_conveyor() -> void:
	var world := await _make_world("furnace", 31)
	var arena: Node3D = world["arena"]
	var belt_x := float(arena.call("belt_centre_x"))
	# Both bots frozen: this is about the floor moving, not about driving.
	var on := _spawn_bot(world, 0, Vector3(belt_x, 0.3, -2.0), Vector3.RIGHT)
	var off := _spawn_bot(world, 1, Vector3(1.5, 0.3, -2.0), Vector3.RIGHT)
	await _settle([on, off], 30)
	var on_start: Vector3 = on.chassis.global_position
	var off_start: Vector3 = off.chassis.global_position
	await _settle([on, off], 150)     # 2.5 s at 1.2 m/s is 3 m of belt
	var carried := on.chassis.global_position.z - on_start.z
	var drifted := (off.chassis.global_position - off_start).length()
	_report("the conveyor carries a bot downstream", carried > 1.0,
		"moved %.2f m along +Z in 2.5 s" % carried)
	_report("the floor beside the conveyor does not move a bot", drifted < 0.25,
		"drifted %.3f m" % drifted)
	await _teardown(world)


func _check_crush() -> void:
	var world := await _make_world("crush", 37)
	var arena: Node3D = world["arena"]
	var centres: Array = arena.call("ram_centres")
	var pinned := _spawn_bot(world, 0, (centres[0] as Vector3) + Vector3.UP * 0.25, Vector3.RIGHT)
	# The diagonal corridor, clear of both strokes at every phase.
	var clear := _spawn_bot(world, 1, Vector3(1.4, 0.25, -3.0), Vector3.LEFT)
	await _settle([pinned, clear], 30)
	_fast_forward(arena, 0.3)
	var pinned_before := _total_condition(pinned)
	var clear_before := _total_condition(clear)
	var pressed := 0.0
	for _i in range(260):
		pinned.apply_input(FightTypes.empty_input())
		clear.apply_input(FightTypes.empty_input())
		await physics_frame
		pressed = maxf(pressed, float(arena.call("rams_extended")))
	_report("a Crush ram completes its stroke", pressed > 0.95,
		"reached %.2f of the stroke" % pressed)
	_report("a bot in the stroke is flattened",
		_total_condition(pinned) < pinned_before - 0.05,
		"%.3f -> %.3f" % [pinned_before, _total_condition(pinned)])
	_report("the crush takes the top face first",
		pinned.condition()["armour"]["top"] < 1.0,
		"top plate %.3f" % float(pinned.condition()["armour"]["top"]))
	_report("a bot in the safe corridor is untouched",
		is_equal_approx(_total_condition(clear), clear_before),
		"%.3f -> %.3f" % [clear_before, _total_condition(clear)])
	await _teardown(world)


func _check_pit_is_out_of_arena() -> void:
	var world := await _make_world("drop_zone", 41)
	var arena: Node3D = world["arena"]
	_ooa_bodies.clear()
	arena.connect("body_out", _on_body_out)
	# On the shut cover: supported, and NOT out of the arena.
	var standing := _spawn_bot(world, 0, Vector3(0.0, 0.3, 0.0), Vector3.RIGHT)
	await _settle([standing], 60)
	_report("the shut pit cover is a floor", standing.chassis.global_position.y > 0.05
		and _ooa_bodies.is_empty(),
		"y = %.2f, %d OOA" % [standing.chassis.global_position.y, _ooa_bodies.size()])
	# Dropped into the pit: out, straight away.
	standing.place_at(Vector3(0.0, -1.2, 0.0), Vector3.RIGHT)
	await _settle([standing], 30)
	_report("the pit volume is part of the OOA sensor", not _ooa_bodies.is_empty(),
		"%d body_out signal(s)" % _ooa_bodies.size())
	await _teardown(world)


func _check_pit_opens() -> void:
	var world := await _make_world("drop_zone", 43)
	var arena: Node3D = world["arena"]
	var opens := float(arena.call("opens_at_s"))
	_report("the pit opens inside the seeded 30 to 60 s window",
		opens >= 30.0 and opens <= 60.0, "%.1f s" % opens)
	_ooa_bodies.clear()
	arena.connect("body_out", _on_body_out)
	var doomed := _spawn_bot(world, 0, Vector3(0.0, 0.3, 0.0), Vector3.RIGHT)
	await _settle([doomed], 40)
	# Wind the cover clock forward to just before the retraction rather than idling
	# through up to a minute of fight. The cover has not moved yet when this returns.
	_fast_forward(arena, 0.1)
	var warned := bool(arena.call("warning_lit"))
	var fell := false
	for _i in range(240):
		doomed.apply_input(FightTypes.empty_input())
		await physics_frame
		fell = fell or doomed.chassis.global_position.y < -0.4
	_report("the warning strip lights before the cover moves", warned, "")
	_report("the cover retracts and drops a bot standing on it", fell,
		"chassis y = %.2f" % doomed.chassis.global_position.y)
	_report("falling in the pit is out of the arena", not _ooa_bodies.is_empty(),
		"%d body_out signal(s)" % _ooa_bodies.size())
	await _teardown(world)


func _check_turntables() -> void:
	var world := await _make_world("coliseum", 53)
	var arena: Node3D = world["arena"]
	var tables: Array = arena.call("turntable_positions")
	var centre: Vector3 = tables[0]
	var on := _spawn_bot(world, 0, centre + Vector3(1.1, 0.3, 0.0), Vector3.RIGHT)
	var off := _spawn_bot(world, 1, Vector3(1.6, 0.3, 3.6), Vector3.LEFT)
	await _settle([on, off], 30)
	var start := _angle_about(on, centre)
	var off_start: Vector3 = off.chassis.global_position
	await _settle([on, off], 180)     # 3 s at 0.6 rad/s is 1.8 rad
	var swept := absf(angle_difference(start, _angle_about(on, centre)))
	var drifted := (off.chassis.global_position - off_start).length()
	_report("a spinning disc carries a bot round with it", swept > 0.6,
		"swept %.2f rad in 3 s" % swept)
	_report("the floor beside a disc does not turn a bot", drifted < 0.25,
		"drifted %.3f m" % drifted)
	await _teardown(world)


func _check_coliseum_spikes() -> void:
	var world := await _make_world("coliseum", 59)
	var arena: Node3D = world["arena"]
	var on := _spawn_bot(world, 0, arena.call("spike_patch_centre") as Vector3
		+ Vector3.UP * 0.25, Vector3.RIGHT)
	# Clear of the spikes, the grinders, the jets and both discs.
	var off := _spawn_bot(world, 1, Vector3(-4.2, 0.25, 3.4), Vector3.LEFT)
	await _settle([on, off], 20)
	var on_before := _total_condition(on)
	var off_before := _total_condition(off)
	var risen := false
	for _i in range(440):
		on.apply_input(FightTypes.empty_input())
		off.apply_input(FightTypes.empty_input())
		await physics_frame
		risen = risen or bool(arena.call("spikes_risen"))
	_report("the Coliseum spike patch still rises", risen, "")
	_report("a bot on the Coliseum spikes is damaged",
		_total_condition(on) < on_before - 0.01,
		"%.3f -> %.3f" % [on_before, _total_condition(on)])
	_report("a bot in a Coliseum safe pocket is untouched",
		is_equal_approx(_total_condition(off), off_before),
		"%.3f -> %.3f" % [off_before, _total_condition(off)])
	await _teardown(world)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
## Build one arena, seeded, outside any fight. Used for the checks that need no physics.
func _make_arena(id: String, seed_value: int) -> Node3D:
	var path := str(ARENAS[id])
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


## A world with an arena in it, the way fight.gd builds one.
func _make_world(id: String, seed_value: int) -> Dictionary:
	var fight := Node3D.new()
	fight.name = "Fight"
	root.add_child(fight)
	var debris := Node3D.new()
	debris.name = "Debris"
	fight.add_child(debris)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var arena: Node3D = (load(str(ARENAS[id])) as PackedScene).instantiate()
	arena.name = "Arena"
	fight.add_child(arena)
	arena.call("setup", rng)
	await physics_frame
	return {"fight": fight, "arena": arena, "rng": rng, "debris": debris}


func _spawn_bot(world: Dictionary, index: int, at: Vector3, facing: Vector3) -> Bot:
	var bot: Bot = (load(BOT_SCENE) as PackedScene).instantiate()
	bot.name = "Bot%d" % index
	(world["fight"] as Node3D).add_child(bot)
	bot.place_at(at, facing)
	bot.setup(FIXTURE_BOT, index, world["rng"] as RandomNumberGenerator)
	bot.place_at(at, facing)
	return bot


func _teardown(world: Dictionary) -> void:
	# Remove from the tree FIRST: queue_free alone leaves the bodies simulating and the
	# node name taken until the end of the frame, which is enough to make the next world
	# start from a different state (docs/stage3-physics-notes.md).
	var fight: Node3D = world["fight"]
	root.remove_child(fight)
	fight.queue_free()
	await physics_frame
	await physics_frame


## Wind an arena's hazard clock forward, with the engine's own call switched off, until
## the next danger is `lead` seconds away. Costs no wall clock and moves nothing that is
## not already moving, because a hazard that has not started has nothing to move.
func _fast_forward(arena: Node3D, lead: float) -> void:
	arena.set_physics_process(false)
	var dt := 1.0 / float(FightTypes.TICK_HZ)
	for _i in range(TIMELINE_TICKS):
		var helpers: Dictionary = arena.call("hazard_helpers")
		if float(helpers.get("next_danger_in_s", 0.0)) <= lead:
			break
		arena.call("_physics_process", dt)
	arena.set_physics_process(true)


func _settle(bots: Array, ticks: int) -> void:
	for _i in range(ticks):
		for b in bots:
			(b as Bot).apply_input(FightTypes.empty_input())
		await physics_frame


func _angle_about(bot: Bot, centre: Vector3) -> float:
	var p: Vector3 = bot.chassis.global_position - centre
	return atan2(p.z, p.x)


func _total_condition(bot: Bot) -> float:
	var c: Dictionary = bot.condition()
	var total := 0.0
	for v in (c["wheels"] as Array):
		total += float(v)
	total += float(c["weapon"]) + float(c["drive"]) + float(c["core"])
	for face in (c["armour"] as Dictionary).values():
		total += float(face)
	return total


func _count(node: Node, kind: String) -> int:
	var n := 0
	if kind == "body":
		n = 1 if (node is PhysicsBody3D or node is Area3D) else 0
	else:
		n = 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		n += _count(child, kind)
	return n


## The same search fight.gd does: by name, then by layer.
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


func _on_body_out(body: Node) -> void:
	_ooa_bodies.append(body)


# ---------------------------------------------------------------------------
# The endgame (brief v4 §2, agent G1). Every arena escalates when fight.gd calls
# set_phase, and none of them ever calms down again.
#
# Driven by hand, like the determinism timeline above: the state machines are what is
# under test, and with no bots in the world the hazard areas are empty, so a tick here is
# exactly the escalation and nothing else.
# ---------------------------------------------------------------------------
const ENDGAME_SEED := 8675309


func _check_endgame_escalation() -> void:
	for id_variant in ARENAS.keys():
		var id := str(id_variant)
		var arena := _make_arena(id, ENDGAME_SEED)
		if arena == null:
			continue
		arena.set_physics_process(false)
		_report("%s exposes set_phase and phase" % id,
			arena.has_method("set_phase") and arena.has_method("phase"), "")
		_report("%s starts in the open phase" % id,
			str(arena.call("phase")) == FightTypes.PHASE_OPEN
				and not bool(arena.call("escalated")), str(arena.call("phase")))

		# Half a minute of the open phase first, so the escalation is measured against a
		# hazard timeline that is actually running.
		var before := _escalation_reading(arena, id)
		_step(arena, 30 * FightTypes.TICK_HZ)

		arena.call("set_phase", FightTypes.PHASE_ENDGAME)
		_report("%s escalates on set_phase" % id,
			str(arena.call("phase")) == FightTypes.PHASE_ENDGAME
				and bool(arena.call("escalated")), "")
		# The key light shift is paint, so it runs on the frame clock; 0.6 s of frames.
		arena.call("_process", 0.7)
		_report("%s shifts the key light to hot" % id,
			is_equal_approx(float(arena.call("light_shift_progress")), 1.0),
			"progress %s" % str(arena.call("light_shift_progress")))

		# Being asked to go back does nothing at all: the escalation is latched.
		arena.call("set_phase", FightTypes.PHASE_OPEN)
		_report("%s cannot be put back to the open phase" % id,
			str(arena.call("phase")) == FightTypes.PHASE_ENDGAME
				and bool(arena.call("escalated")), "")

		_check_escalation_of(arena, id, before)

		# And a full minute of endgame later it is still escalated.
		_step(arena, 60 * FightTypes.TICK_HZ)
		_report("%s is still escalated a minute later" % id,
			bool(arena.call("escalated"))
				and str(arena.call("phase")) == FightTypes.PHASE_ENDGAME, "")
		_free_arena(arena)


## What the arena's own hazard was doing before the endgame, per arena.
func _escalation_reading(arena: Node, id: String) -> Dictionary:
	var out := {}
	if arena.has_method("grinder_period_ticks"):
		out["grinder_ticks"] = int(arena.call("grinder_period_ticks"))
	if id == "furnace" and arena.has_method("belt_velocity"):
		out["belt"] = absf((arena.call("belt_velocity") as Vector3).z)
	if id == "crush" and arena.has_method("ram_cycles"):
		out["cycles"] = (arena.call("ram_cycles") as Array).duplicate()
	if id == "coliseum" and arena.has_method("turntable_rates"):
		out["rates"] = (arena.call("turntable_rates") as Array).duplicate()
	return out


func _check_escalation_of(arena: Node, id: String, before: Dictionary) -> void:
	match id:
		"yard":
			# The centre patch stays risen for the rest of the fight: ten seconds, which
			# is nearly two whole six second cycles, with no gap in it anywhere.
			var down := 0
			for _i in 10 * FightTypes.TICK_HZ:
				arena.call("_physics_process", 1.0 / float(FightTypes.TICK_HZ))
				if not bool(arena.call("spikes_risen")):
					down += 1
			_report("yard: the spikes stay risen", down == 0,
				"%d ticks of ten seconds with the patch down" % down)
		"grinder":
			_report("grinder: the cut rate doubles",
				int(arena.call("grinder_period_ticks")) * 2 == int(before["grinder_ticks"]),
				"%d ticks between bites, was %d"
					% [int(arena.call("grinder_period_ticks")), int(before["grinder_ticks"])])
		"drop_zone":
			# The pit opens on its own and then never closes: two full cycles' worth of
			# ticks with the cover never coming back.
			var opened := false
			var shut_again := 0
			for _i in 90 * FightTypes.TICK_HZ:
				arena.call("_physics_process", 1.0 / float(FightTypes.TICK_HZ))
				if bool(arena.call("pit_open")):
					opened = true
				elif opened:
					shut_again += 1
			_report("drop_zone: the pit opens at the endgame", opened, "")
			_report("drop_zone: and never closes again", shut_again == 0,
				"%d ticks shut after opening" % shut_again)
		"furnace":
			var belt := absf((arena.call("belt_velocity") as Vector3).z)
			_report("furnace: the belt runs at double speed",
				is_equal_approx(belt, float(before["belt"]) * 2.0),
				"%.2f m/s, was %.2f" % [belt, float(before["belt"])])
			# A 4 s period against a 2 s burn on each wall, half a period apart: one wall
			# or the other is alight on every single tick.
			var cold := 0
			for _i in 12 * FightTypes.TICK_HZ:
				arena.call("_physics_process", 1.0 / float(FightTypes.TICK_HZ))
				if not bool(arena.call("jets_firing")):
					cold += 1
			_report("furnace: the jets are on a 4 s period, so the room is never cold",
				cold == 0, "%d cold ticks in twelve seconds" % cold)
		"crush":
			var cycles: Array = arena.call("ram_cycles")
			var halved := true
			for i in cycles.size():
				# A seeded cycle can be an odd number of ticks, so half of it rounds.
				var was := int((before["cycles"] as Array)[i])
				if absi(int(cycles[i]) * 2 - was) > 1:
					halved = false
			_report("crush: the rams cycle at half the period", halved,
				"%s, was %s" % [str(cycles), str(before["cycles"])])
		"coliseum":
			var rates: Array = arena.call("turntable_rates")
			var doubled := true
			for i in rates.size():
				if not is_equal_approx(float(rates[i]),
						float((before["rates"] as Array)[i]) * 2.0):
					doubled = false
			_report("coliseum: the floor discs spin at double speed", doubled,
				"%s, was %s" % [str(rates), str(before["rates"])])
			_report("coliseum: and its grinders speed up with them",
				int(arena.call("grinder_period_ticks")) * 2 == int(before["grinder_ticks"]),
				"%d ticks between bites" % int(arena.call("grinder_period_ticks")))
			var down := 0
			for _i in 10 * FightTypes.TICK_HZ:
				arena.call("_physics_process", 1.0 / float(FightTypes.TICK_HZ))
				if not bool(arena.call("spikes_risen")):
					down += 1
			_report("coliseum: its spike patch stays risen too", down == 0,
				"%d ticks with the patch down" % down)


func _step(arena: Node, ticks: int) -> void:
	for _i in ticks:
		arena.call("_physics_process", 1.0 / float(FightTypes.TICK_HZ))


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
