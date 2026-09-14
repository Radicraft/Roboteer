extends SceneTree
## Headless physics test for the Stage 3 bot and arena (docs/stage3-spec.md §14).
##   Godot --headless --path Arena --script tests/physics_test.gd
## Headless Godot still runs Jolt, so every check below is a real simulation.
## Exit code 0 = all PASS.

const BOT_SCENE := "res://bot/bot.tscn"
const YARD_SCENE := "res://arena/yard.tscn"

## The Stage 3 fixture from docs/bridge-spec.md, with both bots wedge / flipper
## / 4wd as docs/stage3-spec.md §2 requires.
const FIXTURE := {
	"schema": 1,
	"seed": 123456789,
	"arena": "yard",
	"rules": {"duration_s": 90, "ko_count_s": 10},
	"bots": [
		{
			"id": "player-1", "name": "Tinribs", "controller": "player",
			"chassis": "wedge", "drive": "4wd", "weapon": "flipper",
			"utility": ["srimech", "spare_battery"],
			"armour": {
				"front": {"material": "steel", "thickness": 3},
				"sides": {"material": "hdpe", "thickness": 2},
				"rear": {"material": "polycarbonate", "thickness": 1},
				"top": {"material": "titanium", "thickness": 2},
			},
			"damage": {
				"wheels": [1.0, 1.0, 1.0, 1.0], "weapon": 1.0,
				"armour": {"front": 1.0, "sides": 1.0, "rear": 1.0, "top": 1.0},
				"drive": 1.0, "core": 1.0,
			},
		},
		{
			"id": "ai-1", "name": "Scrapheap", "controller": "ai",
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
		},
	],
}

var _checks := 0
var _failures := 0
var _detached_parts: Array[String] = []
var _ooa_bodies: Array = []


## `--determinism-run` makes this script simulate one seeded fight and print a
## single SAMPLE line. The parent run spawns two of those in FRESH PROCESSES and
## compares them: Jolt's solver walks bodies in body-ID order, and a second
## world built in the SAME process gets recycled IDs in a different order, which
## is enough to diverge. A replay always starts a fresh process, so that is the
## case worth testing (measured; see docs/stage3-physics-notes.md).
const DETERMINISM_FLAG := "--determinism-run"


func _initialize() -> void:
	if OS.get_cmdline_user_args().has(DETERMINISM_FLAG):
		_emit_determinism_sample()
	else:
		_run()


func _emit_determinism_sample() -> void:
	var transforms := await _determinism_run()
	print("SAMPLE " + _encode(transforms))
	quit(0)


func _encode(transforms: Array) -> String:
	var parts := PackedStringArray()
	for t_variant in transforms:
		var t: Transform3D = t_variant
		for v in [t.basis.x, t.basis.y, t.basis.z, t.origin]:
			var vec: Vector3 = v
			parts.append("%.9f" % vec.x)
			parts.append("%.9f" % vec.y)
			parts.append("%.9f" % vec.z)
	return ",".join(parts)


## One seeded simulation in a fresh child process. Empty on failure.
func _child_sample() -> PackedFloat64Array:
	var out: Array = []
	var args := PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "tests/physics_test.gd", "--", DETERMINISM_FLAG,
	])
	var code := OS.execute(OS.get_executable_path(), args, out, false)
	var numbers := PackedFloat64Array()
	if code != 0:
		return numbers
	for line_variant in out:
		for line in str(line_variant).split("\n"):
			if not line.begins_with("SAMPLE "):
				continue
			for token in line.substr(7).strip_edges().split(","):
				numbers.append(float(token))
			return numbers
	return numbers


func _run() -> void:
	print("Roboteer physics test, Godot ", Engine.get_version_info()["string"],
		", engine ", ProjectSettings.get_setting("physics/3d/physics_engine"),
		", ", Engine.physics_ticks_per_second, " Hz")
	await _check_drive_straight()
	await _check_turn()
	await _check_pivot()
	await _check_flipper_launch()
	await _check_heavy_impact()
	await _check_out_of_arena()
	await _check_immobile()
	await _check_spikes()
	await _check_srimech()
	await _check_determinism()
	_finish()


# ---------------------------------------------------------------------------
# World helpers
# ---------------------------------------------------------------------------
func _make_world(seed_value: int) -> Dictionary:
	var fight := Node3D.new()
	fight.name = "Fight"
	root.add_child(fight)
	var debris := Node3D.new()
	debris.name = "Debris"
	fight.add_child(debris)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var yard: Yard = (load(YARD_SCENE) as PackedScene).instantiate()
	yard.name = "Arena"
	fight.add_child(yard)
	yard.setup(rng)

	return {"fight": fight, "yard": yard, "rng": rng, "debris": debris}


func _spawn_bot(world: Dictionary, index: int, at: Vector3, facing: Vector3) -> Bot:
	var bot: Bot = (load(BOT_SCENE) as PackedScene).instantiate()
	bot.name = "Bot%d" % index
	(world["fight"] as Node3D).add_child(bot)
	bot.place_at(at, facing)
	bot.setup((FIXTURE["bots"] as Array)[index] as Dictionary, index,
		world["rng"] as RandomNumberGenerator)
	bot.place_at(at, facing)
	return bot


func _teardown(world: Dictionary) -> void:
	# Remove from the tree FIRST: queue_free alone leaves the bodies simulating
	# and the node name taken until the end of the frame, which is enough to
	# make the next world start from a different state.
	var fight: Node3D = world["fight"]
	root.remove_child(fight)
	fight.queue_free()
	await physics_frame
	await physics_frame


func _step(count: int) -> void:
	for _i in range(count):
		await physics_frame


## Step while feeding both bots an input record every tick, the way R does.
func _step_driving(bots: Array, inputs: Array, count: int) -> void:
	for _i in range(count):
		for b in range(bots.size()):
			(bots[b] as Bot).apply_input(inputs[b])
		await physics_frame


func _settle(bots: Array, ticks: int) -> void:
	await _step_driving(bots, _idle_inputs(bots.size()), ticks)


func _idle_inputs(n: int) -> Array:
	var out := []
	for _i in range(n):
		out.append(FightTypes.empty_input())
	return out


func _heading_of(bot: Bot) -> float:
	var fwd := bot.chassis.global_basis.x
	fwd.y = 0.0
	return atan2(-fwd.z, fwd.x)


# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------
func _check_drive_straight() -> void:
	var world := _make_world(1)
	var bot := _spawn_bot(world, 0, Vector3(-3.0, 0.25, 0.0), Vector3.RIGHT)
	await _settle([bot], 30)
	var start: Vector3 = bot.chassis.global_position
	var drive := {"heading": Vector2(1.0, 0.0), "fire": false, "secondary": false}
	await _step_driving([bot], [drive], 120)
	var moved := (bot.chassis.global_position - start).length()
	var up := bot.chassis.global_basis.y.dot(Vector3.UP)
	_report("drive straight 2 s travels over 3 m", moved > 3.0,
		"moved %.2f m" % moved)
	_report("drive straight stays upright", up > 0.7 and not bot.is_inverted(),
		"up.y = %.2f" % up)
	await _teardown(world)


func _check_turn() -> void:
	var world := _make_world(2)
	# Well clear of the spike patch at the centre.
	var bot := _spawn_bot(world, 0, Vector3(-3.0, 0.25, 2.5), Vector3.RIGHT)
	await _settle([bot], 30)
	# Command a heading of world -Z (a 90 degree turn from +X).
	var want := Vector2(0.0, -1.0)
	var want_yaw := atan2(-want.y, want.x)
	var drive := {"heading": want, "fire": false, "secondary": false}
	var best := PI
	for _i in range(90):
		bot.apply_input(drive)
		await physics_frame
		best = minf(best, absf(wrapf(want_yaw - _heading_of(bot), -PI, PI)))
	_report("turn reaches the heading within 15 degrees in 1.5 s",
		best < deg_to_rad(15.0), "closest %.1f degrees" % rad_to_deg(best))
	await _teardown(world)


## The twin-stick scheme's pure pivot: `turn` with no heading spins the bot on the
## spot. It must actually yaw, and it must not drive anywhere while it does.
func _check_pivot() -> void:
	var world := _make_world(21)
	var bot := _spawn_bot(world, 0, Vector3(-3.0, 0.25, 2.5), Vector3.RIGHT)
	await _settle([bot], 30)
	var start_yaw := _heading_of(bot)
	var start: Vector3 = bot.chassis.global_position
	var spin := {"heading": Vector2.ZERO, "fire": false, "secondary": false, "turn": 1.0}
	await _step_driving([bot], [spin], 60)
	var turned := absf(wrapf(_heading_of(bot) - start_yaw, -PI, PI))
	var drifted := (bot.chassis.global_position - start).length()
	_report("turn spins the bot at least 45 degrees on the spot in 1 s",
		turned > deg_to_rad(45.0), "turned %.0f degrees" % rad_to_deg(turned))
	_report("a pure pivot does not drive the bot anywhere", drifted < 0.30,
		"drifted %.2f m" % drifted)
	await _teardown(world)


func _check_flipper_launch() -> void:
	var world := _make_world(3)
	# The real move: ram the opponent's rear, so the low wedge lip gets under it
	# (a head-on or flank hit meets its wheels), then fire.
	var thrower := _spawn_bot(world, 0, Vector3(-2.6, 0.25, 2.6), Vector3.RIGHT)
	var victim := _spawn_bot(world, 1, Vector3(-1.4, 0.25, 2.6), Vector3.RIGHT)
	await _settle([thrower, victim], 40)
	var push := {"heading": Vector2(1.0, 0.0), "fire": false, "secondary": false}
	var idle := FightTypes.empty_input()

	# Stage 4: the charge count comes from the catalogue (8) plus the spare battery
	# (4), so the test reads what the build actually starts with.
	var start_gas: int = thrower.gas_charges
	_report("nothing on the wedge before the ram", not thrower.opponent_on_wedge(), "")
	_report("the flipper reports ready", thrower.flipper_ready(), "")
	# A dry fire sweeps the arm but must not spend gas, or an AI that fires on
	# proximity empties the bottle on thin air.
	thrower.apply_input({"heading": Vector2.ZERO, "fire": true, "secondary": false})
	await _step_driving([thrower, victim], [idle, idle], 70)
	_report("a dry fire keeps its gas charge", thrower.gas_charges == start_gas,
		"charges left %d of %d" % [thrower.gas_charges, start_gas])

	await _step_driving([thrower, victim], [push, idle], 90)
	_report("the opponent reads as on the wedge after the ram",
		thrower.opponent_on_wedge(), "")
	var rest: float = victim.chassis.global_position.y
	var peak := rest
	var self_peak: float = thrower.chassis.global_position.y
	thrower.apply_input({"heading": Vector2(1.0, 0.0), "fire": true, "secondary": false})
	await physics_frame
	for _i in range(30):
		thrower.apply_input(push)
		victim.apply_input(idle)
		await physics_frame
		peak = maxf(peak, victim.chassis.global_position.y)
		self_peak = maxf(self_peak, thrower.chassis.global_position.y)
	_report("flipper throws the other bot above 0.5 m within 0.5 s", peak > 0.5,
		"rest %.2f m, peak %.2f m (rise %.2f m)" % [rest, peak, peak - rest])
	_report("the wielder stays down when it fires", self_peak < 0.3,
		"wielder peak %.2f m" % self_peak)
	_report("a landed throw spends a gas charge", thrower.gas_charges == start_gas - 1,
		"charges left %d of %d" % [thrower.gas_charges, start_gas])
	await _teardown(world)


func _check_heavy_impact() -> void:
	var world := _make_world(4)
	var bot := _spawn_bot(world, 0, Vector3(0.0, 0.25, -2.0), Vector3.RIGHT)
	_detached_parts.clear()
	bot.part_detached.connect(_on_part_detached)
	await _settle([bot], 30)
	var before: float = (bot.condition()["armour"] as Dictionary)["top"]

	var after := before
	var drops := 0
	while drops < 10 and not _detached_parts.has("armour_top"):
		drops += 1
		var weight := RigidBody3D.new()
		weight.mass = 20.0
		weight.collision_layer = FightTypes.LAYER_DEBRIS
		weight.collision_mask = FightTypes.MASK_DEBRIS
		weight.continuous_cd = true
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.3, 0.3, 0.3)
		shape.shape = box
		weight.add_child(shape)
		(world["fight"] as Node3D).add_child(weight)
		weight.global_position = bot.armour_centre("top") + Vector3(0.0, 3.0, 0.0)
		await _step_driving([bot], _idle_inputs(1), 60)
		after = (bot.condition()["armour"] as Dictionary)["top"]
		weight.queue_free()
		await physics_frame

	_report("a 20 kg drop on the top plate takes condition off it", after < before,
		"top %.3f -> %.3f after %d drop(s)" % [before, after, drops])
	_report("the top plate eventually detaches", _detached_parts.has("armour_top"),
		"detached: %s" % str(_detached_parts))
	await _teardown(world)


func _on_part_detached(part: String) -> void:
	_detached_parts.append(part)


func _check_out_of_arena() -> void:
	var world := _make_world(5)
	var yard: Yard = world["yard"]
	_ooa_bodies.clear()
	yard.body_out.connect(_on_body_out)
	var bot := _spawn_bot(world, 0, Vector3(-3.0, 0.25, 0.0), Vector3.RIGHT)
	await _settle([bot], 20)
	bot.place_at(Vector3(7.5, 0.4, 0.0), Vector3.RIGHT)
	await _step(20)
	var saw_chassis := false
	for b in _ooa_bodies:
		if b == bot.chassis:
			saw_chassis = true
	_report("a chassis pushed outside the walls trips the OOA sensor", saw_chassis,
		"%d body_out signal(s)" % _ooa_bodies.size())
	await _teardown(world)


func _on_body_out(body: Node) -> void:
	_ooa_bodies.append(body)


func _check_immobile() -> void:
	var world := _make_world(6)
	var bot := _spawn_bot(world, 0, Vector3(-2.0, 0.25, 2.0), Vector3.RIGHT)
	await _settle([bot], 90)
	var at_rest := bot.is_immobile()
	var drive := {"heading": Vector2(1.0, 0.0), "fire": false, "secondary": false}
	await _step_driving([bot], [drive], 40)
	var when_driving := bot.is_immobile()
	_report("is_immobile() is true after 0.5 s at rest", at_rest, "")
	_report("is_immobile() is false while driving", not when_driving, "")

	# RESULT state: freeze() must stop everything and survive being driven.
	bot.freeze()
	await _step_driving([bot], [drive], 20)
	_report("freeze() stops the bot dead",
		bot.chassis.linear_velocity.length() < 0.001, "")
	await _teardown(world)


func _check_spikes() -> void:
	var world := _make_world(11)
	var yard: Yard = world["yard"]
	# Park on the spike patch and sit through a full 6 s hazard cycle.
	var bot := _spawn_bot(world, 0, Vector3(0.0, 0.25, 0.0), Vector3.RIGHT)
	await _settle([bot], 20)
	var before: Dictionary = bot.condition()
	var risen := false
	for _i in range(440):
		bot.apply_input(FightTypes.empty_input())
		await physics_frame
		risen = risen or yard.spikes_risen()
	var after: Dictionary = bot.condition()
	_report("the spike patch rises on the physics tick", risen, "")
	_report("risen spikes damage a bot parked on them",
		_total_condition(after) < _total_condition(before),
		"condition %.3f -> %.3f" % [_total_condition(before), _total_condition(after)])
	await _teardown(world)


func _total_condition(c: Dictionary) -> float:
	var total := 0.0
	for v in (c["wheels"] as Array):
		total += float(v)
	total += float(c["weapon"]) + float(c["drive"]) + float(c["core"])
	for face in (c["armour"] as Dictionary).values():
		total += float(face)
	return total


func _check_srimech() -> void:
	var world := _make_world(12)
	var bot: Bot = (load(BOT_SCENE) as PackedScene).instantiate()
	bot.name = "BotUpsideDown"
	(world["fight"] as Node3D).add_child(bot)
	# Build the whole assembly already inverted, so no joint is torn.
	bot.global_transform = Transform3D(Basis(Vector3.RIGHT, PI), Vector3(-2.0, 0.22, -2.0))
	bot.setup((FIXTURE["bots"] as Array)[0] as Dictionary, 0,
		world["rng"] as RandomNumberGenerator)
	await _settle([bot], 60)
	var started_inverted := bot.is_inverted()
	var righted := false
	var press := {"heading": Vector2.ZERO, "fire": false, "secondary": true}
	for _i in range(300):
		bot.apply_input(press)
		await physics_frame
		if not bot.is_inverted():
			righted = true
			break
	_report("a bot spawned upside down reads as inverted", started_inverted, "")
	_report("the srimech rights an inverted bot", righted, "")
	await _teardown(world)


func _check_determinism() -> void:
	var a := _child_sample()
	var b := _child_sample()
	if a.is_empty() or b.is_empty() or a.size() != b.size():
		_report("two seeded runs match at tick 600", false,
			"child run produced no sample (%d vs %d numbers)" % [a.size(), b.size()])
		return
	var worst := 0.0
	for i in range(a.size()):
		worst = maxf(worst, absf(a[i] - b[i]))
	_report("two seeded runs match at tick 600", worst == 0.0,
		"max component difference %.9f over %d components" % [worst, a.size()])


func _determinism_run() -> Array:
	var world := _make_world(123456789)
	var yard: Yard = world["yard"]
	var a := _spawn_bot(world, 0, yard.spawn_position(0), yard.spawn_facing(0))
	var b := _spawn_bot(world, 1, yard.spawn_position(1), yard.spawn_facing(1))
	for tick in range(600):
		a.apply_input(_scripted_input(tick, 0))
		b.apply_input(_scripted_input(tick, 1))
		await physics_frame
	var out := [a.chassis.global_transform, b.chassis.global_transform]
	await _teardown(world)
	return out


## A fixed script, not random: the same every run by construction.
func _scripted_input(tick: int, side: int) -> Dictionary:
	var t := float(tick) / 60.0
	var turn := sin(t * 1.7 + float(side) * 2.1)
	var push := 0.6 + 0.4 * cos(t * 0.9 + float(side))
	var heading := Vector2(cos(turn), sin(turn)) * clampf(push, 0.0, 1.0)
	if side == 1:
		heading = -heading
	return {
		"heading": heading,
		"fire": tick == 120 or tick == 400,
		"secondary": tick > 300 and tick < 330,
	}


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------
func _report(name: String, ok: bool, detail: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	var suffix := ""
	if detail != "":
		suffix = "  (" + detail + ")"
	print(("PASS: " if ok else "FAIL: ") + name + suffix)


func _finish() -> void:
	print("%d checks, %d failed" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)
