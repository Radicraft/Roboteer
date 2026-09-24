extends Node
## QA only (wave A venue kit, docs/wave-a-kit-notes.md). Runs the desktop fixture fight in
## an arena, then saves a fixed list of frames from fixed cameras, so a before/after pair
## of the venue can be shot with the same poses:
##
##   Godot --path Arena res://qa/venue_capture.tscn -- --roboteer-capture-arena=yard \
##     --roboteer-venue-shots=DIR [--roboteer-no-venue] [--roboteer-venue-tier=medium]
##
## Frames (all at 1206 x 556, the window size):
##   fight_a / fight_b / fight_c  the real fight camera at three moments
##   wide                         arena_capture.gd's establishing pose (yaw -135, pitch 34, 22 m)
##   reveal                       higher and closer, the endgame reveal's kind of framing
##   gate                         low, toward the opponent's gate and the east stand
##   stand                        from the north-west, across the arena to the south stand
##   screen                       the big screen, close
##   entrance                     the gate pose 1.6 s into the venue entrance (pyro)
## Not referenced by any shipped scene. The fight itself is untouched: cameras are added
## to the world and made current only for the frame being saved.

var _fight: Node = null
var _frames := 0
var _t := 0.0
var _dir := ""
var _plan: Array = []
var _cam: Camera3D = null
var _pending := ""
var _pending_frames := 0


func _ready() -> void:
	_fight = (load("res://fight/fight.tscn") as PackedScene).instantiate()
	add_child(_fight)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--roboteer-venue-shots="):
			_dir = a.substr(23)
	if _dir != "":
		DirAccess.make_dir_recursive_absolute(_dir)
	# [time after the fight starts, name, pose or "" for the fight camera]
	_plan = [
		[6.0, "fight_a", ""], [9.0, "fight_b", ""], [12.0, "fight_c", ""],
		[13.0, "wide", "wide"], [13.6, "reveal", "reveal"], [14.2, "gate", "gate"],
		[14.8, "stand", "stand"], [15.1, "screen", "screen"], [15.4, "north", "north"],
		[16.0, "entrance_go", "gate_entrance"], [17.6, "entrance", "gate_entrance"],
	]


func _process(dt: float) -> void:
	_frames += 1
	if _frames == 3:
		_start()
		return
	if _frames < 3:
		return
	_t += minf(dt, 0.1)
	if _pending != "":
		_pending_frames -= 1
		if _pending_frames <= 0:
			_save(_pending)
			_pending = ""
		return
	if _plan.is_empty():
		if _dir != "":
			get_tree().quit()
		return
	var next: Array = _plan[0]
	if _t < float(next[0]):
		return
	_plan.pop_front()
	var pose := str(next[2])
	if str(next[1]) == "entrance_go":
		var kit := get_tree().root.find_child("VenueKit", true, false)
		if kit != null and kit.has_method("play_entrance"):
			kit.call("play_entrance", 1)
		_set_pose("gate_entrance")
		return
	_set_pose(pose)
	_pending = str(next[1])
	_pending_frames = 3


func _start() -> void:
	var arena := "yard"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--roboteer-capture-arena="):
			arena = a.substr(25)
	var config: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://fight/fixtures/stage3_config.json"))
	config["arena"] = arena
	var debug: Dictionary = config.get("debug", {}) as Dictionary
	debug["player_ai"] = "charge"
	debug["opponent_ai"] = "normal"
	config["debug"] = debug
	var rules: Dictionary = config.get("rules", {}) as Dictionary
	rules["duration_s"] = 180
	config["rules"] = rules
	_fight.call("start_fight", config)


func _world() -> Node:
	return get_tree().root.find_child("World", true, false)


func _set_pose(pose: String) -> void:
	var world := _world()
	if world == null:
		return
	if pose == "":
		if _cam != null:
			_cam.current = false
		var rig := get_tree().root.find_child("CameraRig", true, false)
		if rig != null and rig.has_method("camera"):
			var c := rig.call("camera") as Camera3D
			if c != null:
				c.current = true
		return
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 28.0
		_cam.far = 400.0
		world.add_child(_cam)
	var from := Vector3.ZERO
	var at := Vector3.ZERO
	match pose:
		"wide":
			var d := 22.0
			var pitch := deg_to_rad(34.0)
			var h := d * cos(pitch) / sqrt(2.0)
			from = Vector3(-h, d * sin(pitch), -h)
			at = Vector3(0.0, 0.3, 0.0)
		"reveal":
			from = Vector3(-10.5, 11.5, -10.5)
			at = Vector3(1.0, 0.6, 1.0)
			_cam.fov = 34.0
		"gate":
			from = Vector3(-4.0, 3.2, -1.5)
			at = Vector3(7.0, 2.4, 6.0)
			_cam.fov = 40.0
		"gate_entrance":
			from = Vector3(-1.5, 2.6, -1.5)
			at = Vector3(7.3, 2.4, 7.3)
			_cam.fov = 42.0
		"stand":
			from = Vector3(-3.5, 2.2, -4.0)
			at = Vector3(0.5, 2.6, 8.0)
			_cam.fov = 48.0
		"screen":
			from = Vector3(-1.0, 3.2, 1.5)
			at = Vector3(-1.0, 4.4, 10.5)
			_cam.fov = 40.0
		"north":
			from = Vector3(2.0, 3.0, 3.5)
			at = Vector3(-3.0, 1.2, -9.0)
			_cam.fov = 50.0
	_cam.look_at_from_position(from, at, Vector3.UP)
	_cam.current = true


func _save(name: String) -> void:
	if _dir == "":
		return
	var vp := _world() as Viewport
	if vp == null:
		vp = get_viewport()
	var img := vp.get_texture().get_image()
	if img == null:
		return
	img.save_png(_dir.path_join(name + ".png"))
	var rid := vp.get_viewport_rid()
	var vis := RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE
	var sh := RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW
	print("venue_capture: saved ", name, " ", JSON.stringify({
		"draw_calls": RenderingServer.viewport_get_render_info(rid, vis, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"objects": RenderingServer.viewport_get_render_info(rid, vis, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
		"primitives": RenderingServer.viewport_get_render_info(rid, vis, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
		"shadow_draw_calls": RenderingServer.viewport_get_render_info(rid, sh, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"shadow_primitives": RenderingServer.viewport_get_render_info(rid, sh, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
		"video_mem_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"buffer_mem_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED) / 1048576.0, 0.1),
		"fps": Engine.get_frames_per_second(),
	}))
