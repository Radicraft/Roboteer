extends SceneTree
## Stage 4 assembly test (docs/stage4-spec.md section 3).
##   Godot --headless --path Arena --script tests/assembly_test.gd
##
## What it proves:
##   1. the catalogue the arena reads is byte identical to the one Swift reads;
##   2. BuildRules says what the spec says it says, in the spec's own sentences;
##   3. every chassis x drive x weapon combination BuildRules allows assembles
##      headless with no errors, inside the body budget, at the right mass;
##   4. the models are actually on the bots, and the sockets the assembler reads
##      back out of the .glb files are the ones the manifest promises;
##   5. the assembled bots still drive: 3 m in 2 s, and they turn.
## Exit code 0 = all PASS.

const BOT_SCENE := "res://bot/bot.tscn"
const YARD_SCENE := "res://arena/yard.tscn"
const SHARED_PARTS := "res://../Shared/parts.json"

## The cheapest legal armour, so the budget rejects as few combinations as
## possible and the test covers as much of the catalogue as it can.
const LIGHT_ARMOUR := {
	"front": {"material": "hdpe", "thickness": 1},
	"sides": {"material": "hdpe", "thickness": 1},
	"rear": {"material": "hdpe", "thickness": 1},
	"top": {"material": "hdpe", "thickness": 1},
}

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	print("Roboteer assembly test, Godot ", Engine.get_version_info()["string"])
	_check_catalogue_copies()
	_check_build_rules()
	_check_sockets_match_manifest()
	await _check_every_combination()
	await _check_visuals()
	await _check_driving()
	_finish()


# ---------------------------------------------------------------------------
# 1. The catalogue is one file
# ---------------------------------------------------------------------------
func _check_catalogue_copies() -> void:
	var arena := FileAccess.get_file_as_bytes(PartsCatalogue.PARTS_PATH)
	var shared := FileAccess.get_file_as_bytes(SHARED_PARTS)
	_report("Arena/data/parts.json is byte identical to Shared/parts.json",
		not arena.is_empty() and arena == shared,
		"%d vs %d bytes" % [arena.size(), shared.size()])
	_report("the catalogue has seven chassis, eight drives and sixteen weapons",
		PartsCatalogue.ids("chassis").size() == 7
			and PartsCatalogue.ids("drive").size() == 8
			and PartsCatalogue.ids("weapon").size() == 16,
		"%d / %d / %d" % [PartsCatalogue.ids("chassis").size(),
			PartsCatalogue.ids("drive").size(), PartsCatalogue.ids("weapon").size()])


# ---------------------------------------------------------------------------
# 2. BuildRules
# ---------------------------------------------------------------------------
func _config(chassis: String, drive: String, weapon: String, utility: Array,
		armour: Dictionary = LIGHT_ARMOUR) -> Dictionary:
	return {
		"id": "test-%s-%s-%s" % [chassis, drive, weapon],
		"name": "Test", "controller": "dummy",
		"chassis": chassis, "drive": drive, "weapon": weapon,
		"utility": utility.duplicate(), "armour": armour.duplicate(true),
	}


func _check_build_rules() -> void:
	var legal := _config("wedge", "4wd", "flipper", ["srimech"])
	_report("a legal build validates clean", BuildRules.validate(legal).is_empty(),
		str(BuildRules.validate(legal)))

	var weight := BuildRules.total_weight(_config("wedge", "4wd", "flipper", ["srimech"]))
	# 30 chassis + 16 drive + 16 weapon + 4 srimech + 1 unit hdpe on 5.1 of area
	_report("total_weight adds the catalogue rows and the face formula",
		absf(weight - 71.1) < 0.001, "%.2f kg" % weight)

	var heavy := _config("shell", "tracks", "full_body_spinner", [], {
		"front": {"material": "steel", "thickness": 4},
		"sides": {"material": "steel", "thickness": 4},
		"rear": {"material": "steel", "thickness": 4},
		"top": {"material": "steel", "thickness": 4},
	})
	_report("over the budget reads as a plain sentence with the overage",
		BuildRules.validate(heavy).has("Over the weight budget by 62.2 kg."),
		str(BuildRules.validate(heavy)))

	_report("a wedge with no srimech is rejected by name",
		BuildRules.validate(_config("wedge", "4wd", "flipper", [])) \
			.has("A Wedge needs a srimech."),
		str(BuildRules.validate(_config("wedge", "4wd", "flipper", []))))
	_report("an invertible chassis needs no srimech",
		BuildRules.validate(_config("pyramid", "4wd", "flipper", [])).is_empty(),
		str(BuildRules.validate(_config("pyramid", "4wd", "flipper", []))))
	# Three since wave P: the Level 95 vortex spinner is a full body spinner too.
	_report("the shell only takes its three weapons",
		BuildRules.validate(_config("shell", "4wd", "axe", [])) \
			.has("The Shell only takes a full body spinner, a ram or a vortex spinner."),
		str(BuildRules.validate(_config("shell", "4wd", "axe", []))))
	_report("the full body spinner only fits the shell",
		BuildRules.validate(_config("box", "4wd", "full_body_spinner", ["srimech"])) \
			.has("The Full body spinner only fits the Shell."), "")
	_report("three utility parts are rejected",
		BuildRules.validate(_config("wedge", "4wd", "flipper",
			["srimech", "magnets", "scoop"])).has("There are only two utility slots."), "")
	_report("the same utility part twice is rejected",
		BuildRules.validate(_config("wedge", "4wd", "flipper", ["srimech", "srimech"])) \
			.has("Srimech is fitted twice."), "")

	var thick := _config("wedge", "4wd", "flipper", ["srimech"])
	(thick["armour"] as Dictionary)["top"] = {"material": "steel", "thickness": 7}
	_report("thickness outside 1 to 4 is rejected",
		BuildRules.validate(thick).has("Top armour thickness must be between 1 and 4."),
		str(BuildRules.validate(thick)))
	var bare := _config("wedge", "4wd", "flipper", ["srimech"])
	(bare["armour"] as Dictionary).erase("rear")
	_report("a face with no material is rejected",
		BuildRules.validate(bare).has("The rear needs an armour material."),
		str(BuildRules.validate(bare)))
	_report("no error sentence uses an em dash", not _any_em_dash(), "")


func _any_em_dash() -> bool:
	for config in [_config("wedge", "4wd", "flipper", []),
			_config("shell", "4wd", "axe", []),
			_config("box", "4wd", "full_body_spinner", ["srimech", "srimech", "scoop"])]:
		for line in BuildRules.validate(config):
			if line.contains("—") or line.contains("–"):
				return true
	return false


# ---------------------------------------------------------------------------
# 3. Sockets against the manifest
# ---------------------------------------------------------------------------
func _check_sockets_match_manifest() -> void:
	var manifest_parts: Dictionary = PartsCatalogue.manifest().get("parts", {}) as Dictionary
	if manifest_parts.is_empty():
		_report("the model manifest loads", false, "no parts in the manifest")
		return
	var worst := 0.0
	var checked := 0
	var missing := PackedStringArray()
	for id_variant in manifest_parts.keys():
		var id := str(id_variant)
		var promised := PartsCatalogue.model_sockets(id)
		if promised.is_empty():
			continue
		var node := PartVisuals.instantiate(id)
		if node == null:
			missing.append(id)
			continue
		var found := PartVisuals.read_sockets(node)
		for socket_name in promised.keys():
			checked += 1
			if not found.has(socket_name):
				missing.append("%s/%s" % [id, socket_name])
				continue
			worst = maxf(worst, (found[socket_name] as Vector3).distance_to(
				promised[socket_name] as Vector3))
		node.free()
	_report("every socket reads back where the manifest says it is",
		missing.is_empty() and worst < 0.0005 and checked > 100,
		"%d sockets, worst %.6f m, missing %s" % [checked, worst, missing])


# ---------------------------------------------------------------------------
# 4. Every allowed combination
# ---------------------------------------------------------------------------
func _check_every_combination() -> void:
	var host := Node3D.new()
	host.name = "Assembly"
	root.add_child(host)
	var allowed := 0
	var rejected := 0
	var bad_build := PackedStringArray()
	var bad_bodies := PackedStringArray()
	var bad_mass := PackedStringArray()
	var bad_condition := PackedStringArray()

	for chassis_id in PartsCatalogue.ids("chassis"):
		for drive_id in PartsCatalogue.ids("drive"):
			for weapon_id in PartsCatalogue.ids("weapon"):
				var utility: Array = []
				if not bool(PartsCatalogue.chassis(str(chassis_id)).get("invertible", false)):
					utility.append("srimech")
				var config := _config(str(chassis_id), str(drive_id), str(weapon_id),
					utility)
				if not BuildRules.validate(config).is_empty():
					rejected += 1
					continue
				allowed += 1
				var bot: Bot = (load(BOT_SCENE) as PackedScene).instantiate()
				host.add_child(bot)
				bot.setup(config, 0, RandomNumberGenerator.new())
				var label := "%s/%s/%s" % [chassis_id, drive_id, weapon_id]

				if not bot.build_errors.is_empty():
					bad_build.append(label)

				# Body budget (brief section 12): hull, wheels, weapon, plates.
				var bodies := bot.attached_parts().size()
				var wheels: int = bot.drive_module.wheels.size()
				var cap := 1 + wheels + 5 + 2
				if bodies > cap or wheels > 6:
					bad_bodies.append("%s %d bodies, %d wheels" % [label, bodies, wheels])

				var want := BuildRules.total_weight(config) * Bot.MASS_SCALE
				var got := bot.total_mass()
				if absf(got - want) > want * 0.10:
					bad_mass.append("%s %.1f vs %.1f" % [label, got, want])

				var condition := bot.condition()
				var condition_wheels: Array = condition["wheels"]
				# One entry per wheel, or per track side, or none at all for the
				# two wave P drives that have no wheel bodies (the walker and the
				# hover): exactly what Swift's `Catalogue.Drive.conditionCount`
				# promises the repair bill and the match report.
				var drive_row := PartsCatalogue.drive(str(drive_id))
				var want_wheels := int(drive_row.get("tracks", 0))
				if want_wheels <= 0:
					want_wheels = int(drive_row.get("wheels", 4))
				if condition_wheels.size() != want_wheels:
					bad_condition.append("%s %d entries" % [label, condition_wheels.size()])

				host.remove_child(bot)
				bot.free()

	_report("every allowed combination assembles with no build errors",
		bad_build.is_empty(), "%d allowed, %d rejected, bad: %s"
			% [allowed, rejected, bad_build])
	_report("at least 200 of the 300 combinations are legal", allowed >= 200,
		"%d allowed" % allowed)
	_report("every build stays inside the body budget", bad_bodies.is_empty(),
		str(bad_bodies))
	_report("every build's simulated mass is within 10 percent of the catalogue",
		bad_mass.is_empty(), str(bad_mass))
	_report("condition()[\"wheels\"] has one entry per wheel, or per track side",
		bad_condition.is_empty(), str(bad_condition))
	root.remove_child(host)
	host.free()
	await process_frame


# ---------------------------------------------------------------------------
# 5. The models are on the bots
# ---------------------------------------------------------------------------
func _check_visuals() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var missing := PackedStringArray()
	for chassis_id in PartsCatalogue.ids("chassis"):
		var weapon_id := "full_body_spinner" if str(chassis_id) == "shell" else "flipper"
		var utility: Array = []
		if not bool(PartsCatalogue.chassis(str(chassis_id)).get("invertible", false)):
			utility.append("srimech")
		var config := _config(str(chassis_id), "4wd", weapon_id, utility)
		var bot: Bot = (load(BOT_SCENE) as PackedScene).instantiate()
		host.add_child(bot)
		bot.setup(config, 0, RandomNumberGenerator.new())
		var names := {}
		_gather_names(bot, names)
		var want := ["Model_wheel_standard", "Model_plate_flat_hdpe"]
		# A hull whose .glb has not been made yet wears the procedural profile in
		# its own module, which is also its collision, so it assembles and fights
		# and only looks unfinished. The weapon row below has always worked this
		# way; the chassis row joined it when wave P added the Apex ahead of agent
		# E's models. The gate re-arms itself the moment the model lands.
		if PartVisuals.has_model(str(chassis_id)):
			want.append("Model_" + str(chassis_id))
		if not utility.is_empty():
			want.append("Model_srimech")
		if PartVisuals.has_model(weapon_id):
			want.append("Model_" + weapon_id)
		for wanted in want:
			if not names.has(wanted):
				missing.append("%s: %s" % [chassis_id, wanted])
		host.remove_child(bot)
		bot.free()
	_report("every chassis wears its model, its wheels, its plates and its weapon",
		missing.is_empty(), str(missing))
	root.remove_child(host)
	host.free()
	await process_frame


func _gather_names(node: Node, out: Dictionary) -> void:
	out[String(node.name)] = true
	for child in node.get_children():
		_gather_names(child, out)


# ---------------------------------------------------------------------------
# 6. They still drive
# ---------------------------------------------------------------------------
## Every chassis on 4WD, plus the wedge on every drive: each drive and each hull is
## covered without simulating all three hundred combinations.
func _drive_cases() -> Array:
	var out := []
	for chassis_id in PartsCatalogue.ids("chassis"):
		out.append([str(chassis_id), "4wd"])
	for drive_id in PartsCatalogue.ids("drive"):
		if str(drive_id) != "4wd":
			out.append(["wedge", str(drive_id)])
	return out


func _check_driving() -> void:
	var straight := PackedStringArray()
	var turned := PackedStringArray()
	for case_variant in _drive_cases():
		var case: Array = case_variant
		var chassis_id := str(case[0])
		var drive_id := str(case[1])
		var weapon_id := "full_body_spinner" if chassis_id == "shell" else "flipper"
		var utility: Array = []
		if not bool(PartsCatalogue.chassis(chassis_id).get("invertible", false)):
			utility.append("srimech")
		var config := _config(chassis_id, drive_id, weapon_id, utility)
		var world := _make_world()
		var bot: Bot = (load(BOT_SCENE) as PackedScene).instantiate()
		(world as Node3D).add_child(bot)
		bot.place_at(Vector3(-3.5, 0.25, 2.6), Vector3.RIGHT)
		bot.setup(config, 0, RandomNumberGenerator.new())
		bot.place_at(Vector3(-3.5, 0.25, 2.6), Vector3.RIGHT)
		await _step(bot, FightTypes.empty_input(), 30)

		var start: Vector3 = bot.chassis.global_position
		await _step(bot, {"heading": Vector2(1.0, 0.0), "fire": false,
			"secondary": false}, 120)
		var moved := (bot.chassis.global_position - start).length()
		if moved < 3.0:
			straight.append("%s/%s %.2f m" % [chassis_id, drive_id, moved])

		# A 90 degree turn in 2 s. The bar is halfway, not the whole turn: the
		# catalogue deliberately makes some builds turn badly (Long and Low has a
		# `turn_rate_factor` of 0.7 on a 1.2 m wheelbase) and the point of the check
		# is that every build turns, not that they all turn alike. Omni is the one
		# drive that does not turn on the stick at all: it strafes, and `secondary`
		# is its pivot, which is exactly what spec section 3 asks for.
		var want := Vector2(0.0, -1.0)
		var want_yaw := atan2(-want.y, want.x)
		var pivot: bool = bot.drive_module.strafes()
		var best := PI
		for _i in range(120):
			bot.apply_input({"heading": want, "fire": false, "secondary": pivot})
			await physics_frame
			var fwd := bot.chassis.global_basis.x
			fwd.y = 0.0
			best = minf(best, absf(wrapf(want_yaw - atan2(-fwd.z, fwd.x), -PI, PI)))
		if best > deg_to_rad(45.0):
			turned.append("%s/%s %.0f deg" % [chassis_id, drive_id, rad_to_deg(best)])

		root.remove_child(world)
		world.queue_free()
		await physics_frame
		await physics_frame

	_report("every hull and drive covers 3 m in 2 s", straight.is_empty(), str(straight))
	_report("every hull and drive turns at least halfway to a new heading in 2 s",
		turned.is_empty(), str(turned))


func _make_world() -> Node3D:
	var world := Node3D.new()
	world.name = "Fight"
	root.add_child(world)
	var debris := Node3D.new()
	debris.name = "Debris"
	world.add_child(debris)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var yard: Yard = (load(YARD_SCENE) as PackedScene).instantiate()
	yard.name = "Arena"
	world.add_child(yard)
	yard.setup(rng)
	return world


func _step(bot: Bot, input: Dictionary, count: int) -> void:
	for _i in range(count):
		bot.apply_input(input)
		await physics_frame


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
