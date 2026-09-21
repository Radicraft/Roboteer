extends SceneTree
## Timing probe (not a test): how long the workshop stage takes to stand a machine up.
##   Godot --headless --path Arena --script tests/_stage_timing_probe.gd
## Prints one TIMING line per phase in milliseconds. Helper, so the name starts with _
## and scripts/test-arena.sh skips it.

const STAGE_SCENE := "res://workshop/stage.tscn"
const FIXTURE := "res://fight/fixtures/stage3_config.json"


func _initialize() -> void:
	_run()


func _run() -> void:
	var t0 := Time.get_ticks_usec()
	var stage_scene: PackedScene = load(STAGE_SCENE)
	var t1 := Time.get_ticks_usec()
	print("TIMING load stage.tscn: %.1f ms" % ((t1 - t0) / 1000.0))

	var stage: WorkshopStage = stage_scene.instantiate() as WorkshopStage
	var t2 := Time.get_ticks_usec()
	print("TIMING instantiate stage: %.1f ms" % ((t2 - t1) / 1000.0))

	root.add_child(stage)
	await process_frame
	await process_frame
	var t3 := Time.get_ticks_usec()
	print("TIMING stage enters the tree: %.1f ms" % ((t3 - t2) / 1000.0))

	var text := FileAccess.get_file_as_string(FIXTURE)
	var parsed: Dictionary = JSON.parse_string(text)
	var config: Dictionary = (parsed["bots"] as Array)[0]

	var t4 := Time.get_ticks_usec()
	stage.show_bot(config)
	var t5 := Time.get_ticks_usec()
	print("TIMING show_bot (first, cold): %.1f ms" % ((t5 - t4) / 1000.0))

	await process_frame
	var t6 := Time.get_ticks_usec()
	print("TIMING one frame after the bind: %.1f ms" % ((t6 - t5) / 1000.0))

	stage.show_bot(config)
	var t7 := Time.get_ticks_usec()
	print("TIMING show_bot (second, warm): %.1f ms" % ((t7 - t6) / 1000.0))

	print("TIMING total to a machine on the turntable: %.1f ms" % ((t5 - t0) / 1000.0))
	quit(0)
