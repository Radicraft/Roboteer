extends SceneTree
## Wave C: the blueprint menus in the arena (docs/wave-c-menus-notes.md).
##   Godot --headless --path Arena --script tests/stage_menus_test.gd
##
## Through the shipping path (one Fight node, messages through the Bridge):
##   - `workshop_config.screen` puts the plinth in the Coliseum staging, hides the showroom's
##     room, hands the picture to the venue's environment, and frames each screen;
##   - the machine is on the hero layer and no venue light reaches it (the livery reads true);
##   - the Coliseum instance can never touch physics (no process, no collision layer or mask);
##   - the menu frames the machine as the hero (a big share of the frame, left of centre);
##   - the anchors the leader lines use are on screen and keyed by part;
##   - the pyro fires on arrival and on a win and never loops; the loading screen's build
##     keeps the venue dark;
##   - going dark for a fight releases the venue's environment and stops the kit;
##   - and a fight run after the menus is bit identical to one run before them: the menus are
##     presentation only (same hash as a plain fight, twice).

const FIGHT_SCENE := "res://fight/fight.tscn"
const SLICE := "res://qa/stage_slice_bots.json"
const FIXTURE := "res://fight/fixtures/stage3_config.json"
const DESIGN_SIZE := Vector2i(1206, 556)
const TARGET_TICK := 900
const FRAME_BUDGET := 12000

var _failures := 0
var _checks := 0
var _fight: Node = null


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var host := SubViewport.new()
	host.size = DESIGN_SIZE
	root.add_child(host)
	_fight = (load(FIGHT_SCENE) as PackedScene).instantiate()
	_fight.set("_autostarted", true)
	host.add_child(_fight)
	await _frames(2)
	var bots: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SLICE))
	var hero: Dictionary = bots["hero"]
	var opponent: Dictionary = bots["opponent"]

	# --- a plain fight first (the reference hash), before any menu has been staged
	var config := _fixture()
	# The first fight in a process is thrown away: it has been seen to differ from every
	# later one in a headless run whether or not a menu came between (determinism_test runs
	# three for the same reason). The reference is the second.
	await _simulate(config)
	var plain := await _simulate(config)
	_check(int(plain["tick"]) >= TARGET_TICK, "the plain fight ran to tick %d" % TARGET_TICK)

	# --- legacy: no screen, no staging
	_send({"mode": "menu", "bot": hero})
	await _frames(3)
	var stage: WorkshopStage = _fight.get("_workshop_stage") as WorkshopStage
	_check(stage != null, "the fight has a workshop stage")
	if stage == null:
		_finish()
		return
	_check(not stage.staged(), "no screen: the showroom as it was (no venue)")

	# --- the main menu in the arena
	_send({"mode": "menu", "bot": hero, "screen": "menu", "frame": 0.28})
	await _frames(12)
	_check(stage.staged(), "screen menu: the arena staging is up")
	var venue := stage.menu_venue() as MenuVenue
	_check(venue != null and venue.arena != null, "the Coliseum stands round the plinth")
	for n in WorkshopStage.STAGED_HIDE:
		var node := stage.get_node_or_null(NodePath(n)) as Node3D
		if node != null:
			_check(not node.visible, "the showroom's %s is hidden" % n)
	var stage_env := stage.get_node_or_null("Environment") as WorldEnvironment
	_check(stage_env == null or stage_env.environment == null, "the stage's own environment steps aside")
	_check(venue.world_env != null and venue.world_env.environment != null, "the venue's environment draws")
	_check(venue.arena.process_mode == Node.PROCESS_MODE_DISABLED, "the Coliseum is never processed")
	var bodies := venue.arena.find_children("*", "CollisionObject3D", true, false).size()
	_check(bodies == 0, "the Coliseum carries no collision object at all (%d)" % bodies)
	var meshes := venue.arena.find_children("*", "MeshInstance3D", true, false).size()
	_check(meshes > 20, "but keeps its floor, walls and banners (%d meshes)" % meshes)

	# The livery: the machine on the hero layer only, every venue light leaving it out.
	var machine := stage.bot()
	var off_layer := 0
	for v in machine.find_children("*", "VisualInstance3D", true, false):
		if v is GPUParticles3D or v is Decal:
			continue
		if (v as VisualInstance3D).layers != MenuVenue.HERO_LAYER:
			off_layer += 1
	_check(off_layer == 0, "every mesh of the machine is on the hero layer (%d off)" % off_layer)
	var leaks := 0
	var venue_lights := 0
	for l in venue.find_children("*", "Light3D", true, false):
		venue_lights += 1
		if ((l as Light3D).light_cull_mask & MenuVenue.HERO_LAYER) != 0:
			leaks += 1
	_check(venue_lights > 0 and leaks == 0, "no venue light reaches the machine (%d lights, %d leak)" % [venue_lights, leaks])
	var key := stage.get_node_or_null("KeyLight") as Light3D
	_check(key != null and (key.light_cull_mask & MenuVenue.HERO_LAYER) != 0, "the stage key still lights it")

	# Framing: the machine is the hero, left of centre, clear of the career plate.
	await _seconds(1.0)
	var a := stage.stage_anchors()
	_check(a.get("screen") == "menu" and bool(a.get("settled")), "anchors: menu, settled")
	var box: Array = a.get("hero", [0, 0, 0, 0])
	var share := float(box[2]) - float(box[0])
	_check(share > 0.34, "the menu frames the machine large (%.2f of the width)" % share)
	var cx := (float(box[0]) + float(box[2])) * 0.5
	_check(cx > 0.15 and cx < 0.4 and float(box[2]) < 0.6, "left of centre and clear of the plate (x %.2f to %.2f)" % [float(box[0]), float(box[2])])
	var keys := {}
	var inside := true
	for p in a.get("parts", []):
		keys[str(p["key"])] = true
		var at: Array = p["at"]
		if float(at[0]) < 0.0 or float(at[0]) > 1.0 or float(at[1]) < 0.0 or float(at[1]) > 1.0:
			inside = false
	_check(keys.has("weapon") and keys.has("armour_top"), "anchors carry the weapon and the top armour")
	var wheels := 0
	for k in keys.keys():
		if str(k).begins_with("wheel"):
			wheels += 1
	_check(wheels >= 2, "anchors carry the wheels (%d)" % wheels)
	_check(inside, "every anchor is on screen")
	var pts: Dictionary = a.get("points", {})
	_check(pts.has("weapon") and pts.has("top") and pts.has("centre"), "anchors carry centre, top and weapon points")
	_check(WorkshopStage._anchors_changed({}, a), "a first anchors message always goes")
	_check(not WorkshopStage._anchors_changed(a, a.duplicate(true)), "an unchanged picture sends nothing")

	# The builder: close, moving heads through haze instead of the ring's shafts.
	_send({"mode": "workshop", "bot": hero, "screen": "builder", "focus": "weapon"})
	await _frames(4)
	var close := venue.get_node_or_null("CloseRig") as Node3D
	var ring := venue.get_node_or_null("RingRig") as Node3D
	_check(close != null and close.visible and ring != null and not ring.visible, "builder: the close rig, not the ring")
	_check(stage.director().screen() == "builder", "builder: the director frames the builder")
	# The board: the opponent across the floor, on the hero layer too.
	_send({"mode": "menu", "bot": hero, "screen": "board", "opponent": opponent})
	await _frames(6)
	var opp := stage.opponent_bot()
	_check(opp != null, "board: the opponent stands across the floor")
	var opp_off := 0
	if opp != null:
		for v in opp.find_children("*", "MeshInstance3D", true, false):
			if (v as VisualInstance3D).layers != MenuVenue.HERO_LAYER:
				opp_off += 1
	_check(opp_off == 0, "board: the opponent is on the hero layer too")
	var ba := stage.stage_anchors()
	_check((ba.get("points", {}) as Dictionary).has("opponent"), "board: anchors carry the opponent")
	# The loading screen's build keeps the venue dark.
	stage.set("_build_done", false)
	stage.set("_build_step", -1)
	stage.set_build_step(1, 0.2)
	await _seconds(1.2)
	_check(float(venue.get("_level")) < 0.3, "building: the venue is down with the rig (%.2f)" % float(venue.get("_level")))
	stage.set_build_step(5, 1.0)
	await _seconds(2.5)
	_check(float(venue.get("_level")) > 0.97, "built: the venue is up (%.2f)" % float(venue.get("_level")))

	# Going dark for a fight: the venue lets go of the environment and stops.
	stage.set_active(false)
	_check(venue.world_env.environment == null, "dark: the venue's environment is released")
	_check(venue.kit.process_mode == Node.PROCESS_MODE_DISABLED, "dark: the kit stops")
	_check(not venue.visible, "dark: the venue is hidden")
	stage.set_active(true)
	_check(venue.world_env.environment != null, "lit again: the venue's environment is back")

	# --- presentation only: a fight after all of that is bit identical to the plain one
	var after := await _simulate(config)
	_check(str(after["hash"]) == str(plain["hash"]), "a fight after the menus has the plain fight's hash")
	_send({"mode": "menu", "bot": hero, "screen": "menu"})
	await _frames(10)
	var again := await _simulate(config)
	_check(str(again["hash"]) == str(plain["hash"]), "and again after a second visit (%s)" % str(plain["hash"]).substr(0, 12))

	# --- the pyro, on a stage built at the high tier (a headless run resolves low)
	await _pyro_high(hero)
	# --- tiers: low has no people and no jets
	await _low_tier(hero)
	_finish()


func _pyro_high(hero: Dictionary) -> void:
	VenueKit.force_tier = "high"
	var stage := WorkshopStage.new()
	stage.force_quality_tier("high")
	var holder := SubViewport.new()
	holder.size = DESIGN_SIZE
	holder.own_world_3d = true
	root.add_child(holder)
	holder.add_child(stage)
	stage.show_bot(hero)
	stage.apply_presentation({"bot": hero, "screen": "menu"})
	await _seconds(0.6)
	var venue := stage.menu_venue() as MenuVenue
	_check(venue != null and venue.tier == "high", "high: the arena staging stands")
	if venue == null:
		return
	var jets := venue.jets()
	_check(jets.size() == 2, "two jets stand on the gate's pedestals")
	_check(_fired(jets) == 2, "arriving on the menu fired both jets once (%d)" % _fired(jets))
	_check(jets.all(func(j: MenuPyro) -> bool: return j.last_style() == MenuVenue.JET_ARRIVAL),
		"an arrival fires %s" % MenuVenue.JET_ARRIVAL)
	var shape_ok := true
	for j in jets:
		var jet := j.get_node_or_null("Jet") as GPUParticles3D
		var pm := jet.process_material as ParticleProcessMaterial if jet != null else null
		shape_ok = shape_ok and pm != null and pm.spread <= 3.0 and pm.initial_velocity_min >= 12.0 \
			and pm.particle_flag_align_y and not jet.one_shot
	_check(shape_ok, "each is a jet: a narrow fast streaked column, not a slow soft burst")
	await _seconds(2.5)
	var burning := false
	for j in jets:
		burning = burning or j.burning()
	_check(not burning, "the jets are out again after the burst")
	var before := _fired(jets)
	await _seconds(1.5)
	_check(_fired(jets) == before, "and they never fire on their own")
	stage.apply_presentation({"bot": hero, "screen": "builder", "focus": "weapon"})
	await _frames(4)
	_check(_fired(jets) == before, "builder: no pyro (the launchers are out of frame)")
	stage.apply_presentation({"bot": hero, "screen": "menu"})
	await _frames(4)
	_check(_fired(jets) == before, "back on the menu within %d s: no second burst" % int(MenuVenue.ARRIVAL_COOLDOWN_S))
	stage.apply_presentation({"bot": hero, "screen": "result", "cue": "win"})
	await _frames(4)
	_check(_fired(jets) == before + 2, "result with cue win: both jets fire (%d)" % (_fired(jets) - before))
	_check(jets.all(func(j: MenuPyro) -> bool: return j.last_style() == MenuVenue.JET_WIN),
		"a win fires %s" % MenuVenue.JET_WIN)
	stage.apply_presentation({"bot": hero, "screen": "result", "cue": "win", "frame": 0.5})
	await _frames(4)
	_check(_fired(jets) == before + 2, "a re-send of the result does not fire again")
	VenueKit.force_tier = ""
	holder.queue_free()
	await _frames(2)


func _low_tier(hero: Dictionary) -> void:
	VenueKit.force_tier = "low"
	var stage := WorkshopStage.new()
	stage.force_quality_tier("low")
	var holder := SubViewport.new()
	holder.size = DESIGN_SIZE
	holder.own_world_3d = true
	root.add_child(holder)
	holder.add_child(stage)
	stage.show_bot(hero)
	stage.apply_presentation({"bot": hero, "screen": "menu"})
	await _seconds(0.6)
	var venue := stage.menu_venue() as MenuVenue
	_check(venue != null and stage.staged(), "low: the arena staging still stands")
	if venue != null:
		var crowd := venue.kit.get("crowd") as Node3D if venue.kit != null else null
		_check(crowd == null or not crowd.visible, "low: the crowd is off")
		_check(venue.jets().is_empty(), "low: no jets")
	VenueKit.force_tier = ""
	holder.queue_free()


func _fired(jets: Array) -> int:
	var n := 0
	for j in jets:
		n += (j as MenuPyro).fired_count()
	return n


func _simulate(config: Dictionary) -> Dictionary:
	var steps_before := Engine.max_physics_steps_per_frame
	Engine.max_physics_steps_per_frame = 1
	_fight.call("start_fight", config.duplicate(true), _scripted_inputs())
	var frames := 0
	while frames < FRAME_BUDGET:
		if int(_fight.get("_tick")) >= TARGET_TICK or int(_fight.get("state")) == 3:
			break
		await process_frame
		frames += 1
	Engine.max_physics_steps_per_frame = steps_before
	var parts: Array = [str(_fight.get("_tick")), str(_fight.get("_scrap"))]
	var bots: Array = _fight.get("_bots") as Array
	for i in 2:
		var bot: Node = bots[i]
		if bot == null:
			continue
		var chassis := bot.get("chassis") as Node3D
		if chassis != null and chassis.is_inside_tree():
			var x := chassis.global_transform
			for v in [x.origin, x.basis.x, x.basis.y, x.basis.z]:
				parts.append("%.6f,%.6f,%.6f" % [v.x, v.y, v.z])
		if bot.has_method("condition"):
			parts.append(JSON.stringify(bot.call("condition")))
	var recorder: Object = _fight.get("_recorder")
	if recorder != null:
		parts.append(JSON.stringify(recorder.call("to_inputs")))
	return {"tick": int(_fight.get("_tick")), "hash": "|".join(parts).sha256_text()}


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


func _send(payload: Dictionary) -> void:
	root.get_node("Bridge").call("inject_from_host", {"type": "workshop_config", "json": JSON.stringify(payload)})


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _seconds(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS  ", label)
	else:
		_failures += 1
		print("FAIL  ", label)


func _finish() -> void:
	print("")
	if _failures == 0:
		print("PASS  stage menus: %d checks, 0 failures" % _checks)
		quit(0)
	else:
		print("FAIL  stage menus: %d checks, %d failures" % [_checks, _failures])
		quit(1)
