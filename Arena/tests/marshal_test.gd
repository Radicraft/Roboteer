extends SceneTree
## The Marshal (wave D, docs/wave-d-marshal-notes.md) is presentation and nothing else.
##   Godot --headless --path Arena --script tests/marshal_test.gd
##
## 1. On its own, fed facts: it counts 3, 2, 1 with its light bar in step with the countdown,
##    flashes green at FIGHT and climbs away, counts a knockout segment by segment (the same
##    number the HUD shows), arms and draws the tow line on the lock-up break and the unstick
##    nudge, sprays at a burning machine, goes red at POWER DOWN, shows a yellow card, and
##    wobbles and recovers when something flies through it. It has no collider, no body and
##    no area anywhere under it, it stays inside the walls, and it is 3-5k triangles.
## 2. In real fights: the desktop fixture fought with the Marshal ON and OFF hashes the same,
##    tick for tick (both chassis transforms, both conditions, the hazards and the scrap on
##    every 30th tick, var_to_bytes, bit exact), in two arenas; and a forced lock-up (the
##    rules' own 3 s break) hashes the same ON and OFF and shows the tow line on the tick.
## 3. The bell and the countdown are in step: the Marshal's bar shows the HUD's number.

const FIGHT_SCENE := "res://fight/fight.tscn"
const BOT_SCENE := "res://bot/bot.tscn"
const FIXTURE := "res://fight/fixtures/stage3_config.json"
const SAMPLE_TICKS := 30
const FRAME_BUDGET := 20000
const DT := 1.0 / 60.0

var _checks := 0
var _failures := 0
var _fight: Node = null
var _ctx: HashingContext = null
var _last := -1


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	await _unit()
	if not ResourceLoader.exists(BOT_SCENE) or not ResourceLoader.exists(FIGHT_SCENE):
		print("SKIP  marshal integration: the fight or bot scene is absent")
		_finish()
		return
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	_fight = (load(FIGHT_SCENE) as PackedScene).instantiate()
	root.add_child(_fight)
	await process_frame

	# --- 2. ON and OFF hash the same
	for arena_id in ["yard", "coliseum"]:
		var on: Dictionary = await _simulate(fixture, arena_id, true, 900)
		var off: Dictionary = await _simulate(fixture, arena_id, false, 900)
		print("INFO  %s: marshal on %s, off %s, %d rows, marshal moved %.2f m, beats %s"
			% [arena_id, on["hash"], off["hash"], int(on["samples"]), float(on["travel"]), str(on["beats"])])
		_check(int(on["samples"]) > 20, "%s: the fight was sampled (%d rows)" % [arena_id, int(on["samples"])])
		_check(bool(on["had_marshal"]) and not bool(off["had_marshal"]),
			"%s: the Marshal was there ON and absent OFF" % arena_id)
		_check(float(on["travel"]) > 1.0, "%s: and it flew (%.2f m)" % [arena_id, float(on["travel"])])
		_check(str(on["hash"]) == str(off["hash"]),
			"%s: Marshal ON hashes the same as OFF, tick for tick (%s)" % [arena_id, str(on["hash"])])
		_check(bool(on["countdown_in_step"]),
			"%s: through the countdown the bar showed the HUD's number every frame (%s)"
				% [arena_id, str(on["countdown_seen"])])

	# --- the lock-up break, shown on its tick, and nothing moved by showing it
	var lock_on: Dictionary = await _simulate(fixture, "yard", true, 600, "lockup")
	var lock_off: Dictionary = await _simulate(fixture, "yard", false, 600, "lockup")
	print("INFO  lock-up: on %s, off %s, breaks %d / %d, tow line drawn %s, events %s"
		% [lock_on["hash"], lock_off["hash"], int(lock_on["breaks"]), int(lock_off["breaks"]),
			str(lock_on["tow_seen"]), str(lock_on["events"])])
	_check(int(lock_on["breaks"]) >= 1 and int(lock_on["breaks"]) == int(lock_off["breaks"]),
		"the forced shoving match was broken by the rules, the same number of times ON and OFF (%d)"
			% int(lock_on["breaks"]))
	_check(bool(lock_on["tow_seen"]), "the Marshal drew the tow line for the break")
	_check((lock_on["events"] as Array).has("lockup_tow"), "and the commentary heard lockup_tow")
	_check(str(lock_on["hash"]) == str(lock_off["hash"]),
		"the lock-up fight hashes the same with the Marshal ON and OFF (%s)" % str(lock_on["hash"]))
	_finish()


# ---------------------------------------------------------------- 1. on its own

func _unit() -> void:
	var m: FightMarshal = FightMarshal.new()
	root.add_child(m)
	await process_frame
	m.configure(5.0)
	var cam := Vector3(0.0, 8.0, 7.0)
	var bots := [{"pos": Vector3(-3.0, 0.2, 3.0), "vel": Vector3.ZERO, "live": true},
		{"pos": Vector3(3.0, 0.2, -3.0), "vel": Vector3.ZERO, "live": true}]

	# no physics anywhere under it
	var physical: Array = []
	_collect_physics(m, physical)
	_check(physical.is_empty(), "the Marshal has no body, collider or area (%d found)" % physical.size())
	var tris := m.triangle_count()
	_check(tris >= 3000 and tris <= 6500,
		"the Marshal is a phone-budget model (%d triangles drawn, 4.7k authored + blur discs)" % tris)
	_check(ResourceLoader.exists(FightMarshal.MODEL), "its model is on disk (%s)" % FightMarshal.MODEL)

	# the countdown: 3 blocks, 2, 1, then FIGHT all green
	var want := {3: 6, 2: 4, 1: 2}
	for n in [3, 2, 1]:
		m.step(DT, {"state": "countdown", "countdown_left": float(n) - 0.3, "camera": cam, "bots": bots})
		_check(m.bar_lit() == int(want[n]) and m.bar_colour() == FightMarshal.COL_START,
			"countdown %d: %d segments lit, amber (%d)" % [n, int(want[n]), m.bar_lit()])
	m.step(DT, {"state": "countdown", "countdown_left": 9.0, "camera": cam, "bots": bots})
	_check(m.bar_lit() == 0, "during the intro it stands by, not counting (%d lit)" % m.bar_lit())
	m.on_fight_start()
	m.step(DT, {"state": "fighting", "camera": cam, "bots": bots})
	_check(m.bar_colour() == FightMarshal.COL_GO and m.mode == FightMarshal.MODE_LIFT,
		"FIGHT: the bar flashes green and it lifts")
	for i in 150:
		m.step(DT, {"state": "fighting", "camera": cam, "bots": bots})
	_check(m.mode == FightMarshal.MODE_PATROL and m.position_now().y > 2.0,
		"then it watches from high up (%s, %.2f m)" % [m.mode, m.position_now().y])

	# the knockout count: one segment per second left, amber then red
	for left in [8, 5, 3]:
		m.step(DT, {"state": "fighting", "camera": cam, "bots": bots,
			"ko": {"index": 1, "show": true, "seconds_left": left}})
		_check(m.mode == FightMarshal.MODE_COUNT and m.bar_lit() == left,
			"knockout count %d: %d segments (%d, %s)" % [left, left, m.bar_lit(), m.mode])
	_check(m.bar_colour() == FightMarshal.COL_COUNT_LOW, "the last three are red")
	for i in 120:
		m.step(DT, {"state": "fighting", "camera": cam, "bots": bots,
			"ko": {"index": 1, "show": true, "seconds_left": 3}})
	var over: Vector3 = (bots[1] as Dictionary)["pos"]
	_check(Vector2(m.position_now().x - over.x, m.position_now().z - over.z).length() < 1.2
			and m.position_now().y > over.y + 0.6,
		"it flew over the machine it is counting (%s, machine %s)" % [str(m.position_now()), str(over)])

	# the lock-up: armed by the rules' own timer, the tow line on the impulse, then gone
	m.step(DT, {"state": "fighting", "camera": cam, "bots": bots,
		"lockup": {"progress": 0.6, "a": bots[0]["pos"], "b": bots[1]["pos"]}})
	_check(m.mode == FightMarshal.MODE_TOW, "a lock-up building: it comes in to tow (%s)" % m.mode)
	m.on_lockup_break(bots[0]["pos"], bots[1]["pos"])
	m.step(DT, {"state": "fighting", "camera": cam, "bots": bots})
	_check(m.tow_line_visible() and m.bar_lit() == FightMarshal.SEGMENTS,
		"the break: tow line drawn, bar full")
	for i in 60:
		m.step(DT, {"state": "fighting", "camera": cam, "bots": bots})
	_check(not m.tow_line_visible(), "and the line is gone half a second later")
	m.on_unstick(bots[0]["pos"])
	m.step(DT, {"state": "fighting", "camera": cam, "bots": bots})
	_check(m.tow_line_visible(), "the unstick nudge draws the line too")

	# fire: over to the burning machine, nozzle on it
	var burning := false
	for i in 240:
		m.step(DT, {"state": "fighting", "camera": cam, "bots": bots,
			"burning": {"index": 0, "pos": bots[0]["pos"]}})
		burning = burning or m.spraying()
	_check(m.mode == FightMarshal.MODE_SPRAY and burning, "a burning machine gets the extinguisher")
	for i in 150:
		m.step(DT, {"state": "fighting", "camera": cam, "bots": bots})
	_check(not m.spraying(), "and it stops when the fire is out")

	# the knock: wobbles, then recovers
	m.knock(Vector3(3.0, 0.5, 0.0))
	m.step(DT, {"state": "fighting", "camera": cam, "bots": bots})
	_check(m.wobbling(), "debris through its space: it wobbles")
	for i in 120:
		m.step(DT, {"state": "fighting", "camera": cam, "bots": bots})
	_check(not m.wobbling() and absf(m.rotation.x) < 0.4 and absf(m.rotation.z) < 0.4,
		"and recovers level (%s)" % str(m.rotation))
	# something fast through its space knocks it by itself
	var at := m.position_now()
	var before := m.beats_said.count("wobble")
	for i in 100:
		m.step(DT, {"state": "fighting", "camera": cam, "bots": bots})
	m.step(DT, {"state": "fighting", "camera": cam, "bots": bots,
		"debris": [{"pos": m.position_now() + Vector3(0.2, 0.0, 0.0), "vel": Vector3(-4.0, 1.0, 0.0)}]})
	_check(m.beats_said.count("wobble") == before + 1, "a flying part through it knocks it on its own")

	# POWER DOWN and the card (after the knock's flicker has settled)
	for i in 60:
		m.step(DT, {"state": "fighting", "camera": cam, "bots": bots})
	m.step(DT, {"state": "result", "camera": cam, "bots": bots})
	_check(m.mode == FightMarshal.MODE_STOP and m.bar_colour() == FightMarshal.COL_STOP
			and m.bar_lit() == FightMarshal.SEGMENTS, "POWER DOWN: all ten red")
	m.show_card(Vector3(1.0, 0.2, 1.0))
	for i in 40:
		m.step(DT, {"state": "result", "camera": cam, "bots": bots})
	_check(m.card_out() and m.bar_colour() == FightMarshal.COL_CARD and m.beats_said.has("card"),
		"a house bot's late hit: the yellow card is out, bar yellow")
	for i in 120:
		m.step(DT, {"state": "result", "camera": cam, "bots": bots})
	_check(not m.card_out() and m.mode == FightMarshal.MODE_STOP, "then back to POWER DOWN")

	# never through a wall, never on the floor
	var worst := 0.0
	var lowest := 99.0
	for i in 400:
		m.step(DT, {"state": "fighting", "camera": cam, "bots": [
			{"pos": Vector3(4.9, 0.2, 4.9), "vel": Vector3.ZERO, "live": true},
			{"pos": Vector3(-4.9, 0.2, -4.9), "vel": Vector3.ZERO, "live": true}],
			"ko": {"index": 0, "show": true, "seconds_left": 5}})
		worst = maxf(worst, maxf(absf(m.position_now().x), absf(m.position_now().z)))
		lowest = minf(lowest, m.position_now().y)
	_check(worst <= 5.0 and lowest >= 0.5,
		"counting a machine in a corner it stays inside the walls and off the floor (%.2f m, %.2f m up)"
			% [worst, lowest])
	_check(m.beats_said.has("fight_start") and m.beats_said.has("count") and m.beats_said.has("tow")
			and m.beats_said.has("spray") and m.beats_said.has("stop"),
		"it said every beat (%s)" % str(m.beats_said))
	m.queue_free()
	await process_frame


static func _collect_physics(node: Node, out: Array) -> void:
	if node is CollisionObject3D or node is CollisionShape3D or node is PhysicsBody3D \
			or node is Area3D or node is Joint3D:
		out.append(node)
	for c in node.get_children():
		_collect_physics(c, out)


# ---------------------------------------------------------------- 2. real fights

func _simulate(fixture: Dictionary, arena_id: String, marshal_on: bool, ticks: int,
		setup: String = "") -> Dictionary:
	var config := fixture.duplicate(true)
	config["arena"] = arena_id
	(config["rules"] as Dictionary)["duration_s"] = 180
	(config["presentation"] as Dictionary)["marshal"] = marshal_on
	var script: Array = []
	if setup == "lockup":
		(config["debug"] as Dictionary)["opponent_ai"] = "charge"
		((config["bots"] as Array)[1] as Dictionary)["weapon"] = "ram"
		for t in range(1, ticks + 1):
			script.append([t, 1.0, 0.0, 0, 0, 0.0, 0])
	_ctx = HashingContext.new()
	_ctx.start(HashingContext.HASH_SHA256)
	_last = -1
	var samples := [0]
	var done := [false]
	var on_step := func() -> void:
		if done[0]:
			return
		var tick := int(_fight.get("_tick"))
		var over := int(_fight.get("state")) == 3
		if tick == _last and not over:
			return
		_last = tick
		if tick % SAMPLE_TICKS != 0 and tick < ticks and not over:
			return
		samples[0] += 1
		var row := [tick, int(_fight.get("state"))]
		for bot in _fight.get("_bots") as Array:
			if bot == null or not is_instance_valid(bot):
				row.append(null)
				continue
			var chassis: Node3D = bot.get("chassis") as Node3D
			row.append(null if over else chassis.global_transform)
			row.append(bot.call("condition"))
		var arena: Node = _fight.get("_arena")
		if arena != null and arena.has_method("hazard_helpers"):
			row.append(arena.call("hazard_helpers"))
		row.append((_fight.get("_scrap") as Array).duplicate())
		_ctx.update(var_to_bytes(row))
		if tick >= ticks or over:
			done[0] = true
	physics_frame.connect(on_step)
	if script.is_empty():
		_fight.call("start_fight", config)
	else:
		_fight.call("start_fight", config, script)
	if setup == "lockup":
		# Nose to nose in the open, before the first fight tick (the countdown holds them).
		var bots: Array = _fight.call("bots")
		_fight.call("set_down", bots[0], Vector3(-2.6, 0.0, 2.4), Vector3(1.0, 0.0, 0.0))
		_fight.call("set_down", bots[1], Vector3(-1.75, 0.0, 2.4), Vector3(-1.0, 0.0, 0.0))
	var had := _fight.call("marshal") != null
	var travel := 0.0
	var prev := Vector3.INF
	var in_step := true
	var seen: Dictionary = {}
	var tow_seen := false
	var frames := 0
	while not done[0] and frames < FRAME_BUDGET:
		await process_frame
		frames += 1
		var m: FightMarshal = _fight.call("marshal")
		if m == null:
			continue
		if prev != Vector3.INF:
			travel += m.position_now().distance_to(prev)
		prev = m.position_now()
		tow_seen = tow_seen or m.tow_line_visible()
		if int(_fight.get("state")) == 1 and m.mode == FightMarshal.MODE_START:
			var left := FightTypes.COUNTDOWN_S - float(_fight.get("_countdown_time"))
			var step := int(ceil(left))
			if step >= 1 and step <= 3 and absf(left - round(left)) > 0.05:
				var lit := m.bar_lit()
				seen[step] = lit
				if lit != int({3: 6, 2: 4, 1: 2}[step]):
					in_step = false
	physics_frame.disconnect(on_step)
	var marshal_now: FightMarshal = _fight.call("marshal")
	return {
		"hash": _ctx.finish().hex_encode().substr(0, 16),
		"samples": samples[0],
		"had_marshal": had,
		"travel": travel,
		"beats": marshal_now.beats_said.duplicate() if marshal_now != null else [],
		"countdown_in_step": in_step and seen.size() == 3,
		"countdown_seen": seen,
		"breaks": int(_fight.get("lockup_breaks")),
		"tow_seen": tow_seen,
		"events": (_fight.get("show_events") as Array).duplicate(),
	}


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
		print("PASS  marshal: %d checks, 0 failures" % _checks)
		quit(0)
	else:
		print("FAIL  marshal: %d checks, %d failures" % [_checks, _failures])
		quit(1)
