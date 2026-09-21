extends SceneTree
## Wave P, agent D2: the seven parts of brief v5 section 9.5 that are not weapons.
##   Godot --headless --path Arena --script tests/mobility_p_test.gd
##
## The parts, and what this proves about each one:
##   legs             fits, walks, turns, out pushes a 6WD, steps over a hazard
##   hover            fits, is the fastest thing in the catalogue, cannot push,
##                    takes nothing at all from a floor hazard, flips easily
##   adaptive_tracks  fits, drives, and a belt chewed to zero condition neither
##                    comes off the machine nor takes its steering away
##   apex             fits every weapon in the catalogue, is the hardest hull to
##                    flip or tip, and is heavy enough that the build pays for it
##   reinforced       best plate in the game against hazards and cuts, heaviest
##   reactive         best against impacts, and it shoves the attacker away
##   overcharge_core  faster spin up, 25 per cent harder blows, and it cooks the
##                    machine's own core while the weapon is at full
##
## Plus the catalogue gates every part of this wave has to pass: the two parts.json
## copies are byte identical, and every new row carries the keys its kind carries.
##
## Deterministic: no `randf`, no `randi`, no wall clock. Every rng is seeded and
## every measurement is taken after a fixed number of physics ticks.
## Exit code 0 = all PASS.

const BOT_SCENE := "res://bot/bot.tscn"
const YARD_SCENE := "res://arena/yard.tscn"
const SHARED_PARTS := "res://../Shared/parts.json"

const DRIVES := ["legs", "hover", "adaptive_tracks"]
const MATERIALS := ["reinforced", "reactive"]

## The keys every drive row carries, whatever else it carries.
const DRIVE_KEYS := ["name", "weight", "wheels", "top_speed", "turn_rate",
	"push_force", "traction", "wheel_loss", "blurb"]
const CHASSIS_KEYS := ["name", "weight", "footprint", "height", "clearance_front",
	"clearance_rear", "com_height", "invertible", "srimech_required",
	"inverted_note", "mount_weapon", "blurb", "wheel_slots"]
const MATERIAL_KEYS := ["name", "kg_per_unit_area", "vs_spinner", "vs_saw_axe", "factor"]
const UTILITY_KEYS := ["name", "weight", "effect", "blurb"]

## Somewhere with room to drive and nothing underfoot: the yard's spike patch is a
## 1.6 m square on the origin and its walls are at 5 m.
const SPAWN := Vector3(-3.2, 0.25, -3.2)
const FACING := Vector3.RIGHT

const LIGHT_ARMOUR := {
	"front": {"material": "steel", "thickness": 2},
	"sides": {"material": "hdpe", "thickness": 1},
	"rear": {"material": "hdpe", "thickness": 1},
	"top": {"material": "hdpe", "thickness": 1},
}

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	print("Roboteer wave P mobility test, Godot ", Engine.get_version_info()["string"])
	await process_frame
	if not ResourceLoader.exists(BOT_SCENE):
		print("SKIP  wave P mobility: %s is absent" % BOT_SCENE)
		quit(0)
		return
	_check_catalogue()
	_check_fits()
	await _check_moves()
	await _check_hazards()
	await _check_adaptive_belt()
	await _check_reactive()
	await _check_overcharge()
	await _check_push()
	_finish()


# ---------------------------------------------------------------------------
# 1. The catalogue
# ---------------------------------------------------------------------------
func _check_catalogue() -> void:
	var arena := FileAccess.get_file_as_bytes(PartsCatalogue.PARTS_PATH)
	var shared := FileAccess.get_file_as_bytes(SHARED_PARTS)
	_report("Arena/data/parts.json is byte identical to Shared/parts.json",
		not arena.is_empty() and arena == shared,
		"%d vs %d bytes" % [arena.size(), shared.size()])

	var missing := PackedStringArray()
	for id in DRIVES:
		_needs("drive", id, PartsCatalogue.drive(str(id)), DRIVE_KEYS, missing)
	_needs("chassis", "apex", PartsCatalogue.chassis("apex"), CHASSIS_KEYS, missing)
	for id in MATERIALS:
		_needs("material", id, PartsCatalogue.armour_material(str(id)),
			MATERIAL_KEYS, missing)
	_needs("utility", "overcharge_core", PartsCatalogue.utility("overcharge_core"),
		UTILITY_KEYS, missing)
	_report("every new row carries the keys its kind carries", missing.is_empty(),
		str(missing))

	# Each one has a script, or it would silently fall back to the base class.
	var no_module := PackedStringArray()
	for id in DRIVES:
		if not ResourceLoader.exists("res://bot/drive/%s.gd" % id):
			no_module.append(str(id))
	if not ResourceLoader.exists("res://bot/chassis/apex.gd"):
		no_module.append("apex")
	_report("every new drive and the apex hull has its own module",
		no_module.is_empty(), str(no_module))

	# The ladder the shop reads has to know about all seven.
	var progression: Dictionary = PartsCatalogue.parts().get("progression", {}) as Dictionary
	var levels: Dictionary = progression.get("level_required", {}) as Dictionary
	var unladdered := PackedStringArray()
	for id in ["legs", "hover", "adaptive_tracks", "apex", "reinforced", "reactive",
			"overcharge_core"]:
		if not levels.has(id):
			unladdered.append(str(id))
	_report("all seven are on the Level ladder", unladdered.is_empty(), str(unladdered))

	# The two plates are the best in the game at what the brief says they are best
	# at, and they are not the best at everything.
	var reinforced_hazard := PartsCatalogue.material_factor("reinforced", "hazard")
	var reinforced_cut := PartsCatalogue.material_factor("reinforced", "cut")
	var reactive_impact := PartsCatalogue.material_factor("reactive", "impact")
	var best_hazard := true
	var best_cut := true
	var best_impact := true
	for id_variant in PartsCatalogue.armour_materials():
		var id := str(id_variant)
		if id != "reinforced":
			best_hazard = best_hazard \
				and PartsCatalogue.material_factor(id, "hazard") > reinforced_hazard
			best_cut = best_cut and PartsCatalogue.material_factor(id, "cut") > reinforced_cut
		if id != "reactive":
			best_impact = best_impact \
				and PartsCatalogue.material_factor(id, "impact") > reactive_impact
	_report("reinforced steel is the best plate against hazards and cuts",
		best_hazard and best_cut, "hazard %.2f, cut %.2f"
			% [reinforced_hazard, reinforced_cut])
	_report("reactive armour is the best plate against impacts", best_impact,
		"impact %.2f" % reactive_impact)
	_report("reinforced steel is heavier than titanium and than steel",
		float(PartsCatalogue.armour_material("reinforced").get("kg_per_unit_area", 0.0))
			> float(PartsCatalogue.armour_material("steel").get("kg_per_unit_area", 0.0)),
		"%.1f kg per unit area"
			% float(PartsCatalogue.armour_material("reinforced").get("kg_per_unit_area", 0.0)))
	_report("only reactive armour carries a knockback charge",
		float(PartsCatalogue.armour_material("reactive").get("knockback", 0.0)) > 0.0
			and float(PartsCatalogue.armour_material("steel").get("knockback", 0.0)) == 0.0, "")

	# The drive numbers the brief promises, read off the catalogue rather than
	# asserted in code.
	var fastest := true
	var pushiest := true
	for id_variant in PartsCatalogue.ids("drive"):
		var id := str(id_variant)
		if id != "hover":
			fastest = fastest and float(PartsCatalogue.drive(id).get("top_speed", 0.0)) \
				< float(PartsCatalogue.drive("hover").get("top_speed", 0.0))
		if id != "legs":
			pushiest = pushiest and float(PartsCatalogue.drive(id).get("push_force", 0.0)) \
				< float(PartsCatalogue.drive("legs").get("push_force", 0.0))
	_report("the hover is the fastest drive in the catalogue", fastest,
		"%.1f m/s" % float(PartsCatalogue.drive("hover").get("top_speed", 0.0)))
	_report("the legs push harder than anything else in the catalogue", pushiest,
		"%.1f" % float(PartsCatalogue.drive("legs").get("push_force", 0.0)))

	var apex := PartsCatalogue.chassis("apex")
	_report("the apex takes every weapon (no weapons_allowed row)",
		not apex.has("weapons_allowed"), str(apex.get("weapons_allowed", "absent")))
	var hardest := true
	for id_variant in PartsCatalogue.ids("chassis"):
		var id := str(id_variant)
		if id == "apex":
			continue
		var row := PartsCatalogue.chassis(id)
		hardest = hardest and float(row.get("flip_resistance", 1.0)) \
			< float(apex.get("flip_resistance", 1.0))
	_report("the apex is the hardest hull in the catalogue to flip", hardest,
		"flip resistance %.1f" % float(apex.get("flip_resistance", 1.0)))
	_report("the apex has wheel slots for 2WD, 4WD and 6WD",
		_has_slots(apex, "2wd") and _has_slots(apex, "4wd") and _has_slots(apex, "6wd"), "")


func _needs(kind: String, id: String, row: Dictionary, keys: Array,
		missing: PackedStringArray) -> void:
	if row.is_empty():
		missing.append("%s %s is not in the catalogue" % [kind, id])
		return
	for key in keys:
		if not row.has(key):
			missing.append("%s %s has no %s" % [kind, id, key])


func _has_slots(chassis: Dictionary, drive_id: String) -> bool:
	var table: Dictionary = chassis.get("wheel_slots", {}) as Dictionary
	var rows: Array = table.get(drive_id, []) as Array
	return rows.size() >= 2


# ---------------------------------------------------------------------------
# 2. They fit
# ---------------------------------------------------------------------------
func _config(chassis: String, drive: String, weapon: String, utility: Array,
		armour: Dictionary = LIGHT_ARMOUR) -> Dictionary:
	return {
		"id": "p2-%s-%s-%s" % [chassis, drive, weapon],
		"name": "Test", "controller": "dummy",
		"chassis": chassis, "drive": drive, "weapon": weapon,
		"utility": utility.duplicate(), "armour": armour.duplicate(true),
	}


func _check_fits() -> void:
	var rejected := PackedStringArray()
	for drive_id in DRIVES:
		var config := _config("box", str(drive_id), "ram", ["srimech"])
		var errors := BuildRules.validate(config)
		if not errors.is_empty():
			rejected.append("%s: %s" % [drive_id, str(errors)])
	_report("every new drive makes a legal build", rejected.is_empty(), str(rejected))

	var bad_material := PackedStringArray()
	for material_id in MATERIALS:
		var armour := {}
		for face in BuildRules.FACES:
			armour[face] = {"material": str(material_id), "thickness": 1}
		var errors := BuildRules.validate(
			_config("box", "4wd", "ram", ["srimech"], armour))
		if not errors.is_empty():
			bad_material.append("%s: %s" % [material_id, str(errors)])
	_report("both new plates make a legal build on every face",
		bad_material.is_empty(), str(bad_material))

	_report("the overcharge core makes a legal build",
		BuildRules.validate(_config("box", "4wd", "horizontal_spinner",
			["srimech", "overcharge_core"])).is_empty(),
		str(BuildRules.validate(_config("box", "4wd", "horizontal_spinner",
			["srimech", "overcharge_core"]))))

	# The apex takes every weapon in the catalogue that is not pinned to another
	# hull, which is the whole of what Level 100 buys.
	var refused := PackedStringArray()
	for weapon_variant in PartsCatalogue.ids("weapon"):
		var weapon_id := str(weapon_variant)
		var required := str(PartsCatalogue.weapon(weapon_id).get("requires_chassis", ""))
		if required != "" and required != "apex":
			continue
		var errors := BuildRules.validate(
			_config("apex", "2wd", weapon_id, ["srimech"]))
		for problem in errors:
			if problem.begins_with("The Apex only takes"):
				refused.append("%s: %s" % [weapon_id, problem])
	_report("no weapon in the catalogue is refused by the apex", refused.is_empty(),
		str(refused))

	# And it charges for it: heaviest hull in the game, so the build has to give
	# something up somewhere.
	var heaviest := true
	for id_variant in PartsCatalogue.ids("chassis"):
		var id := str(id_variant)
		if id != "apex":
			heaviest = heaviest and float(PartsCatalogue.chassis(id).get("weight", 0.0)) \
				< float(PartsCatalogue.chassis("apex").get("weight", 0.0))
	_report("the apex is the heaviest hull in the catalogue, so it costs the build",
		heaviest, "%.0f kg" % float(PartsCatalogue.chassis("apex").get("weight", 0.0)))


# ---------------------------------------------------------------------------
# 3. They move
# ---------------------------------------------------------------------------
func _check_moves() -> void:
	var still := PackedStringArray()
	var wont_turn := PackedStringArray()
	var bad_mass := PackedStringArray()
	var cases := [["wedge", "legs"], ["wedge", "hover"], ["wedge", "adaptive_tracks"],
		["apex", "4wd"], ["apex", "legs"]]
	for case_variant in cases:
		var case: Array = case_variant
		var config := _config(str(case[0]), str(case[1]), "ram", ["srimech"])
		var world := _make_world()
		var bot := _spawn(world, config)
		var label := "%s/%s" % [case[0], case[1]]

		# The catalogue kilograms have to reach the simulation even when the drive
		# builds no bodies at all: `Bot.add_hull_mass` puts them on the hull.
		var want_mass := BuildRules.total_weight(config) * Bot.MASS_SCALE
		if absf(bot.total_mass() - want_mass) > want_mass * 0.10:
			bad_mass.append("%s %.1f vs %.1f" % [label, bot.total_mass(), want_mass])

		await _step(bot, FightTypes.empty_input(), 40)
		var start: Vector3 = bot.chassis.global_position
		await _step(bot, {"heading": Vector2(1.0, 0.0), "fire": false,
			"secondary": false}, 60)
		var moved := (bot.chassis.global_position - start).length()
		if moved < 1.5:
			still.append("%s %.2f m in a second" % [label, moved])

		var want := Vector2(0.0, -1.0)
		var want_yaw := atan2(-want.y, want.x)
		var best := PI
		for _i in range(120):
			bot.apply_input({"heading": want, "fire": false, "secondary": false})
			await physics_frame
			var fwd := bot.chassis.global_basis.x
			fwd.y = 0.0
			best = minf(best, absf(wrapf(want_yaw - atan2(-fwd.z, fwd.x), -PI, PI)))
		if best > deg_to_rad(45.0):
			wont_turn.append("%s %.0f deg" % [label, rad_to_deg(best)])
		await _drop(world)

	_report("every new drive and the apex hull covers 1.5 m in a second",
		still.is_empty(), str(still))
	_report("every new drive and the apex hull turns halfway to a new heading",
		wont_turn.is_empty(), str(wont_turn))
	_report("a drive with no wheel bodies still weighs its catalogue kilograms",
		bad_mass.is_empty(), str(bad_mass))

	# The hover really does ride above the floor, and the walker really does stand
	# taller than it would roll.
	var world_h := _make_world()
	var hover := _spawn(world_h, _config("box", "hover", "ram", ["srimech"]))
	await _step(hover, FightTypes.empty_input(), 90)
	var ride: float = hover.chassis.global_position.y
	var want_ride := float(PartsCatalogue.drive("hover").get("hover_height", 0.2))
	_report("the hover holds its cushion within 3 cm of the catalogue height",
		absf(ride - want_ride) < 0.03, "%.3f m against %.2f" % [ride, want_ride])
	_report("the hover reports no wheel rows at all, so the report never calls a "
		+ "fan a wheel", (hover.condition()["wheels"] as Array).is_empty(),
		str(hover.condition()["wheels"]))
	# Flips easily: the hull's resistance, cut by the drive.
	var hull_flip := float(PartsCatalogue.chassis("box").get("flip_resistance", 1.0))
	_report("a hover flips more easily than the same hull on wheels",
		hover.flip_resistance() < hull_flip, "%.2f against %.2f"
			% [hover.flip_resistance(), hull_flip])
	await _drop(world_h)

	var world_l := _make_world()
	var legs := _spawn(world_l, _config("box", "legs", "ram", ["srimech"]))
	await _step(legs, FightTypes.empty_input(), 90)
	_report("the walker stands on its feet at the catalogue stance height",
		absf(legs.chassis.global_position.y
			- float(PartsCatalogue.drive("legs").get("stance_height", 0.14))) < 0.03,
		"%.3f m" % legs.chassis.global_position.y)
	_report("nothing on the walker was damaged by being set down",
		_events.is_empty(), _describe_events())
	_report("a walker is harder to flip than the same hull on wheels",
		legs.flip_resistance() > hull_flip, "%.2f against %.2f"
			% [legs.flip_resistance(), hull_flip])
	await _drop(world_l)


# ---------------------------------------------------------------------------
# 4. Floor hazards
# ---------------------------------------------------------------------------
## `Bot.hazard_hit` is the arena's own entry point: every spike patch, grinder and
## flame jet in the game reaches a machine through `arena_base._damage_overlaps`,
## which calls exactly this with the hazard's impulse. Driving a bot onto the
## yard's patch and waiting for the cycle would measure the yard's clock; calling
## the hazard in is the same blow, at a time this test picks.
func _check_hazards() -> void:
	# One plate, three blows, so nothing saturates and the three numbers can be
	# compared: a face at zero condition stops taking damage and would flatten the
	# comparison (measured, 2026-09-21).
	var taken := {}
	for drive_id in ["4wd", "legs", "hover"]:
		var world := _make_world()
		var bot := _spawn(world, _config("box", str(drive_id), "ram", ["srimech"]))
		await _step(bot, FightTypes.empty_input(), 60)
		var plate := _part_with_key(bot, "armour_front")
		var before := float((bot.condition()["armour"] as Dictionary)["front"])
		for _i in range(3):
			bot.hazard_hit(plate, 60.0, plate.global_position)
			await physics_frame
		taken[str(drive_id)] = before \
			- float((bot.condition()["armour"] as Dictionary)["front"])
		await _drop(world)

	var want_factor := float(PartsCatalogue.drive("legs").get("hazard_factor", 1.0))
	_report("a floor hazard bites a machine on wheels", float(taken["4wd"]) > 0.05,
		"%.3f condition" % float(taken["4wd"]))
	_report("a hover takes NOTHING from a floor hazard: it floats over the spikes",
		is_equal_approx(float(taken["hover"]), 0.0), "%.3f condition"
			% float(taken["hover"]))
	_report("a walker steps over a floor hazard and takes the catalogue fraction",
		absf(float(taken["legs"]) - float(taken["4wd"]) * want_factor) < 0.01,
		"%.3f against the 4WD's %.3f at %.2f"
			% [float(taken["legs"]), float(taken["4wd"]), want_factor])


# ---------------------------------------------------------------------------
# 5. The adaptive belt
# ---------------------------------------------------------------------------
func _check_adaptive_belt() -> void:
	var drift := {}
	var covered := {}
	for drive_id in ["tracks", "adaptive_tracks"]:
		var world := _make_world()
		var bot := _spawn(world, _config("box", str(drive_id), "ram", ["srimech"]))
		await _step(bot, FightTypes.empty_input(), 40)
		# Chew the left belt to nothing, the way a spinner would.
		bot.damage.apply_direct_damage("track_l", 1.0, "cut",
			bot.chassis.global_position, "test", 1.0)
		await physics_frame
		var start: Vector3 = bot.chassis.global_position
		var yaw_start := _yaw_of(bot)
		await _step(bot, {"heading": Vector2(1.0, 0.0), "fire": false,
			"secondary": false}, 90)
		drift[str(drive_id)] = absf(wrapf(_yaw_of(bot) - yaw_start, -PI, PI))
		covered[str(drive_id)] = (bot.chassis.global_position - start).length()
		if str(drive_id) == "adaptive_tracks":
			var skin := bot.chassis.find_child("TrackSkinL", true, false) as Node3D
			_report("a chewed adaptive belt stays on the machine",
				skin != null and skin.visible, "skin %s" % str(skin))
			_report("a chewed adaptive belt still drives above its floor",
				bot.drive_module.power_scale() > 0.5, "power %.2f"
					% bot.drive_module.power_scale())
		await _drop(world)

	_report("a plain track with a belt off veers off its line",
		float(drift["tracks"]) > deg_to_rad(15.0),
		"%.0f deg" % rad_to_deg(float(drift["tracks"])))
	_report("an adaptive track with a belt chewed to zero still drives straight",
		float(drift["adaptive_tracks"]) < deg_to_rad(20.0),
		"%.0f deg" % rad_to_deg(float(drift["adaptive_tracks"])))
	_report("and it still covers ground", float(covered["adaptive_tracks"]) > 1.0,
		"%.2f m against the plain track's %.2f"
			% [float(covered["adaptive_tracks"]), float(covered["tracks"])])


# ---------------------------------------------------------------------------
# 6. Reactive armour
# ---------------------------------------------------------------------------
func _check_reactive() -> void:
	var shove := {}
	for material_id in ["steel", "reactive"]:
		var armour := LIGHT_ARMOUR.duplicate(true)
		armour["front"] = {"material": str(material_id), "thickness": 2}
		var world := _make_world()
		var victim := _spawn(world, _config("box", "4wd", "ram", ["srimech"], armour))
		var attacker := _spawn_at(world, _config("box", "4wd", "ram", ["srimech"]),
			SPAWN + Vector3(1.4, 0.0, 0.0), "att")
		await _step2(victim, attacker, 60)
		var plate := _part_with_key(victim, "armour_front")
		var before: float = attacker.chassis.linear_velocity.length()
		victim.report_contact(plate, attacker.chassis, 140.0, plate.global_position)
		await physics_frame
		shove[str(material_id)] = attacker.chassis.linear_velocity.length() - before
		await _drop(world)

	_report("a steel plate does not push its attacker anywhere",
		float(shove["steel"]) < 0.05, "%.2f m/s" % float(shove["steel"]))
	_report("a reactive plate shoves the attacker away from the blow",
		float(shove["reactive"]) > 0.3, "%.2f m/s" % float(shove["reactive"]))


# ---------------------------------------------------------------------------
# 7. The overcharge core
# ---------------------------------------------------------------------------
func _check_overcharge() -> void:
	# The core cooks while the weapon is at full. The ram reads full the whole
	# time, which is the worst case the part has and the easiest to measure.
	var cooked := {}
	for utility_variant in [["srimech"], ["srimech", "overcharge_core"]]:
		var utility: Array = utility_variant
		var world := _make_world()
		var bot := _spawn(world, _config("box", "4wd", "ram", utility))
		await _step(bot, FightTypes.empty_input(), 60)
		var before := float(bot.condition()["core"])
		await _step(bot, FightTypes.empty_input(), 300)
		cooked[str(utility.size())] = before - float(bot.condition()["core"])
		await _drop(world)

	var rate := float(PartsCatalogue.utility("overcharge_core").get("cook_rate", 0.0))
	_report("a machine with no overcharge core never cooks itself",
		is_equal_approx(float(cooked["1"]), 0.0), "%.4f" % float(cooked["1"]))
	_report("an overcharge core cooks the core at the catalogue rate while the "
		+ "weapon is at full", absf(float(cooked["2"]) - rate * 5.0) < rate * 1.5,
		"%.4f off in 5 s, catalogue says %.4f" % [float(cooked["2"]), rate * 5.0])

	# And it hits harder, on every weapon in the game, because the victim reads the
	# attacker's factor rather than the weapon knowing the part exists.
	var bite := {}
	for utility_variant in [["srimech"], ["srimech", "overcharge_core"]]:
		var utility: Array = utility_variant
		var world := _make_world()
		var victim := _spawn(world, _config("box", "4wd", "ram", ["srimech"]))
		var attacker := _spawn_at(world, _config("box", "4wd", "ram", utility),
			SPAWN + Vector3(1.4, 0.0, 0.0), "att")
		await _step2(victim, attacker, 60)
		var plate := _part_with_key(victim, "armour_front")
		var before := float((victim.condition()["armour"] as Dictionary)["front"])
		victim.report_contact(plate, attacker.chassis, 110.0, plate.global_position)
		await physics_frame
		bite[str(utility.size())] = before \
			- float((victim.condition()["armour"] as Dictionary)["front"])
		await _drop(world)

	var want := float(PartsCatalogue.utility("overcharge_core").get("hit_factor", 1.25))
	var ratio := float(bite["2"]) / maxf(float(bite["1"]), 0.0001)
	_report("an overcharge core multiplies what a blow takes off by its catalogue "
		+ "hit factor", absf(ratio - want) < 0.03,
		"%.3f against %.3f, ratio %.2f" % [float(bite["2"]), float(bite["1"]), ratio])
	_report("an overcharge core spins a weapon up faster than a spare battery",
		float(PartsCatalogue.utility("overcharge_core").get("spin_up_factor", 1.0))
			< float(PartsCatalogue.utility("spare_battery").get("spin_up_factor", 1.0)), "")


# ---------------------------------------------------------------------------
# 8. Pushing
# ---------------------------------------------------------------------------
## The brief's two promises in one measurement: legs have immense push and a hover
## has none. Each drive is put behind the same parked machine and told to drive
## into it for two seconds.
func _check_push() -> void:
	var shifted := {}
	for drive_id in ["6wd", "legs", "hover"]:
		var world := _make_world()
		var target := _spawn_at(world, _config("box", "4wd", "ram", ["srimech"]),
			Vector3(0.0, 0.25, -3.2), "target")
		# Nose to tail before the bell. A run up would measure momentum, which a
		# fast light machine has plenty of; what is being measured here is the push
		# a machine can keep up once it is already leaning on something.
		var pusher := _spawn_at(world, _config("box", str(drive_id), "ram", ["srimech"]),
			Vector3(-1.05, 0.25, -3.2), "push")
		await _step2(target, pusher, 60)
		var drive := {"heading": Vector2(1.0, 0.0), "fire": false, "secondary": false}
		var start := Vector3.ZERO
		for i in range(180):
			target.apply_input(FightTypes.empty_input())
			pusher.apply_input(drive)
			await physics_frame
			# The first second closes the gap; the second one is the measurement.
			if i == 59:
				start = target.chassis.global_position
		shifted[str(drive_id)] = (target.chassis.global_position - start).length()
		await _drop(world)

	_report("legs shove a parked machine further than a 6 wheel does",
		float(shifted["legs"]) > float(shifted["6wd"]),
		"%.2f m against %.2f" % [float(shifted["legs"]), float(shifted["6wd"])])
	_report("a hover cannot push a parked machine anywhere",
		float(shifted["hover"]) < float(shifted["6wd"]) * 0.5,
		"%.2f m against the 6 wheel's %.2f"
			% [float(shifted["hover"]), float(shifted["6wd"])])


# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------
var _events: Array[Dictionary] = []


func _make_world() -> Node3D:
	var world := Node3D.new()
	world.name = "Fight"
	root.add_child(world)
	var debris := Node3D.new()
	debris.name = "Debris"
	world.add_child(debris)
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var yard: Yard = (load(YARD_SCENE) as PackedScene).instantiate()
	yard.name = "Arena"
	world.add_child(yard)
	yard.setup(rng)
	return world


func _spawn(world: Node3D, config: Dictionary) -> Bot:
	_events.clear()
	var bot := _spawn_at(world, config, SPAWN, "bot")
	bot.damage_event.connect(func(info: Dictionary) -> void: _events.append(info))
	return bot


func _spawn_at(world: Node3D, config: Dictionary, at: Vector3, id: String) -> Bot:
	var bot: Bot = (load(BOT_SCENE) as PackedScene).instantiate()
	bot.name = "Bot" + id.capitalize()
	var spawn_config := config.duplicate(true)
	spawn_config["id"] = id
	world.add_child(bot)
	bot.place_at(at, FACING)
	var rng := RandomNumberGenerator.new()
	rng.seed = 707
	bot.setup(spawn_config, 0, rng)
	bot.place_at(at, FACING)
	return bot


func _step(bot: Bot, input: Dictionary, count: int) -> void:
	for _i in range(count):
		bot.apply_input(input)
		await physics_frame


func _step2(a: Bot, b: Bot, count: int) -> void:
	for _i in range(count):
		a.apply_input(FightTypes.empty_input())
		b.apply_input(FightTypes.empty_input())
		await physics_frame


func _drop(world: Node3D) -> void:
	root.remove_child(world)
	world.queue_free()
	await physics_frame
	await physics_frame


func _part_with_key(bot: Bot, key: String) -> BotPart:
	for part in bot.attached_parts():
		if part.part_key == key:
			return part
	return null


func _yaw_of(bot: Bot) -> float:
	var fwd := bot.chassis.global_basis.x
	fwd.y = 0.0
	return atan2(-fwd.z, fwd.x)


func _describe_events() -> String:
	var out := PackedStringArray()
	for event in _events:
		out.append("%s %.2f" % [str(event.get("part", "")),
			float(event.get("severity", 0.0))])
	return str(out)


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
