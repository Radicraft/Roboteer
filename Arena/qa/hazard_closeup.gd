extends Node3D
## QA only (wave A hazards, docs/wave-a-hazards-notes.md): close-ups of every hazard's
## render mesh, spikes forced up and rams forced out, saved as PNGs. Not shipped.
##   Godot --path Arena res://qa/hazard_closeup.tscn -- --roboteer-closeup=DIR
## Then a second pass at the FIGHT camera's distance (7 m, yaw -135, pitch 50, 28 deg):
## each arena's clock is wound by hand to 0.5 s before its first timed hazard acts, the
## shared warning layer is left to animate on that frozen clock, and the frame is saved
## (warn_<id>.png); then wound on into the hit (hit_<id>.png).

const SHOTS := [
	["yard", Vector3(0.0, 0.0, 0.0), 3.2],
	["grinder", Vector3(-3.3, 0.0, 1.1), 2.2],
	["furnace", Vector3(-1.2, 0.3, 4.6), 2.2],
	["crush", Vector3(3.6, 0.3, 1.2), 4.0],
	["drop_zone", Vector3(0.0, 0.0, 0.0), 4.5],
	["coliseum", Vector3(-2.9, 0.0, 2.9), 5.0],
]

var _dir := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--roboteer-closeup="):
			_dir = a.substr(19)
	if _dir == "":
		_dir = OS.get_user_data_dir() + "/closeup"
	DirAccess.make_dir_recursive_absolute(_dir)
	_run()


func _run() -> void:
	var paths := {"yard": "res://arena/yard.tscn", "grinder": "res://arena/grinder.tscn",
		"furnace": "res://arena/furnace.tscn", "crush": "res://arena/crush.tscn",
		"drop_zone": "res://arena/drop_zone.tscn", "coliseum": "res://arena/coliseum.tscn"}
	for shot in SHOTS:
		var id: String = shot[0]
		var arena: Node3D = (load(paths[id]) as PackedScene).instantiate()
		add_child(arena)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		arena.call("setup", rng)
		arena.set_physics_process(false)
		if arena.has_method("_set_spikes"):
			arena.call("_set_spikes", 1.0)
		if id == "crush":
			for ram in arena.get("_rams"):
				arena.call("_set_ram", ram, 0.7)
		if id == "drop_zone":
			arena.call("_set_cover", 0.6)
		if id == "furnace":
			for jet in arena.get("_jets_north"):
				arena.call("_tick_flame_jet", jet, true)
			# The south wall faces the camera: leave it cold so the nozzle hardware shows.
		var cam := Camera3D.new()
		cam.fov = 28.0
		add_child(cam)
		var target: Vector3 = shot[1]
		var d: float = shot[2]
		var yaw := deg_to_rad(-135.0)
		var pitch := deg_to_rad(50.0)
		var back := Vector3(sin(yaw), 0.0, cos(yaw)) * -1.0
		cam.position = target + Vector3(-cos(pitch) * d * 0.7071, sin(pitch) * d, -cos(pitch) * d * 0.7071)
		cam.look_at(target, Vector3.UP)
		cam.current = true
		for _i in range(20):
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/closeup_%s.png" % [_dir, id])
		print("closeup: saved ", id)
		cam.queue_free()
		arena.queue_free()
		await get_tree().process_frame
	for shot in SHOTS:
		await _warn_pass(str(shot[0]), paths[str(shot[0])])
	get_tree().quit()


func _warn_pass(id: String, path: String) -> void:
	var arena: Node3D = (load(path) as PackedScene).instantiate()
	add_child(arena)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	arena.call("setup", rng)
	arena.set_physics_process(false)
	var target := Vector3.ZERO
	var found := ""
	for _t in range(90 * 60):
		for e_variant in arena.call("hazard_schedule"):
			var e: Dictionary = e_variant
			if bool(e["always_on"]) or bool(e["active"]):
				continue
			if float(e["in_s"]) <= 0.5:
				found = str(e["id"])
				target = e["position"]
				break
		if found != "":
			break
		arena._physics_process(1.0 / 60.0)
	if found == "":
		# Always-on only (the Grinder): stand a dummy "machine" next to a disc instead.
		found = "grinder_0"
		var sched: Array = arena.call("hazard_schedule")
		target = (sched[0] as Dictionary)["position"]
	var cam := Camera3D.new()
	cam.fov = 28.0
	add_child(cam)
	var d := 7.0
	var pitch := deg_to_rad(50.0)
	cam.position = target + Vector3(-cos(pitch) * d * 0.7071, sin(pitch) * d, -cos(pitch) * d * 0.7071)
	cam.look_at(target, Vector3.UP)
	cam.current = true
	for _i in range(14):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/warn_%s_%s.png" % [_dir, id, found])
	for _t in range(40):
		arena._physics_process(1.0 / 60.0)
		var hit := false
		for e_variant in arena.call("hazard_schedule"):
			if str((e_variant as Dictionary)["id"]) == found and bool((e_variant as Dictionary)["active"]):
				hit = true
		if hit:
			break
	for _i in range(12):
		arena._physics_process(1.0 / 60.0)
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/hit_%s_%s.png" % [_dir, id, found])
	print("closeup: warn and hit ", id, " ", found)
	cam.queue_free()
	arena.queue_free()
	await get_tree().process_frame
