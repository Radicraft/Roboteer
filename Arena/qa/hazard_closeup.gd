extends Node3D
## QA only (wave A hazards, docs/wave-a-hazards-notes.md): close-ups of every hazard's
## render mesh, spikes forced up and rams forced out, saved as PNGs. Not shipped.
##   Godot --path Arena res://qa/hazard_closeup.tscn -- --roboteer-closeup=DIR

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
	get_tree().quit()
