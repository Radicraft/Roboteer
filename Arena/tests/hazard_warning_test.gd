extends SceneTree
## Wave A: the shared hazard warning language (docs/wave-a-hazards-notes.md).
##   Godot --headless --path Arena --script tests/hazard_warning_test.gd
##
## Headless and fast: the six arenas are built on their own and their hazard tick is
## driven by hand (arenas_test does the same), 90 s of timeline each. It asserts:
##   * hazard_schedule() exists on every arena and lists every hazard it has
##   * it is READ-ONLY: a timeline read ten times a tick is identical to one never read
##   * every timed hazard's clock runs down by exactly one tick per tick and reaches 0 on
##     the tick it acts, so the 1.25 s wind-up lands where it claims to
##   * the owner's rule: no warning starts later than the AI can perceive the hazard
##     (re-derived from opponent_ai.gd's own constants, so it fails if they grow)
##   * whenever the arena tells the AI a timed hazard is live, the player's telegraph is
##     already out of IDLE for it
##   * the telegraph node exists, adds no collision and its switch works
##   * wave B pacing: the same guarantee through a whole STAGED round (set_stage at 0:45
##     and 1:30, set_phase at 2:00, the final stage at 2:35): every activation of every
##     timed hazard, including the ones that were asleep, is preceded by at least the
##     shared warning of unbroken countdown, and every sleeping hazard wakes and acts

const ARENAS := {
	"yard": "res://arena/yard.tscn",
	"grinder": "res://arena/grinder.tscn",
	"drop_zone": "res://arena/drop_zone.tscn",
	"furnace": "res://arena/furnace.tscn",
	"crush": "res://arena/crush.tscn",
	"coliseum": "res://arena/coliseum.tscn",
}
## Hazards each arena must list, by kind.
const EXPECT := {
	"yard": {"spikes": 1},
	"grinder": {"grinder": 2},
	"drop_zone": {"pit": 1},
	"furnace": {"flame": 8},          # wave B: + the east bank, asleep until the wake stage
	"crush": {"ram": 2},
	"coliseum": {"spikes": 1, "grinder": 2, "flame": 2, "turntable": 2},
}
const AI_SCRIPT := "res://ai/opponent_ai.gd"
const SEED := 4242
const TICKS := 90 * 60
const TICK := 1.0 / 60.0

var _checks := 0
var _failures := 0


func _initialize() -> void:
	await _run()


func _run() -> void:
	await process_frame
	var ai: GDScript = load(AI_SCRIPT) as GDScript
	var horizon := 0.0
	if ai != null:
		var consts: Dictionary = ai.get_script_constant_map()
		var lead := float(consts.get("HAZARD_LEAD_S", 0.0))
		for skill in (consts.get("SKILLS", {}) as Dictionary).values():
			horizon = maxf(horizon, float((skill as Dictionary).get("danger_s", 0.0)) + lead)
		horizon = maxf(horizon, float(consts.get("SPIKE_AVOID_LEAD_S", 0.0)))
	_check(horizon > 0.0, "read the AI's longest look at a clocked hazard from opponent_ai.gd (%.2f s)"
		% horizon)

	for id_variant in ARENAS.keys():
		var id := str(id_variant)
		_check_arena(id, horizon)
	for id_variant in ARENAS.keys():
		_check_staged(str(id_variant), horizon)
	_finish()


func _check_arena(id: String, horizon: float) -> void:
	var quiet := _make(id)
	var read := _make(id)
	if quiet == null or read == null:
		_check(false, "%s builds" % id)
		return
	_check(read.has_method("hazard_schedule"), "%s exposes hazard_schedule()" % id)
	var telegraph := read.get_node_or_null("HazardTelegraph")
	_check(telegraph != null, "%s has the shared HazardTelegraph child" % id)
	if telegraph != null:
		_check(_bodies(telegraph) == 0, "%s: the telegraph adds no collision object" % id)

	# What it lists.
	var counts := {}
	for e in read.call("hazard_schedule"):
		var kind := str((e as Dictionary)["kind"])
		counts[kind] = int(counts.get(kind, 0)) + 1
	var want: Dictionary = EXPECT[id]
	for kind in want.keys():
		_check(int(counts.get(kind, 0)) == int(want[kind]),
			"%s lists %d %s (%d)" % [id, int(want[kind]), kind, int(counts.get(kind, 0))])

	# Read-only, perception and exactness, over 90 s.
	var same := true
	var mismatch_at := -1
	var late_warning := ""
	var exact := true
	var exact_note := ""
	var prev_in := {}
	var saw_activation := {}
	for tick in range(TICKS):
		var sched: Array = read.call("hazard_schedule")
		for _i in range(9):
			read.call("hazard_schedule")
			read.call("hazard_helpers")
		# The AI's view at this instant: every position it is told is dangerous.
		var helpers: Dictionary = read.call("hazard_helpers")
		var danger: Array = helpers.get("danger_positions", [])
		var spike_rise := float(read.call("seconds_to_spike_rise"))
		for e_variant in sched:
			var e: Dictionary = e_variant
			var eid := str(e["id"])
			if bool(e["always_on"]):
				continue
			var in_s := float(e["in_s"])
			var active := bool(e["active"])
			var warn_s := float(e["warn_s"])
			var telegraph_live := active or in_s <= warn_s
			# 1. The AI is told this hazard is dangerous: the player must already be told.
			if not telegraph_live and _listed(danger, e) and not _always_listed(id, str(e["kind"])):
				late_warning = "%s at tick %d (in %.2f s, window %.2f s)" % [eid, tick, in_s, warn_s]
			# 2. The spike clock the AI reads directly.
			if str(e["kind"]) == "spikes" and not active and spike_rise <= horizon and in_s > warn_s:
				late_warning = "%s spike clock at tick %d (AI %.2f s, window %.2f s)" \
					% [eid, tick, spike_rise, warn_s]
			# 3. Exact countdown: down one tick per tick, 0 on the activation tick.
			if prev_in.has(eid):
				var was := float(prev_in[eid])
				if not active and was < 900.0 and in_s < 900.0 and in_s < was \
						and absf((was - in_s) - TICK) > 0.0001:
					exact = false
					exact_note = "%s ticked %.4f s at tick %d" % [eid, was - in_s, tick]
				if active and not bool(saw_activation.get(eid + "_on", false)):
					saw_activation[eid] = true
					if was > TICK + 0.0001 and was < 900.0:
						exact = false
						exact_note = "%s went active with %.4f s still on its clock" % [eid, was]
			saw_activation[eid + "_on"] = active
			prev_in[eid] = 0.0 if active else in_s
		quiet._physics_process(TICK)
		read._physics_process(TICK)
		if same and not _same(quiet, read):
			same = false
			mismatch_at = tick
	_check(same, "%s: reading the schedule ten times a tick changes nothing over 90 s%s"
		% [id, "" if same else " (diverged at tick %d)" % mismatch_at])
	_check(late_warning == "", "%s: no warning starts after the AI can see the hazard%s"
		% [id, "" if late_warning == "" else " (" + late_warning + ")"])
	_check(exact, "%s: every hazard clock runs down one tick per tick and reads 0 as it acts%s"
		% [id, "" if exact else " (" + exact_note + ")"])
	for e_variant in read.call("hazard_schedule"):
		var e: Dictionary = e_variant
		if bool(e["always_on"]) or bool(e.get("dormant", false)):
			continue          # wave B: a sleeping hazard acts only once staged (below)
		_check(bool(saw_activation.get(str(e["id"]), false)),
			"%s: %s acted at least once in 90 s on seed %d" % [id, str(e["id"]), SEED])
		if str(e["kind"]) == "spikes":
			_check(float(e["warn_s"]) >= horizon,
				"%s: the spike patch arms %.2f s out, no later than the AI's %.2f s"
					% [id, float(e["warn_s"]), horizon])

	# The switch.
	var script: GDScript = load("res://arena/hazard_telegraph.gd") as GDScript
	if script != null:
		script.set("enabled", false)
		_check(script.get("enabled") == false, "HazardTelegraph.enabled can be switched off")
		var off := _make(id)
		var node := off.get_node_or_null("HazardTelegraph") if off != null else null
		_check(node != null and not node.is_processing() and not (node as Node3D).visible,
			"%s: a telegraph built while switched off does nothing" % id)
		script.set("enabled", true)
		if off != null:
			_free(off)
	_free(quiet)
	_free(read)


# ---------------------------------------------------------------------------
# Wave B pacing: the warning guarantee through a staged round.
# ---------------------------------------------------------------------------
## Arena ticks for the stage calls: fight.gd's fight ticks plus the countdown the arena
## ticks through (ArenaBase.FIGHT_START_TICKS).
const STAGED_TICKS := 180 * 60
const STAGE_AT := {2700: 1, 5400: 2, 9300: 4}
const ENDGAME_AT := 7200


func _check_staged(id: String, horizon: float) -> void:
	var arena := _make(id)
	if arena == null:
		_check(false, "%s builds (staged)" % id)
		return
	var start := int(ArenaBase.FIGHT_START_TICKS)
	var words: Array = []
	for st in [1, 2, 4]:
		words.append(str(arena.call("stage_word", st)))
	_check(not "" in words, "%s: every stage has a word for the HUD (%s)" % [id, str(words)])
	var run := {}            # id -> ticks of unbroken countdown ending now
	var prev_in := {}
	var was_active := {}
	var acted := {}
	var short := ""
	var late := ""
	for tick in range(STAGED_TICKS + start):
		var fight_tick := tick - start
		if STAGE_AT.has(fight_tick):
			arena.call("set_stage", int(STAGE_AT[fight_tick]))
		if fight_tick == ENDGAME_AT:
			arena.call("set_phase", FightTypes.PHASE_ENDGAME)
		var danger: Array = (arena.call("hazard_helpers") as Dictionary).get("danger_positions", [])
		for e_variant in arena.call("hazard_schedule"):
			var e: Dictionary = e_variant
			var eid := str(e["id"])
			if bool(e["always_on"]):
				acted[eid] = true
				continue
			var active := bool(e["active"])
			var in_s := float(e["in_s"])
			if not active and in_s > float(e["warn_s"]) and _listed(danger, e) \
					and not _always_listed(id, str(e["kind"])):
				late = "%s at fight tick %d (in %.2f s)" % [eid, fight_tick, in_s]
			if active:
				if not bool(was_active.get(eid, false)):
					acted[eid] = true
					# The first activation of the timeline may start from the seeded phase
					# (the unstaged check above covers that); after the bell, every one needs
					# the warning.
					if fight_tick > 0 and int(run.get(eid, 0)) < ArenaBase.WARN_LEAD_TICKS - 2:
						short = "%s acted at fight tick %d after %d ticks of countdown" \
							% [eid, fight_tick, int(run.get(eid, 0))]
				run[eid] = 0
			else:
				var was := float(prev_in.get(eid, ArenaBase.NEVER_S))
				if in_s <= ArenaBase.WARN_LEAD_S + 0.0001 and absf((was - in_s) - TICK) < 0.0001:
					run[eid] = int(run.get(eid, 0)) + 1
				elif in_s <= ArenaBase.WARN_LEAD_S + 0.0001:
					run[eid] = 1        # a jump INTO the warning starts the count again
				else:
					run[eid] = 0
			prev_in[eid] = in_s
			was_active[eid] = active
		arena._physics_process(TICK)
	_check(short == "", "%s: through a staged round every activation had the full warning%s"
		% [id, "" if short == "" else " (" + short + ")"])
	_check(late == "", "%s: through a staged round the AI is never told first%s"
		% [id, "" if late == "" else " (" + late + ")"])
	var missing: Array = []
	for e_variant in arena.call("hazard_schedule"):
		var eid := str((e_variant as Dictionary)["id"])
		if not bool(acted.get(eid, false)):
			missing.append(eid)
	_check(missing.is_empty(), "%s: every hazard, sleeping ones too, is live by the bell%s"
		% [id, "" if missing.is_empty() else " (never: " + str(missing) + ")"])
	_check(int(arena.call("stage")) == 4, "%s: the arena latched the final stage" % id)
	_free(arena)


## Jets, rams and grinders sit on the AI's danger list at every tick with no clock at
## all, so for them the always-visible idle outline is the matching warning.
func _always_listed(id: String, kind: String) -> bool:
	return kind in ["flame", "ram", "grinder"] and id in ["furnace", "crush", "coliseum", "grinder"]


func _listed(danger: Array, e: Dictionary) -> bool:
	var pos: Vector3 = e["position"]
	var size: Vector2 = e["size"]
	var reach := maxf(size.x, size.y) * 0.5 + 0.1
	for d in danger:
		var p := d as Vector3
		if Vector2(p.x - pos.x, p.z - pos.z).length() <= reach:
			return true
	return false


func _same(a: Node, b: Node) -> bool:
	var ha: Dictionary = a.call("hazard_helpers")
	var hb: Dictionary = b.call("hazard_helpers")
	return var_to_bytes(ha) == var_to_bytes(hb) \
		and bool(a.call("spikes_risen")) == bool(b.call("spikes_risen"))


func _make(id: String) -> Node3D:
	var packed := load(str(ARENAS[id])) as PackedScene
	if packed == null:
		return null
	var arena: Node3D = packed.instantiate()
	arena.name = "Arena_" + id
	root.add_child(arena)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	arena.call("setup", rng)
	arena.set_physics_process(false)
	return arena


func _free(arena: Node) -> void:
	root.remove_child(arena)
	arena.queue_free()


func _bodies(node: Node) -> int:
	var n := 1 if node is CollisionObject3D or node is CollisionShape3D else 0
	for child in node.get_children():
		n += _bodies(child)
	return n


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
		print("PASS  hazard warnings: %d checks, 0 failures" % _checks)
		quit(0)
	else:
		print("FAIL  hazard warnings: %d checks, %d failures" % [_checks, _failures])
		quit(1)
