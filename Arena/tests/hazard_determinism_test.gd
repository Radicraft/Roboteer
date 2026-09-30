extends SceneTree
## Wave A hazards (docs/wave-a-hazards-notes.md): the presentation work on the arenas (the
## shared hazard warning layer, new hazard meshes, exposure and wall tint, idle sparks,
## the belt scroll, hazard shake and haptics) must not move the simulation by one bit.
##
##   Godot --headless --path Arena --script tests/hazard_determinism_test.gd
##   Godot --headless --path Arena --script tests/hazard_determinism_test.gd -- --record
##
## How: the desktop QA fixture (res://fight/fixtures/stage3_config.json, the one
## determinism_test uses) is fought in each of the six arenas through the real Fight
## scene. On every physics step at a multiple of SAMPLE_TICKS the bots' chassis
## transforms, their condition() and the arena's hazard_helpers() are serialised with
## var_to_bytes (bit exact, no float printing), and the whole run is hashed. GOLDEN holds
## the hashes recorded on commit ac12e1e, BEFORE any wave A change: the arenas with the
## warning layer on have to produce exactly those numbers.
##
## One more check: the Coliseum (every hazard at once) is run a second time with the
## warning layer switched off (HazardTelegraph.enabled = false) and must hash the same as
## with it on, so the layer is proven inert on its own and not only by the golden.
##
## The goldens are for this machine's Jolt build (macOS arm64, Godot 4.6). A different
## CPU or engine build may legitimately differ; `--record` prints fresh numbers, which
## must be recorded on a tree WITHOUT the change under test.

const FIGHT_SCENE := "res://fight/fight.tscn"
const BOT_SCENE := "res://bot/bot.tscn"
const FIXTURE := "res://fight/fixtures/stage3_config.json"
const TELEGRAPH_SCRIPT := "res://arena/hazard_telegraph.gd"

const SAMPLE_TICKS := 30
## Fight ticks per arena: enough for every timed hazard to fire at least once on this
## seed (the Drop Zone pit opens between 30 and 60 s, so it gets the longest run).
const TICKS := {
	"yard": 900,
	"grinder": 900,
	"furnace": 1500,
	"crush": 1200,
	"drop_zone": 3700,
	"coliseum": 1200,
}
const ORDER := ["yard", "grinder", "furnace", "crush", "drop_zone", "coliseum"]
## Frames allowed per run before calling it hung.
const FRAME_BUDGET := 20000

## Recorded on ac12e1e (before wave A), macOS arm64, Godot 4.6, with `--record`.
## crush and coliseum end on a result: re-recorded 2026-09-25 on 1fbb1b5 (before the combat
## feel wave) once the result row stopped hashing transforms (see `_sample`); every row before
## the result is the same bytes as the ac12e1e run, and the other four are unchanged.
## Re-recorded 2026-09-27 on 4822d27 (coordinator), deliberately, for the day's simulation
## changes: hero wedge ballast 3 -> 2 kg (bc591ba), hazard phases folded from FIGHT not
## tick 0 (a8bc994), weapons balance + flipper end-on lift (900f15e, 6c038c9), lifter and
## axe drive fixes (d6ebcfd, 97d6de2). Two --record runs gave identical bytes, and the
## coliseum warning layer OFF still hashes the same as ON (the layer is inert).
## Re-recorded 2026-09-28 on 087fa87 (integration, docs/wave-b-integration-notes.md), for the
## wave B simulation changes, traced commit by commit (--record at every Arena commit from
## e994cd3, which still gave the 2026-09-27 numbers below it, to 39e0cd3):
##   boost f902361 + ede4db2 + c72dd92 (the AI presses BOOST, the unstick nudge, the 3 s
##     lock-up break) move ALL SIX; drop_zone and coliseum move by this alone.
##   stages 00056bb moves yard, grinder, furnace and crush on top: their sleeping WAKE
##     hazards (wall grinders, centre / corridor spike patches, east jets) are new bodies in
##     the physics space from tick 0 (as docs/wave-b-pacing-notes.md measured in isolation).
##   Nothing else moves any of them: the intro, test arena, loading screen, srimech retry,
##     fight stages, National shove, type swap and judges commits hash the same as the one
##     before. The furnace now ends at tick 247 (the boosted AI flipper rings the idle
##     fixture player out over the west wall; a ring-out, not a fault).
## Was (2026-09-27, 4822d27): yard c229c004e455d784, grinder 40975d7bf1357d36, furnace
## f861978cfae492eb, crush b9c453dd0581b13a, drop_zone 2f84d6c683eb34f6, coliseum
## 475bd101e767f21d.
## Re-recorded 2026-09-30 on wave-d-marshal (docs/wave-d-marshal-notes.md), deliberately, for
## ONE simulation change: the pin rule (fight.gd PIN_LIMIT_S). In the Drop Zone's 3700 tick
## run the fixture's AI holds the idle player on a wall for 4 s and the Marshal tows it off, so
## drop_zone moves 3c8a0a72052ca8cf -> ba6a58ff2e2a9c78. The other five never hold a pin that
## long and are unchanged, and the Marshal itself (presentation, tests/marshal_test.gd) moves
## nothing. Proven below: with the rule switched off drop_zone gives back 3c8a0a72052ca8cf.
const PRE_PIN_RULE_DROP_ZONE := "3c8a0a72052ca8cf"
const GOLDEN := {
	"yard": "c814ec9e2c1a3b19",
	"grinder": "948cea0b512e1375",
	"furnace": "fa79709c3fddc315",
	"crush": "29b028f7726a2f2f",
	"drop_zone": "ba6a58ff2e2a9c78",
	"coliseum": "7c37e036b6df6957",
}

var _checks := 0
var _failures := 0
var _fight: Node = null
var _record := false

# Per run sampling state, filled from the physics_frame signal.
var _ctx: HashingContext = null
var _last_tick := -1
var _samples := 0
var _target := 0
var _first_fire := {}


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	_record = "--record" in OS.get_cmdline_user_args()
	if not ResourceLoader.exists(BOT_SCENE) or not ResourceLoader.exists(FIGHT_SCENE):
		print("SKIP  hazard determinism: the bot or fight scene is absent")
		quit(0)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	if not parsed is Dictionary:
		_check(false, "the desktop QA fixture loads")
		_finish()
		return
	var fixture: Dictionary = parsed

	var hashes := {}
	for arena_id in ORDER:
		var result: Dictionary = await _simulate(fixture, arena_id, true)
		hashes[arena_id] = result["hash"]
		print("INFO  %s: %d samples to tick %d, hash %s, first activations %s"
			% [arena_id, int(result["samples"]), int(result["tick"]), str(result["hash"]),
				str(result["fires"])])
		if _record:
			continue
		if not GOLDEN.has(arena_id):
			_check(false, "%s has a golden hash recorded" % arena_id)
			continue
		_check(str(result["hash"]) == str(GOLDEN[arena_id]),
			"%s: the fight with the wave A arena presentation matches the pre-change golden (%s)"
				% [arena_id, str(result["hash"])])

	if _record:
		print("")
		print("const GOLDEN := {")
		for arena_id in ORDER:
			print("\t\"%s\": \"%s\"," % [arena_id, str(hashes[arena_id])])
		print("}")
		quit(0)
		return

	# wave D: the one golden that moved, moved for the pin rule and nothing else.
	var fight_script: GDScript = load(FIGHT_SCENE.replace(".tscn", ".gd")) as GDScript
	fight_script.set("pin_rule_enabled", false)
	var no_rule: Dictionary = await _simulate(fixture, "drop_zone", true)
	fight_script.set("pin_rule_enabled", true)
	print("INFO  drop_zone with the pin rule off: %s" % str(no_rule["hash"]))
	_check(str(no_rule["hash"]) == PRE_PIN_RULE_DROP_ZONE,
		"drop_zone with the pin rule off hashes the pre-rule golden (%s)" % str(no_rule["hash"]))

	# The layer on its own: off and on must agree in the arena with every hazard.
	var script: GDScript = load(TELEGRAPH_SCRIPT) as GDScript
	_check(script != null, "the shared hazard warning layer exists (%s)" % TELEGRAPH_SCRIPT)
	if script != null:
		script.set("enabled", false)
		var off: Dictionary = await _simulate(fixture, "coliseum", false)
		script.set("enabled", true)
		_check(str(off["hash"]) == str(hashes["coliseum"]),
			"coliseum: warning layer OFF hashes the same as ON (%s and %s)"
				% [str(off["hash"]), str(hashes["coliseum"])])
	_finish()


func _simulate(fixture: Dictionary, arena_id: String, expect_telegraph: bool) -> Dictionary:
	if _fight == null:
		_fight = (load(FIGHT_SCENE) as PackedScene).instantiate()
		root.add_child(_fight)
		await process_frame
	var config := fixture.duplicate(true)
	config["arena"] = arena_id
	var rules: Dictionary = config.get("rules", {}) as Dictionary
	rules["duration_s"] = 180
	config["rules"] = rules

	_ctx = HashingContext.new()
	_ctx.start(HashingContext.HASH_SHA256)
	_last_tick = -1
	_samples = 0
	_target = int(TICKS[arena_id])
	_first_fire = {}
	var done := [false]
	var on_step := func() -> void:
		if done[0]:
			return
		if _sample():
			done[0] = true
	physics_frame.connect(on_step)
	_fight.call("start_fight", config)
	var arena: Node = _fight.call("arena") if _fight.has_method("arena") else _fight.get("_arena")
	if arena != null and arena.has_signal("hazard_fx"):
		arena.connect("hazard_fx", func(kind: String, active: bool, _p: Vector3) -> void:
			if active and not _first_fire.has(kind):
				_first_fire[kind] = int(_fight.get("_tick")))
	if expect_telegraph and not _record and arena != null:
		_check(arena.get_node_or_null("HazardTelegraph") != null,
			"%s builds the shared HazardTelegraph node" % arena_id)

	var frames := 0
	while not done[0] and frames < FRAME_BUDGET:
		await process_frame
		frames += 1
	physics_frame.disconnect(on_step)
	# A fight that ended early (a KO) is compared where it ended.
	return {
		"hash": _ctx.finish().hex_encode().substr(0, 16),
		"samples": _samples,
		"tick": _last_tick,
		"fires": _first_fire.duplicate(),
	}


## One physics step. Returns true when the run is complete.
func _sample() -> bool:
	var tick := int(_fight.get("_tick"))
	var state := int(_fight.get("state"))
	var over := state == 3                         # State.RESULT
	if tick == _last_tick and not over:
		return false
	if tick % SAMPLE_TICKS != 0 and tick < _target and not over:
		_last_tick = tick
		return false
	_last_tick = tick
	_samples += 1
	var row := [tick, state]
	var bots: Array = _fight.get("_bots") as Array
	for bot in bots:
		if bot == null or not is_instance_valid(bot):
			row.append(null)
			continue
		# The RESULT row leaves the chassis transforms out. Since combat feel B7 (2026-09-24)
		# the bodies keep moving through the 3.5 s finish beat after the result (a machine
		# thrown on the deciding tick carries on over the wall) where they used to be zeroed,
		# so the one physics step between the result and this sample moves them. That is
		# presentation after the fight is decided; the tick, state, condition and scrap of
		# the result row are still hashed. Proven 2026-09-25: re-freezing at the result on
		# 7dd1f62 gives back the ac12e1e hashes bit for bit (docs/wave-a-combat-notes.md).
		var chassis: Node3D = bot.get("chassis") as Node3D
		if over:
			row.append(null)
		else:
			row.append(chassis.global_transform if chassis != null and chassis.is_inside_tree() else null)
		row.append(bot.call("condition") if bot.has_method("condition") else {})
	var arena: Node = _fight.get("_arena")
	if arena != null and is_instance_valid(arena) and arena.has_method("hazard_helpers"):
		row.append(arena.call("hazard_helpers"))
	row.append((_fight.get("_scrap") as Array).duplicate())
	_ctx.update(var_to_bytes(row))
	return tick >= _target or over


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
		print("PASS  hazard determinism: %d checks, 0 failures" % _checks)
		quit(0)
	else:
		print("FAIL  hazard determinism: %d checks, %d failures" % [_checks, _failures])
		quit(1)
