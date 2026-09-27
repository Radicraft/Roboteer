extends SceneTree
## The six weapons of brief v5 section 9.5 (wave P, agent D1).
##   Godot --headless --path Arena --script tests/weapons_p_test.gd
##
##   shock_prod   35  contact prod that disrupts the target's drive for a moment
##   tesla_arc    60  short arc to the nearest part, stalls its weapon and drive
##   drill_lance  65  spinning lance that ignores half the armour factor
##   twin_saw     75  two saws, wider reach, higher damage
##   napalm_cannon 80 lobs a burning charge that leaves a patch of fire
##   vortex_spinner 95 full body spinner with angled teeth that throw as well as hit
##
## `weapons_test.gd` already fits every weapon to every legal hull and insists it
## does something, so nothing here repeats the matrix. This file asks the question
## the matrix cannot: does the SPECIAL EFFECT happen, and does it END. A weapon
## that stalls a drive for ever, or lights a fire that never goes out, passes a
## damage test and ruins a fight.
##
## DETERMINISM. Every rng here is seeded by hand and nothing reads a clock. The
## weapons themselves draw no randomness at all except the flamethrower's first
## disruption kind, which none of these six shares.
##
## Each scenario builds its world inside its own SubViewport with own_world_3d,
## exactly as `fight.gd` and `weapons_test.gd` do: two scenarios run back to back
## in the shared root physics space do not reproduce each other, because recycled
## body RIDs change the solver's order.
##
## Exit code 0 = all PASS.

const BOT_SCENE := "res://bot/bot.tscn"
const YARD_SCENE := "res://arena/yard.tscn"
const FIGHT_SCENE := "res://fight/fight.tscn"
const CONTROLS_SCRIPT := "res://ui/controls.gd"
const AI_SCRIPT := "res://ai/opponent_ai.gd"

## fight.gd's State enum, which is not reachable from outside the script.
const STATE_FIGHTING := 2

const MINE := ["shock_prod", "tesla_arc", "drill_lance", "twin_saw",
	"napalm_cannon", "vortex_spinner"]

const LIGHT := {
	"front": {"material": "hdpe", "thickness": 1},
	"sides": {"material": "hdpe", "thickness": 1},
	"rear": {"material": "hdpe", "thickness": 1},
	"top": {"material": "hdpe", "thickness": 1},
}
const STEEL := {
	"front": {"material": "steel", "thickness": 1},
	"sides": {"material": "steel", "thickness": 1},
	"rear": {"material": "steel", "thickness": 1},
	"top": {"material": "steel", "thickness": 1},
}

## The lane weapons_test uses, at z = 3, well clear of the yard's spike patch.
const LANE_Z := 3.0
const ATTACKER_AT := Vector3(2.55, 0.3, LANE_Z)
const TARGET_AT := Vector3(4.15, 0.3, LANE_Z)
## The target parks broadside on so the attacker meets a clean flank rather than
## the target's own weapon, and it carries a ram, which has no moving part.
const TARGET_FACING := Vector3.BACK

const HZ := 60

var _checks := 0
var _failures := 0
var _results: Array = []


func _initialize() -> void:
	await _run()


func _run() -> void:
	print("Roboteer wave P weapons test, Godot ", Engine.get_version_info()["string"])
	await process_frame
	_check_catalogue()
	_check_words()
	_check_ai_profiles()
	_check_pierce_arithmetic()
	if not ResourceLoader.exists(BOT_SCENE):
		print("SKIP  wave P weapons: %s is absent" % BOT_SCENE)
		_finish()
		return
	await _check_fits()
	await _check_shock_prod()
	await _check_tesla_arc()
	await _check_drill_lance()
	await _check_twin_saw()
	await _check_napalm_cannon()
	await _check_vortex_spinner()
	await _check_result_is_well_formed()
	_finish()


# ---------------------------------------------------------------------------
# 1. The catalogue rows
# ---------------------------------------------------------------------------
func _check_catalogue() -> void:
	var kinds := {"shock_prod": "prod", "tesla_arc": "arc", "drill_lance": "drill",
		"twin_saw": "saw", "napalm_cannon": "flame", "vortex_spinner": "fbs"}
	var missing := PackedStringArray()
	var wrong_kind := PackedStringArray()
	for id in MINE:
		var row := PartsCatalogue.weapon(id)
		if row.is_empty():
			missing.append(id)
			continue
		if str(row.get("kind", "")) != str(kinds[id]):
			wrong_kind.append("%s is %s" % [id, str(row.get("kind", ""))])
	_report("all six weapons are in the catalogue", missing.is_empty(), str(missing))
	_report("and each carries the kind the contracts file fixed",
		wrong_kind.is_empty(), str(wrong_kind))
	if not missing.is_empty():
		return

	# Every key the existing rows of the same kind carry, plus the keys Swift's
	# Catalogue reads for a weapon. A row missing one of these reads as a nil in
	# the shop, which is a blank stat bar rather than a crash, so nothing else
	# would ever catch it.
	var wants := {
		"shock_prod": ["name", "weight", "kind", "reach", "height_band", "reset_s",
			"dps", "disrupt_s", "blurb"],
		"tesla_arc": ["name", "weight", "kind", "reach", "height_band", "spin_up_s",
			"reset_s", "dps", "disrupt_s", "blurb"],
		"drill_lance": ["name", "weight", "kind", "reach", "height_band",
			"spin_up_s", "dps", "knockback", "blurb"],
		"twin_saw": ["name", "weight", "kind", "reach", "height_band", "spin_up_s",
			"dps", "knockback", "blades", "blurb"],
		"napalm_cannon": ["name", "weight", "kind", "reach", "height_band", "dps",
			"disrupt_s", "fuel_s", "charges", "reset_s", "ranged", "patch_radius",
			"blurb"],
		"vortex_spinner": ["name", "weight", "kind", "reach", "height_band",
			"spin_up_s", "impulse", "control_penalty", "lift", "blurb"],
	}
	var gaps := PackedStringArray()
	for id in MINE:
		var row := PartsCatalogue.weapon(id)
		for key in (wants[id] as Array):
			if not row.has(key):
				gaps.append("%s/%s" % [id, str(key)])
	_report("every row carries every key its kind's rows carry", gaps.is_empty(),
		str(gaps))

	# The ladder, and the price the ladder implies. Price is factor times weight
	# (Shared/parts.json `economy`), so weight IS the price lever and the six have
	# to climb with the Level they unlock at.
	var ladder: Dictionary = (PartsCatalogue.parts().get("progression", {}) as Dictionary) \
		.get("level_required", {}) as Dictionary
	var levels := PackedStringArray()
	for id in MINE:
		if not ladder.has(id):
			levels.append(id)
	_report("all six are on the Level ladder", levels.is_empty(), str(levels))

	var last_level := 0
	var last_weight := 0.0
	var order := PackedStringArray()
	for id in MINE:
		var level := int(ladder.get(id, 0))
		var weight := float(PartsCatalogue.weapon(id).get("weight", 0.0))
		if level <= last_level or weight <= last_weight:
			order.append("%s L%d %.0f kg" % [id, level, weight])
		last_level = level
		last_weight = weight
	_report("each one costs more than the one below it on the ladder",
		order.is_empty(), str(order))

	# A weapon nobody can carry is not a weapon. The heaviest hull and drive that
	# each one is legal on has to leave room for it inside the 100 kg budget.
	var unbuildable := PackedStringArray()
	for id in MINE:
		var buildable := false
		for chassis_variant in PartsCatalogue.ids("chassis"):
			for drive_variant in PartsCatalogue.ids("drive"):
				if BuildRules.validate(_config("b", str(chassis_variant), id,
						str(drive_variant))).is_empty():
					buildable = true
					break
			if buildable:
				break
		if not buildable:
			unbuildable.append(id)
	_report("every one of them fits inside the weight budget on some machine",
		unbuildable.is_empty(), str(unbuildable))

	var shell_allows: Array = PartsCatalogue.chassis("shell").get("weapons_allowed", []) as Array
	_report("the shell's weapons_allowed lists the vortex spinner",
		shell_allows.has("vortex_spinner"), str(shell_allows))
	_report("and the vortex spinner is not welded to one hull",
		str(PartsCatalogue.weapon("vortex_spinner").get("requires_chassis", "")) == "",
		str(PartsCatalogue.weapon("vortex_spinner").get("requires_chassis", "")))

	# Nothing a player reads may carry an em dash or an exclamation mark.
	var bad_words := PackedStringArray()
	for id in MINE:
		var row := PartsCatalogue.weapon(id)
		for key in ["name", "blurb"]:
			var text := str(row.get(key, ""))
			if text.contains("—") or text.contains("–") or text.contains("!"):
				bad_words.append("%s/%s" % [id, str(key)])
	_report("no name or blurb uses an em dash or an exclamation mark",
		bad_words.is_empty(), str(bad_words))


# ---------------------------------------------------------------------------
# 2. The words on the button
# ---------------------------------------------------------------------------
func _check_words() -> void:
	if not ResourceLoader.exists(CONTROLS_SCRIPT):
		_report("the controls script is present", false, CONTROLS_SCRIPT)
		return
	var controls := load(CONTROLS_SCRIPT) as GDScript
	var words: Dictionary = controls.get("WEAPON_WORDS") as Dictionary
	var holds: Dictionary = controls.get("WEAPON_HOLDS") as Dictionary
	var missing := PackedStringArray()
	var not_held := PackedStringArray()
	for id in MINE:
		var kind := str(PartsCatalogue.weapon(id).get("kind", ""))
		if not words.has(kind) or str(words[kind]) == "":
			missing.append("%s (%s)" % [id, kind])
		if not holds.has(kind):
			missing.append("%s hold (%s)" % [id, kind])
		elif not bool(holds[kind]):
			not_held.append("%s (%s)" % [id, kind])
	_report("every new weapon has a word and a working style on the button",
		missing.is_empty(), str(missing))
	# All six are worked by holding the thumb down. A mortar or a coil worked by a
	# tap would be a timing test on a touchscreen with the muzzle out of shot.
	_report("and all six are held rather than tapped", not_held.is_empty(),
		str(not_held))


# ---------------------------------------------------------------------------
# 3. The AI knows how to fight with them
# ---------------------------------------------------------------------------
func _check_ai_profiles() -> void:
	if not ResourceLoader.exists(AI_SCRIPT):
		_report("the opponent AI script is present", false, AI_SCRIPT)
		return
	var ai := load(AI_SCRIPT) as GDScript
	var by_kind: Dictionary = ai.get("PROFILES") as Dictionary
	var by_id: Dictionary = ai.get("PROFILES_BY_ID") as Dictionary
	var keys := ["standoff", "engage", "flank", "spin_up", "hold", "latch", "orbit"]

	var missing_kind := PackedStringArray()
	for kind in ["prod", "arc", "drill"]:
		if not by_kind.has(kind):
			missing_kind.append(kind)
	_report("the three new weapon kinds each have a profile",
		missing_kind.is_empty(), str(missing_kind))

	var missing_id := PackedStringArray()
	var short_rows := PackedStringArray()
	for id in MINE:
		if not by_id.has(id):
			missing_id.append(id)
			continue
		var row: Dictionary = by_id[id] as Dictionary
		for key in keys:
			if not row.has(key):
				short_rows.append("%s/%s" % [id, key])
	_report("and every one of the six has a profile of its own",
		missing_id.is_empty(), str(missing_id))
	_report("each of those rows carries all seven columns", short_rows.is_empty(),
		str(short_rows))

	# Every weapon in the catalogue, old and new, resolves to a complete row: an
	# AI that reads a missing column crashes mid fight rather than fighting badly.
	var incomplete := PackedStringArray()
	for id_variant in PartsCatalogue.ids("weapon"):
		var id := str(id_variant)
		var kind := str(PartsCatalogue.weapon(id).get("kind", ""))
		var row: Dictionary = by_id.get(id, by_kind.get(kind, {})) as Dictionary
		for key in keys:
			if not row.has(key):
				incomplete.append("%s/%s" % [id, key])
	_report("every weapon in the catalogue resolves to a complete profile",
		incomplete.is_empty(), str(incomplete))

	# The lobbed weapon is the only one that wants to fight at arm's length, and
	# it is the only one whose row differs from its kind's.
	var napalm: Dictionary = by_id["napalm_cannon"] as Dictionary
	var flame: Dictionary = by_kind["flame"] as Dictionary
	_report("the napalm cannon stands off where the flamethrower closes",
		float(napalm["standoff"]) > float(flame["standoff"]),
		"%.2f against %.2f" % [float(napalm["standoff"]), float(flame["standoff"])])


# ---------------------------------------------------------------------------
# 4. The drill lance's armour rule, as arithmetic
# ---------------------------------------------------------------------------
## "Ignores half the armour's factor" means the material's own `cut` factor moved
## halfway to 1.0, in both directions: steel stops being four times as good as
## HDPE and becomes less than twice as good.
func _check_pierce_arithmetic() -> void:
	var steel := PartsCatalogue.material_factor("steel", "cut")
	var hdpe := PartsCatalogue.material_factor("hdpe", "cut")
	_report("the catalogue still says steel 0.4 and HDPE 1.6 against a cut",
		is_equal_approx(steel, 0.4) and is_equal_approx(hdpe, 1.6),
		"%.2f and %.2f" % [steel, hdpe])
	_report("steel's 0.4 pierces at 0.7",
		is_equal_approx(BotDamage.pierce_factor(steel), 0.7),
		"%.3f" % BotDamage.pierce_factor(steel))
	_report("HDPE's 1.6 pierces at 1.3",
		is_equal_approx(BotDamage.pierce_factor(hdpe), 1.3),
		"%.3f" % BotDamage.pierce_factor(hdpe))
	_report("a material with nothing to say is unchanged",
		is_equal_approx(BotDamage.pierce_factor(1.0), 1.0),
		"%.3f" % BotDamage.pierce_factor(1.0))
	var spread_cut := hdpe / maxf(steel, 0.001)
	var spread_pierce := BotDamage.pierce_factor(hdpe) \
		/ maxf(BotDamage.pierce_factor(steel), 0.001)
	_report("so the lance's spread across the materials is half the saw's",
		spread_pierce < spread_cut * 0.55,
		"%.2f against %.2f" % [spread_pierce, spread_cut])


# ---------------------------------------------------------------------------
# 5. They fit, they build a body, and their reach is the catalogue's
# ---------------------------------------------------------------------------
func _check_fits() -> void:
	var world := _make_world()
	var bad := PackedStringArray()
	var bodies_seen := PackedStringArray()
	for id in MINE:
		var chassis_id := _hull_for(id)
		var bot := _spawn(world, _config("f", chassis_id, id),
			Vector3(0.0, 0.3, LANE_Z))
		var bodies := 0
		var weapon_mass := 0.0
		for part in bot.attached_parts():
			if part.part_kind == "weapon":
				bodies += 1
				weapon_mass += part.mass
		bodies_seen.append("%s on %s: %d bodies, %.1f kg simulated"
			% [id, chassis_id, bodies, weapon_mass])
		if bodies < 1:
			bad.append("%s: no weapon body" % id)
		if not bot.build_errors.is_empty():
			bad.append("%s: %s" % [id, str(bot.build_errors)])
		var want_reach := float(PartsCatalogue.weapon(id).get("reach", 0.0))
		if absf(bot.weapon_reach() - want_reach) > 0.001:
			bad.append("%s: reach %.2f not %.2f" % [id, bot.weapon_reach(), want_reach])
		if bot.weapon_status().is_empty():
			bad.append("%s: no status text" % id)
		# The weight the shop charges for is the weight the fight simulates,
		# however many bodies the weapon is made of.
		var want_mass := float(PartsCatalogue.weapon(id).get("weight", 0.0)) \
			* Bot.MASS_SCALE
		if absf(weapon_mass - want_mass) > want_mass * 0.02:
			bad.append("%s: %.2f kg of bodies against %.2f priced"
				% [id, weapon_mass, want_mass])
		world.remove_child(bot)
		bot.free()
	for line in bodies_seen:
		print("      " + line)
	_report("all six assemble, weigh what the shop charges and name themselves",
		bad.is_empty(), str(bad))
	await _drop(world)


# ---------------------------------------------------------------------------
# 6. Shock prod: the drive goes, and comes back
# ---------------------------------------------------------------------------
func _check_shock_prod() -> void:
	var world := _make_world()
	var attacker := _spawn(world, _config("prod", "wedge", "shock_prod"), ATTACKER_AT)
	var target := _spawn(world, _config("prey", "box", "ram", TARGET_DRIVE),
		TARGET_AT, TARGET_FACING)
	await _settle([attacker, target], 30)

	var weapon: WeaponBase = attacker.weapon
	var before := _condition_total(target)
	var stalled := false
	var stalled_at := -1
	for i in range(240):
		attacker.apply_input(_input(Vector2(1.0, 0.0), true))
		target.apply_input(_idle())
		await physics_frame
		if bool(target.is_disrupted("drive")):
			stalled = true
			if stalled_at < 0:
				stalled_at = i
	var removed := before - _condition_total(target)
	var shocks := int(weapon.call("shocks"))
	_report("the prod takes condition off what it touches", removed > 0.0005,
		"%.4f removed" % removed)
	_report("and stalls the other machine's drive", stalled and shocks >= 1,
		"%d shocks, first stall at tick %d" % [shocks, stalled_at])

	# And it ENDS. The catalogue says 1.2 s, so a second and a half of nobody
	# touching it has to be enough, or a prod bot simply deletes the opponent.
	for _i in range(int(round(1.6 * float(HZ)))):
		attacker.apply_input(_idle())
		target.apply_input(_idle())
		await physics_frame
	_report("the stall wears off when the prod comes away",
		not bool(target.is_disrupted("drive")),
		"still stalled %s" % bool(target.is_disrupted("drive")))

	# The disruption has a cooldown, so a held prod cannot stall every tick. Four
	# seconds of contact buys the first stall plus one per reset_s after it, and
	# no more: at 2.5 s that is two, and a prod without the cooldown would have
	# scored well over a hundred.
	var reset_s := maxf(float(PartsCatalogue.weapon("shock_prod")
		.get("reset_s", 2.5)), 0.01)
	var ceiling := int(floor(4.0 / reset_s)) + 1
	_report("and it cannot stall faster than reset_s allows", shocks <= ceiling,
		"%d stalls in four seconds against a ceiling of %d" % [shocks, ceiling])
	await _drop(world)


# ---------------------------------------------------------------------------
# 7. Tesla arc: charge, jump, stall both systems, recharge
# ---------------------------------------------------------------------------
func _check_tesla_arc() -> void:
	var world := _make_world()
	var attacker := _spawn(world, _config("arc", "box", "tesla_arc"), ATTACKER_AT)
	var target := _spawn(world, _config("prey", "box", "ram", TARGET_DRIVE),
		TARGET_AT, TARGET_FACING)
	await _settle([attacker, target], 30)
	var weapon: WeaponBase = attacker.weapon

	# Held on the spot, out of range: the coil fills over spin_up_s and then waits
	# with nowhere to go, rather than firing into the empty arena.
	var charge_ticks := int(round(float(weapon.call("charge_s")) * float(HZ)))
	for _i in range(charge_ticks):
		attacker.apply_input(_input(Vector2.ZERO, true))
		target.apply_input(_idle())
		await physics_frame
	_report("the coil is full after spin_up_s", attacker.weapon_readiness() > 0.99,
		"%.2f" % attacker.weapon_readiness())

	var before := _condition_total(target)
	var weapon_out := false
	var drive_out := false
	for _i in range(200):
		attacker.apply_input(_input(Vector2(1.0, 0.0), true))
		target.apply_input(_idle())
		await physics_frame
		weapon_out = weapon_out or bool(target.is_disrupted("weapon"))
		drive_out = drive_out or bool(target.is_disrupted("drive"))
	var arcs := int(weapon.call("arcs"))
	var removed := before - _condition_total(target)
	_report("the arc jumps once the other machine is inside its reach", arcs >= 1,
		"%d discharges" % arcs)
	_report("and takes condition off the part it jumped to", removed > 0.0005,
		"%.4f removed" % removed)
	_report("it stalls their weapon AND their drive", weapon_out and drive_out,
		"weapon %s, drive %s" % [weapon_out, drive_out])

	for _i in range(int(round(2.0 * float(HZ)))):
		attacker.apply_input(_idle())
		target.apply_input(_idle())
		await physics_frame
	_report("and both come back",
		not bool(target.is_disrupted("weapon"))
			and not bool(target.is_disrupted("drive")),
		"weapon out %s, drive out %s" % [bool(target.is_disrupted("weapon")),
			bool(target.is_disrupted("drive"))])
	_report("a spent coil is empty and a released one does not bank its charge",
		attacker.weapon_readiness() < 0.05, "%.2f" % attacker.weapon_readiness())
	await _drop(world)


# ---------------------------------------------------------------------------
# 8. Drill lance: it bores, and the plate matters less than it does to a saw
# ---------------------------------------------------------------------------
func _check_drill_lance() -> void:
	var world := _make_world()
	var attacker := _spawn(world, _config("drill", "wedge", "drill_lance"), ATTACKER_AT)
	var target := _spawn(world, _config("prey", "box", "ram", TARGET_DRIVE),
		TARGET_AT, TARGET_FACING, STEEL)
	await _settle([attacker, target], 30)
	var weapon: WeaponBase = attacker.weapon

	var spin_ticks := int(round(float(weapon.call("spin_up_s")) * float(HZ)))
	for _i in range(spin_ticks):
		attacker.apply_input(_input(Vector2.ZERO, true))
		target.apply_input(_idle())
		await physics_frame
	_report("the lance is at speed after spin_up_s",
		attacker.weapon_readiness() > 0.99, "%.2f" % attacker.weapon_readiness())

	var before := _condition_total(target)
	for _i in range(200):
		attacker.apply_input(_input(Vector2(1.0, 0.0), true))
		target.apply_input(_idle())
		await physics_frame
	var removed := before - _condition_total(target)
	_report("and it bores through a steel plated machine", removed > 0.0005,
		"%.4f removed, %.2f s in the work"
			% [removed, float(weapon.call("boring_seconds"))])

	for _i in range(int(round(2.0 * float(HZ)))):
		attacker.apply_input(_idle())
		target.apply_input(_idle())
		await physics_frame
	_report("and it coasts down when the thumb comes off",
		attacker.weapon_readiness() < 0.05, "%.2f" % attacker.weapon_readiness())

	# The rule itself, through the real damage path rather than through the
	# arithmetic: the same amount reported as "pierce" takes 1.75 times as much
	# off a steel plate as the same amount reported as "cut".
	var cut := _direct_hit(target, "armour_front", "cut")
	var pierce := _direct_hit(target, "armour_front", BotDamage.SOURCE_PIERCE)
	_report("a pierce takes more off steel than a cut of the same size does",
		pierce > cut * 1.5 and pierce < cut * 2.0,
		"%.4f against %.4f" % [pierce, cut])
	_report("and the lance says how much of the plate it ignores",
		is_equal_approx(float(weapon.call("armour_pierce")), 0.5),
		"%.2f" % float(weapon.call("armour_pierce")))
	await _drop(world)


## One unit of direct damage through `Bot.take_direct_damage`, the real path, and
## what it actually removed. The part is put back afterwards, so the caller's
## machine is exactly as it was.
func _direct_hit(bot: Bot, part_key: String, source: String) -> float:
	var part: BotPart = null
	for candidate in bot.attached_parts():
		if candidate.part_key == part_key:
			part = candidate
			break
	if part == null:
		return 0.0
	var before: float = bot.damage.value_for(part_key)
	bot.take_direct_damage(part, 0.1, source, "test")
	var after: float = bot.damage.value_for(part_key)
	bot.damage.pending.clear()
	bot.damage._set_value(part_key, before)
	return before - after


# ---------------------------------------------------------------------------
# 9. Twin saw: two discs, one weapon
# ---------------------------------------------------------------------------
func _check_twin_saw() -> void:
	var world := _make_world()
	var attacker := _spawn(world, _config("twin", "box", "twin_saw"), ATTACKER_AT)
	var target := _spawn(world, _config("prey", "box", "ram", TARGET_DRIVE),
		TARGET_AT, TARGET_FACING)
	await _settle([attacker, target], 30)
	var weapon: WeaponBase = attacker.weapon

	_report("it builds one body per blade",
		int(weapon.call("blade_count")) == 2 and int(weapon.call("blades_left")) == 2,
		"%d of %d" % [int(weapon.call("blades_left")), int(weapon.call("blade_count"))])

	var spin_ticks := int(round(float(weapon.call("spin_up_s")) * float(HZ)))
	for _i in range(spin_ticks):
		attacker.apply_input(_input(Vector2.ZERO, true))
		target.apply_input(_idle())
		await physics_frame
	_report("both discs are at speed after spin_up_s",
		attacker.weapon_readiness() > 0.99, "%.2f" % attacker.weapon_readiness())

	var before := _condition_total(target)
	for _i in range(200):
		attacker.apply_input(_input(Vector2(1.0, 0.0), true))
		target.apply_input(_idle())
		await physics_frame
	var removed := before - _condition_total(target)
	_report("and they cut", removed > 0.0005,
		"%.4f removed, %.2f s in the work"
			% [removed, float(weapon.call("cutting_seconds"))])

	# The arbor's whole `dps` goes into whichever discs are biting (twin_saw.gd `_cut`,
	# since 2026-09-25), so one disc alone cuts at the catalogue rate and two split it.
	# That one disc still has to out-cut the whole Level 5 saw. (This read dps / 2
	# until 2026-09-27, the model before the shared arbor; the twin saw's dps was cut
	# 0.13 -> 0.065 that day after it went 8-1 and 9-0 in the gauntlet.)
	var share := float(PartsCatalogue.weapon("twin_saw").get("dps", 0.0))
	var saw := float(PartsCatalogue.weapon("saw").get("dps", 0.0))
	_report("one disc alone still beats the whole Level 5 saw", share > saw,
		"%.3f against %.3f" % [share, saw])
	await _drop(world)


# ---------------------------------------------------------------------------
# 10. Napalm cannon: fire on the floor, that goes out
# ---------------------------------------------------------------------------
func _check_napalm_cannon() -> void:
	var world := _make_world()
	var attacker := _spawn(world, _config("napalm", "box", "napalm_cannon"),
		ATTACKER_AT)
	var target := _spawn(world, _config("prey", "box", "ram", TARGET_DRIVE),
		TARGET_AT, TARGET_FACING)
	await _settle([attacker, target], 30)
	var weapon: WeaponBase = attacker.weapon
	var rack: int = attacker.gas_charges
	_report("the rack holds the catalogue's shells",
		rack == int(PartsCatalogue.weapon("napalm_cannon").get("charges", 0)),
		"%d shells" % rack)

	# One shell, thrown from a standstill. The machine never moves, so anything
	# the target loses was lost to the fire and to nothing else.
	var before := _condition_total(target)
	var lit_at := -1
	for i in range(150):
		attacker.apply_input(_input(Vector2.ZERO, i < 2))
		target.apply_input(_idle())
		await physics_frame
		if lit_at < 0 and int(weapon.call("burning_patches")) > 0:
			lit_at = i
	var removed := before - _condition_total(target)
	_report("holding the button throws a shell", int(weapon.call("shots_fired")) >= 1,
		"%d away" % int(weapon.call("shots_fired")))
	_report("and it comes out of the rack", attacker.gas_charges < rack,
		"%d left of %d" % [attacker.gas_charges, rack])
	_report("the charge flies before it lands", lit_at > 0,
		"alight at tick %d" % lit_at)
	_report("and the fire burns a machine the cannon never touched",
		removed > 0.0005, "%.4f removed from %.1f m away"
			% [removed, ATTACKER_AT.distance_to(TARGET_AT)])
	_report("a second of standing in it cuts their drive",
		bool(target.is_disrupted("drive")),
		"stalled %s" % bool(target.is_disrupted("drive")))

	# The patch goes out on its own. fuel_s is 6 s; the lit tick plus that plus a
	# second of slack has to leave the floor clear, or a napalm bot fills the
	# arena with permanent fire.
	var burn_ticks := int(round((float(PartsCatalogue.weapon("napalm_cannon")
		.get("fuel_s", 6.0)) + 1.5) * float(HZ)))
	for _i in range(burn_ticks):
		attacker.apply_input(_idle())
		target.apply_input(_idle())
		await physics_frame
	_report("and then it goes out", int(weapon.call("burning_patches")) == 0,
		"%d still alight" % int(weapon.call("burning_patches")))
	_report("the stall it caused wears off too",
		not bool(target.is_disrupted("drive")),
		"still stalled %s" % bool(target.is_disrupted("drive")))

	# The rack is finite, and an empty one says so rather than firing for free.
	for _i in range(int(round(14.0 * float(HZ)))):
		attacker.apply_input(_input(Vector2.ZERO, true))
		target.apply_input(_idle())
		await physics_frame
	_report("the rack runs dry and the readout says so",
		attacker.gas_charges == 0 and attacker.weapon_status() == "DRY",
		"%d left, reads %s" % [attacker.gas_charges, attacker.weapon_status()])

	# The bell puts the fires out: nothing may be left burning into the next fight.
	attacker.apply_input(_input(Vector2.ZERO, true))
	await physics_frame
	weapon.freeze()
	await physics_frame
	await physics_frame
	_report("and the bell puts out anything still alight",
		int(weapon.call("burning_patches")) == 0,
		"%d alight after the freeze" % int(weapon.call("burning_patches")))
	await _drop(world)


# ---------------------------------------------------------------------------
# 11. Vortex spinner: the ring that throws
# ---------------------------------------------------------------------------
func _check_vortex_spinner() -> void:
	var world := _make_world()
	var attacker := _spawn(world, _config("vortex", "shell", "vortex_spinner"),
		ATTACKER_AT)
	var target := _spawn(world, _config("prey", "box", "ram", TARGET_DRIVE),
		TARGET_AT, TARGET_FACING)
	await _settle([attacker, target], 30)
	var weapon: WeaponBase = attacker.weapon

	_report("the teeth are raked the catalogue's amount",
		float(weapon.call("lift")) > 0.0,
		"lift %.2f" % float(weapon.call("lift")))

	var spin_ticks := int(round(float(weapon.call("spin_up_s")) * float(HZ)))
	for _i in range(spin_ticks):
		attacker.apply_input(_input(Vector2.ZERO, true))
		target.apply_input(_idle())
		await physics_frame
	_report("the ring is at speed after spin_up_s",
		attacker.weapon_readiness() > 0.99, "%.2f" % attacker.weapon_readiness())
	_report("and at speed the armour faces are out of the world",
		bool(weapon.call("shielded")), "shielded %s" % bool(weapon.call("shielded")))

	var before := _condition_total(target)
	var rest: float = target.chassis.global_position.y
	var lifted := 0.0
	for _i in range(200):
		attacker.apply_input(_input(Vector2(1.0, 0.0), true))
		target.apply_input(_idle())
		await physics_frame
		lifted = maxf(lifted, target.chassis.global_position.y - rest)
	var removed := before - _condition_total(target)
	_report("the vortex takes condition off what it bites", removed > 0.0005,
		"%.4f removed" % removed)
	# Angled teeth throw as well as hit: a flat full body spinner bats its
	# opponent across the floor, this one gets it off the floor.
	_report("and it throws what it bites upward", lifted > 0.01,
		"%.3f m off the floor" % lifted)

	weapon.freeze()
	await physics_frame
	_report("the bell stops the ring and gives the faces back",
		not bool(weapon.call("shielded")) and attacker.weapon_readiness() <= 0.0,
		"shielded %s, readiness %.2f"
			% [bool(weapon.call("shielded")), attacker.weapon_readiness()])
	await _drop(world)


# ---------------------------------------------------------------------------
# 12. A fight carrying two of them still produces a well formed result
# ---------------------------------------------------------------------------
func _check_result_is_well_formed() -> void:
	var bridge: Node = root.get_node_or_null("Bridge")
	if bridge == null or not ResourceLoader.exists(FIGHT_SCENE):
		print("SKIP  the result check needs the Bridge autoload and the fight scene")
		return
	var fight: Node = (load(FIGHT_SCENE) as PackedScene).instantiate()
	root.add_child(fight)
	await process_frame

	_results = []
	bridge.message_sent.connect(_on_message_sent)
	var config := _fight_config()
	bridge.inject_from_host({"type": "fight_config", "json": JSON.stringify(config)})
	await process_frame
	fight.call("_set_state", STATE_FIGHTING)
	for _i in range(180):
		await physics_frame
	fight.call("_finish", "ko", 0, 1)
	await process_frame
	var result := _last_result()
	bridge.message_sent.disconnect(_on_message_sent)

	_report("a fight with the new weapons sends a result", not result.is_empty(), "")
	if not result.is_empty():
		var missing := PackedStringArray()
		for key in ["schema", "damage", "scrap", "hits", "parts_lost",
				"condition_start", "scrap_breakdown"]:
			if not result.has(key):
				missing.append(key)
		_report("and it carries every key a result carries", missing.is_empty(),
			str(missing))
		var scrap: Dictionary = result.get("scrap", {}) as Dictionary
		var bad := PackedStringArray()
		for id_variant in scrap.keys():
			var value := float(scrap[id_variant])
			if is_nan(value) or is_inf(value) or value < 0.0:
				bad.append("%s %s" % [str(id_variant), str(value)])
		_report("every scrap figure is a real number", bad.is_empty(), str(bad))
		var damage: Dictionary = result.get("damage", {}) as Dictionary
		_report("both machines reported their condition", damage.size() == 2,
			"%d entries" % damage.size())

	root.remove_child(fight)
	fight.queue_free()
	await process_frame


func _fight_config() -> Dictionary:
	var text := FileAccess.get_file_as_string("res://fight/fixtures/stage3_config.json")
	var parsed: Variant = JSON.parse_string(text)
	var config: Dictionary = parsed as Dictionary if parsed is Dictionary else {}
	var bots: Array = config.get("bots", []) as Array
	if bots.size() >= 2:
		(bots[0] as Dictionary)["weapon"] = "napalm_cannon"
		(bots[1] as Dictionary)["chassis"] = "shell"
		(bots[1] as Dictionary)["weapon"] = "vortex_spinner"
		(bots[1] as Dictionary)["utility"] = []
		(bots[1] as Dictionary)["armour"] = LIGHT.duplicate(true)
	return config


func _on_message_sent(type: String, payload: Dictionary) -> void:
	if type == FightTypes.MSG_FIGHT_RESULT:
		_results.append(payload)


func _last_result() -> Dictionary:
	return (_results[-1] as Dictionary) if not _results.is_empty() else {}


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------
## The target's drive. A 2wd box is the lightest legal machine to park in the
## lane, so the budget never rejects the fixture whatever it is carrying.
const TARGET_DRIVE := "2wd"


## A hull each weapon is legal on, and light enough to carry it. A hull that names
## the weapon in its own `weapons_allowed` wins, so a full body spinner is tried on
## the machine built for it; otherwise it is the first hull the rules allow.
func _hull_for(weapon_id: String) -> String:
	var fallback := ""
	for chassis_variant in PartsCatalogue.ids("chassis"):
		var chassis_id := str(chassis_variant)
		if not BuildRules.validate(_config("h", chassis_id, weapon_id)).is_empty():
			continue
		var allowed: Array = PartsCatalogue.chassis(chassis_id) \
			.get("weapons_allowed", []) as Array
		if allowed.has(weapon_id):
			return chassis_id
		if fallback == "":
			fallback = chassis_id
	return fallback if fallback != "" else "box"


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
	var arena: Node3D = (load(YARD_SCENE) as PackedScene).instantiate()
	arena.name = "Arena"
	world.add_child(arena)
	if arena.has_method("setup"):
		arena.call("setup", rng)
	return world


func _spawn(world: Node3D, config: Dictionary, at: Vector3,
		facing: Vector3 = Vector3.RIGHT, armour: Dictionary = {}) -> Bot:
	if not armour.is_empty():
		config = config.duplicate(true)
		config["armour"] = armour.duplicate(true)
	var bot: Bot = (load(BOT_SCENE) as PackedScene).instantiate()
	world.add_child(bot)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
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


func _settle(bots: Array, ticks: int) -> void:
	for _i in range(ticks):
		for b in bots:
			(b as Bot).apply_input(_idle())
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
