extends SceneTree
## Timing probe (not a test): the warm DRAW, which headless cannot run, and what it buys the
## first stage frame. Needs a renderer, so it is run WINDOWED, silent:
##
##   Godot --path Arena --audio-driver Dummy --script tests/_warmup_draw_probe.gd [-- --warm]
##   Godot --path Arena --audio-driver Dummy --rendering-method gl_compatibility \
##         --script tests/_warmup_draw_probe.gd [-- --warm]
##
## Without --warm it stands the stage up cold and times the first frames with a machine
## on the turntable. With --warm it runs the whole ArenaWarmUp walk first (reading plus the
## off screen draw), prints its phases, then does the same. Compare the two runs. Godot's
## on-disk shader cache survives between runs, so clear it (the project's user:// folder,
## `shader_cache`) before each run for a truly cold number.

const STAGE_SCENE := "res://workshop/stage.tscn"
const FIXTURE := "res://fight/fixtures/stage3_config.json"


func _initialize() -> void:
	_run()


func _run() -> void:
	var warm := OS.get_cmdline_user_args().has("--warm")
	print("PROBE adapter '%s' rd %s warm %s" % [RenderingServer.get_video_adapter_name(),
		str(RenderingServer.get_rendering_device() != null), str(warm)])
	var t0 := Time.get_ticks_usec()
	if warm:
		var warmup := ArenaWarmUp.new()
		root.add_child(warmup)
		await process_frame
		warmup.begin({})
		var frames := 0
		while warmup.running() and frames < 5000:
			frames += 1
			await process_frame
		print("TIMING warm-up walk: %.1f ms over %d frames (read %.1f ms, draw %.1f ms, drawn %d)"
			% [warmup.elapsed_ms(), frames, warmup._read_ms, warmup._draw_ms, warmup._warmed])

	var camera := Camera3D.new()
	root.add_child(camera)
	camera.look_at_from_position(Vector3(0.0, 1.4, 4.5), Vector3(0, 0.3, 0), Vector3.UP)
	camera.current = true

	var t1 := Time.get_ticks_usec()
	var stage: Node = (load(STAGE_SCENE) as PackedScene).instantiate()
	root.add_child(stage)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var config: Dictionary = ((parsed as Dictionary)["bots"] as Array)[0] as Dictionary
	stage.call("show_bot", config)
	var t2 := Time.get_ticks_usec()
	print("TIMING stage up and machine bound: %.1f ms" % ((t2 - t1) / 1000.0))
	var last := t2
	var worst := 0.0
	for i in 6:
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		worst = maxf(worst, ms)
		print("TIMING frame %d with the machine on the turntable: %.1f ms" % [i + 1, ms])
		last = now
	print("TIMING first six frames: %.1f ms (worst %.1f ms); launch to sixth frame %.1f ms"
		% [(last - t2) / 1000.0, worst, (last - t0) / 1000.0])
	quit(0)
