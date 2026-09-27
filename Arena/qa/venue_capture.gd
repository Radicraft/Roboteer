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
##   near_se / near_s / near_e    the fight camera's pose at the owner's closer default, a
##                                metre off the far walls (fixed, so treatments compare)
##   near_se_react                the same, 0.9 s after a big-hit crowd reaction
##   concept                      the Yard concept image's angle (near corner, high, 44 deg lens)
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
var _custom := PackedFloat64Array()
var _offset := 0.0
var _when := ""


func _ready() -> void:
	_fight = (load("res://fight/fight.tscn") as PackedScene).instantiate()
	add_child(_fight)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--roboteer-venue-shots="):
			_dir = a.substr(23)
	if _dir != "":
		DirAccess.make_dir_recursive_absolute(_dir)
	# --roboteer-venue-offset=S: every frame S seconds later (the Drop Zone's pit opens
	# between 30 and 60 s, so its concept frame needs the fight to have run that long).
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--roboteer-venue-offset="):
			_offset = float(a.get_slice("=", 1))
		# --roboteer-venue-when=METHOD: hold the plan until the arena's METHOD() is true
		# (pit_open), then shoot it from there. Gives up after 120 s.
		if a.begins_with("--roboteer-venue-when="):
			_when = a.get_slice("=", 1)
	# --roboteer-venue-pose=fx,fy,fz,tx,ty,tz,fov: ONE extra frame "pose" from that camera
	# at 7 s, then quit (quick look-dev without the full plan).
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--roboteer-venue-pose="):
			var v := a.get_slice("=", 1).split_floats(",")
			if v.size() >= 7:
				_custom = v
				_plan = [[7.0, "pose", "custom"]]
				return
	# [time after the fight starts, name, pose or "" for the fight camera]
	_plan = _full_plan()
	# --roboteer-venue-only=a,b: shoot only those frames (quick look-dev passes).
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--roboteer-venue-only="):
			var keep := a.get_slice("=", 1).split(",")
			_plan = _plan.filter(func(e: Array) -> bool: return str(e[1]) in keep)


func _full_plan() -> Array:
	return [
		[6.0, "fight_a", ""],
		[7.0, "near_se", "near_se"], [7.5, "near_s", "near_s"], [8.0, "near_e", "near_e"],
		[8.4, "react_go", "near_se"], [9.3, "near_se_react", "near_se"],
		[10.0, "fight_b", ""], [12.0, "fight_c", ""],
		[12.6, "concept", "concept"],
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
	if _when != "":
		var arena := get_tree().root.find_child("World", true, false)
		var ar: Node = _fight.call("arena") if _fight.has_method("arena") else null
		if (ar != null and ar.has_method(_when) and bool(ar.call(_when))) or _t > 120.0:
			print("venue_capture: ", _when, " at ", snappedf(_t, 0.1))
			_offset = _t - float(next[0]) + 2.5
			_when = ""
		return
	if _t < float(next[0]) + _offset:
		return
	_plan.pop_front()
	var pose := str(next[2])
	if str(next[1]) == "react_go":
		var k := get_tree().root.find_child("VenueKit", true, false)
		if k != null and k.has_method("on_crowd_reaction"):
			k.call("on_crowd_reaction", "big_hit", 1.0)
		return
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
	_cam.fov = 28.0
	match pose:
		"near_se", "near_s", "near_e":
			# The fight camera's own pose (yaw -135, pitch 50, 28 degree lens) at the owner's
			# closer default: about 6.2 m, 12 % in from today's 7 m, with the machines a metre
			# or so off a far wall. This is the frame the crowd has to hold up in.
			var target := Vector3(3.55, 0.15, 3.55)
			if pose == "near_s":
				target = Vector3(0.6, 0.15, 3.85)
			elif pose == "near_e":
				target = Vector3(3.85, 0.15, 0.6)
			var p := deg_to_rad(50.0)
			var dist := 6.2
			var back := Vector3(-0.70710678, 0.0, -0.70710678) * cos(p)
			from = target + (back + Vector3(0.0, sin(p), 0.0)) * dist
			at = target
		"concept":
			# The Yard concept's own angle (docs/look/arenas/yard-concept.webp): above the
			# near corner, across the arena to the far corner, the container crowd on the
			# left and the south stand on the right.
			from = Vector3(-7.4, 7.0, -7.4)
			at = Vector3(1.4, 0.0, 1.4)
			_cam.fov = 44.0
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
		"custom":
			from = Vector3(_custom[0], _custom[1], _custom[2])
			at = Vector3(_custom[3], _custom[4], _custom[5])
			_cam.fov = _custom[6]
		"north":
			from = Vector3(2.0, 3.0, 3.5)
			at = Vector3(-3.0, 1.2, -9.0)
			_cam.fov = 50.0
	# Poses are authored for a 10 m arena: scale them to this one (the Coliseum is 12 m).
	var k := _arena_scale()
	if pose in ["concept", "wide", "reveal"]:
		from *= k
		at *= k
	elif pose in ["near_se", "near_s", "near_e"]:
		var shift := at * (k - 1.0)
		from += shift
		at += shift
	_cam.look_at_from_position(from, at, Vector3.UP)
	_cam.current = true


func _arena_scale() -> float:
	var ar: Node = _fight.call("arena") if _fight != null and _fight.has_method("arena") else null
	if ar != null and ar.has_method("arena_half_extent"):
		return float(ar.call("arena_half_extent")) / 5.0
	return 1.0


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
