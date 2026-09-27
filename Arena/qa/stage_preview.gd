extends Node3D
## QA preview: the workshop stage with the fixture bot and a workshop-mode camera.
## Run: Godot --path Arena res://qa/stage_preview.tscn -- --roboteer-shots=DIR,3,4 [--roboteer-cam=menu]
##
## Wave A (docs/wave-a-stage-notes.md) adds:
##   --roboteer-shot=faceoff|showroom|garage|part:weapon   the stage director's shots
##   --roboteer-slice      the proving slice machines (res://qa/stage_slice_bots.json)
##   --roboteer-spark=S    fire the attract test-fire spark S seconds in (for a capture)
##   --roboteer-quit-after=S   quit S seconds in (captures without a watchdog)
##   --roboteer-measure[=off1,off2]  print the mean CPU and GPU frame times from 3 s to 8 s,
##       with the named features switched off (ssr, ssao, volumetric, glow, dof, probe,
##       post, haze), for the per feature cost table in docs/wave-a-stage-notes.md
##   --roboteer-hide=Name1,Name2   hide stage nodes by name (find which light makes a glint)
##   --roboteer-build=STEP[:F]  pose the loading screen's build on the turntable at row STEP
##       (ArenaWarmUp.STEP_*, 0 hull .. 4 lights, F = that row's fraction), for the
##       docs/look/loading/built-*.jpg captures
##   --roboteer-frame=F   where the machine lands across the screen, as the shell's
##       `workshop_config.frame` (0.28 for every menu screen, StageLayout.botFrame)

var _quit_after := -1.0
var _spark_at := -1.0
var _t := 0.0
var _stage: WorkshopStage = null
var _measure := false
var _cpu := 0.0
var _gpu := 0.0
var _frames := 0


func _ready() -> void:
	var stage := WorkshopStage.new()
	stage.name = "Stage"
	_stage = stage
	var rig_scene: PackedScene = load("res://ui/camera_rig.tscn")
	var rig: Node3D = rig_scene.instantiate()
	rig.name = "CameraRig"
	add_child(rig)
	add_child(stage)
	var bot_cfg: Dictionary = {}
	var slice := "--roboteer-slice" in OS.get_cmdline_user_args()
	if slice and FileAccess.file_exists("res://qa/stage_slice_bots.json"):
		var bots: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://qa/stage_slice_bots.json"))
		bot_cfg = bots.get("hero", {})
	if bot_cfg.is_empty():
		var cfg_text := FileAccess.get_file_as_string("res://fight/fixtures/stage3_config.json")
		var config: Dictionary = JSON.parse_string(cfg_text)
		bot_cfg = (config["bots"] as Array)[0]
	stage.show_bot(bot_cfg)
	stage.set_auto_rotate(true)
	var mode := "workshop"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--roboteer-cam="):
			mode = a.substr(15)
		elif a.begins_with("--roboteer-quit-after="):
			_quit_after = a.substr(22).to_float()
		elif a.begins_with("--roboteer-build="):
			var pose := a.substr(17).split(":")
			stage.set_build_step(int(pose[0]), float(pose[1]) if pose.size() > 1 else 0.0)
		elif a.begins_with("--roboteer-spark="):
			_spark_at = a.substr(17).to_float()
		elif a.begins_with("--roboteer-hide="):
			for node_name in a.substr(16).split(",", false):
				for n in stage.find_children(node_name, "Node3D", true, false):
					(n as Node3D).visible = false
		elif a.begins_with("--roboteer-measure"):
			_measure = true
			var off := a.substr(19).split(",", false) if a.length() > 19 else PackedStringArray()
			_switch_off(off)
	rig.call("set_mode", mode)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--roboteer-frame=") and rig.has_method("set_frame_bias"):
			rig.call("set_frame_bias", a.substr(17).to_float())
	# Agent S 2026-09-14: the stage animates itself from _process, so a preview only has to
	# stand still and watch. These two numbers are what to quote when reporting how the
	# animation looked: the tier decides the particle budget (docs/stage-animation.md).
	var shot := stage.director().shot() if stage.director() != null else ""
	print("stage_preview ready, camera mode ", mode, ", shot '", shot,
		"', tier ", stage.quality_tier(), ", ", stage.particle_budget(), " billboards")


func _process(delta: float) -> void:
	_t += delta
	if _spark_at >= 0.0 and _t >= _spark_at:
		_spark_at = -1.0
		_stage.fire_test_spark()
	if OS.get_environment("STAGE_DEBUG") != "" and int(_t * 2.0) != int((_t - delta) * 2.0):
		var d := _stage.director()
		print("t=%.1f pose=%s opp=%s hero=%s" % [_t, d.pose(), _stage.opponent_point(), _stage.hero_bounds()])
		var ob := _stage.opponent_bot()
		var cam := get_viewport().get_camera_3d()
		print("  platform=", _stage.platform_share(), " hoff=", cam.h_offset if cam else 0.0, " hero_px=", cam.unproject_position(_stage.hero_bounds()["centre"]) if cam else Vector2.ZERO, " cam=", cam.get_path() if cam else null, " opp_bot=", ob, " slot_vis=", _stage.get_node("OpponentSlot").is_visible_in_tree(),
			" opp_px=", cam.unproject_position(_stage.opponent_point()) if cam else Vector2.ZERO, " vp=", get_viewport().get_visible_rect().size)
	if _measure:
		var vp := get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(vp, true)
		if _t > 3.0 and _t < 8.0:
			_cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) \
				+ RenderingServer.get_frame_setup_time_cpu()
			_gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
			_frames += 1
		elif _t >= 8.0:
			print("stage_measure frames=%d cpu_ms=%.3f gpu_ms=%.3f size=%s" % [_frames,
				_cpu / maxf(_frames, 1), _gpu / maxf(_frames, 1), get_viewport().get_visible_rect().size])
			get_tree().quit()
			return
	if _quit_after > 0.0 and _t >= _quit_after:
		get_tree().quit()


func _switch_off(features: PackedStringArray) -> void:
	var env: Environment = (_stage.get_node("Environment") as WorldEnvironment).environment
	for f in features:
		match f:
			"ssr": env.ssr_enabled = false
			"ssao": env.ssao_enabled = false
			"volumetric":
				env.volumetric_fog_enabled = false
			"glow": env.glow_enabled = false
			"dof": _stage.director().set_dof_enabled(false)
			"probe":
				var probe := _stage.get_node_or_null("RoomProbe")
				if probe != null:
					probe.queue_free()
			"post":
				var post := _stage.get_node_or_null("PostVignette")
				if post != null:
					post.queue_free()
			"haze":
				for child in _stage.get_children():
					if child is GPUParticles3D:
						(child as GPUParticles3D).emitting = false
						(child as GPUParticles3D).visible = false
