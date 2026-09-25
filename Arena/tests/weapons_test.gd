extends SceneTree
## Every weapon, on every hull the builder will let you bolt it to.
##   Godot --headless --path Arena --script tests/weapons_test.gd
##
## Added 2026-09-16 (wave F, agent F5) after the owner's first phone playtest:
## "the weapons are not all responding or working once built in the workshop".
## `weapons_a_test` and `weapons_b_test` each prove their own five weapons work on
## a hull chosen to suit them. Nobody was testing the other 30 combinations the
## builder offers, and two whole clusters of them did nothing at all:
##
##   1. a mid band weapon on a Tall Tank took the DECK, 0.405 m up, so the bar
##      swept at 0.67 to 0.73 m, the blade at 0.57 to 0.88 and the flame nozzle at
##      0.66 to 0.75, above the 0.48 m roof of the tallest machine in the game;
##   2. the crusher hung its jaw `PIVOT_LIFT` above whatever socket the hull
##      offered and its bite gap stood 0.057 m proud of its own nose, behind its
##      own front armour. It clamped a Box and clamped nothing on a Wedge, a
##      Long/Low or a Pyramid, and holding the button shut on a Pyramid pitched
##      the machine onto its nose so it could not drive.
##
## So this file's rule is: the matrix, not the representative case. Every weapon
## is fitted to every legal chassis and has to DO something to a machine parked in
## front of it. Exit code 0 = all PASS.
##
## Every scenario builds its world inside its own SubViewport with own_world_3d,
## exactly as fight.gd and weapons_a_test do: two scenarios run back to back in the
## shared root physics space do not reproduce each other (recycled body RIDs change
## the solver's order).

const BOT_SCENE := "res://bot/bot.tscn"
const YARD_SCENE := "res://arena/yard.tscn"
const TEST_ARENA_SCENE := "res://arena/test_arena.tscn"

const LIGHT := {
	"front": {"material": "hdpe", "thickness": 1},
	"sides": {"material": "hdpe", "thickness": 1},
	"rear": {"material": "hdpe", "thickness": 1},
	"top": {"material": "hdpe", "thickness": 1},
}
## The lane weapons_b_test uses, at z = 3, well clear of the yard's spike patch
## (1.6 m square on the origin, phase from the seed). A weapon check run through
## the middle measures the spikes, not the weapon.
const LANE_Z := 3.0
const ATTACKER_AT := Vector3(2.55, 0.3, LANE_Z)
const TARGET_AT := Vector3(4.15, 0.3, LANE_Z)
## The target parks broadside on so the attacker meets a clean flank rather than
## the target's own weapon, and it carries a ram, which has no moving part to catch
## (weapons_b_test trap 8: a flipper's arm reaches 0.55 m and is what gets hit).
const TARGET_FACING := Vector3.BACK

## Weapons the primary button does nothing for, by design: brief section 5.3's
## "no moving parts, the entire weight budget goes into speed and armour". The
## coach callout says so too ("RAM tap (passive weapon; the button does nothing)").
const PASSIVE := ["ram"]
## Worked by a TAP: holding gives one action and then nothing until the button is
## released, so the test has to let go between presses the way a thumb does.
const TAP_WORKED := ["axe"]
## Worked by getting UNDER the other machine first. Holding a lifter's forks up on
## the approach is a bot driving at a wall with a shelf on the front: the forks
## have to be down while it closes and go up once it is under. That is how a player
## works one, and a test that holds from the first tick measures nothing. The
## flipper is worked the same way: you close with the arm down and fire once you
## are under, not with the ram cycling all the way in.
const UNDER_WORKED := ["lifter", "flipper"]
## Weapons whose whole job is to get the other machine off the floor. They take no
## condition at all (a flipper's damage is the landing and the wall), so "it works"
## is measured as a lift, not as damage.
const LIFT_WORKED := ["lifter", "flipper"]
## What counts as having got under and picked a machine up, in metres. A flipper
## managing this throws over a metre; a lifter on a wedge, whose own ramp gets
## there first and rides the victim up rather than onto the tines, makes 0.05.
const MIN_LIFT := 0.04
## What counts as a shove, for the one weapon with no input at all.
const MIN_SHOVE := 0.15

var _checks := 0
var _failures := 0
var _events: Array[Dictionary] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	print("Roboteer weapons matrix test, Godot ", Engine.get_version_info()["string"])
	await process_frame
	if not ResourceLoader.exists(BOT_SCENE):
		print("SKIP  weapons matrix: %s is absent" % BOT_SCENE)
		quit(0)
		return
	await _check_assembly()
	await _check_matrix()
	await _check_mechanics()
	await _check_secondary()
	await _check_round_trip()
	await _check_test_arena()
	_finish()


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------
func _config(id: String, chassis_id: String, weapon_id: String,
		drive_id: String = "4wd", armour: Dictionary = LIGHT) -> Dictionary:
	var utility: Array = []
	if not bool(PartsCatalogue.chassis(chassis_id).get("invertible", false)):
		utility.append("srimech")
	return {
		"id": id, "name": id, "controller": "player",
		"chassis": chassis_id, "drive": drive_id, "weapon": weapon_id,
		"utility": utility, "armour": armour.duplicate(true),
	}


## Every (weapon, chassis) pair BuildRules lets a player build, in a fixed order.
func _matrix() -> Array:
	var out: Array = []
	for weapon_variant in PartsCatalogue.ids("weapon"):
		for chassis_variant in PartsCatalogue.ids("chassis"):
			var weapon_id := str(weapon_variant)
			var chassis_id := str(chassis_variant)
			if not BuildRules.validate(_config("m", chassis_id, weapon_id)).is_empty():
				continue
			out.append([weapon_id, chassis_id])
	return out


func _make_world(arena_scene: String = YARD_SCENE) -> Node3D:
	var viewport := SubViewport.new()
	viewport.name = "Space"
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	var world := Node3D.new()
	world.name = "Fight"
	viewport.add_child(world)
	var debris := Node3D.new()
	debris.name = "Debris"
	world.add_child(debris)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var arena: Node3D = (load(arena_scene) as PackedScene).instantiate()
	arena.name = "Arena"
	world.add_child(arena)
	if arena.has_method("setup"):
		arena.call("setup", rng)
	return world


func _spawn(world: Node3D, config: Dictionary, at: Vector3,
		facing: Vector3 = Vector3.RIGHT) -> Bot:
	var bot: Bot = (load(BOT_SCENE) as PackedScene).instantiate()
	world.add_child(bot)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	bot.place_at(at, facing)
	bot.setup(config, 0, rng)
	bot.place_at(at, facing)
	return bot


## The same machine, assembled already on its back. The root transform is set
## BEFORE `setup`, so every body and every joint is built in that pose and nothing
## is torn (docs/stage3-physics-notes.md, and `physics_test._check_srimech`).
func _spawn_inverted(world: Node3D, config: Dictionary, at: Vector3) -> Bot:
	var bot: Bot = (load(BOT_SCENE) as PackedScene).instantiate()
	world.add_child(bot)
	bot.global_transform = Transform3D(Basis(Vector3.RIGHT, PI), at)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	bot.setup(config, 0, rng)
	return bot


func _drop(world: Node3D) -> void:
	var viewport := world.get_parent()
	root.remove_child(viewport)
	viewport.queue_free()
	await physics_frame
	await physics_frame


func _input(heading: Vector2, fire: bool, secondary: bool = false) -> Dictionary:
	return {"heading": heading, "fire": fire, "secondary": secondary}


func _idle() -> Dictionary:
	return _input(Vector2.ZERO, false)


func _condition_total(bot: Bot) -> float:
	var c := bot.condition()
	var total := float(c["weapon"]) + float(c["drive"]) + float(c["core"])
	for v in (c["wheels"] as Array):
		total += float(v)
	for key in (c["armour"] as Dictionary).keys():
		total += float((c["armour"] as Dictionary)[key])
	return total


func _report(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("%s: %s%s" % ["PASS" if ok else "FAIL", label,
		"" if detail == "" else "  (%s)" % detail])


func _finish() -> void:
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


# ---------------------------------------------------------------------------
# 1. Every pair assembles with a real weapon body
# ---------------------------------------------------------------------------
func _check_assembly() -> void:
	var world := _make_world()
	var bad := PackedStringArray()
	for pair_variant in _matrix():
		var pair: Array = pair_variant
		var weapon_id := str(pair[0])
		var chassis_id := str(pair[1])
		var bot := _spawn(world, _config("a", chassis_id, weapon_id),
			Vector3(0.0, 0.3, LANE_Z))
		var label := "%s/%s" % [weapon_id, chassis_id]
		var bodies := 0
		for part in bot.attached_parts():
			if part.part_kind == "weapon":
				bodies += 1
		if bodies < 1:
			bad.append("%s: no weapon body" % label)
		if not bot.build_errors.is_empty():
			bad.append("%s: %s" % [label, str(bot.build_errors)])
		var catalogue_reach := float(PartsCatalogue.weapon(weapon_id).get("reach", 0.0))
		if absf(bot.weapon_reach() - catalogue_reach) > 0.001:
			bad.append("%s: reach %.2f not %.2f" % [label, bot.weapon_reach(),
				catalogue_reach])
		world.remove_child(bot)
		bot.free()
	_report("every legal weapon and chassis pair assembles with a weapon body",
		bad.is_empty(), str(bad))
	await _drop(world)


# ---------------------------------------------------------------------------
# 2. THE MATRIX: every weapon has to reach a machine parked in front of it
# ---------------------------------------------------------------------------
## Spin up on the spot for two seconds, then drive into the target for three with
## the primary worked the way that weapon is worked. Every weapon except the ram
## has to take condition off the target or throw it; the ram, which has no input at
## all, has to shove it.
func _check_matrix() -> void:
	var weak := PackedStringArray()
	var lines := PackedStringArray()
	for pair_variant in _matrix():
		var pair: Array = pair_variant
		var weapon_id := str(pair[0])
		var chassis_id := str(pair[1])
		var result := await _engage(weapon_id, chassis_id)
		var label := "%s/%s" % [weapon_id, chassis_id]
		var removed := float(result["removed"])
		var lifted := float(result["lifted"])
		var pushed := float(result["pushed"])
		lines.append("%s removed %.3f lifted %.2f pushed %.2f" % [label, removed,
			lifted, pushed])
		if weapon_id in PASSIVE:
			# No input at all: it has to shove, which is the whole weapon.
			if pushed < MIN_SHOVE:
				weak.append("%s shoved nothing (%.2f m)" % [label, pushed])
		elif weapon_id in LIFT_WORKED:
			# It has to get under and pick the machine up.
			if lifted < MIN_LIFT:
				weak.append("%s lifted nothing (%.2f m)" % [label, lifted])
		elif removed <= 0.0005:
			# Everything else has to take condition off it.
			weak.append("%s removed nothing (%.4f)" % [label, removed])
	for line in lines:
		print("      " + line)
	_report("every weapon works on every hull the builder allows it on",
		weak.is_empty(), str(weak))


## One engagement. Returns what the target lost, how high it went and how far it
## was shoved.
func _engage(weapon_id: String, chassis_id: String) -> Dictionary:
	var world := _make_world()
	var attacker := _spawn(world, _config("attacker", chassis_id, weapon_id),
		ATTACKER_AT)
	var target := _spawn(world, _config("target", "box", "ram", "2wd"),
		TARGET_AT, TARGET_FACING)
	await _settle([attacker, target], 30)
	var before := _condition_total(target)
	var rest: Vector3 = target.chassis.global_position
	var lifted := 0.0
	var tap := weapon_id in TAP_WORKED
	for i in range(300):
		var heading := Vector2.ZERO if i < 120 else Vector2(1.0, 0.0)
		# A tap weapon gets a fresh rising edge every 20 ticks, which is a thumb;
		# a lifter closes with its forks down and raises them once it is under.
		var fire := true
		if tap:
			fire = (i % 20) < 10
		elif weapon_id in UNDER_WORKED:
			fire = i >= 200
		attacker.apply_input(_input(heading, fire))
		target.apply_input(_idle())
		await physics_frame
		lifted = maxf(lifted, target.chassis.global_position.y - rest.y)
	var removed := before - _condition_total(target)
	var pushed := Vector2(target.chassis.global_position.x - rest.x,
		target.chassis.global_position.z - rest.z).length()
	await _drop(world)
	return {"removed": removed, "lifted": lifted, "pushed": pushed}


func _settle(bots: Array, ticks: int) -> void:
	for _i in range(ticks):
		for b in bots:
			(b as Bot).apply_input(_idle())
		await physics_frame


# ---------------------------------------------------------------------------
# 3. What each weapon is supposed to DO, one representative hull each
# ---------------------------------------------------------------------------
func _check_mechanics() -> void:
	await _check_spin_ups()
	await _check_lifter()
	await _check_crusher()
	await _check_axe()
	await _check_flame()
	await _check_ram_is_passive()


## The four held, spun weapons: readiness rises 0 to 1 over the catalogue's
## spin_up_s while the button is down, and coasts when it is released.
func _check_spin_ups() -> void:
	var world := _make_world()
	var bad := PackedStringArray()
	for pair_variant in [["horizontal_spinner", "wedge"], ["vertical_spinner", "box"],
			["saw", "long_low"], ["full_body_spinner", "shell"]]:
		var pair: Array = pair_variant
		var bot := _spawn(world, _config("w", str(pair[1]), str(pair[0])),
			Vector3(-2.0, 0.3, LANE_Z))
		if bot.weapon_readiness() > 0.001:
			bad.append("%s starts at %.2f" % [pair[0], bot.weapon_readiness()])
		var ticks := int(round(float(bot.weapon.call("spin_up_s"))
			* float(FightTypes.TICK_HZ)))
		for _i in range(ticks):
			bot.apply_input(_input(Vector2.ZERO, true))
			await physics_frame
		var full := bot.weapon_readiness()
		if full < 0.99:
			bad.append("%s reads %.2f after spin_up_s" % [pair[0], full])
		for _i in range(30):
			bot.apply_input(_idle())
			await physics_frame
		var coasted := bot.weapon_readiness()
		if coasted >= full or coasted <= 0.0:
			bad.append("%s coasts to %.2f" % [pair[0], coasted])
		world.remove_child(bot)
		bot.free()
	_report("every spun weapon reaches its ready speed while held and coasts after",
		bad.is_empty(), str(bad))
	await _drop(world)


func _check_lifter() -> void:
	var world := _make_world()
	var bot := _spawn(world, _config("l", "box", "lifter"), Vector3(-2.0, 0.3, LANE_Z))
	await _settle([bot], 20)
	for _i in range(90):
		bot.apply_input(_input(Vector2.ZERO, true))
		await physics_frame
	var raised: float = bot.weapon.call("lift_fraction")
	for _i in range(90):
		bot.apply_input(_idle())
		await physics_frame
	var lowered: float = bot.weapon.call("lift_fraction")
	_report("the lifter raises its forks while held and lowers them after",
		raised > 0.8 and lowered < 0.2, "raised %.2f, lowered %.2f" % [raised, lowered])
	await _drop(world)


## The claw has to clamp on EVERY hull, which is the half of this that was broken:
## before 2026-09-16 it clamped a Box and nothing else.
func _check_crusher() -> void:
	var bad := PackedStringArray()
	for chassis_variant in PartsCatalogue.ids("chassis"):
		var chassis_id := str(chassis_variant)
		if not BuildRules.validate(_config("c", chassis_id, "crusher")).is_empty():
			continue
		var world := _make_world()
		var attacker := _spawn(world, _config("claw", chassis_id, "crusher"),
			ATTACKER_AT)
		var target := _spawn(world, _config("prey", "box", "ram", "2wd"),
			TARGET_AT, TARGET_FACING)
		await _settle([attacker, target], 30)
		var weapon: WeaponBase = attacker.weapon
		var open_at_rest: float = weapon.call("open_fraction")
		var clamped := false
		var before := _condition_total(target)
		for i in range(300):
			var heading := Vector2.ZERO if i < 60 else Vector2(1.0, 0.0)
			attacker.apply_input(_input(heading, true))
			target.apply_input(_idle())
			await physics_frame
			clamped = clamped or bool(weapon.call("is_clamped"))
		var chewed := before - _condition_total(target)
		if open_at_rest < 0.8:
			bad.append("%s rides %.0f%% open" % [chassis_id, open_at_rest * 100.0])
		if not clamped:
			bad.append("%s never clamped" % chassis_id)
		if chewed <= 0.0:
			bad.append("%s chewed nothing" % chassis_id)
		await _drop(world)
	_report("the crusher clamps and chews on every hull it fits", bad.is_empty(),
		str(bad))


## The axe is worked by the EDGE: one tap, one swing, then nothing at all until
## reset_s has run out. That is the design, and it is why the matrix taps it.
func _check_axe() -> void:
	var world := _make_world()
	var bot := _spawn(world, _config("a", "box", "axe"), Vector3(-2.0, 0.3, LANE_Z))
	await _settle([bot], 20)
	var weapon: WeaponBase = bot.weapon
	var rest_ready: bool = bool(weapon.call("ready"))
	bot.apply_input(_input(Vector2.ZERO, true))
	await physics_frame
	# Combat feel D5: the model winds back on the press (presentation only, AxeWindup).
	var windup: AxeWindup = weapon.get("windup")
	var winding := windup != null and windup.is_winding()
	var swept := 0.0
	var was: float = weapon.call("arm_angle")
	for _i in range(30):
		bot.apply_input(_input(Vector2.ZERO, true))
		await physics_frame
		var now: float = weapon.call("arm_angle")
		swept += absf(now - was)
		was = now
	_report("the axe model winds back on the press and is back on the arm after it",
		winding and not windup.is_winding()
			and is_equal_approx(AxeWindup.angle_at(AxeWindup.WINDUP_PEAK_S), AxeWindup.WINDUP_DEG)
			and AxeWindup.angle_at(AxeWindup.WINDUP_S) == 0.0,
		"winding after the press %s, done after 0.5 s %s" % [winding,
			windup != null and not windup.is_winding()])
	var busy: bool = not bool(weapon.call("ready"))
	var reset_ticks := int(round((float(bot.weapon.spec.get("reset_s", 1.4)) + 0.4)
		* float(FightTypes.TICK_HZ)))
	for _i in range(reset_ticks):
		bot.apply_input(_idle())
		await physics_frame
	_report("the axe swings on a tap, goes dead, then cocks again",
		rest_ready and swept > deg_to_rad(60.0) and busy
			and bool(weapon.call("ready")),
		"rest ready %s, swept %.0f degrees, dead after %s, ready again %s" % [
			rest_ready, rad_to_deg(swept), busy, bool(weapon.call("ready"))])
	await _drop(world)


func _check_flame() -> void:
	var world := _make_world()
	var attacker := _spawn(world, _config("f", "wedge", "flamethrower"),
		Vector3(2.9, 0.3, LANE_Z))
	var target := _spawn(world, _config("prey", "box", "ram", "2wd"),
		Vector3(3.8, 0.3, LANE_Z), TARGET_FACING)
	await _settle([attacker, target], 30)
	var full: float = attacker.weapon.call("fuel_left")
	var before := _condition_total(target)
	for _i in range(180):
		attacker.apply_input(_input(Vector2.ZERO, true))
		target.apply_input(_idle())
		await physics_frame
	var left: float = attacker.weapon.call("fuel_left")
	var burned := before - _condition_total(target)
	_report("the flamethrower burns gas and burns the machine in front of it",
		left < full - 2.5 and burned > 0.0,
		"fuel %.1f -> %.1f s, condition removed %.4f" % [full, left, burned])
	await _drop(world)


func _check_ram_is_passive() -> void:
	var world := _make_world()
	var bot := _spawn(world, _config("r", "wedge", "ram"), Vector3(-2.0, 0.3, LANE_Z))
	await _settle([bot], 20)
	var ready := bot.weapon_readiness()
	var status := bot.weapon_status()
	for _i in range(60):
		bot.apply_input(_input(Vector2.ZERO, true))
		await physics_frame
	_report("the ram is always ready and the button is documented as doing nothing",
		ready >= 0.99 and status == "RAM" and bot.weapon_readiness() >= 0.99,
		"readiness %.2f, status \"%s\"" % [ready, status])
	await _drop(world)


# ---------------------------------------------------------------------------
# 4. The secondary: self righting, and the flipper's gas
# ---------------------------------------------------------------------------
func _check_secondary() -> void:
	var world := _make_world()
	# A wedge with a srimech, on its back. The WHOLE ASSEMBLY is built inverted
	# (physics_test does the same): rolling the chassis body alone afterwards tears
	# every joint on the machine and measures a wreck rather than a bot.
	var bot := _spawn_inverted(world, _config("s", "wedge", "flipper"),
		Vector3(-2.0, 0.4, LANE_Z))
	await _settle([bot], 60)
	var was_inverted := bot.is_inverted()
	for _i in range(240):
		bot.apply_input(_input(Vector2.ZERO, false, true))
		await physics_frame
	_report("secondary rights a machine with a srimech",
		was_inverted and not bot.is_inverted(),
		"inverted at rest %s, inverted after %s" % [was_inverted, bot.is_inverted()])
	await _drop(world)

	# An invertible hull has no srimech and still has to get off its back.
	var world2 := _make_world()
	var shell := _spawn_inverted(world2, _config("i", "shell", "ram"),
		Vector3(-2.0, 0.4, LANE_Z))
	await _settle([shell], 60)
	var shell_over := shell.is_inverted()
	for _i in range(240):
		shell.apply_input(_input(Vector2.ZERO, false, true))
		await physics_frame
	_report("an invertible hull rights itself with no srimech fitted",
		shell_over and not shell.is_inverted(),
		"inverted at rest %s, inverted after %s" % [shell_over, shell.is_inverted()])
	await _drop(world2)

	# Gas: a spare battery adds charges, a dry fire keeps one, a landed throw spends
	# one (docs/stage3-physics-notes.md section 7).
	var world3 := _make_world()
	var config := _config("g", "wedge", "flipper")
	config["utility"] = ["srimech", "spare_battery"]
	var wielder := _spawn(world3, config, Vector3(1.6, 0.3, LANE_Z))
	var victim := _spawn(world3, _config("v", "box", "ram", "2wd"),
		Vector3(2.35, 0.3, LANE_Z), Vector3.LEFT)
	await _settle([wielder, victim], 30)
	var charges_at_start: int = wielder.gas_charges
	for _i in range(20):
		wielder.apply_input(_input(Vector2.ZERO, true))
		victim.apply_input(_idle())
		await physics_frame
	var after_dry: int = wielder.gas_charges
	var peak := victim.chassis.global_position.y
	for i in range(240):
		wielder.apply_input(_input(Vector2(1.0, 0.0), i > 90))
		victim.apply_input(_idle())
		await physics_frame
		peak = maxf(peak, victim.chassis.global_position.y)
	_report("a spare battery adds the catalogue's extra gas charges",
		charges_at_start == FightTypes.FLIPPER_CHARGES
			+ int(PartsCatalogue.utility("spare_battery").get("extra_charges", 0)),
		"%d charges" % charges_at_start)
	_report("the flipper throws the machine in front of it and spends gas doing it",
		peak > 0.3 and wielder.gas_charges < after_dry,
		"peak %.2f m, charges %d -> %d -> %d" % [peak, charges_at_start, after_dry,
			wielder.gas_charges])
	await _drop(world3)


# ---------------------------------------------------------------------------
# 5. A config round trip through JSON, and a rebuild
# ---------------------------------------------------------------------------
## The shell sends the build as JSON text, so every id is a String, every thickness
## arrives as a float and the utility list is a plain Array. A build assembled from
## the parsed text has to be the same machine as one assembled from the Dictionary,
## and it has to still work.
func _check_round_trip() -> void:
	var source := _config("rt", "box", "horizontal_spinner", "6wd", {
		"front": {"material": "titanium", "thickness": 3},
		"sides": {"material": "hdpe", "thickness": 2},
		"rear": {"material": "polycarbonate", "thickness": 1},
		"top": {"material": "steel", "thickness": 2},
	})
	source["utility"] = ["srimech", "spare_battery"]
	source["livery"] = "#d1662b"
	var text := JSON.stringify(source)
	var parsed: Variant = JSON.parse_string(text)
	_report("a bot config survives JSON as a Dictionary", parsed is Dictionary,
		str(typeof(parsed)))
	if not (parsed is Dictionary):
		return
	var world := _make_world()
	var direct := _spawn(world, source, Vector3(-3.0, 0.3, LANE_Z))
	var round_trip := _spawn(world, parsed as Dictionary, Vector3(-1.0, 0.3, LANE_Z))
	var same := _describe(direct) == _describe(round_trip)
	_report("the same machine comes back out of the JSON", same,
		"%s vs %s" % [_describe(direct), _describe(round_trip)])
	# And it still spins up. A weapon that assembles but never runs is the bug.
	var ticks := int(round(float(round_trip.weapon.call("spin_up_s"))
		* float(FightTypes.TICK_HZ)))
	for _i in range(ticks):
		round_trip.apply_input(_input(Vector2.ZERO, true))
		direct.apply_input(_idle())
		await physics_frame
	_report("the weapon built from the JSON still runs",
		round_trip.weapon_readiness() > 0.99,
		"readiness %.2f" % round_trip.weapon_readiness())
	await _drop(world)

	# Rebuilt on the workshop stage twice over, the way the builder does on every
	# keystroke, and then dropped into a fight.
	var stage := WorkshopStage.new()
	root.add_child(stage)
	stage.show_bot(source)
	stage.show_bot(source)
	var staged: Node = stage.bot()
	var summary := stage.bot_summary()
	_report("the workshop stage rebuilds the whole machine on every edit",
		staged != null and str(summary.get("weapon", "")) == "horizontal_spinner"
			and int(summary.get("wheels", 0)) == 6
			and (summary.get("utility", []) as Array).size() == 2,
		str(summary.get("weapon", "")) + " wheels %d utility %s" % [
			int(summary.get("wheels", 0)), str(summary.get("utility", []))])
	root.remove_child(stage)
	stage.queue_free()
	await physics_frame


func _describe(bot: Bot) -> String:
	var parts := PackedStringArray()
	for part in bot.attached_parts():
		parts.append("%s:%s:%s:%.3f" % [part.part_key, part.part_kind,
			part.material_name, part.mass])
	parts.sort()
	return "%s|%s|%.4f|%.4f|%s" % [str(bot.weapon.kind),
		str(bot.weapon.socket_transform().origin), bot.weapon_reach(),
		float(bot.build_summary()["total"]), ",".join(parts)]


# ---------------------------------------------------------------------------
# 6. The workshop test arena, which is where the owner tries a build
# ---------------------------------------------------------------------------
## `rules.mode = "test"` puts the player in `arena/test_arena.tscn`: the Yard with
## the spikes taken out and a target pad on the north wall. A weapon that works in
## the Yard has to work in there, because that is the room the player judges the
## build in.
func _check_test_arena() -> void:
	if not ResourceLoader.exists(TEST_ARENA_SCENE):
		print("SKIP  test arena: %s is absent" % TEST_ARENA_SCENE)
		return
	var bad := PackedStringArray()
	for weapon_variant in ["horizontal_spinner", "saw", "crusher", "flamethrower"]:
		var world := _make_world(TEST_ARENA_SCENE)
		var attacker := _spawn(world, _config("attacker", "wedge",
			str(weapon_variant)), ATTACKER_AT)
		var target := _spawn(world, _config("target", "box", "ram", "2wd"),
			TARGET_AT, TARGET_FACING)
		await _settle([attacker, target], 30)
		var before := _condition_total(target)
		for i in range(300):
			var heading := Vector2.ZERO if i < 120 else Vector2(1.0, 0.0)
			attacker.apply_input(_input(heading, true))
			target.apply_input(_idle())
			await physics_frame
		var removed := before - _condition_total(target)
		if removed <= 0.0005:
			bad.append("%s removed %.4f" % [weapon_variant, removed])
		await _drop(world)
	_report("weapons work in the workshop test arena too", bad.is_empty(), str(bad))
