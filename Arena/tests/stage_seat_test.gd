extends SceneTree
## Owner bug 2026-09-24: "on the screens where a robot model is on the floor, the wheels
## always go through the floor". For EVERY drive in the catalogue, the machine on the stage
## must stand with its lowest ground contact point (wheels, belts, feet, skirt) within 2 mm
## of the surface under it: the raised turntable, the retracted (face-off) turntable, and
## the opponent's slot on the arena floor.
##   Godot --headless --path Arena --script tests/stage_seat_test.gd
##
## Measured from the assembled RENDER meshes, the same way the stage seats them, so a
## models pass that changes a wheel's radius or tread is covered without editing this file.

const TOLERANCE_M := 0.002

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var stage := WorkshopStage.new()
	stage.force_quality_tier("low")
	root.add_child(stage)
	await process_frame
	var catalogue: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/parts.json"))
	var drives: Array = []
	var drive_table: Variant = catalogue.get("drive", {})
	if drive_table is Dictionary:
		for id in (drive_table as Dictionary).keys():
			drives.append(str(id))
	elif drive_table is Array:
		for entry in drive_table:
			drives.append(str((entry as Dictionary).get("id", "")))
	_check(drives.size() >= 8, "the catalogue lists every drive (%d)" % drives.size())
	for drive in drives:
		var config := {"id": "seat-" + drive, "name": "Seat", "chassis": "box", "drive": drive,
			"weapon": "ram", "utility": [], "livery": "#E8641E",
			"armour": {"front": {"material": "steel", "thickness": 2},
				"sides": {"material": "steel", "thickness": 2},
				"rear": {"material": "steel", "thickness": 2},
				"top": {"material": "steel", "thickness": 2}}}
		# Raised turntable (showroom, garage, builder).
		stage.set_platform(true)
		stage.call("_animate_platform", 0.0)
		stage.show_bot(config)
		var hero := stage.bot()
		_check(hero != null, "%s: the machine builds" % drive)
		if hero == null:
			continue
		var contacts := stage.ground_contact_meshes(hero)
		_check(not contacts.is_empty(), "%s: the machine has ground contact meshes (%d)" % [drive, contacts.size()])
		var raised := stage.ground_contact_height(hero, stage.turntable())
		_check(absf(raised) <= TOLERANCE_M,
			"%s: on the raised turntable the lowest contact is %.1f mm from its top" % [drive, raised * 1000.0])
		# The same contact measured vertex by vertex rather than by boxes: a box round a
		# spun wheel is lower than its tyre, which would leave the machine floating.
		var vertex_low := INF
		var tinv := stage.turntable().global_transform.affine_inverse()
		for mesh in contacts:
			vertex_low = minf(vertex_low, _vertex_lowest(mesh, tinv))
		_check(absf(vertex_low) <= TOLERANCE_M,
			"%s: vertex exact, the tyres/belts/feet touch the turntable (%.1f mm)" % [drive, vertex_low * 1000.0])
		# Independent of the seating rule: nothing else on the machine (a wedge lip, a
		# skirt, a scoop) may be buried either. 3 mm allows a tyre's tread to kiss.
		var any_lowest := INF
		var inv := stage.turntable().global_transform.affine_inverse()
		for mesh in stage.call("_meshes_under", hero):
			var mb: AABB = inv * (mesh as MeshInstance3D).global_transform * (mesh as MeshInstance3D).get_aabb()
			any_lowest = minf(any_lowest, mb.position.y)
		_check(any_lowest >= -0.003,
			"%s: no other part of the machine is below the platform top (%.1f mm)" % [drive, any_lowest * 1000.0])
		print("INFO  %s: the legacy placement sank the contact %.1f mm" % [drive, float(stage.get_meta("last_seat_lift", 0.0)) * 1000.0])
		var top_world := stage.turntable().global_position.y
		_check(absf(top_world - WorkshopStage.STAGE_HEIGHT) < 0.0005,
			"%s: the raised turntable top is the platform top" % drive)
		# Retracted (face-off): the whole turntable comes down to the floor.
		stage.set_platform(false)
		stage.call("_animate_platform", 0.0)
		var floor_gap := _lowest_world(stage, hero)
		_check(absf(floor_gap) <= TOLERANCE_M,
			"%s: with the platform retracted the lowest contact is %.1f mm from the arena floor" % [drive, floor_gap * 1000.0])
		# The opponent slot stands its machine on the arena floor.
		stage.show_opponent(config)
		var opp := stage.opponent_bot()
		if opp != null:
			var opp_gap := _lowest_world(stage, opp)
			_check(absf(opp_gap) <= TOLERANCE_M,
				"%s: the opponent's lowest contact is %.1f mm from the arena floor" % [drive, opp_gap * 1000.0])
		stage.show_opponent({})
		stage.set_platform(true)
		stage.call("_animate_platform", 0.0)
	_finish()


func _vertex_lowest(mesh: MeshInstance3D, inv: Transform3D) -> float:
	var low := INF
	if mesh.mesh == null:
		return low
	var xf := inv * mesh.global_transform
	for surface in mesh.mesh.get_surface_count():
		var verts: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for v in verts:
			low = minf(low, (xf * v).y)
	return low


func _lowest_world(stage: WorkshopStage, machine: Node3D) -> float:
	var lowest := INF
	for mesh in stage.ground_contact_meshes(machine):
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		lowest = minf(lowest, box.position.y)
	return lowest - stage.global_position.y


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
		print("PASS  stage seat: %d checks, 0 failures" % _checks)
		quit(0)
	else:
		print("FAIL  stage seat: %d checks, %d failures" % [_checks, _failures])
		quit(1)
