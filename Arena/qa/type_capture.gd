extends SceneTree
## QA only (wave B fonts, docs/wave-b-fonts-notes.md). Starts the fixture fight in a real
## window, freezes it after the countdown, and stamps every big word the HUD can show so
## the Blueprint type can be checked for clipping at the design size:
##
##   Godot --path Arena --audio-driver Dummy --resolution 1206x556 \
##     --script qa/type_capture.gd -- --type-shots=DIR [--type-arena=furnace]
##
## Files: countdown, clock, endgame, hazards-up, wake, hazard-kill, ring-out, pit,
## ko-count, result-ring-out, result-judges. Not referenced by any shipped scene.

const FIGHT_SCENE := "res://fight/fight.tscn"
const FIXTURE := "res://fight/fixtures/stage3_config.json"

var _dir := ""
var _arena := "furnace"
var _fight: Node = null


func _initialize() -> void:
	for raw in OS.get_cmdline_user_args():
		var a := str(raw)
		if a.begins_with("--type-shots="):
			_dir = a.get_slice("=", 1)
		elif a.begins_with("--type-arena="):
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
	for i in 90:
		await process_frame
	hud.call("show_countdown", "3")
	await _settle(4)
	_save("countdown")
	hud.call("show_countdown", "")
	# Let the fight's own countdown finish so its numbers are not under the band.
	var guard := 0
	while _fight.call("_state_name", _fight.get("state")) == "countdown" and guard < 600:
		guard += 1
		await process_frame
	await _settle(6)
	var stings := [
		["endgame", "ENDGAME", false],
		["hazards-up", "HAZARDS UP", false],
		["wake", "THE FURNACE WAKES", false],
		["hazard-kill", "HAZARD KILL", true],
		["ring-out", "OUT OF THE ARENA", true],
		["pit", "INTO THE PIT", true],
	]
	for s in stings:
		hud.call("show_stage_sting", str(s[1]), bool(s[2]))
		await _settle(12)
		_save(str(s[0]))
		hud.call("hide_endgame_sting")
	_save("clock")
	hud.call("show_ko_count", 7, "Clatterbox", false)
	await _settle(10)
	_save("ko-count")
	hud.call("show_result", "Out of the arena", "Tinribs")
	await _settle(10)
	_save("result-ring-out")
	hud.call("show_result", "Judges decision", "Clatterbox")
	await _settle(10)
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
		print("type_capture: ", file_name)
