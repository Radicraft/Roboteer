extends SceneTree
## The venue kit's contract (docs/wave-a-contracts.md section 2, docs/wave-a-kit-notes.md).
##   Godot --headless --path Arena --script tests/venue_kit_test.gd
##
## 1. STRUCTURE. The Yard scene carries exactly one VenueKit; built at the high tier it has
##    a crowd, lights within the budget, and NOTHING that can touch physics: no
##    CollisionObject3D (bodies, areas) and no CollisionShape3D anywhere under it.
## 2. TIERS. Medium and low build strictly less: fewer cards, fewer lights, fewer particles.
## 3. DETERMINISM. The Yard fixture fight is run to tick TARGET_TICK three ways, on one
##    Fight node exactly as the shell re-arms it: with the kit at the HIGH tier, WITHOUT the
##    kit (VenueKit.disabled), and with the kit at the LOW tier. Chassis transforms,
##    condition(), scrap, replay rows, damage events and the outcome must be identical, and
##    the three fight hashes printed must be the same string.

const FIGHT_SCENE := "res://fight/fight.tscn"
const YARD_SCENE := "res://arena/yard.tscn"
const FIXTURE := "res://fight/fixtures/stage3_config.json"
const TARGET_TICK := 1800
const FRAME_BUDGET := 12000
const EPSILON := 1.0e-4

var _checks := 0
var _failures := 0
var _fight: Node = null


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	await _structure()
	if not ResourceLoader.exists("res://bot/bot.tscn"):
		print("SKIP  venue kit determinism: no bot scene")
		_finish()
		return
	var config := _fixture()
	_check(str(config.get("arena", "")) == "yard", "the fixture fights in the Yard")
	var script := _scripted_inputs()

	VenueKit.disabled = false
	VenueKit.force_tier = "high"
	var with_kit := await _simulate(config, script)
	var kit_stats: Dictionary = with_kit["kit"]
	_check(int(kit_stats.get("cards", 0)) > 100,
		"the high-tier kit was really built during the fight (%d cards)" % int(kit_stats.get("cards", 0)))

	VenueKit.disabled = true
	var without_kit := await _simulate(config, script)
	_check((without_kit["kit"] as Dictionary).is_empty(), "the run without the kit had no VenueKit in the world")

	VenueKit.disabled = false
	VenueKit.force_tier = "low"
	var low_kit := await _simulate(config, script)
	VenueKit.force_tier = ""

	print("fight hash, kit high:  ", with_kit["hash"])
	print("fight hash, no kit:    ", without_kit["hash"])
	print("fight hash, kit low:   ", low_kit["hash"])
	_compare(with_kit, without_kit, "with the kit against without it")
	_compare(with_kit, low_kit, "high-tier kit against low-tier kit")
	_finish()


# ---------------------------------------------------------------------------------
func _structure() -> void:
	var tiers := {}
	for t in ["high", "medium", "low"]:
		VenueKit.force_tier = t
		var yard := (load(YARD_SCENE) as PackedScene).instantiate()
		root.add_child(yard)
		await process_frame
		await process_frame
		var kits := yard.find_children("*", "VenueKit", true, false)
		_check(kits.size() == 1, "%s: the Yard has exactly one VenueKit (%d)" % [t, kits.size()])
		if kits.is_empty():
			yard.queue_free()
			continue
		var kit := kits[0] as VenueKit
		_check(kit.get_parent() == yard and kit.name == "VenueKit", "%s: it is the direct child named VenueKit" % t)
		var bad := _physics_nodes(kit)
		_check(bad.is_empty(), "%s: nothing under VenueKit can collide (%s)" % [t, ", ".join(bad)])
		var s: Dictionary = kit.stats()
		tiers[t] = s
		print("      %s tier: %s" % [t, JSON.stringify(s)])
		_check(int(s["lights"]) <= int(VenueKit.LIGHT_BUDGET[t]),
			"%s: real lights within the budget (%d of %d)" % [t, int(s["lights"]), int(VenueKit.LIGHT_BUDGET[t])])
		for light in kit.find_children("*", "Light3D", true, false):
			_check(not (light as Light3D).shadow_enabled, "%s: kit light %s casts no shadow" % [t, light.name])
		yard.queue_free()
		await process_frame
	VenueKit.force_tier = ""
	if tiers.size() == 3:
		var h: Dictionary = tiers["high"]
		var m: Dictionary = tiers["medium"]
		var l: Dictionary = tiers["low"]
		_check(int(h["cards"]) > int(m["cards"]) and int(m["cards"]) > int(l["cards"]),
			"crowd cards thin out by tier (%d, %d, %d)" % [int(h["cards"]), int(m["cards"]), int(l["cards"])])
		_check(int(h["lights"]) >= int(m["lights"]) and int(m["lights"]) >= int(l["lights"]),
			"real lights drop by tier (%d, %d, %d)" % [int(h["lights"]), int(m["lights"]), int(l["lights"])])
		_check(int(h["particles"]) > int(m["particles"]) and int(m["particles"]) > int(l["particles"]),
			"particle budget drops by tier (%d, %d, %d)" % [int(h["particles"]), int(m["particles"]), int(l["particles"])])
		_check(int(l["specks"]) == 0 and int(l["silhouettes"]) == 0, "low tier has no specks and no silhouettes")


func _physics_nodes(node: Node) -> Array:
	var out: Array = []
	if node is CollisionObject3D or node is CollisionShape3D or node is CollisionPolygon3D \
			or node is PhysicsBody3D or node is Area3D or node is SoftBody3D:
		out.append(str(node.get_path()))
	for c in node.get_children():
		out.append_array(_physics_nodes(c))
	return out


# ---------------------------------------------------------------------------------
func _simulate(config: Dictionary, script: Array) -> Dictionary:
	if _fight == null:
		_fight = (load(FIGHT_SCENE) as PackedScene).instantiate()
		root.add_child(_fight)
		await process_frame
	var fight: Node = _fight
	fight.call("start_fight", config.duplicate(true), script)
	var damage_events := [0]
	for bot in (fight.get("_bots") as Array):
		if bot != null:
			bot.connect("damage_event", func(_info: Dictionary) -> void: damage_events[0] += 1)
	var kit_stats := {}
	var frames := 0
	while frames < FRAME_BUDGET:
		if kit_stats.is_empty() and frames > 3:
			var arena: Node = fight.call("arena")
			if arena != null:
				var kit := arena.get_node_or_null("VenueKit") as VenueKit
				if kit != null and kit.crowd != null:
					kit_stats = kit.stats()
		if int(fight.get("_tick")) >= TARGET_TICK or int(fight.get("state")) == 3:
			break
		await process_frame
		frames += 1
	var snap := {
		"tick": int(fight.get("_tick")),
		"transforms": [Transform3D(), Transform3D()],
		"conditions": [{}, {}],
		"scrap": (fight.get("_scrap") as Array).duplicate(),
		"replay": [],
		"outcome": str(fight.get("_hud_banner")),
		"damage_events": damage_events[0],
		"kit": kit_stats,
	}
	var bots: Array = fight.get("_bots") as Array
	for i in 2:
		var bot: Node = bots[i]
		if bot == null:
			continue
		var chassis := bot.get("chassis") as Node3D
		if chassis != null and chassis.is_inside_tree():
			(snap["transforms"] as Array)[i] = chassis.global_transform
		if bot.has_method("condition"):
			(snap["conditions"] as Array)[i] = (bot.call("condition") as Dictionary).duplicate(true)
	var recorder: Object = fight.get("_recorder")
	if recorder != null:
		snap["replay"] = (recorder.call("to_inputs") as Array).duplicate(true)
	snap["hash"] = _hash(snap)
	return snap


## One string for a fight's end state: every transform to 1e-6 m, the conditions, the
## scrap, the replay rows, the damage count and the outcome, through SHA-256.
func _hash(s: Dictionary) -> String:
	var parts: Array = [str(s["tick"]), str(s["outcome"]), str(s["damage_events"]), str(s["scrap"])]
	for t in s["transforms"]:
		var x: Transform3D = t
		for v in [x.origin, x.basis.x, x.basis.y, x.basis.z]:
			parts.append("%.6f,%.6f,%.6f" % [v.x, v.y, v.z])
	parts.append(JSON.stringify(s["conditions"]))
	parts.append(JSON.stringify(s["replay"]))
	return "|".join(parts).sha256_text()


func _compare(a: Dictionary, b: Dictionary, tag: String) -> void:
	_check(int(a["tick"]) == int(b["tick"]), "%s: same tick (%d, %d)" % [tag, int(a["tick"]), int(b["tick"])])
	for i in 2:
		var ta: Transform3D = (a["transforms"] as Array)[i]
		var tb: Transform3D = (b["transforms"] as Array)[i]
		_check((ta.origin - tb.origin).length() <= EPSILON, "%s: bot %d position identical" % [tag, i])
		_check(JSON.stringify((a["conditions"] as Array)[i]) == JSON.stringify((b["conditions"] as Array)[i]),
			"%s: bot %d condition() identical" % [tag, i])
	_check(a["scrap"] == b["scrap"], "%s: scrap identical" % tag)
	_check(a["replay"] == b["replay"], "%s: replay rows identical" % tag)
	_check(int(a["damage_events"]) == int(b["damage_events"]),
		"%s: damage events identical (%d)" % [tag, int(a["damage_events"])])
	_check(str(a["hash"]) == str(b["hash"]), "%s: fight hash identical" % tag)


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
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	return parsed as Dictionary if parsed is Dictionary else {}


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("PASS  ", label)
	else:
		_failures += 1
		print("FAIL  ", label)


func _finish() -> void:
	print("")
	if _failures == 0:
		print("PASS  venue kit: %d checks, 0 failures" % _checks)
		quit(0)
	else:
		print("FAIL  venue kit: %d checks, %d failures" % [_checks, _failures])
		quit(1)
