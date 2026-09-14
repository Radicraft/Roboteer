extends SceneTree
## The three builds proof (docs/stage4-spec.md §6, brief §15 Stage 4: "Verify three
## different builds genuinely play differently against the same opponent").
##
##   Godot --headless --path Arena --script tests/builds_test.gd
##
## Three machines, each driven by the AI, each against the SAME opponent from the SAME
## seed, and their fights have to differ in ways that follow from what they are built out
## of rather than from noise:
##
##   (a) wedge / 4wd / flipper, hdpe sides    throws the opponent into the air
##   (b) box / 6wd / horizontal_spinner, steel 1   takes armour off
##   (c) long_low / tracks / ram, titanium    pushes, and barely scratches anything
##
## If these three fight the same, the builder is decoration and Stage 4 has failed.
##
## SKIPs until agents W1 and W2 have landed the weapons two of the builds are made of.

const FIGHT_SCENE := "res://fight/fight.tscn"
const FIXTURE := "res://fight/fixtures/stage3_config.json"
const REQUIRED_WEAPONS := [
	"res://bot/weapons/horizontal_spinner.gd",
	"res://bot/weapons/ram.gd",
]

const SECONDS := 60
const TICKS := SECONDS * 60
const FRAME_BUDGET := 600000
const SEED := 20260913

## Above this the opponent counts as thrown, not merely bumped.
const AIRTIME_M := 0.4
## Chassis centres this close counts as being on them.
const PUSH_RANGE_M := 1.3

var _failures := 0
var _checks := 0
var _fight: Node = null


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame

	for path in REQUIRED_WEAPONS:
		if not ResourceLoader.exists(path):
			print("SKIP  builds: %s is absent, the weapons have not landed yet" % path)
			quit(0)
			return
	if not ResourceLoader.exists(FIGHT_SCENE):
		print("SKIP  builds: %s is absent" % FIGHT_SCENE)
		quit(0)
		return

	var results: Array = []
	for build in [_build_a(), _build_b(), _build_c()]:
		results.append(await _fight_once(build))

	var a: Dictionary = results[0]
	var b: Dictionary = results[1]
	var c: Dictionary = results[2]

	for row_variant in results:
		var row: Dictionary = row_variant
		print("      %-28s %5.1f kg  panels %d  throws %d  push %.2f m in %.1f s = %.2f m/s"
			% [str(row["label"]), float(row["weight"]), int(row["panels_off"]),
				int(row["throws"]), float(row["push"]), float(row["contact_s"]),
				float(row["push_rate"])])
		print("      %-28s condition removed %.2f  hits %d  impulse %.0f (mean %.1f)"
			% ["", float(row["damage_removed"]), int(row["hits"]),
				float(row["impulse"]), float(row["mean_impulse"])])

	# Every build is legal. A test that proves three illegal builds play differently
	# proves nothing, so this comes first.
	for row_variant in results:
		var row: Dictionary = row_variant
		_check(float(row["weight"]) <= 100.0,
			"%s is inside the weight budget (%.1f kg)" % [str(row["label"]), float(row["weight"])])
		_check((row["errors"] as Array).is_empty(),
			"%s passes BuildRules (%s)" % [str(row["label"]), ", ".join(row["errors"] as Array)])

	# (b) the spinner takes armour off. That is what a spinner is for.
	_check(int(b["panels_off"]) >= 1,
		"the spinner build removes at least one panel (%d)" % int(b["panels_off"]))

	# (a) the flipper puts the opponent in the air, more than once.
	_check(int(a["throws"]) >= 2,
		"the flipper build throws the opponent above %.1f m at least twice (%d)"
			% [AIRTIME_M, int(a["throws"])])

	# (c) the ram pushes hardest and damages least. Both halves matter: a ram that also
	# out-damaged the spinner would mean the damage model is not reading the weapon.
	#
	# Push is measured per second OF CONTACT and only along the direction we are shoving
	# in. Total travel is the wrong metric and was the first version of this test: it is
	# dominated by the drive and the AI, so a 4wd bot that drives in circles near its
	# opponent "pushed" 13.70 m while the tracked ram "pushed" 6.85 m without either
	# number saying anything about pushing.
	_check(float(c["push_rate"]) > float(a["push_rate"])
			and float(c["push_rate"]) > float(b["push_rate"]),
		"the ram build pushes through hardest (%.2f m/s of contact against %.2f and %.2f)"
			% [float(c["push_rate"]), float(a["push_rate"]), float(b["push_rate"])])
	# Not a strict less-than: three builds that all fail to remove any condition are a
	# different failure, and it should be reported as itself rather than as a ram result.
	_check(float(c["damage_removed"]) <= float(a["damage_removed"])
			and float(c["damage_removed"]) <= float(b["damage_removed"]),
		"the ram build removes no more condition than the others (%.2f against %.2f and %.2f)"
			% [float(c["damage_removed"]), float(a["damage_removed"]), float(b["damage_removed"])])
	if float(a["damage_removed"]) + float(b["damage_removed"]) + float(c["damage_removed"]) <= 0.0:
		print("NOTE  no build removed any condition at all, so the damage comparison is vacuous")

	# A ram is a weight of steel with no moving parts: fewer blows, each one harder. The
	# impulse is on the damage_event payload, so this reads what the physics actually did
	# rather than what the catalogue says it should do.
	if int(a["hits"]) > 0 and int(b["hits"]) > 0 and int(c["hits"]) > 0:
		_check(float(c["mean_impulse"]) > float(a["mean_impulse"])
				and float(c["mean_impulse"]) > float(b["mean_impulse"]),
			"the ram build lands the heaviest blows (mean impulse %.1f against %.1f and %.1f)"
				% [float(c["mean_impulse"]), float(a["mean_impulse"]), float(b["mean_impulse"])])
	else:
		print("NOTE  not every build landed a damage event, so the impulse comparison is skipped"
			+ " (hits %d / %d / %d)" % [int(a["hits"]), int(b["hits"]), int(c["hits"])])

	# And the three fights are not the same fight.
	_check(not (is_equal_approx(float(a["damage_removed"]), float(b["damage_removed"]))
			and is_equal_approx(float(b["damage_removed"]), float(c["damage_removed"]))),
		"the three builds do not produce identical fights")

	_finish()


# ---------------------------------------------------------------- the builds

func _armour(front: String, sides: String, rear: String, top: String, thickness: int) -> Dictionary:
	return {
		"front": {"material": front, "thickness": thickness},
		"sides": {"material": sides, "thickness": thickness},
		"rear": {"material": rear, "thickness": thickness},
		"top": {"material": top, "thickness": thickness},
	}


func _damage() -> Dictionary:
	return {
		"wheels": [1.0, 1.0, 1.0, 1.0], "weapon": 1.0,
		"armour": {"front": 1.0, "sides": 1.0, "rear": 1.0, "top": 1.0},
		"drive": 1.0, "core": 1.0,
	}


func _build_a() -> Dictionary:
	return {
		"id": "player-1", "name": "Tinribs", "controller": "player",
		"chassis": "wedge", "drive": "4wd", "weapon": "flipper", "utility": ["srimech"],
		"armour": _armour("steel", "hdpe", "hdpe", "steel", 2),
		"damage": _damage(), "label": "wedge / 4wd / flipper",
	}


## Steel at thickness 1, not 2. A box with six wheels and a spinner has 82 kg of chassis,
## drive, weapon and srimech before a single plate goes on, and four faces of steel 2 is
## 30.6 kg on top of that: 112.6 kg, over the budget by 12.6 (measured with
## BuildRules.total_weight). Steel 1 is 15.3 kg of armour and the build lands at 97.3 kg.
## That is the real trade a spinner build makes and it belongs in the fixture: the weight
## goes into the weapon, so the armour has to give.
func _build_b() -> Dictionary:
	return {
		"id": "player-1", "name": "Grinder", "controller": "player",
		"chassis": "box", "drive": "6wd", "weapon": "horizontal_spinner", "utility": ["srimech"],
		"armour": _armour("steel", "steel", "steel", "steel", 1),
		"damage": _damage(), "label": "box / 6wd / horizontal_spinner",
	}


func _build_c() -> Dictionary:
	return {
		"id": "player-1", "name": "Shunt", "controller": "player",
		"chassis": "long_low", "drive": "tracks", "weapon": "ram", "utility": ["srimech"],
		"armour": _armour("titanium", "titanium", "titanium", "titanium", 2),
		"damage": _damage(), "label": "long_low / tracks / ram",
	}


## The same opponent every time: box, 4wd, saw, all steel (spec §6).
func _opponent() -> Dictionary:
	return {
		"id": "ai-1", "name": "Scrapheap", "controller": "ai",
		"chassis": "box", "drive": "4wd", "weapon": "saw", "utility": ["srimech"],
		"armour": _armour("steel", "steel", "steel", "steel", 2),
		"damage": _damage(),
	}


# ---------------------------------------------------------------- one fight

func _fight_once(build: Dictionary) -> Dictionary:
	var label := str(build.get("label", ""))
	var bot_config: Dictionary = build.duplicate(true)
	bot_config.erase("label")

	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	config["seed"] = SEED
	config["rules"] = {"mode": "fight", "duration_s": SECONDS, "ko_count_s": 9999}
	config["debug"] = {"opponent_ai": "normal", "player_ai": "normal"}
	config["bots"] = [bot_config, _opponent()]

	var errors: Array = []
	var weight := 0.0
	if ClassDB.class_exists("BuildRules") or ResourceLoader.exists("res://bot/build_rules.gd"):
		var rules: GDScript = load("res://bot/build_rules.gd")
		if rules != null:
			weight = float(rules.call("total_weight", bot_config))
			errors = rules.call("validate", bot_config) as Array

	# Each fight gets its own Fight node, and fight.gd gives each fight its own World3D.
	_fight = (load(FIGHT_SCENE) as PackedScene).instantiate()
	root.add_child(_fight)
	await process_frame
	_fight.call("start_fight", config)
	await process_frame

	var bots: Array = _fight.get("_bots") as Array
	var panels_off := {"count": 0}
	if bots[1] != null and bots[1].has_signal("part_detached"):
		bots[1].connect("part_detached", func(part: String) -> void:
			if part.begins_with("armour"):
				panels_off["count"] += 1)

	# Contact impulses, read off the damage events the player's machine caused.
	var blows := {"hits": 0, "impulse": 0.0}
	for bot in bots:
		if bot != null and bot.has_signal("damage_event"):
			bot.connect("damage_event", func(info: Dictionary) -> void:
				if str(info.get("attacker", "")) == "player-1":
					blows["hits"] += 1
					blows["impulse"] += absf(float(info.get("impulse", 0.0))))

	var throws := 0
	var was_up := false
	var push := 0.0
	var contact_ticks := 0
	var last_foe := _position(bots[1])
	var frames := 0
	while frames < FRAME_BUDGET and int(_fight.get("_tick")) < TICKS \
			and int(_fight.get("state")) != 3:
		await physics_frame
		frames += 1
		var foe := _position(bots[1])
		var me := _position(bots[0])
		var up := foe.y > AIRTIME_M
		if up and not was_up:
			throws += 1
		was_up = up
		# Push through: while we are on them, how far they went in the direction we are
		# shoving. Travel across or toward us is theirs, not ours, and does not count.
		var gap := Vector2(foe.x - me.x, foe.z - me.z)
		if gap.length() <= PUSH_RANGE_M and gap.length() > 0.0001:
			contact_ticks += 1
			var moved := Vector2(foe.x - last_foe.x, foe.z - last_foe.z)
			push += maxf(0.0, moved.dot(gap.normalized()))
		last_foe = foe

	var tallies: Array = _fight.get("_tallies") as Array
	var damage_removed := float((tallies[0] as Dictionary).get("damage_removed", 0.0))

	root.remove_child(_fight)
	_fight.queue_free()
	_fight = null
	await process_frame
	await process_frame

	var contact_s := float(contact_ticks) / 60.0
	var hits := int(blows["hits"])
	return {
		"label": label, "weight": weight, "errors": errors,
		"panels_off": int(panels_off["count"]), "throws": throws,
		"push": push, "contact_s": contact_s,
		"push_rate": push / maxf(contact_s, 0.0001),
		"damage_removed": damage_removed,
		"hits": hits, "impulse": float(blows["impulse"]),
		"mean_impulse": float(blows["impulse"]) / float(maxi(hits, 1)),
	}


func _position(bot: Node) -> Vector3:
	if bot == null:
		return Vector3.ZERO
	var chassis: Variant = bot.get("chassis")
	if chassis is Node3D and (chassis as Node3D).is_inside_tree():
		return (chassis as Node3D).global_position
	return Vector3.ZERO


# ---------------------------------------------------------------- harness

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS  ", label)
	else:
		_failures += 1
		printerr("FAIL  ", label)
		print("FAIL  ", label)


func _finish() -> void:
	print("")
	if _failures == 0:
		print("PASS  builds: %d checks, 0 failures" % _checks)
		quit(0)
	else:
		print("FAIL  builds: %d checks, %d failures" % [_checks, _failures])
		quit(1)
