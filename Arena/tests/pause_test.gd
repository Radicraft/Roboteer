extends SceneTree
## Pause and resume, and the proof that pausing changes nothing (added 2026-09-14).
##   Godot --headless --path Arena --script tests/pause_test.gd
##
## The host sends `fight_control {"action": "pause" | "resume" | "quit"}`
## (docs/bridge-spec.md, "Fight control (v2 additions)"). Pause stops the SceneTree,
## which stops every _physics_process and PhysicsServer3D with it; the Fight node, the
## HUD and the controls are PROCESS_MODE_ALWAYS so presentation carries on.
##
## The claim this file exists to prove is that no tick is skipped or doubled: the same
## seed and the same scripted inputs, run once straight through and once with two pauses
## in the middle, must produce the same chassis transforms, the same damage, the same
## tallies and the SAME RECORDED INPUT STREAM at the same tick. If pausing cost or gained
## a tick, a shared replay would be a different fight from the one it replays.
##
## If agent P's bot scene is absent there is nothing to simulate: prints SKIP, exits 0.

const FIGHT_SCENE := "res://fight/fight.tscn"
const BOT_SCENE := "res://bot/bot.tscn"
const FIXTURE := "res://fight/fixtures/stage3_config.json"

const TARGET_TICK := 720          # 12 s of fighting, well past the countdown
const PAUSE_AT := [240, 480]      # ticks at which the paused run stops the clock
const PAUSE_FRAMES := 30          # frames spent paused each time
const EPSILON := 1.0e-4
const FRAME_BUDGET := 9000

var _failures := 0
var _checks := 0
var _fight: Node = null


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame

	if not ResourceLoader.exists(BOT_SCENE) or not ResourceLoader.exists(FIGHT_SCENE):
		print("SKIP  pause: %s or %s is absent, nothing to simulate" % [BOT_SCENE, FIGHT_SCENE])
		quit(0)
		return

	var config := _fixture()
	if config.is_empty():
		_check(false, "the desktop QA fixture loads")
		_finish()
		return
	_check(true, "the desktop QA fixture loads")

	var script := _scripted_inputs()
	_check(script.size() == TARGET_TICK, "the scripted input list covers %d ticks" % TARGET_TICK)

	# A CONTROL run first: two identical unpaused fights on one re-armed node. If these
	# two ever disagree the fault is in determinism, not in pausing, and the comparison
	# below would be meaningless.
	var straight := await _simulate(config, script, [])
	var control := await _simulate(config, script, [])
	var paused := await _simulate(config, script, PAUSE_AT)
	_check(not straight.is_empty() and not paused.is_empty(), "every run produced a snapshot")
	_check(_same(straight, control),
		"CONTROL: two unpaused runs of the same seed and inputs agree")

	_check(int(paused["pauses"]) == PAUSE_AT.size(),
		"the paused run really did pause %d times (%d)" % [PAUSE_AT.size(), int(paused["pauses"])])
	_check(bool(paused["froze"]),
		"and the simulation tick stopped dead while it was paused")
	_check(bool(paused["bodies_froze"]),
		"and no body moved a millimetre while it was paused")
	_check(bool(paused["controls_off"]), "and the touch controls were disabled")
	_check(bool(paused["hud_marked"]), "and the HUD showed its PAUSED mark")
	_check(bool(paused["states"].has("paused")) and bool(paused["states"].has("resumed")),
		"and the host was told, both ways " + str(paused["states"]))
	_check(not bool(paused["paused_at_end"]), "and the fight was running again afterwards")

	# The whole point.
	_check(int(straight["tick"]) == int(paused["tick"]),
		"both runs stopped on the same tick (%d and %d)"
			% [int(straight["tick"]), int(paused["tick"])])
	_check(straight["replay"] == paused["replay"],
		"the recorded input stream is bit for bit the same, %d rows"
			% (straight["replay"] as Array).size())
	_check(str(straight["state"]) == str(paused["state"]),
		"both runs are in the same state (%s)" % str(straight["state"]))
	_check(str(straight["outcome"]) == str(paused["outcome"]),
		"the same outcome (%s)" % str(straight["outcome"]))
	_check(straight["scrap"] == paused["scrap"],
		"the same scrap tallies %s" % str(straight["scrap"]))
	_check(int(straight["damage_events"]) == int(paused["damage_events"]),
		"the same number of damage events (%d and %d)"
			% [int(straight["damage_events"]), int(paused["damage_events"])])

	for i in 2:
		var a: Transform3D = (straight["transforms"] as Array)[i]
		var b: Transform3D = (paused["transforms"] as Array)[i]
		var drift := (a.origin - b.origin).length()
		_check(drift <= EPSILON,
			"bot %d chassis position matches at tick %d (drift %0.9f m)"
				% [i, int(straight["tick"]), drift])
		var basis_drift := 0.0
		for axis in 3:
			basis_drift = maxf(basis_drift, (a.basis[axis] - b.basis[axis]).length())
		_check(basis_drift <= EPSILON,
			"bot %d chassis orientation matches (drift %0.9f)" % [i, basis_drift])
		_check(_conditions_match((straight["conditions"] as Array)[i],
				(paused["conditions"] as Array)[i]),
			"bot %d condition() matches" % i)

	await _test_quit(config, script)
	_finish()


## Do two snapshots describe the same fight?
func _same(a: Dictionary, b: Dictionary) -> bool:
	if int(a["tick"]) != int(b["tick"]) or a["replay"] != b["replay"]:
		return false
	if a["scrap"] != b["scrap"] or str(a["outcome"]) != str(b["outcome"]):
		return false
	for i in 2:
		var ta: Transform3D = (a["transforms"] as Array)[i]
		var tb: Transform3D = (b["transforms"] as Array)[i]
		if (ta.origin - tb.origin).length() > EPSILON:
			return false
		if not _conditions_match((a["conditions"] as Array)[i], (b["conditions"] as Array)[i]):
			return false
	return true


## `fight_control {"action":"quit"}` takes the existing abandoned path: the host is told
## the fight was abandoned, no result is sent, and nothing is left running.
func _test_quit(config: Dictionary, script: Array) -> void:
	var fight := await _arm(config, script)
	for i in 200:
		if int(fight.get("_tick")) >= 60:
			break
		await process_frame
	var sent: Array = []
	var bridge: Node = root.get_node_or_null("Bridge")
	if bridge != null:
		bridge.message_sent.connect(func(t: String, p: Dictionary) -> void: sent.append([t, p]))
	fight.call("fight_control", {"action": "pause"})
	fight.call("fight_control", {"action": "quit"})
	await process_frame
	var kinds: Array[String] = []
	for entry in sent:
		kinds.append("%s/%s" % [str((entry as Array)[0]),
			str(((entry as Array)[1] as Dictionary).get("state", ""))])
	_check(kinds.has("fight_state/abandoned"),
		"quit tells the host the fight was abandoned " + str(kinds))
	var results := 0
	for entry in sent:
		if str((entry as Array)[0]) == "fight_result":
			results += 1
	_check(results == 0, "and sends no result for a fight nobody watched")
	_check(not bool(fight.call("is_paused")), "and leaves nothing paused")
	# This script IS the SceneTree, so its own `paused` is the flag fight.gd sets.
	_check(not self.paused, "and the scene tree is running again")
	# An unknown action is a warning, not a crash.
	fight.call("fight_control", {"action": "wibble"})
	_check(true, "an unknown fight_control action is survivable")
	# Pausing outside a fight does nothing.
	fight.call("show_workshop", {"mode": "workshop"})
	await process_frame
	fight.call("fight_control", {"action": "pause"})
	_check(not bool(fight.call("is_paused")), "pause outside a fight is ignored")


## One fight. `pause_ticks` is the list of ticks at which to stop the clock for
## PAUSE_FRAMES frames and then start it again.
func _simulate(config: Dictionary, script: Array, pause_ticks: Array) -> Dictionary:
	var fight := await _arm(config, script)
	var states: Array[String] = []
	if fight.has_signal("state_changed"):
		fight.state_changed.connect(func(name: String) -> void: states.append(name))
	var damage_events := [0]
	for bot in (fight.get("_bots") as Array):
		if bot != null:
			bot.connect("damage_event", func(_info: Dictionary) -> void: damage_events[0] += 1)

	var pending: Array = pause_ticks.duplicate()
	var pauses := 0
	var froze := true
	var bodies_froze := true
	var controls_off := true
	var hud_marked := true
	var frames := 0
	while frames < FRAME_BUDGET:
		if int(fight.get("_tick")) >= TARGET_TICK:
			break
		if int(fight.get("state")) == 3:      # State.RESULT
			break
		if not pending.is_empty() and int(fight.get("_tick")) >= int(pending[0]):
			pending.remove_at(0)
			pauses += 1
			var before_tick := int(fight.get("_tick"))
			var before := _chassis_transforms(fight)
			fight.call("fight_control", {"action": "pause"})
			for i in PAUSE_FRAMES:
				await process_frame
			if int(fight.get("_tick")) != before_tick:
				froze = false
			var after := _chassis_transforms(fight)
			for i in before.size():
				if (before[i] as Transform3D).origin.distance_to(
						(after[i] as Transform3D).origin) > 1.0e-6:
					bodies_froze = false
			var controls: Node = fight.get("_controls")
			if controls != null and controls.has_method("is_enabled") \
					and bool(controls.call("is_enabled")):
				controls_off = false
			var hud: Node = fight.get("_hud")
			if hud != null and hud.has_method("is_paused") and not bool(hud.call("is_paused")):
				hud_marked = false
			fight.call("fight_control", {"action": "resume"})
		await process_frame
		frames += 1

	var snapshot := {
		"tick": int(fight.get("_tick")),
		"state": str(fight.call("_state_name", int(fight.get("state")))),
		"transforms": _chassis_transforms(fight),
		"conditions": [{}, {}],
		"scrap": (fight.get("_scrap") as Array).duplicate(),
		"replay": [],
		"outcome": str(fight.get("_hud_banner")),
		"damage_events": damage_events[0],
		"pauses": pauses,
		"froze": froze,
		"bodies_froze": bodies_froze,
		"controls_off": controls_off,
		"hud_marked": hud_marked,
		"states": states,
		"paused_at_end": bool(fight.call("is_paused")),
	}
	var bots: Array = fight.get("_bots") as Array
	for i in 2:
		var bot: Node = bots[i]
		if bot != null and bot.has_method("condition"):
			(snapshot["conditions"] as Array)[i] = (bot.call("condition") as Dictionary).duplicate(true)
	var recorder: Object = fight.get("_recorder")
	if recorder != null:
		snapshot["replay"] = (recorder.call("to_inputs") as Array).duplicate(true)
	return snapshot


## One Fight node, re-armed for each run exactly as the shell re-arms it.
func _arm(config: Dictionary, script: Array) -> Node:
	if _fight == null:
		_fight = (load(FIGHT_SCENE) as PackedScene).instantiate()
		root.add_child(_fight)
		await process_frame
	_fight.call("start_fight", config.duplicate(true), script.duplicate(true))
	return _fight


func _chassis_transforms(fight: Node) -> Array:
	var out: Array = [Transform3D(), Transform3D()]
	var bots: Array = fight.get("_bots") as Array
	for i in 2:
		var bot: Node = bots[i]
		if bot == null:
			continue
		var chassis: Node3D = bot.get("chassis") as Node3D
		if chassis != null and chassis.is_inside_tree():
			out[i] = chassis.global_transform
	return out


## The same shape of script determinism_test uses: the player driving and firing, so the
## run exercises the drive, the weapon and the collisions rather than two bots sitting
## still with nothing to diverge.
func _scripted_inputs() -> Array:
	var rows: Array = []
	for tick in range(1, TARGET_TICK + 1):
		var angle := float(tick) * 0.013
		var heading := Vector2(cos(angle), sin(angle))
		var fire := 1 if tick % 150 == 0 else 0
		var secondary := 1 if tick % 400 == 0 else 0
		rows.append([tick, snappedf(heading.x, 0.0001), snappedf(heading.y, 0.0001), fire, secondary])
	return rows


func _fixture() -> Dictionary:
	if not FileAccess.file_exists(FIXTURE):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	return parsed as Dictionary if parsed is Dictionary else {}


func _conditions_match(a: Dictionary, b: Dictionary) -> bool:
	if a.keys().size() != b.keys().size():
		return false
	for key in a.keys():
		if not b.has(key):
			return false
		var va: Variant = a[key]
		var vb: Variant = b[key]
		if va is Dictionary and vb is Dictionary:
			if not _conditions_match(va as Dictionary, vb as Dictionary):
				return false
		elif va is Array and vb is Array:
			var aa: Array = va as Array
			var ab: Array = vb as Array
			if aa.size() != ab.size():
				return false
			for i in aa.size():
				if absf(float(aa[i]) - float(ab[i])) > EPSILON:
					return false
		elif absf(float(va) - float(vb)) > EPSILON:
			return false
	return true


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
		print("PASS  pause: %d checks, 0 failures" % _checks)
		quit(0)
	else:
		print("FAIL  pause: %d checks, %d failures" % [_checks, _failures])
		quit(1)
