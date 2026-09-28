extends Node3D
## QA only (wave C hazards, docs/wave-c-hazards-notes.md): every hazard and moving arena
## element, frame by frame through its states (rest, arming, coming out, active, going
## back), from the FIGHT camera (yaw -135, pitch 50, 28 degree lens, 6.2 m) and from a
## close low angle, so "where does it come from" can be judged by eye. Not shipped
## (export_presets excludes qa/*_capture.*).
##
##   Godot --path Arena res://qa/hazard_states_capture.tscn --audio-driver Dummy \
##     -- --roboteer-hs-dir=DIR [--roboteer-hs-only=yard_spikes,crush_ram]
##
## Writes DIR/<job>__<state>__<cam>.png. The arena's clock is wound by hand
## (_physics_process called tick by tick, physics processing off), exactly as
## hazard_closeup.gd does, so every state is the real timeline, and the shared warning
## layer animates on the frozen clock while the frame settles.

const ARENAS := {
	"yard": "res://arena/yard.tscn", "grinder": "res://arena/grinder.tscn",
	"furnace": "res://arena/furnace.tscn", "crush": "res://arena/crush.tscn",
	"drop_zone": "res://arena/drop_zone.tscn", "coliseum": "res://arena/coliseum.tscn",
	"gauntlet": "res://arena/events/gauntlet.tscn",
	"pinball": "res://arena/events/pinball.tscn",
	"test_bay": "res://arena/test_arena.tscn",
}
const TICK := 1.0 / 60.0

var _dir := ""
var _only: PackedStringArray = []
## Seconds of frame clock a "target_drop" frame lets the arena's _process run before it is
## frozen (the easing is presentation, on the frame clock).
var _hold_process := -1.0


## [job, arena, target, close_from, close_at, steps]
## A step: [state name or "" for no frame, kind, arg].
func _jobs() -> Array:
	var spike_steps := [
		["rest", "none", null],
		["arming", "arm", "spikes"],
		["rising", "ext_up", "spikes"],
		["up", "ext_full", "spikes"],
		["sinking", "ext_down", "spikes"],
		["after", "ticks", 30],
	]
	var wake_spikes := [
		["asleep", "none", null],
		["", "stage", 2],
		["waking", "arm", "spikes"],
		["rising", "ext_up", "spikes"],
		["up", "ext_full", "spikes"],
		["sinking", "ext_down", "spikes"],
	]
	var wake_grinder := [
		["asleep", "none", null],
		["", "stage", 2],
		["waking", "arm", "grinder_0"],
		["spinning", "awake", "grinder_0"],
	]
	return [
		["yard_spikes", "yard", Vector3.ZERO, Vector3(-1.9, 0.42, -1.5), Vector3(0.0, 0.12, 0.0), spike_steps],
		["yard_wake_grinder", "yard", Vector3(0, 0, -3.6), Vector3(-1.1, 1.0, -2.5), Vector3(0.0, -0.05, -3.6), wake_grinder],
		["grinder_disc", "grinder", Vector3(-3.3, 0, 1.1), Vector3(-2.2, 1.0, 2.1), Vector3(-3.3, -0.05, 1.1),
			[["running", "ticks", 20]]],
		["grinder_wake_spikes", "grinder", Vector3.ZERO, Vector3(-1.8, 0.42, -1.4), Vector3(0.0, 0.12, 0.0), wake_spikes],
		["drop_zone_pit", "drop_zone", Vector3.ZERO, Vector3(-2.6, 0.9, -2.2), Vector3(0.0, -0.3, 0.0), [
			["closed", "none", null],
			["warning", "arm", "pit"],
			["opening", "ext_up", "pit"],
			["open", "ext_full", "pit"],
			["closing", "ext_down", "pit"],
		]],
		["drop_zone_pocket", "drop_zone", Vector3.ZERO, Vector3(-0.9, 1.3, 0.35), Vector3(1.2, -0.25, 0.0), [
			["opening", "ext_up", "pit"],
			["open", "ext_full", "pit"],
		]],
		["furnace_north_jet", "furnace", Vector3(-0.3, 0, -3.6), Vector3(0.6, 0.5, -2.0), Vector3(-0.3, 0.3, -4.8), [
			["rest", "none", null],
			["arming", "arm", "jet_1"],
			["burning", "active", ["jet_1", 30]],
			["after", "idle", ["jet_1", 20]],
		]],
		["furnace_east_jet", "furnace", Vector3(3.6, 0, 0.3), Vector3(2.2, 0.5, 1.4), Vector3(4.8, 0.3, 0.3), [
			["asleep", "none", null],
			["", "stage", 2],
			["waking", "arm", "jet_6"],
			["burning", "active", ["jet_6", 30]],
		]],
		["furnace_belt", "furnace", Vector3(-4.0, 0, -3.0), Vector3(-2.3, 0.7, -2.2), Vector3(-4.2, 0.0, -4.8),
			[["running", "ticks", 30]]],
		["crush_ram", "crush", Vector3(-3.9, 0, -1.2), Vector3(-3.4, 1.0, 1.5), Vector3(-4.8, 0.3, -1.0), [
			["rest", "none", null],
			["arming", "arm", "ram_west"],
			["pressing", "ext_up", "ram_west"],
			["hold", "ext_full", "ram_west"],
			["retracting", "ext_down", "ram_west"],
		]],
		["crush_wake_spikes", "crush", Vector3.ZERO, Vector3(-1.8, 0.42, -1.4), Vector3(0.0, 0.12, 0.0), wake_spikes],
		["coliseum_spikes", "coliseum", Vector3.ZERO, Vector3(-2.2, 0.45, -1.8), Vector3(0.0, 0.12, 0.0), spike_steps],
		["coliseum_turntable", "coliseum", Vector3(-2.9, 0, 2.9), Vector3(-0.3, 0.6, 1.4), Vector3(-2.9, 0.0, 2.9),
			[["turning", "ticks", 20]]],
		["coliseum_grinder", "coliseum", Vector3(-4.6, 0, -1.5), Vector3(-3.5, 1.0, -0.5), Vector3(-4.6, -0.05, -1.5),
			[["running", "ticks", 20]]],
		["coliseum_jet", "coliseum", Vector3(-1.2, 0, -4.6), Vector3(-0.2, 0.5, -3.0), Vector3(-1.2, 0.3, -5.8), [
			["rest", "none", null],
			["arming", "arm", "jet_0"],
			["burning", "active", ["jet_0", 30]],
		]],
		["coliseum_banners", "coliseum", Vector3(0, 0, -5.0), Vector3(0.2, 1.3, -3.2), Vector3(-1.5, 1.8, -6.1),
			[["dressing", "ticks", 5]]],
		["yard_overview", "yard", Vector3(0, 0, 0), Vector3(-4.3, 0.35, -4.3), Vector3(2.0, 0.2, 2.0),
			[["dressing", "ticks", 5]]],
		["grinder_overview", "grinder", Vector3(0, 0, 0), Vector3(-4.3, 0.35, -4.3), Vector3(2.0, 0.2, 2.0),
			[["dressing", "ticks", 5]]],
		["drop_zone_overview", "drop_zone", Vector3(0, 0, 0), Vector3(-4.3, 0.35, -4.3), Vector3(2.0, 0.2, 2.0),
			[["dressing", "ticks", 5]]],
		["furnace_overview", "furnace", Vector3(0, 0, 0), Vector3(4.3, 0.35, -4.3), Vector3(-2.0, 0.2, 2.0),
			[["dressing", "ticks", 5]]],
		["crush_overview", "crush", Vector3(0, 0, 0), Vector3(-4.3, 0.35, 4.3), Vector3(2.0, 0.2, -2.0),
			[["dressing", "ticks", 5]]],
		["coliseum_overview", "coliseum", Vector3(0, 0, 0), Vector3(-5.2, 0.35, -5.2), Vector3(2.4, 0.2, 2.4),
			[["dressing", "ticks", 5]]],
		["test_bay_floor", "test_bay", Vector3(0, 0, -1.5), Vector3(-2.6, 1.2, 0.4), Vector3(0.0, 0.0, -2.6),
			[["floor", "none", null]]],
		["pinball_target", "pinball", Vector3(-1.5, 0, -2.6), Vector3(-0.3, 0.7, -1.4), Vector3(-1.5, 0.0, -2.6), [
			["up", "none", null],
			["down", "target_drop", 0.5],
		]],
		["gauntlet_press", "gauntlet", Vector3(4.6, 0, -1.0), Vector3(0.6, 2.4, -2.6), Vector3(4.6, 1.2, 0.4), [
			["up", "none", null],
			["down", "press_down", null],
		]],
	]


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--roboteer-hs-dir="):
			_dir = a.get_slice("=", 1)
		if a.begins_with("--roboteer-hs-only="):
			_only = a.get_slice("=", 1).split(",")
	if _dir == "":
		_dir = OS.get_user_data_dir() + "/hazard_states"
	DirAccess.make_dir_recursive_absolute(_dir)
	_run()


func _run() -> void:
	for job_variant in _jobs():
		var job: Array = job_variant
		if not _only.is_empty() and not (str(job[0]) in _only):
			continue
		await _do_job(job)
	get_tree().quit()


func _do_job(job: Array) -> void:
	var id: String = job[0]
	var arena: Node3D = (load(ARENAS[job[1]]) as PackedScene).instantiate()
	add_child(arena)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	arena.call("setup", rng)
	arena.set_physics_process(false)
	var target: Vector3 = job[2]
	var fight_cam := Camera3D.new()
	fight_cam.fov = 28.0
	fight_cam.far = 400.0
	add_child(fight_cam)
	var p := deg_to_rad(50.0)
	var back := Vector3(-0.70710678, 0.0, -0.70710678) * cos(p)
	fight_cam.look_at_from_position(target + (back + Vector3(0, sin(p), 0)) * 6.2, target, Vector3.UP)
	var close_cam := Camera3D.new()
	close_cam.fov = 42.0
	close_cam.far = 400.0
	add_child(close_cam)
	close_cam.look_at_from_position(job[3], job[4], Vector3.UP)
	if id.ends_with("_banners"):
		# QA work light only, so dark dressing against a dark wall can be judged.
		var work := OmniLight3D.new()
		work.light_energy = 4.0
		work.omni_range = 9.0
		work.position = job[3]
		add_child(work)
	var last := -1.0
	for step_variant in job[5]:
		var step: Array = step_variant
		var state: String = step[0]
		var ok := _wind(arena, str(step[1]), step[2])
		if not ok:
			print("hazard_states: ", id, " ", state, " NOT REACHED")
		if state == "":
			continue
		if _hold_process >= 0.0:
			arena.set_process(true)
			var t0 := Time.get_ticks_msec()
			while Time.get_ticks_msec() - t0 < int(_hold_process * 1000.0):
				await get_tree().process_frame
			arena.set_process(false)
			_hold_process = -1.0
		for cam in [fight_cam, close_cam]:
			(cam as Camera3D).current = true
			for _i in range(10):
				# A burning jet's flame is particles on the arena's own tick clock: keep the
				# clock running a tick a frame while the frame settles, or it never draws.
				if str(step[1]) == "active" and cam == fight_cam:
					_step(arena)
				await get_tree().process_frame
			# A window behind the others on a busy Mac stops presenting frames and the
			# viewport texture goes stale (identical files): draw two frames by hand.
			RenderingServer.force_draw(true, 0.0)
			RenderingServer.force_draw(true, 0.0)
			var tag := "fight" if cam == fight_cam else "close"
			get_viewport().get_texture().get_image().save_png(
				"%s/%s__%s__%s.png" % [_dir, id, state, tag])
		arena.set_process(true)
		print("hazard_states: ", id, " ", state, " tick ", arena.get("_ticks"))
	fight_cam.queue_free()
	close_cam.queue_free()
	arena.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _entry(arena: Node, hid: String) -> Dictionary:
	for e_variant in arena.call("hazard_schedule"):
		var e: Dictionary = e_variant
		if str(e["id"]) == hid:
			return e
	return {}


## How far out the hazard is, 0 home to 1 fully out, read off the real node.
func _ext(arena: Node, hid: String) -> float:
	match hid:
		"spikes":
			var spikes: Array = arena.get("_spikes")
			if spikes.is_empty():
				return 0.0
			return clampf(((spikes[0] as Node3D).position.y + 0.2) / 0.45, 0.0, 1.0)
		"pit":
			return float(arena.call("_cover_amount"))
		"ram_west", "ram_east":
			var ram: Dictionary = (arena.get("_rams") as Array)[0 if hid == "ram_west" else 1]
			var body := ram["body"] as Node3D
			return absf(body.position.x - float(ram["rest_x"])) / 0.9
	return 0.0


func _step(arena: Node) -> void:
	arena.call("_physics_process", TICK)


func _wind(arena: Node, kind: String, arg: Variant) -> bool:
	var limit := 60 * 90
	match kind:
		"none":
			return true
		"ticks":
			for _i in range(int(arg)):
				_step(arena)
			return true
		"stage":
			arena.call("set_stage", 1)
			arena.call("set_stage", int(arg))
			return true
		"arm":
			for _i in range(limit):
				var e := _entry(arena, str(arg))
				if not e.is_empty() and not bool(e["active"]) and float(e["in_s"]) <= 0.7 \
						and float(e["in_s"]) > 0.2:
					return true
				_step(arena)
			return false
		"awake":
			for _i in range(limit):
				var e := _entry(arena, str(arg))
				if bool(e.get("always_on", false)):
					for _k in range(30):
						_step(arena)
					return true
				_step(arena)
			return false
		"active":
			var a: Array = arg
			for _i in range(limit):
				if bool(_entry(arena, str(a[0])).get("active", false)):
					for _k in range(int(a[1])):
						_step(arena)
					return true
				_step(arena)
			return false
		"idle":
			var a: Array = arg
			for _i in range(limit):
				if not bool(_entry(arena, str(a[0])).get("active", true)):
					for _k in range(int(a[1])):
						_step(arena)
					return true
				_step(arena)
			return false
		"ext_up", "ext_down":
			var prev := _ext(arena, str(arg))
			for _i in range(limit):
				_step(arena)
				var now := _ext(arena, str(arg))
				var moving := now > prev if kind == "ext_up" else now < prev
				if moving and now >= 0.4 and now <= 0.65:
					return true
				prev = now
			return false
		"ext_full":
			for _i in range(limit):
				_step(arena)
				if _ext(arena, str(arg)) >= 0.999:
					for _k in range(6):
						_step(arena)
					return true
			return false
		"target_drop":
			# The rule's own jump (body to TARGET_DOWN_Y), then a short wait on the frame
			# clock; arg = seconds of easing to let run before the frame.
			var t: Dictionary = (arena.get("_targets") as Array)[0]
			var body := t["body"] as Node3D
			if arena.has_method("_ease_target_mesh"):
				arena.call("_ease_target_mesh", t, body.position.y - float(arena.get("TARGET_DOWN_Y")))
			body.position.y = float(arena.get("TARGET_DOWN_Y"))
			_hold_process = float(arg)
			return true
		"press_down":
			for _i in range(limit):
				_step(arena)
				var presses: Array = arena.get("_presses")
				if not presses.is_empty() and bool((presses[0] as Dictionary).get("down", false)):
					for _k in range(10):
						_step(arena)
					return true
			return false
	return false
