extends Node
## QA only (wave C crowd, docs/wave-c-crowd-notes.md). Runs the desktop fixture fight in an
## arena and records the CROWD: for each shot one still and a short clip of frames from the
## World viewport, with a big-hit crowd reaction fired part way through the clip, so the
## crowd's idle, its reaction and its settle are all in one clip.
##
##   Godot --path Arena res://qa/crowd_capture.tscn --fixed-fps 15 -- \
##     --roboteer-capture-arena=yard --roboteer-crowd-out=DIR \
##     [--roboteer-crowd-shots=fight,near,wide,stand,front] [--roboteer-crowd-frames=45] \
##     [--roboteer-venue-crowd=human|real|broadcast]
##
## Run with --fixed-fps so every frame advances the same time (shader TIME included): the
## clip plays at that rate whatever the desktop manages. Frames are saved at window size.
## Not referenced by any shipped scene; the fight is untouched (cameras only).

var _fight: Node = null
var _frames := 0
var _t := 0.0
var _dir := ""
var _shots: Array = ["fight", "wide", "stand", "front"]
var _clip_frames := 45
var _react_at := 15
var _cam: Camera3D = null
var _shot := -1
var _shot_frame := 0
var _start_at := 6.0
var _react_key := "big_hit"


func _ready() -> void:
	_fight = (load("res://fight/fight.tscn") as PackedScene).instantiate()
	add_child(_fight)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--roboteer-crowd-out="):
			_dir = a.get_slice("=", 1)
		elif a.begins_with("--roboteer-crowd-shots="):
			_shots = Array(a.get_slice("=", 1).split(","))
		elif a.begins_with("--roboteer-crowd-frames="):
			_clip_frames = int(a.get_slice("=", 1))
			_react_at = _clip_frames / 3
		elif a.begins_with("--roboteer-crowd-react="):
			# big_hit (default), verdict_clear or verdict_close: the reaction fired in the clip.
			_react_key = a.get_slice("=", 1)
		elif a.begins_with("--roboteer-crowd-start="):
			_start_at = float(a.get_slice("=", 1))
	if _dir != "":
		DirAccess.make_dir_recursive_absolute(_dir)


func _process(dt: float) -> void:
	_frames += 1
	if _frames == 3:
		_start()
		return
	if _frames < 3:
		return
	_t += dt
	if _t < _start_at:
		return
	if _shot < 0 or _shot_frame > _clip_frames + 2:
		_shot += 1
		_shot_frame = 0
		if _shot >= _shots.size():
			get_tree().quit()
			return
		_apply_stage()
		_set_pose(str(_shots[_shot]))
		return
	_shot_frame += 1
	# Two frames to settle the camera, then the clip.
	var f := _shot_frame - 3
	if f < 0:
		return
	if f == _react_at:
		var k := get_tree().root.find_child("VenueKit", true, false)
		if k != null and k.has_method("on_crowd_reaction"):
			k.call("on_crowd_reaction", _react_key, 1.0)
	_save("%s/%03d" % [_shots[_shot], f], f == 0)


func _start() -> void:
	var arena := "yard"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--roboteer-capture-arena="):
			arena = a.get_slice("=", 1)
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


func _arena_half() -> float:
	var ar: Node = _fight.call("arena") if _fight != null and _fight.has_method("arena") else null
	if ar != null and ar.has_method("arena_half_extent"):
		return float(ar.call("arena_half_extent"))
	return 5.0


func _set_pose(pose: String) -> void:
	var world := _world()
	if world == null:
		return
	if pose == "fight":
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
		_cam.far = 400.0
		world.add_child(_cam)
	var h := _arena_half()
	var from := Vector3.ZERO
	var at := Vector3.ZERO
	_cam.fov = 28.0
	match pose:
		"near":
			# The fight camera's own pose (yaw -135, pitch 50, 28 degree lens) at the owner's
			# closer default, the machines a metre off the far corner: the south-east stands.
			var target := Vector3(h - 1.45, 0.15, h - 1.45)
			var p := deg_to_rad(50.0)
			var back := Vector3(-0.70710678, 0.0, -0.70710678) * cos(p)
			from = target + (back + Vector3(0.0, sin(p), 0.0)) * 6.2
			at = target
		"wide":
			# The concept images' angle: above the near corner, across to the far stands.
			from = Vector3(-7.4, 7.0, -7.4) * h / 5.0
			at = Vector3(1.4, 0.0, 1.4) * h / 5.0
			_cam.fov = 44.0
		"stand":
			# Across the arena to the south stand, a broadcast "crowd shot".
			from = Vector3(-0.7, 2.2, -0.8) * h / 5.0
			at = Vector3(0.1, 2.6, 1.6) * h / 5.0 + Vector3(0, 0, h)
			_cam.fov = 40.0
		"close":
			# About three metres off the front rail: faces, hands, clothes (a replay or a KO
			# orbit passing the stand).
			from = Vector3(-0.6, 1.5, h - 2.6)
			at = Vector3(0.4, 2.2, h + 2.5)
			_cam.fov = 36.0
		"front":
			# Close on the front rows: what a replay or a KO orbit passes.
			from = Vector3(-1.0, 1.9, h - 3.2)
			at = Vector3(0.6, 2.2, h + 2.0)
			_cam.fov = 44.0
	# --roboteer-crowd-lift=Y,AT: raise the stand shots (a venue whose stands start high).
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--roboteer-crowd-lift=") and pose in ["stand", "front", "close"]:
			var v := a.get_slice("=", 1).split_floats(",")
			from.y += v[0]
			at.y += v[1] if v.size() > 1 else v[0]
	_cam.look_at_from_position(from, at, Vector3.UP)
	_cam.current = true


## --roboteer-crowd-stage=k=v,k=v: shader uniforms on every crowd layer (look-dev).
func _apply_stage() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--roboteer-crowd-stage="):
			continue
		var crowd := get_tree().root.find_child("Crowd", true, false)
		if crowd == null or not crowd.has_method("stage"):
			return
		var params := {}
		for kv in a.substr(23).split(","):
			var v := kv.split("=")
			if v.size() == 2:
				params[v[0]] = int(v[1]) if v[0] == "debug_view" else float(v[1])
		crowd.call("stage", params)


func _save(name: String, still: bool) -> void:
	if _dir == "":
		return
	var vp := _world() as Viewport
	if vp == null:
		vp = get_viewport()
	var img := vp.get_texture().get_image()
	if img == null:
		return
	if still:
		DirAccess.make_dir_recursive_absolute(_dir.path_join(name.get_base_dir()))
		img.save_png(_dir.path_join(name.get_base_dir() + "_still.png"))
		var rid := vp.get_viewport_rid()
		var vis := RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE
		var crowd := get_tree().root.find_child("Crowd", true, false)
		if crowd != null and name.begins_with(str(_shots[0])):
			print("crowd_counts: ", JSON.stringify({"cards": crowd.call("card_count"),
				"silhouettes": crowd.call("silhouette_count"), "specks": crowd.call("speck_count"),
				"people3d": crowd.call("people_count") if crowd.has_method("people_count") else 0,
				"flags": crowd.call("flag_count") if crowd.has_method("flag_count") else 0}))
		print("crowd_capture: ", name.get_base_dir(), " ", JSON.stringify({
			"draw_calls": RenderingServer.viewport_get_render_info(rid, vis, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
			"primitives": RenderingServer.viewport_get_render_info(rid, vis, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
			"video_mem_mb": snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, 0.1),
		}))
	# --roboteer-crowd-half: clip frames at half size (quick looks).
	if "--roboteer-crowd-half" in OS.get_cmdline_user_args():
		img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_BILINEAR)
	img.save_png(_dir.path_join(name + ".png"))
