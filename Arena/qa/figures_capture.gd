extends SceneTree
## QA only (wave D figures, docs/wave-d-figures-notes.md). Starts the fixture fight in a real
## window, freezes it after the countdown and stamps every figure the fight feed shows, so
## the figures face can be checked for clipping and for the gap after "." and ":":
##
##   Godot --path Arena --audio-driver Dummy --resolution 1434x660 \
##     --script qa/figures_capture.gd -- --fig-shots=DIR [--fig-arena=yard]
##
## Files: clock (2:58 on the clock bug, which rounds up, and 1280 on the scrap bug),
## clock-low (0:10, scrap 45), ko-count, result-judges. Not referenced by any shipped scene.

const FIGHT_SCENE := "res://fight/fight.tscn"
const FIXTURE := "res://fight/fixtures/stage3_config.json"

var _dir := ""
var _arena := "yard"
var _fight: Node = null


func _initialize() -> void:
	for raw in OS.get_cmdline_user_args():
		var a := str(raw)
		if a.begins_with("--fig-shots="):
			_dir = a.get_slice("=", 1)
		elif a.begins_with("--fig-arena="):
			_arena = a.get_slice("=", 1)
	if _dir != "":
		DirAccess.make_dir_recursive_absolute(_dir)
	_run()


func _run() -> void:
	await process_frame
	_fight = (load(FIGHT_SCENE) as PackedScene).instantiate()
	root.add_child(_fight)
	for i in 5:
		await process_frame
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	config["arena"] = _arena
	config["intro"] = "none"
	(config["rules"] as Dictionary)["duration_s"] = 180
	_fight.call("start_fight", config)
	var hud: Node = _fight.get("_hud")
	var guard := 0
	while _fight.call("_state_name", _fight.get("state")) == "countdown" and guard < 900:
		guard += 1
		await process_frame
	# Stop the fight's own clock so the stamped values stay put.
	_fight.set_process(false)
	_fight.set_physics_process(false)
	hud.call("hide_countdown")
	await _settle(4)
	hud.call("set_time_left", 177.4)
	hud.call("set_scrap", 1280)
	await _settle(40)
	_save("clock")
	hud.call("set_time_left", 9.2)
	hud.call("set_scrap", 45)
	await _settle(40)
	_save("clock-low")
	hud.call("show_ko_count", 7, "Clatterbox", false)
	await _settle(10)
	_save("ko-count")
	hud.call("hide_ko_count")
	hud.call("show_result", "Judges decision", "Clatterbox")
	await _settle(20)
	_save("result-judges")
	quit(0)


func _settle(frames: int) -> void:
	for i in frames:
		await process_frame


func _save(file_name: String) -> void:
	if _dir == "":
		return
	var img := root.get_texture().get_image()
	if img != null:
		img.save_png(_dir.path_join(file_name + ".png"))
		print("figures_capture: ", file_name)
