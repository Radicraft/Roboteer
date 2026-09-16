extends SceneTree
## The three assembly faults the owner found on his phone on 2026-09-16, each
## turned into a permanent gate.
##   Godot --headless --path Arena --script tests/assembly_bugs_test.gd
##
##   1. "Robot always loses armour when driving off at the start of the match (you
##      see it lying on the floor)." A part that arrives at ZERO condition was
##      destroyed in an earlier fight (the shell carries `damage` between fights
##      and only the workshop's Repair clears it). `Bot._apply_initial_damage`
##      DETACHED it, which spawned it as a free rigid body inside the hull,
##      untinted, and the first tick dropped it on the spawn mark. Section 2.
##   2. Nothing may come off a PRISTINE machine that has not been hit. Section 1
##      drives every chassis, every armour material and both extremes of thickness
##      for three seconds from the spawn and asserts nothing sheds.
##   3. "Building screen customisations are not all showing." Section 3 assembles a
##      build with every builder field set to a non-default value and asserts each
##      one reaches the scene tree: the hull, the wheels, the weapon, BOTH utility
##      parts at different points, five plates whose model and collider track the
##      thickness, a different material per face, and the livery.
##
## Exit code 0 = all PASS.

const BOT_SCENE := "res://bot/bot.tscn"
const YARD_SCENE := "res://arena/yard.tscn"

## The player spawn, and a heading along the south wall. Driving from the spawn
## through the middle crosses the yard's spike patch (1.6 m square on the origin),
## and a check that meant to measure the assembly would be measuring the hazard.
const SPAWN := Vector3(-3.2, 0.25, -3.2)
const FACING := Vector3.RIGHT
## How close to the 5 m wall a run is allowed to get before it stops.
const WALL_STANDOFF := 4.0

var _checks := 0
var _failures := 0
var _detached: Array[String] = []
var _events: Array[Dictionary] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	print("Roboteer assembly bugs test, Godot ", Engine.get_version_info()["string"])
	await process_frame
	if not ResourceLoader.exists(BOT_SCENE):
		print("SKIP  assembly bugs: %s is absent" % BOT_SCENE)
		quit(0)
		return
	await _check_nothing_sheds()
	await _check_carried_damage()
	await _check_every_field_shows()
	_finish()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _config(chassis_id: String, drive_id: String, weapon_id: String,
		armour: Dictionary, utility: Array = []) -> Dictionary:
	var fitted := utility.duplicate()
	if not bool(PartsCatalogue.chassis(chassis_id).get("invertible", false)) \
			and not fitted.has("srimech"):
		fitted.append("srimech")
	return {
		"id": "player-1", "name": "Probe", "controller": "player",
		"chassis": chassis_id, "drive": drive_id, "weapon": weapon_id,
		"utility": fitted, "armour": armour,
	}


func _uniform(material: String, thickness: int) -> Dictionary:
	var out := {}
	for face in BotDamage.ARMOUR_FACES:
		out[face] = {"material": material, "thickness": thickness}
	return out


func _make_world() -> Node3D:
	var viewport := SubViewport.new()
	viewport.name = "Space"
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	var world := Node3D.new()
	world.name = "Fight"
	viewport.add_child(world)
	# The Debris node fight.gd gives the bots, so a detached part has somewhere to
	# be reparented to. Section 2's whole point is that nothing ever arrives here.
	var debris := Node3D.new()
	debris.name = "Debris"
	world.add_child(debris)
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	var yard: Yard = (load(YARD_SCENE) as PackedScene).instantiate()
	yard.name = "Arena"
	world.add_child(yard)
	yard.setup(rng)
	return world


## Exactly fight.gd's own spawn order: the root transform goes to the spawn mark
## BEFORE setup, the machine is assembled, then `place_at` re-anchors every body
## and every joint.
func _spawn(world: Node3D, config: Dictionary) -> Bot:
	var bot: Bot = (load(BOT_SCENE) as PackedScene).instantiate()
	bot.name = "Bot0"
	var look := Transform3D(Basis(), SPAWN).looking_at(SPAWN + FACING, Vector3.UP)
	bot.transform = look
	world.add_child(bot)
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	bot.setup(config, 0, rng)
	bot.place_at(SPAWN, FACING)
	_detached.clear()
	_events.clear()
	bot.part_detached.connect(func(part: String) -> void: _detached.append(part))
	bot.damage_event.connect(func(info: Dictionary) -> void: _events.append(info))
	return bot


func _drop(world: Node3D) -> void:
	var viewport := world.get_parent()
	root.remove_child(viewport)
	viewport.queue_free()
	await physics_frame
	await physics_frame


## The countdown, then three seconds of driving off the mark: the moment the owner
## is describing.
func _countdown_and_drive(bot: Bot, seconds: float) -> void:
	var idle := FightTypes.empty_input()
	for _i in range(int(FightTypes.COUNTDOWN_S * float(FightTypes.TICK_HZ))):
		bot.apply_input(idle)
		await physics_frame
	var drive := {"heading": Vector2(FACING.x, FACING.z), "fire": false,
		"secondary": false}
	for _i in range(int(seconds * float(FightTypes.TICK_HZ))):
		bot.apply_input(drive)
		await physics_frame
		# Stop short of the wall. The fastest build in the catalogue (a Shell on
		# four wheels) covers 8.1 m in the three seconds and arrives at the east
		# wall at speed, and its ring takes a 49 N s contact off it. That is a real
		# hit on a machine that ran out of room, not a part falling off, and this
		# gate is about the assembly.
		var at: Vector3 = bot.chassis.global_position
		if absf(at.x) > WALL_STANDOFF or absf(at.z) > WALL_STANDOFF:
			return


func _all_parts(node: Node) -> Array[BotPart]:
	var out: Array[BotPart] = []
	if node is BotPart:
		out.append(node as BotPart)
	for child in node.get_children():
		out.append_array(_all_parts(child))
	return out


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		out.append_array(_meshes(child))
	return out


## Every damage event recorded, with the impulse that caused it: an event with no
## hit is the whole point of section 1, so the failure has to say what it was.
func _describe_events() -> String:
	var out := PackedStringArray()
	for ev in _events:
		out.append("%s %.3f at tick %d, J %.1f, from %s at %s" % [
			str(ev.get("part", "")), float(ev.get("severity", 0.0)),
			int(ev.get("tick", 0)), float(ev.get("impulse", 0.0)),
			str(ev.get("attacker", "")),
			str((ev.get("position", Vector3.ZERO) as Vector3).snapped(
				Vector3.ONE * 0.01))])
	return ", ".join(out)


func _report(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("%s: %s%s" % ["PASS" if ok else "FAIL", label,
		"" if detail == "" else "  (%s)" % detail])


func _finish() -> void:
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


# ---------------------------------------------------------------------------
# 1. Nothing comes off a machine that has not been hit
# ---------------------------------------------------------------------------
## Every chassis, every armour material, both ends of the thickness range, driven
## off the spawn mark for three seconds. Nothing may detach and no damage event may
## be recorded: a machine that sheds a plate on the way to the fight has a bug, and
## it is the one the owner reported.
func _check_nothing_sheds() -> void:
	var bad := PackedStringArray()
	var builds := 0
	for chassis_variant in PartsCatalogue.ids("chassis"):
		var chassis_id := str(chassis_variant)
		var weapon_id := "full_body_spinner" if chassis_id == "shell" else "flipper"
		for material_variant in PartsCatalogue.armour_materials():
			for thickness in [1, 4]:
				var config := _config(chassis_id, "4wd", weapon_id,
					_uniform(str(material_variant), thickness))
				if not BuildRules.validate(config).is_empty():
					# Over the budget at four units of steel, and that is the
					# builder's business, not this test's: the bot still assembles.
					pass
				var label := "%s/%s/%d" % [chassis_id, material_variant, thickness]
				var world := _make_world()
				var bot := _spawn(world, config)
				await _countdown_and_drive(bot, 3.0)
				builds += 1
				if not _detached.is_empty():
					bad.append("%s shed %s" % [label, str(_detached)])
				if not _events.is_empty():
					bad.append("%s took damage with no hit: %s"
						% [label, _describe_events()])
				await _drop(world)
	_report("no catalogue chassis and armour combination sheds a part driving off "
		+ "the spawn", bad.is_empty(), "%d builds, %s" % [builds, str(bad)])

	# Every drive as well: the wheels are joint-attached bodies too.
	var bad_drive := PackedStringArray()
	for drive_variant in PartsCatalogue.ids("drive"):
		var world := _make_world()
		var bot := _spawn(world, _config("box", str(drive_variant), "axe",
			_uniform("steel", 2)))
		await _countdown_and_drive(bot, 3.0)
		if not _detached.is_empty() or not _events.is_empty():
			bad_drive.append("%s shed %s, %d events" % [drive_variant,
				str(_detached), _events.size()])
		await _drop(world)
	_report("no drive sheds a wheel driving off the spawn", bad_drive.is_empty(),
		str(bad_drive))


# ---------------------------------------------------------------------------
# 2. THE BUG: a machine carrying damage from an earlier fight
# ---------------------------------------------------------------------------
## The report, word for word: "robot always loses armour when driving off at the
## start of the match (you see it lying on the floor)". Deterministic, every fight,
## for as long as the machine carried a destroyed plate in its saved `damage`.
##
## A part at zero condition is RETIRED, not detached: it is out of the physics
## world, invisible, weightless, and never handed to the Debris node. The machine
## fights without it, which is what a destroyed plate means.
func _check_carried_damage() -> void:
	var world := _make_world()
	var config := _config("wedge", "4wd", "flipper", {
		"front": {"material": "steel", "thickness": 3},
		"sides": {"material": "hdpe", "thickness": 2},
		"rear": {"material": "polycarbonate", "thickness": 1},
		"top": {"material": "titanium", "thickness": 2},
	})
	# Exactly the `damage` block the shell sends after a fight that took the top
	# plate and the front left wheel off.
	config["damage"] = {
		"wheels": [0.0, 1.0, 1.0, 1.0], "weapon": 1.0,
		"armour": {"front": 1.0, "sides": 1.0, "rear": 1.0, "top": 0.0},
		"drive": 1.0, "core": 1.0,
	}
	var bot := _spawn(world, config)
	var mass_with_holes := bot.total_mass()
	await _countdown_and_drive(bot, 3.0)

	var loose := PackedStringArray()
	var retired := PackedStringArray()
	for part in _all_parts(world):
		if not part.detached:
			continue
		if part.retired:
			retired.append(str(part.name))
			if part.visible:
				loose.append("%s is still drawn" % part.name)
			if part.collision_layer != 0 or part.collision_mask != 0:
				loose.append("%s is still in the collision world" % part.name)
			continue
		loose.append("%s is lying on the floor %.2f m from the machine"
			% [part.name, part.global_position.distance_to(
				bot.chassis.global_position)])
	var debris := world.get_node_or_null("Debris")
	var in_debris := 0 if debris == null else _all_parts(debris).size()

	_report("a plate destroyed in an earlier fight is not fitted to this one",
		loose.is_empty(), "retired %s, loose %s" % [str(retired), str(loose)])
	_report("and it is never handed to the arena floor as debris", in_debris == 0,
		"%d bodies under Debris" % in_debris)
	_report("the two destroyed parts are the two that are missing",
		retired.size() == 2, str(retired))
	_report("the machine still reads the carried damage it was sent",
		float((bot.condition()["armour"] as Dictionary)["top"]) == 0.0
			and float((bot.condition()["wheels"] as Array)[0]) == 0.0,
		str(bot.condition()))

	# A retired part weighs nothing: the machine is lighter without its top plate.
	var world2 := _make_world()
	var whole := _spawn(world2, _config("wedge", "4wd", "flipper", {
		"front": {"material": "steel", "thickness": 3},
		"sides": {"material": "hdpe", "thickness": 2},
		"rear": {"material": "polycarbonate", "thickness": 1},
		"top": {"material": "titanium", "thickness": 2},
	}))
	_report("and the machine is lighter for the parts it has lost",
		mass_with_holes < whole.total_mass() - 0.5,
		"%.2f kg against %.2f kg" % [mass_with_holes, whole.total_mass()])
	await _drop(world2)
	await _drop(world)


# ---------------------------------------------------------------------------
# 3. Every builder field reaches the machine
# ---------------------------------------------------------------------------
## The builder has six tabs: chassis, drive, weapon, utility, armour (a material
## and a thickness per face) and livery. Every one of them is in the
## `workshop_config` the shell sends, so every one of them has to be visible on the
## machine the shell gets back.
func _check_every_field_shows() -> void:
	var world := _make_world()
	# Every field off its default: a Tall Tank, six wheels, a crusher, two utility
	# parts that are neither the srimech nor anything with its own mounting rule,
	# four different materials, four different thicknesses and a livery that is not
	# the team colour.
	var config := _config("tall_tank", "6wd", "crusher", {
		"front": {"material": "titanium", "thickness": 4},
		"sides": {"material": "hdpe", "thickness": 3},
		"rear": {"material": "polycarbonate", "thickness": 2},
		"top": {"material": "steel", "thickness": 1},
	}, ["spare_battery", "counterweight"])
	config["utility"] = ["spare_battery", "counterweight"]
	config["livery"] = "#d1662b"
	var bot := _spawn(world, config)
	await physics_frame

	# The chassis: its own model, not a fallback loft.
	var hull := bot.chassis_module.model
	_report("the chassis choice puts that hull's model on the machine",
		hull != null and str(hull.name).to_lower().contains("tall_tank"),
		"" if hull == null else str(hull.name))

	# The drive: one body per catalogue wheel, each of them drawn.
	var wheels := 0
	var undrawn := 0
	for part in bot.attached_parts():
		if part.part_kind != "wheel":
			continue
		wheels += 1
		if _meshes(part).is_empty():
			undrawn += 1
	_report("the drive choice puts its own wheels on the machine",
		wheels == int(PartsCatalogue.drive("6wd").get("wheels", 0)) and undrawn == 0,
		"%d wheels, %d undrawn" % [wheels, undrawn])

	# The weapon: a body, drawn, of the weapon that was asked for.
	var weapon_bodies := 0
	var weapon_drawn := 0
	for part in bot.attached_parts():
		if part.part_kind != "weapon":
			continue
		weapon_bodies += 1
		if not _meshes(part).is_empty():
			weapon_drawn += 1
	_report("the weapon choice puts its own body on the machine and draws it",
		weapon_bodies >= 1 and weapon_drawn >= 1 and bot.weapon.kind == "crusher",
		"%d bodies, %d drawn, kind %s" % [weapon_bodies, weapon_drawn,
			bot.weapon.kind])

	# BOTH utility slots. This is the one that was broken: the spare battery and
	# the counterweight both took utility_socket(0) and came out at the same point,
	# one model wholly inside the other, so a player who fitted two parts saw one.
	var utility_nodes := {}
	for node in _named_under(bot.chassis, ["spare_battery", "counterweight"]):
		utility_nodes[_which(str(node.name), ["spare_battery", "counterweight"])] = node
	var apart := 0.0
	if utility_nodes.size() == 2:
		var keys := utility_nodes.keys()
		apart = (utility_nodes[keys[0]] as Node3D).global_position.distance_to(
			(utility_nodes[keys[1]] as Node3D).global_position)
	_report("both utility slots put a part on the machine, in different places",
		utility_nodes.size() == 2 and apart > 0.05,
		"%d fitted, %.3f m apart" % [utility_nodes.size(), apart])

	# Five plates, each drawn.
	var panels := {}
	for part in bot.attached_parts():
		if part.part_kind == "armour":
			panels[str(part.name)] = part
	var plate_undrawn := PackedStringArray()
	for key in panels.keys():
		if _meshes(panels[key]).is_empty():
			plate_undrawn.append(str(key))
	_report("every armour face is a plate on the machine and every plate is drawn",
		panels.size() == 5 and plate_undrawn.is_empty(),
		"%d plates, undrawn %s" % [panels.size(), str(plate_undrawn)])
	await _drop(world)

	await _check_thickness_shows()
	await _check_material_shows()
	await _check_livery_shows()


## A thickness change has to reach the model AND the collider. Plates grow inward,
## so the silhouette does not move (docs/stage4-assembly-notes.md section 11), but
## the plate itself is four times as thick and that is what the player is buying.
func _check_thickness_shows() -> void:
	var thin := await _plate_sizes(1)
	var thick := await _plate_sizes(4)
	var bad := PackedStringArray()
	for key in thin.keys():
		var a: Array = thin[key]
		var b: Array = thick[key]
		if float(b[0]) <= float(a[0]) * 1.5:
			bad.append("%s model %.3f -> %.3f" % [key, a[0], b[0]])
		if float(b[1]) <= float(a[1]) * 1.5:
			bad.append("%s collider %.4f -> %.4f" % [key, a[1], b[1]])
	_report("an armour thickness change shows on the plate model and its collider",
		bad.is_empty() and thin.size() == 5, str(bad))


## Returns "PanelFront" -> [model x scale, collider x size] for a uniform build.
func _plate_sizes(thickness: int) -> Dictionary:
	var world := _make_world()
	var bot := _spawn(world, _config("box", "4wd", "flipper",
		_uniform("steel", thickness)))
	await physics_frame
	var out := {}
	for part in bot.attached_parts():
		if part.part_kind != "armour":
			continue
		var model_scale := 0.0
		var collider := 0.0
		for child in part.get_children():
			var shape := child as CollisionShape3D
			if shape != null:
				if shape.shape is BoxShape3D:
					collider = (shape.shape as BoxShape3D).size.x
				continue
			var node := child as Node3D
			# The FIRST model child is the plate. The top plate also carries the
			# srimech (it leaves with the plate, Stage 3's rule), and reading that
			# one instead would report a scale that never moves.
			if node != null and model_scale == 0.0:
				model_scale = node.scale.x
		out[str(part.name)] = [model_scale, collider]
	await _drop(world)
	return out


## Two machines that differ ONLY in a face's material have to look different on
## that face. Asserting the material by name would tie this test to the art
## layer's own naming, so it asserts the difference instead.
func _check_material_shows() -> void:
	var steel := await _face_materials("steel")
	var hdpe := await _face_materials("hdpe")
	var titanium := await _face_materials("titanium")
	var same := PackedStringArray()
	for key in steel.keys():
		if str(steel[key]) == str(hdpe[key]):
			same.append("%s steel and hdpe both %s" % [key, steel[key]])
		if str(steel[key]) == str(titanium[key]):
			same.append("%s steel and titanium both %s" % [key, steel[key]])
	_report("an armour material change shows on every face", same.is_empty()
		and steel.size() == 5, "steel %s" % str(steel))


## "PanelFront" -> a signature of the materials bound to that plate's surfaces.
func _face_materials(material: String) -> Dictionary:
	var world := _make_world()
	var bot := _spawn(world, _config("box", "4wd", "flipper",
		_uniform(material, 2)))
	await physics_frame
	var out := {}
	for part in bot.attached_parts():
		if part.part_kind != "armour":
			continue
		out[str(part.name)] = _material_signature(part)
	await _drop(world)
	return out


func _material_signature(node: Node) -> String:
	var names := PackedStringArray()
	for mesh_instance in _meshes(node):
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		for i in range(mesh.get_surface_count()):
			var bound := mesh_instance.get_surface_override_material(i)
			if bound == null:
				bound = mesh_instance.material_override
			if bound == null:
				continue
			var tag := str(bound.resource_name)
			if bound is StandardMaterial3D:
				tag += "#" + (bound as StandardMaterial3D).albedo_color.to_html(false)
			names.append(tag)
	names.sort()
	return ",".join(names)


## The livery has to reach the machine, and it has to reach it everywhere the
## painted metal slot is used, not just the hull.
func _check_livery_shows() -> void:
	var a := await _livery_signature("#2f6fd1")
	var b := await _livery_signature("#94291f")
	_report("the livery colour reaches the machine and changes with the build",
		a != "" and a != b, "%s vs %s" % [a.substr(0, 60), b.substr(0, 60)])


func _livery_signature(hex: String) -> String:
	var world := _make_world()
	var config := _config("wedge", "4wd", "flipper", _uniform("steel", 2))
	config["livery"] = hex
	var bot := _spawn(world, config)
	await physics_frame
	var out := _material_signature(bot.chassis)
	await _drop(world)
	return out


## Every Node3D under `node` whose name mentions one of `ids`.
func _named_under(node: Node, ids: Array) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for child in node.get_children():
		var as3d := child as Node3D
		if as3d != null and _which(str(child.name), ids) != "":
			out.append(as3d)
		out.append_array(_named_under(child, ids))
	return out


func _which(name: String, ids: Array) -> String:
	var lower := name.to_lower()
	for id_variant in ids:
		if lower.contains(str(id_variant)):
			return str(id_variant)
	return ""
