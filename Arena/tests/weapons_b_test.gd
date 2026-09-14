extends SceneTree
## Stage 4 weapons B test (docs/stage4-spec.md section 4): the lifter, the crusher,
## the axe, the ram and the flamethrower.
##   Godot --headless --path Arena --script tests/weapons_b_test.gd
##
## Every check below is a REAL simulation: a real Bot assembled from the real
## catalogue, in the real yard, driven by the real input record. Headless Godot
## still runs Jolt, so a weapon that only works on paper fails here.
##
## What it proves, one weapon at a time:
##   lifter     raises to 70 degrees inside 1.5 s at the catalogue lift_rate, and
##              lowers again, without launching itself or its load
##   crusher    bites, holds, pins (the victim cannot drive out of it) and chews
##   axe        sweeps the whole arc in 0.15 s, is dead for reset_s, and pays the
##              top bonus on a lid and nothing extra on a nose
##   ram        delivers more momentum than the same bot carrying a dead plate
##   flame      burns fuel_s seconds of gas, damages everything in the cone, and
##              disrupts a victim held in it for one second
## and that two runs of the same seed are identical at tick 600.
##
## Exit code 0 = all PASS.

const BOT_SCENE := "res://bot/bot.tscn"
const YARD_SCENE := "res://arena/yard.tscn"

## Determinism is checked in FRESH CHILD PROCESSES, not by building a second world
## in this one. Jolt walks bodies in body-ID order and a second world gets recycled
## IDs in a different order, which is enough to diverge; a replay always starts a
## fresh process, so that is the case worth testing. Same idiom as physics_test.
const DETERMINISM_FLAG := "--determinism-run"
const DETERMINISM_TICKS := 600

var _checks := 0
var _failures := 0
var _events: Array[Dictionary] = []


func _initialize() -> void:
	if OS.get_cmdline_user_args().has(DETERMINISM_FLAG):
		_emit_determinism_sample()
	else:
		_run()


func _run() -> void:
	print("Roboteer weapons B test, Godot ", Engine.get_version_info()["string"],
		", ", Engine.physics_ticks_per_second, " Hz")
	await _check_lifter()
	await _check_crusher()
	await _check_axe()
	await _check_ram()
	await _check_flamethrower()
	_check_determinism()
	_finish()


# ---------------------------------------------------------------------------
# World helpers
# ---------------------------------------------------------------------------
const ARMOUR := {
	"front": {"material": "steel", "thickness": 2},
	"sides": {"material": "hdpe", "thickness": 1},
	"rear": {"material": "hdpe", "thickness": 1},
	"top": {"material": "hdpe", "thickness": 1},
}


## All steel, for the axe: the two placements have to differ by the BONUS and
## nothing else, and a mixed build hides it. An HDPE lid takes impact at 0.5 and a
## steel nose at 1.0, so a bonused hit on the plastic scores 0.176 and an unbonused
## hit on the steel scores 0.220, and the comparison measures the material.
const STEEL := {
	"front": {"material": "steel", "thickness": 2},
	"sides": {"material": "steel", "thickness": 2},
	"rear": {"material": "steel", "thickness": 2},
	"top": {"material": "steel", "thickness": 2},
}


func _config(id: String, weapon: String, chassis: String = "wedge",
		armour: Dictionary = ARMOUR) -> Dictionary:
	return {
		"id": id, "name": id, "controller": "dummy",
		"chassis": chassis, "drive": "4wd", "weapon": weapon,
		"utility": ["srimech"], "armour": armour.duplicate(true),
	}


## EVERY SCENARIO BELOW RUNS AT z = 3, and that is not decoration. The yard's
## spike patch is 1.6 m square ON THE ORIGIN and its phase comes from the seed, so
## two weapon checks written at z = 0 with different seeds get different answers:
## the crusher's pin measured 0.03 m/s under one seed and 1.56 m/s under another,
## and the difference was the spikes coming up under the victim and throwing it out
## of the claw. A weapon test must measure the weapon.
const LANE_Z := 3.0


func _at(x: float) -> Vector3:
	return Vector3(x, 0.25, LANE_Z)


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
	return {"fight": fight, "rng": rng}


func _spawn(world: Dictionary, cfg: Dictionary, index: int, at: Vector3,
		facing: Vector3) -> Bot:
	var bot: Bot = (load(BOT_SCENE) as PackedScene).instantiate()
	bot.name = "Bot%d" % index
	(world["fight"] as Node3D).add_child(bot)
	bot.place_at(at, facing)
	bot.setup(cfg, index, world["rng"] as RandomNumberGenerator)
	bot.place_at(at, facing)
	return bot


func _teardown(world: Dictionary) -> void:
	# Out of the tree FIRST: queue_free alone leaves the bodies simulating until
	# the end of the frame, which is enough to colour the next world.
	var fight: Node3D = world["fight"]
	root.remove_child(fight)
	fight.queue_free()
	await physics_frame
	await physics_frame


func _step(bots: Array, inputs: Array, count: int) -> void:
	for _i in range(count):
		for b in range(bots.size()):
			(bots[b] as Bot).apply_input(inputs[b])
		await physics_frame


func _idle() -> Dictionary:
	return FightTypes.empty_input()


func _idles(n: int) -> Array:
	var out := []
	for _i in range(n):
		out.append(_idle())
	return out


func _press(heading: Vector2 = Vector2.ZERO) -> Dictionary:
	return {"heading": heading, "fire": true, "secondary": false}


func _drive(heading: Vector2) -> Dictionary:
	return {"heading": heading, "fire": false, "secondary": false}


func _watch(bot: Bot) -> void:
	_events.clear()
	bot.damage_event.connect(func(info: Dictionary) -> void: _events.append(info))


func _events_from(attacker: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in _events:
		if str(e["attacker"]) == attacker:
			out.append(e)
	return out


# ---------------------------------------------------------------------------
# 1. Lifter: slow, strong, no launch
# ---------------------------------------------------------------------------
func _check_lifter() -> void:
	var world := _make_world(41)
	var bot := _spawn(world, _config("lift", "lifter"), 0,
		_at(-2.0), Vector3.RIGHT)
	await _step([bot], _idles(1), 60)
	var w = bot.weapon
	_report("the lifter fits one hinged body on the front socket",
		w != null and w.arm != null and w.joint != null
			and bot.attached_parts().size() == 11,
		"%d bodies" % bot.attached_parts().size())
	_report("at rest the forks are down, ready and at floor level",
		w.readiness() > 0.95 and w.height_band() == "floor"
			and w.status_text() == "LIFT 0%",
		"%.2f ready, band %s, \"%s\", tip %.3f m" % [w.readiness(),
			w.height_band(), w.status_text(), w.tip_height()])

	# Held for 1.5 s at the catalogue lift_rate of 1.2 rad/s. 70 degrees is 1.22
	# rad, so a working lifter is there in 1.02 s and still holding at 1.50 s.
	var peak := 0.0
	var highest := 0.0
	for _i in range(90):
		bot.apply_input(_press())
		await physics_frame
		peak = maxf(peak, w.lift_angle())
		highest = maxf(highest, bot.chassis.global_position.y)
	_report("held, the forks reach 70 degrees inside 1.5 s",
		peak >= deg_to_rad(69.0), "%.1f degrees" % rad_to_deg(peak))
	_report("at full lift the forks read high", w.height_band() == "high"
		and w.status_text() == "LIFT 100%",
		"band %s, \"%s\", tip %.3f m" % [w.height_band(), w.status_text(),
			w.tip_height()])
	_report("a lifter never launches itself", highest < 0.25,
		"wielder peak %.3f m" % highest)

	await _step([bot], _idles(1), 120)
	_report("released, the forks come back down",
		w.lift_angle() < deg_to_rad(6.0) and w.height_band() == "floor",
		"%.1f degrees, band %s" % [rad_to_deg(w.lift_angle()), w.height_band()])
	_report("a lowered lifter is ready again", w.readiness() > 0.95,
		"%.2f" % w.readiness())
	await _teardown(world)


# ---------------------------------------------------------------------------
# 2. Crusher: bite, pin, chew
# ---------------------------------------------------------------------------
func _check_crusher() -> void:
	var world := _make_world(42)
	var att := _spawn(world, _config("claw", "crusher", "box"), 0,
		_at(-2.0), Vector3.RIGHT)
	var vic := _spawn(world, _config("prey", "flipper", "box"), 1,
		_at(-0.9), Vector3.LEFT)
	await _step([att, vic], _idles(2), 60)
	var w = att.weapon
	_watch(vic)
	_report("the jaw rides open and says so",
		w.open_fraction() > 0.8 and w.status_text() == "OPEN",
		"%.0f%% open, \"%s\"" % [w.open_fraction() * 100.0, w.status_text()])

	# Creep in with the jaw shutting: the bite has to happen in the fight, not be
	# arranged by placing a part inside the claw.
	var clamped_at := -1
	for i in range(180):
		att.apply_input(_press(Vector2(0.35, 0.0)))
		vic.apply_input(_idle())
		await physics_frame
		if clamped_at < 0 and w.is_clamped():
			clamped_at = i
	_report("closing on an opponent clamps it", w.is_clamped()
		and w.status_text() == "CLAMP",
		"clamped at tick %d, \"%s\", holding %s" % [clamped_at, w.status_text(),
			str(w.clamped_part().part_key if w.clamped_part() != null else "nothing")])
	_report("a clamped bot has its drive fought", vic.is_disrupted("drive"), "")

	# The pin: the victim drives flat out and cannot get away.
	var before := _condition_of(vic, "armour_front")
	var worst := 0.0
	# The wielder holds the button and NOTHING ELSE: leaving 15 percent of throttle
	# on walked the pair forward at 0.16 m/s, which is not the victim escaping, it
	# is the claw carrying it, and the check would have been measuring the wrong
	# bot.
	for i in range(120):
		att.apply_input(_press())
		vic.apply_input(_drive(Vector2(-1.0, 0.0)))
		await physics_frame
		if i >= 60:
			worst = maxf(worst, vic.chassis.linear_velocity.length())
	_report("a pinned bot cannot drive out of the claw", worst < 0.1,
		"top speed %.3f m/s over the second second of trying" % worst)
	_report("the claw chews what it is holding",
		_condition_of(vic, "armour_front") < before,
		"front plate %.4f -> %.4f" % [before, _condition_of(vic, "armour_front")])
	_report("the chewing is recorded as damage from the claw",
		not _events_from("claw").is_empty(),
		"%d events" % _events_from("claw").size())

	# Letting go.
	await _step([att, vic], _idles(2), 30)
	_report("releasing the button frees the victim",
		not w.is_clamped() and not vic.is_disrupted("drive")
			and w.status_text() == "OPEN",
		"\"%s\", disrupted %s" % [w.status_text(), str(vic.is_disrupted("drive"))])
	await _teardown(world)


func _condition_of(bot: Bot, key: String) -> float:
	var c := bot.condition()
	if key.begins_with("armour_"):
		return float((c["armour"] as Dictionary)[key.substr(7)])
	return float(c.get(key, 0.0))


# ---------------------------------------------------------------------------
# 3. Axe: one huge hit, then nothing for reset_s
# ---------------------------------------------------------------------------
## THE TWO PLACEMENTS ARE MEASURED, not guessed, and both are a real fight
## position rather than a rig.
##   0.78 m, a WEDGE turned broadside: the head crosses an opponent's lid height
##   (0.24 m) 0.85 m ahead of the wielder's centre, and a wedge is 0.64 m across,
##   so parked alongside at 0.78 m its DECK is under the arc. A flank attack.
##   1.30 m, a TALL TANK nose on: its front plate stands 0.52 m tall and is by far
##   the nearest body to the head all the way down, so the axe bangs its nose and
##   pays no bonus. Charging something taller than you.
## That pair is the catalogue's whole promise for this weapon: the answer to a low
## flat lid, merely loud against something tall.
func _check_axe() -> void:
	var top_severity := await _axe_swing("on a flank", _at(-1.22),
		Vector3.BACK, "wedge", true)
	var nose_severity := await _axe_swing("on a tall nose", _at(-0.70),
		Vector3.LEFT, "tall_tank", false)
	_report("a hit on the lid scores harder than a hit on a nose",
		top_severity > nose_severity * 1.3,
		"%.4f vs %.4f" % [top_severity, nose_severity])


## Returns the severity the swing took off the victim.
func _axe_swing(label: String, at: Vector3, facing: Vector3, chassis: String,
		want_top: bool) -> float:
	var world := _make_world(43)
	var att := _spawn(world, _config("axe", "axe"), 0,
		_at(-2.0), Vector3.RIGHT)
	var vic := _spawn(world, _config("prey", "flipper", chassis, STEEL), 1, at, facing)
	await _step([att, vic], _idles(2), 60)
	var w = att.weapon
	_watch(vic)
	if want_top:
		_report("the axe waits cocked and ready",
			w.readiness() >= 1.0 and w.status_text() == "READY"
				and absf(w.arm_angle() - w.rest_angle) < deg_to_rad(4.0),
			"\"%s\", arm %.1f degrees" % [w.status_text(), rad_to_deg(w.arm_angle())])

	att.apply_input(_press())
	await physics_frame
	var travelled := 0.0
	for _i in range(9):
		att.apply_input(_idle())
		vic.apply_input(_idle())
		await physics_frame
		travelled = maxf(travelled, w.rest_angle - w.arm_angle())
	if want_top:
		_report("the swing throws the whole arc in 0.15 s",
			travelled > w.sweep() * 0.85,
			"%.1f of %.1f degrees" % [rad_to_deg(travelled), rad_to_deg(w.sweep())])
		_report("a second press during the reset does nothing",
			w.readiness() < 1.0 and w.status_text() == "RESET",
			"\"%s\", %.2f ready" % [w.status_text(), w.readiness()])

	# reset_s from the end of the swing, then it is cocked again.
	var reset_ticks := int(round(1.4 * 60.0))
	await _step([att, vic], _idles(2), reset_ticks + 6)
	if want_top:
		_report("after reset_s the arm is cocked and ready again",
			w.readiness() >= 1.0 and w.status_text() == "READY"
				and absf(w.arm_angle() - w.rest_angle) < deg_to_rad(10.0),
			"\"%s\", arm %.1f of %.1f degrees" % [w.status_text(),
				rad_to_deg(w.arm_angle()), rad_to_deg(w.rest_angle)])
		_report("the top bonus is the catalogue's, exactly",
			is_equal_approx(w.strike_amount(true), w.strike_amount(false) * 1.6),
			"%.4f vs %.4f" % [w.strike_amount(true), w.strike_amount(false)])

	var strike: Dictionary = w.last_strike()
	var severity := 0.0
	for e in _events_from("axe"):
		severity += float(e["severity"])
	_report("the axe lands a blow %s and it is recorded on the victim" % label,
		not strike.is_empty() and severity > 0.0,
		"struck %s, top %s, %d events, %.4f severity" % [
			str(strike.get("part", "nothing")), str(strike.get("top", false)),
			_events_from("axe").size(), severity])
	_report("%s reads as a %s face" % [label, "top" if want_top else "non top"],
		bool(strike.get("top", false)) == want_top,
		"top = %s" % str(strike.get("top", false)))
	await _teardown(world)
	return severity


# ---------------------------------------------------------------------------
# 4. Ram: the same charge, harder
# ---------------------------------------------------------------------------
## THE CONTROL IS A BENT RAM, not a bot with no weapon, and that is the point of
## the check. An inert plate is a different shape in a different place (on a box it
## stands 0.18 m proud of the nose, on a wedge it is buried inside the bodywork),
## so a bot carrying one is not the same bot minus the bonus, it is a different
## bot. `set_jammed()` leaves the mass, the spike and the geometry exactly where
## they are and turns the multiplier off, which is also a real state the game
## reaches when the ram's condition hits zero. Box against box, because a wedge
## victim turns any head on charge into a ride up its own ramp and what is being
## measured then is the ramp.
func _check_ram() -> void:
	var with_ram := await _charge(false)
	var without := await _charge(true)
	_report("a ram delivers more than the same ram bent",
		float(with_ram["early"]) > float(without["early"]) * 1.10
			and float(with_ram["moved"]) > float(without["moved"]),
		"victim 0.13 s after the hit %.3f m/s vs %.3f, peak %.3f vs %.3f, pushed %.2f m vs %.2f" % [
			with_ram["early"], without["early"], with_ram["peak"], without["peak"],
			with_ram["moved"], without["moved"]])
	_report("both charges arrived at the same speed, so that is the weapon",
		absf(float(with_ram["closing"]) - float(without["closing"])) < 0.15,
		"%.3f m/s vs %.3f" % [with_ram["closing"], without["closing"]])
	_report("the bonus momentum went forward, into the victim, once",
		Vector3(with_ram["extra"]).x > 0.0 and int(with_ram["hits"]) == 1,
		"%s N s in %d blow(s)" % [str(with_ram["extra"]), with_ram["hits"]])


## One head on charge, with the bonus on or bent off. THE THROTTLE IS CUT AT
## CONTACT, because a bot that keeps driving turns the collision into a shove and a
## shove hides the weapon: the victim ends up travelling at the pusher's top speed
## whatever it was hit with (measured, 1.632 m/s with the bonus and 1.632 without).
## What a ram actually buys is the impulse of the hit, so the hit is what is
## measured.
func _charge(bent: bool) -> Dictionary:
	var world := _make_world(44)
	var att := _spawn(world, _config("charger", "ram", "box"), 0,
		_at(-2.4), Vector3.RIGHT)
	# THE VICTIM CARRIES NO WEAPON (an unknown id fits the Bot's inert plate), and
	# that is not tidiness. A flipper's arm reaches 0.55 m past its owner's front
	# socket, so the first version of this check had the ram charging into a 4 kg
	# arm on a hinge: `get_colliding_bodies()` said "Flipper" for 45 ticks and
	# nothing else, the arm gave way, and the bonus had almost nothing to multiply.
	# What is being measured here is a ram hitting a bot, so it hits a bot.
	var vic := _spawn(world, _config("prey", "none", "box"), 1,
		_at(-0.5), Vector3.LEFT)
	if bent:
		att.weapon.set_jammed()
	await _step([att, vic], _idles(2), 40)
	var start: float = vic.chassis.global_position.x
	var peak := 0.0
	var closing := 0.0
	var hit := -1
	for i in range(150):
		att.apply_input(_drive(Vector2(1.0, 0.0)))
		vic.apply_input(_idle())
		await physics_frame
		# 0.08, not 0.03: a settled bot still jitters at 0.03 and the throttle would
		# be cut half a second before anything touched it.
		if vic.chassis.linear_velocity.length() > 0.08:
			closing = att.chassis.linear_velocity.length()
			hit = i
			break
	# `early` is the victim 0.13 s after the hit, and it is the honest measure of
	# an impulse bonus. A victim still in contact with the bot that hit it cannot
	# travel faster than that bot, so a peak taken a second later says almost
	# nothing; what the bonus buys is being knocked away SOONER.
	var early := 0.0
	for i in range(45):
		att.apply_input(_idle())
		vic.apply_input(_idle())
		await physics_frame
		var v: float = vic.chassis.linear_velocity.length()
		peak = maxf(peak, v)
		if i == 7:
			early = v
	_report("the charge reached the victim" if not bent else
		"the bent charge reached the victim too", hit >= 0, "contact at tick %d" % hit)
	var extra := Vector3.ZERO
	var hits := 0
	if att.weapon.has_method("bonus_delivered"):
		extra = att.weapon.bonus_delivered()
		hits = att.weapon.bonus_hits()
	if not bent:
		_report("a ram is always ready and has nothing to spin up",
			att.weapon.readiness() >= 1.0 and att.weapon.status_text() == "RAM", "")
	var moved: float = vic.chassis.global_position.x - start
	await _teardown(world)
	return {"peak": peak, "closing": closing, "moved": moved, "extra": extra,
		"hits": hits, "early": early}


# ---------------------------------------------------------------------------
# 5. Flamethrower: 20 seconds of gas, and what it does with them
# ---------------------------------------------------------------------------
func _check_flamethrower() -> void:
	var world := _make_world(45)
	var att := _spawn(world, _config("flame", "flamethrower"), 0,
		_at(-2.0), Vector3.RIGHT)
	var vic := _spawn(world, _config("prey", "flipper"), 1,
		_at(-0.95), Vector3.LEFT)
	await _step([att, vic], _idles(2), 60)
	var w = att.weapon
	_watch(vic)
	_report("a full bottle reads full",
		w.readiness() >= 1.0 and w.status_text() == "FUEL 20s",
		"\"%s\"" % w.status_text())

	var before := _total_condition(vic)
	var disrupted_at := -1
	var kinds: Array[String] = []
	for i in range(180):
		att.apply_input(_press())
		vic.apply_input(_idle())
		await physics_frame
		for kind in ["weapon", "drive"]:
			if vic.is_disrupted(kind) and not kinds.has(kind):
				kinds.append(kind)
		if disrupted_at < 0 and not kinds.is_empty():
			disrupted_at = i
	_report("a second in the fire disrupts the victim",
		disrupted_at >= 55 and disrupted_at <= 75,
		"disrupted at tick %d (%.2f s)" % [disrupted_at, disrupted_at / 60.0])
	_report("the disruption alternates, so three seconds takes both systems",
		kinds.has("weapon") and kinds.has("drive"), str(kinds))
	_report("everything in the cone burns",
		_total_condition(vic) < before and not _events_from("flame").is_empty(),
		"condition %.3f -> %.3f over %d events" % [before, _total_condition(vic),
			_events_from("flame").size()])
	_report("the gauge counts the gas down at one second per second",
		absf(w.fuel_left() - 17.0) < 0.1 and w.status_text() == "FUEL 17s",
		"%.2f s left, \"%s\"" % [w.fuel_left(), w.status_text()])

	# Burn the bottle dry. 20 s of fuel, 3 s already gone.
	var dry_at := -1
	for i in range(1120):
		att.apply_input(_press())
		vic.apply_input(_idle())
		await physics_frame
		if dry_at < 0 and w.fuel_left() <= 0.0:
			dry_at = i
	_report("the bottle holds exactly fuel_s seconds",
		dry_at >= 0 and absf((180 + dry_at + 1) / 60.0 - 20.0) < 0.1,
		"empty after %.2f s of burning" % ((180 + dry_at + 1) / 60.0))
	_report("a dry flamethrower says so and stops burning",
		w.readiness() == 0.0 and w.status_text() == "DRY" and not w.burning(),
		"\"%s\", burning %s" % [w.status_text(), str(w.burning())])
	await _teardown(world)


func _total_condition(bot: Bot) -> float:
	var c := bot.condition()
	var total := 0.0
	for v in (c["wheels"] as Array):
		total += float(v)
	total += float(c["weapon"]) + float(c["drive"]) + float(c["core"])
	for key in (c["armour"] as Dictionary).keys():
		total += float((c["armour"] as Dictionary)[key])
	return total


# ---------------------------------------------------------------------------
# 6. Determinism
# ---------------------------------------------------------------------------
func _check_determinism() -> void:
	var a := _child_sample()
	var b := _child_sample()
	if a.is_empty() or b.is_empty() or a.size() != b.size():
		_report("two seeded weapon runs match at tick %d" % DETERMINISM_TICKS, false,
			"child run produced no sample (%d vs %d numbers)" % [a.size(), b.size()])
		return
	var worst := 0.0
	for i in range(a.size()):
		worst = maxf(worst, absf(a[i] - b[i]))
	_report("two seeded weapon runs match at tick %d" % DETERMINISM_TICKS,
		worst == 0.0,
		"max component difference %.9f over %d components" % [worst, a.size()])


func _child_sample() -> PackedFloat64Array:
	var out: Array = []
	var args := PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "tests/weapons_b_test.gd", "--", DETERMINISM_FLAG,
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


func _emit_determinism_sample() -> void:
	var sample := await _determinism_run()
	print("SAMPLE " + sample)
	quit(0)


## Two of these weapons under scripted input for ten seconds: the flamethrower,
## which is the only one of the five that draws on the rng, and the crusher, which
## is the only one that pushes on the other bot every tick.
func _determinism_run() -> String:
	var world := _make_world(987654321)
	var a := _spawn(world, _config("flame", "flamethrower"), 0,
		_at(-1.6), Vector3.RIGHT)
	var b := _spawn(world, _config("claw", "crusher", "box"), 1,
		_at(-0.5), Vector3.LEFT)
	for tick in range(DETERMINISM_TICKS):
		a.apply_input(_scripted_input(tick, 0))
		b.apply_input(_scripted_input(tick, 1))
		await physics_frame
	var parts := PackedStringArray()
	for bot in [a, b]:
		for part in (bot as Bot).attached_parts():
			var t: Transform3D = part.global_transform
			for v in [t.basis.x, t.basis.y, t.basis.z, t.origin]:
				var vec: Vector3 = v
				parts.append("%.9f" % vec.x)
				parts.append("%.9f" % vec.y)
				parts.append("%.9f" % vec.z)
	parts.append("%.9f" % float(a.weapon.fuel_left()))
	await _teardown(world)
	return ",".join(parts)


## A fixed script, not random: the same every run by construction.
func _scripted_input(tick: int, side: int) -> Dictionary:
	var t := float(tick) / 60.0
	var turn := sin(t * 1.3 + float(side) * 2.1)
	var push := 0.5 + 0.5 * cos(t * 0.7 + float(side))
	var heading := Vector2(cos(turn), sin(turn)) * clampf(push, 0.0, 1.0)
	if side == 1:
		heading = -heading
	return {
		"heading": heading,
		"fire": (tick / 40) % 2 == 0,
		"secondary": false,
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
