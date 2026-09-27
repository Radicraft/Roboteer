extends SceneTree
## Weapons A (agent W1): horizontal spinner, vertical spinner, full body spinner, saw.
##   Godot --headless --path Arena --script tests/weapons_a_test.gd
##
## What it proves, in the order spec section 4 asks for it:
##   1. each weapon assembles on its chassis through the real Bot and a real config,
##      with its bodies registered as part_kind "weapon";
##   2. readiness rises from 0 to 1 over the catalogue's `spin_up_s` while the
##      button is held, and coasts down when it is released;
##   3. a target Bot placed in reach takes a damage_event on the face that was
##      struck, within 2 s of contact;
##   4. the horizontal spinner's own chassis lurches on a hit (`self_destabilise`);
##   5. the saw removes HDPE faster than steel over the same fixed 5 s of contact;
##   6. the full body spinner scales the drive while it is spun up, and its faces
##      are out of the collision world above 30 percent spin;
##   7. a jammed weapon delivers nothing;
##   8. two runs from the same seed are identical at tick 600.
## Exit code 0 = all PASS.
##
## MEASURED, and it cost an hour: every scenario builds its world inside its OWN
## SubViewport, exactly as `fight.gd` does. Two scenarios run back to back in the
## SHARED root physics space do not reproduce each other (R2 found the same thing
## in Stage 3 and wrote it into fight.gd's `_build_world`): with recycled body RIDs
## the solver's order changes, and four bots driving into a wall diverged by a
## metre in ten seconds. In its own space the same run repeats exactly.

const BOT_SCENE := "res://bot/bot.tscn"
const YARD_SCENE := "res://arena/yard.tscn"

const LIGHT_ARMOUR := {
	"front": {"material": "hdpe", "thickness": 1},
	"sides": {"material": "hdpe", "thickness": 1},
	"rear": {"material": "hdpe", "thickness": 1},
	"top": {"material": "hdpe", "thickness": 1},
}
## The target parks broadside on, so the attacker meets a clean armour face rather
## than the target's own weapon sticking off its nose, and it parks with its back to
## the east wall so it cannot simply be shoved out of reach. A target free to slide
## away takes one hit and then coasts, and whether a second hit lands comes down to
## where it happened to stop: the first version of this test passed on its own and
## failed inside the suite for exactly that reason.
const TARGET_FACING := Vector3.BACK
const ATTACKER_AT := Vector3(2.55, 0.3, 0.0)
const TARGET_AT := Vector3(4.15, 0.3, 0.0)

var _checks := 0
var _failures := 0
## Filled by `_watch`, one row per damage_event on the watched bot.
var _events: Array[Dictionary] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	print("Roboteer weapons A test, Godot ", Engine.get_version_info()["string"])
	await process_frame
	if not ResourceLoader.exists(BOT_SCENE):
		print("SKIP  weapons A: %s is absent" % BOT_SCENE)
		quit(0)
		return
	await _check_assembly()
	await _check_spin_up()
	await _check_hits()
	await _check_reaction()
	await _check_saw_materials()
	await _check_full_body_spinner()
	await _check_jammed()
	await _check_determinism()
	_finish()


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------
func _config(name: String, chassis: String, drive: String, weapon: String,
		armour: Dictionary = LIGHT_ARMOUR) -> Dictionary:
	var utility: Array = []
	if not bool(PartsCatalogue.chassis(chassis).get("invertible", false)):
		utility.append("srimech")
	return {
		"id": name, "name": name, "controller": "dummy",
		"chassis": chassis, "drive": drive, "weapon": weapon,
		"utility": utility, "armour": armour.duplicate(true),
	}


func _armour(material: String, thickness: int) -> Dictionary:
	var out := {}
	for face in ["front", "sides", "rear", "top"]:
		out[face] = {"material": material, "thickness": thickness}
	return out


## One world in one physics space. See the header: this is what makes two runs of
## the same scenario reproduce each other.
func _make_world() -> Node3D:
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
	var yard: Yard = (load(YARD_SCENE) as PackedScene).instantiate()
	yard.name = "Arena"
	world.add_child(yard)
	yard.setup(rng)
	return world


func _spawn(world: Node3D, config: Dictionary, at: Vector3, facing: Vector3,
		seed_value: int = 7) -> Bot:
	var bot: Bot = (load(BOT_SCENE) as PackedScene).instantiate()
	world.add_child(bot)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	bot.place_at(at, facing)
	bot.setup(config, 0, rng)
	bot.place_at(at, facing)
	return bot


func _drop(world: Node3D) -> void:
	var viewport := world.get_parent()
	root.remove_child(viewport)
	viewport.queue_free()
	await physics_frame
	await physics_frame


func _input_for(heading: Vector2, fire: bool) -> Dictionary:
	return {"heading": heading, "fire": fire, "secondary": false}


func _watch(bot: Bot) -> void:
	_events.clear()
	bot.damage_event.connect(func(info: Dictionary) -> void:
		_events.append(info))


## Direct (non impulse) damage: the saw's cut and the spinners' bite both arrive
## with impulse 0, which is how the test tells a weapon's own damage apart from the
## shove of one bot driving into another.
func _direct_total(part_prefix: String = "") -> float:
	var total := 0.0
	for ev in _events:
		if float(ev.get("impulse", 0.0)) != 0.0:
			continue
		if part_prefix != "" and not str(ev.get("part", "")).begins_with(part_prefix):
			continue
		total += float(ev.get("severity", 0.0))
	return total


# ---------------------------------------------------------------------------
# 1. Assembly
# ---------------------------------------------------------------------------
func _check_assembly() -> void:
	var cases := [
		["horizontal_spinner", "wedge", "SpinnerBar"],
		["horizontal_spinner", "box", "SpinnerBar"],
		["vertical_spinner", "wedge", "SpinnerDrum"],
		["vertical_spinner", "box", "SpinnerDrum"],
		["saw", "wedge", "SawBlade"],
		["saw", "box", "SawBlade"],
		["full_body_spinner", "shell", "SpinnerRing"],
	]
	var world := _make_world()
	var bad := PackedStringArray()
	for case_variant in cases:
		var case: Array = case_variant
		var weapon_id := str(case[0])
		var chassis_id := str(case[1])
		var body_name := str(case[2])
		var bot := _spawn(world, _config("w", chassis_id, "4wd", weapon_id),
			Vector3(0.0, 0.3, 0.0), Vector3.RIGHT)
		var label := "%s on %s" % [weapon_id, chassis_id]
		if not bot.build_errors.is_empty():
			bad.append("%s: %s" % [label, bot.build_errors])
		var found: BotPart = null
		for part in bot.attached_parts():
			if String(part.name) == body_name:
				found = part
		if found == null:
			bad.append("%s: no %s body" % [label, body_name])
		else:
			if found.part_kind != "weapon" or found.part_key != FightTypes.PART_WEAPON:
				bad.append("%s: %s is %s/%s" % [label, body_name, found.part_kind,
					found.part_key])
			if found.mass <= 0.5:
				bad.append("%s: %s weighs %.2f" % [label, body_name, found.mass])
		if absf(bot.weapon_reach() - float(PartsCatalogue.weapon(weapon_id).get(
				"reach", 0.0))) > 0.001:
			bad.append("%s: reach %.2f" % [label, bot.weapon_reach()])
		world.remove_child(bot)
		bot.free()
	_report("every W1 weapon assembles on its chassis as a registered weapon body",
		bad.is_empty(), str(bad))

	# The shell hands its ring over the moment full_body_spinner.gd exists.
	var shell := _spawn(world, _config("s", "shell", "4wd", "full_body_spinner"),
		Vector3(0.0, 0.3, 0.0), Vector3.RIGHT)
	var hull_keeps_ring: bool = shell.chassis_module.call("has_own_ring")
	_report("the Shell gives its ring to the full body spinner",
		not hull_keeps_ring, "has_own_ring = %s" % hull_keeps_ring)
	world.remove_child(shell)
	shell.free()
	await _drop(world)


# ---------------------------------------------------------------------------
# 2. Spin up
# ---------------------------------------------------------------------------
func _check_spin_up() -> void:
	var world := _make_world()
	var bad := PackedStringArray()
	for weapon_variant in ["horizontal_spinner", "vertical_spinner", "saw",
			"full_body_spinner"]:
		var weapon_id := str(weapon_variant)
		var chassis_id := "shell" if weapon_id == "full_body_spinner" else "wedge"
		var bot := _spawn(world, _config("w", chassis_id, "4wd", weapon_id),
			Vector3(-2.0, 0.3, -2.0), Vector3.RIGHT)
		var up_s := float(bot.weapon.call("spin_up_s"))
		var ticks := int(round(up_s * float(FightTypes.TICK_HZ)))
		if bot.weapon_readiness() > 0.001:
			bad.append("%s starts at %.2f" % [weapon_id, bot.weapon_readiness()])
		var half := 0.0
		for i in range(ticks):
			bot.apply_input(_input_for(Vector2.ZERO, true))
			await physics_frame
			if i == int(ticks / 2) - 1:
				half = bot.weapon_readiness()
		var full := bot.weapon_readiness()
		if absf(half - 0.5) > 0.08:
			bad.append("%s is %.2f at half of spin_up_s" % [weapon_id, half])
		if full < 0.99:
			bad.append("%s is %.2f after spin_up_s" % [weapon_id, full])
		if not bot.weapon_status().begins_with("SPIN") \
				and not bot.weapon_status().begins_with("SAW"):
			bad.append("%s status \"%s\"" % [weapon_id, bot.weapon_status()])
		# Released, it coasts down rather than stopping dead.
		for _i in range(30):
			bot.apply_input(_input_for(Vector2.ZERO, false))
			await physics_frame
		var coasted := bot.weapon_readiness()
		if coasted >= full or coasted <= 0.0:
			bad.append("%s coasts to %.2f" % [weapon_id, coasted])
		world.remove_child(bot)
		bot.free()
	_report("readiness rises 0 to 1 over spin_up_s while held, then coasts down",
		bad.is_empty(), str(bad))
	await _drop(world)


# ---------------------------------------------------------------------------
# 3. A hit on a target in reach
# ---------------------------------------------------------------------------
## Spin up on the spot, then drive into a target parked broadside on just ahead of
## the nose. The target runs 2WD so its rear wheels are out of the way and the
## attacker meets the side plate, which makes "the expected part" unambiguous.
func _engage(weapon_id: String, chassis_id: String, target_armour: Dictionary,
		spin_ticks: int, drive_ticks: int, jam: bool = false) -> Dictionary:
	var world := _make_world()
	var attacker := _spawn(world, _config("attacker", chassis_id, "4wd", weapon_id),
		ATTACKER_AT, Vector3.RIGHT)
	var target := _spawn(world, _config("target", "box", "2wd", "ram", target_armour),
		TARGET_AT, TARGET_FACING)
	_watch(target)
	if jam:
		attacker.weapon.set_jammed()
	var peak_yaw := 0.0
	var was := Vector3.ZERO
	for _i in range(spin_ticks):
		attacker.apply_input(_input_for(Vector2.ZERO, true))
		target.apply_input(_input_for(Vector2.ZERO, false))
		await physics_frame
	for _i in range(drive_ticks):
		attacker.apply_input(_input_for(Vector2(1.0, 0.0), true))
		target.apply_input(_input_for(Vector2.ZERO, false))
		await physics_frame
		var now: Vector3 = attacker.chassis.angular_velocity
		peak_yaw = maxf(peak_yaw, (now - was).length())
		was = now
	return {"world": world, "attacker": attacker, "target": target,
		"peak_yaw": peak_yaw}


## THE FACE A BITE LANDS ON is the Bot's business, not the weapon's. A blow that
## reaches bare hull rather than a plate is credited by `Bot.take_direct_damage` to
## the top plate while the top plate lives (P2's rule for every direct damage
## weapon), and a plate only covers the middle 0.6 m of a 0.8 m flank, so the test
## asks for an armour face and prints which, rather than demanding one face.
func _check_hits() -> void:
	var bad := PackedStringArray()
	var hit := PackedStringArray()
	for case_variant in [["horizontal_spinner", "wedge"], ["vertical_spinner", "wedge"],
			["saw", "wedge"], ["full_body_spinner", "shell"]]:
		var case: Array = case_variant
		var weapon_id := str(case[0])
		var spin_s := float(PartsCatalogue.weapon(weapon_id).get("spin_up_s", 0.4))
		# 120 driving ticks is the 2 s of contact the spec asks for.
		var run := await _engage(weapon_id, str(case[1]), LIGHT_ARMOUR,
			int(spin_s * 60.0) + 10, 120)
		var armour := _direct_total("armour_")
		var faces := {}
		for ev in _events:
			if float(ev.get("impulse", 0.0)) == 0.0:
				faces[str(ev.get("part", ""))] = true
		# The drum meets the target's rear wheel first. Since the spinner bite (owner decision
		# 2026-09-24: a part takes two or three clean hits) that wheel no longer dies to the
		# first bite, so in 2 s every drum bite is on the wheel: running gear counts for it.
		if weapon_id == "vertical_spinner" and armour <= 0.0:
			armour = _direct_total("wheel_")
		if armour <= 0.0:
			bad.append("%s took no armour off in 2 s (its own damage landed on %s)"
				% [weapon_id, faces.keys()])
		else:
			hit.append("%s %s %.2f" % [weapon_id, faces.keys(), armour])
		var attacker: Bot = run["attacker"]
		var left := float((attacker.condition() as Dictionary).get("weapon", 0.0))
		if left < 0.5:
			bad.append("%s ground its OWN condition to %.2f in 2 s"
				% [weapon_id, left])
		await _drop(run["world"])
	_report("every W1 weapon damages an armour face (the drum: armour or a wheel) of a target in reach within 2 s",
		bad.is_empty(), str(bad) if not bad.is_empty() else " ".join(hit))


# ---------------------------------------------------------------------------
# 4. The horizontal spinner's reaction
# ---------------------------------------------------------------------------
## The same engagement twice: once with the catalogue's `self_destabilise`, once
## with it zeroed. The wielder's per tick angular velocity change has to be bigger
## with the reaction on, which is the "the bar wrecks your own driving line"
## promise in spec section 4.
func _check_reaction() -> void:
	var with_it := await _engage_with_destabilise(
		float(PartsCatalogue.weapon("horizontal_spinner").get("self_destabilise", 0.6)))
	var bit := float(with_it["damage"]) > 0.0
	var without := await _engage_with_destabilise(0.0)
	_report("a horizontal spinner hit lurches its own chassis",
		bit and float(with_it["peak"]) > float(without["peak"]) * 1.25
			and float(with_it["peak"]) > 0.2,
		"peak angular velocity change a tick in the 0.25 s after the first bite %.3f with, %.3f without, %.2f condition taken"
			% [with_it["peak"], without["peak"], with_it["damage"]])


func _engage_with_destabilise(factor: float) -> Dictionary:
	var world := _make_world()
	var attacker := _spawn(world, _config("attacker", "wedge", "4wd",
		"horizontal_spinner"), ATTACKER_AT, Vector3.RIGHT)
	var target := _spawn(world, _config("target", "box", "2wd", "ram", LIGHT_ARMOUR),
		TARGET_AT, TARGET_FACING)
	_watch(target)
	attacker.weapon.spec["self_destabilise"] = factor
	var peak := 0.0
	var was := Vector3.ZERO
	for _i in range(160):
		attacker.apply_input(_input_for(Vector2.ZERO, true))
		target.apply_input(_input_for(Vector2.ZERO, false))
		await physics_frame
	# Only the FIRST bite counts: the peak is read from the tick the bite lands to
	# 0.25 s after it. Both runs are the same tick for tick up to that bite, so it is
	# a clean with/without comparison. MEASURED 2026-09-27: over the whole 4 s the
	# peak is set by the bar knocking the wall and the target again once the wielder
	# is already spinning (about 8 rad/s a tick with the reaction on or off), which
	# drowns the reaction the check is about.
	var bit_at := -1
	for i in range(240):
		attacker.apply_input(_input_for(Vector2(1.0, 0.0), true))
		target.apply_input(_input_for(Vector2.ZERO, false))
		await physics_frame
		var now: Vector3 = attacker.chassis.angular_velocity
		if bit_at < 0 and _direct_total() > 0.0:
			bit_at = i
		if bit_at >= 0 and i <= bit_at + 15:
			peak = maxf(peak, (now - was).length())
		was = now
	var taken := _direct_total()
	await _drop(world)
	return {"peak": peak, "damage": taken}


# ---------------------------------------------------------------------------
# 5. The saw's cut factor
# ---------------------------------------------------------------------------
## The same 5 s of contact against the same build in two materials. Only the saw's
## own damage on an armour face counts: the shove of driving into the target is
## impact damage and is not the saw's work.
func _check_saw_materials() -> void:
	var hdpe := await _saw_for(_armour("hdpe", 2))
	var steel := await _saw_for(_armour("steel", 2))
	# Two measures, because they answer different questions. The TOTAL is what the
	# fight sees over five seconds and depends on how long the blade stayed on the
	# plate; the PER CUT figure is the catalogue factor itself (0.06 / 60 x 1.6
	# against x 0.4), and it is the one that must land on four.
	var rate := float(hdpe["per_cut"]) / maxf(float(steel["per_cut"]), 0.000001)
	_report("a saw survives five seconds of grinding on steel",
		float(steel["blade"]) > 0.3 and float(hdpe["blade"]) > 0.3,
		"blade condition %.2f on HDPE, %.2f on steel"
			% [hdpe["blade"], steel["blade"]])
	_report("the saw takes HDPE off faster than steel over the same 5 s",
		float(hdpe["total"]) > float(steel["total"]) and float(steel["total"]) > 0.0
			and rate > 3.0,
		"hdpe %.4f total / %.5f per cut, steel %.4f / %.5f, cut factor ratio %.2f"
			% [hdpe["total"], hdpe["per_cut"], steel["total"], steel["per_cut"], rate])


func _saw_for(armour: Dictionary) -> Dictionary:
	var run := await _engage("saw", "wedge", armour, 40, 300)
	var total := 0.0
	var cuts := 0
	for ev in _events:
		if float(ev.get("impulse", 0.0)) != 0.0:
			continue
		if not str(ev.get("part", "")).begins_with("armour_"):
			continue
		total += float(ev.get("severity", 0.0))
		cuts += 1
	var attacker: Bot = run["attacker"]
	var blade := float((attacker.condition() as Dictionary).get("weapon", 0.0))
	await _drop(run["world"])
	return {"total": total, "per_cut": total / maxf(float(cuts), 1.0), "cuts": cuts,
		"blade": blade}


# ---------------------------------------------------------------------------
# 6. The full body spinner
# ---------------------------------------------------------------------------
func _check_full_body_spinner() -> void:
	var world := _make_world()
	var bot := _spawn(world, _config("fbs", "shell", "4wd", "full_body_spinner"),
		Vector3(-2.5, 0.3, -2.5), Vector3.RIGHT)
	var penalty := float(PartsCatalogue.weapon("full_body_spinner").get(
		"control_penalty", 0.5))

	# Stopped: the drive is untouched.
	bot.apply_input(_input_for(Vector2(1.0, 0.0), false))
	var cold := _motor_targets(bot)
	await physics_frame

	for _i in range(int(3.5 * 60.0) + 10):
		bot.apply_input(_input_for(Vector2.ZERO, true))
		await physics_frame
	var spun := bot.weapon_readiness()

	bot.apply_input(_input_for(Vector2(1.0, 0.0), true))
	var hot := _motor_targets(bot)
	await physics_frame

	var ratio := 0.0
	var samples := 0
	for i in range(mini(cold.size(), hot.size())):
		if absf(cold[i]) > 0.01:
			ratio += hot[i] / cold[i]
			samples += 1
	ratio = ratio / maxf(float(samples), 1.0)
	_report("the full body spinner scales the drive by control_penalty while spun up",
		samples > 0 and absf(ratio - penalty) < 0.06,
		"spin %.2f, wheel targets scaled by %.3f against a catalogue %.2f"
			% [spun, ratio, penalty])

	var shielded: bool = bot.weapon.call("shielded")
	var exposed := PackedStringArray()
	for part in bot.attached_parts():
		if part.part_kind == "armour" and (part.collision_layer != 0
				or part.collision_mask != 0):
			exposed.append(String(part.name))
	_report("above 30 percent spin the faces are out of the collision world",
		shielded and exposed.is_empty(), "shielded %s, still live: %s"
			% [shielded, exposed])

	# Jam the ring: it coasts down, and the faces come back.
	bot.weapon.set_jammed()
	for _i in range(int(12.0 * 60.0)):
		bot.apply_input(_input_for(Vector2.ZERO, false))
		await physics_frame
		if float(bot.weapon.call("spin")) <= 0.30:
			break
	var back := true
	for part in bot.attached_parts():
		if part.part_kind == "armour" and part.collision_layer == 0:
			back = false
	_report("a stopped ring gives the faces back",
		back and not bool(bot.weapon.call("shielded")),
		"spin %.2f" % float(bot.weapon.call("spin")))
	await _drop(world)


func _motor_targets(bot: Bot) -> Array[float]:
	var out: Array[float] = []
	for hinge in bot.drive_module.joints:
		if is_instance_valid(hinge):
			out.append(float(hinge.get_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY)))
	return out


# ---------------------------------------------------------------------------
# 7. A jammed weapon
# ---------------------------------------------------------------------------
func _check_jammed() -> void:
	var bad := PackedStringArray()
	for weapon_variant in ["horizontal_spinner", "saw"]:
		var weapon_id := str(weapon_variant)
		var run := await _engage(weapon_id, "wedge", LIGHT_ARMOUR, 160, 180, true)
		var direct := _direct_total()
		var attacker: Bot = run["attacker"]
		if direct > 0.0:
			bad.append("%s still removed %.3f" % [weapon_id, direct])
		if attacker.weapon_readiness() > 0.0:
			bad.append("%s still reads ready" % weapon_id)
		if attacker.weapon_status() != "JAMMED":
			bad.append("%s reads \"%s\"" % [weapon_id, attacker.weapon_status()])
		await _drop(run["world"])
	_report("a jammed weapon spins down and delivers nothing", bad.is_empty(),
		str(bad))


# ---------------------------------------------------------------------------
# 8. Determinism
# ---------------------------------------------------------------------------
func _check_determinism() -> void:
	var first := await _digest_run()
	var second := await _digest_run()
	_report("two runs from the same seed agree at tick 600", first == second,
		"%s\n        vs %s" % [first, second])


## 600 ticks of two scripted head on engagements, all four W1 weapons at once,
## digested to a string. Any divergence in contact ordering, in the overlap order
## the saw's area reports, or in the spin bookkeeping shows up here.
func _digest_run() -> String:
	var world := _make_world()
	var bots: Array[Bot] = []
	bots.append(_spawn(world, _config("a", "wedge", "4wd", "horizontal_spinner"),
		Vector3(-1.6, 0.3, -1.6), Vector3.RIGHT, 11))
	bots.append(_spawn(world, _config("b", "box", "4wd", "saw"),
		Vector3(0.4, 0.3, -1.6), Vector3.LEFT, 12))
	bots.append(_spawn(world, _config("c", "shell", "4wd", "full_body_spinner"),
		Vector3(-1.6, 0.3, 1.6), Vector3.RIGHT, 13))
	bots.append(_spawn(world, _config("d", "wedge", "4wd", "vertical_spinner"),
		Vector3(0.4, 0.3, 1.6), Vector3.LEFT, 14))
	for tick in range(600):
		var fire := tick > 60
		var heading := Vector2.ZERO if tick < 240 else Vector2(1.0, 0.0)
		bots[0].apply_input(_input_for(heading, fire))
		bots[1].apply_input(_input_for(-heading, fire))
		bots[2].apply_input(_input_for(heading, fire))
		bots[3].apply_input(_input_for(-heading, fire))
		await physics_frame
	var parts := PackedStringArray()
	for bot in bots:
		var t: Transform3D = bot.chassis.global_transform
		parts.append("%s:%.5f,%.5f,%.5f|%.4f|%s" % [bot.bot_id, t.origin.x,
			t.origin.y, t.origin.z, bot.weapon_readiness(),
			JSON.stringify(bot.condition())])
	await _drop(world)
	return " ".join(parts)


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
