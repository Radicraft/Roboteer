extends SceneTree
## Scratch (wave B pacing): capture the fight HUD with the BOOST button, ready and charging,
## with the coach callouts up. Windowed only. Not a test (leading underscore).
##   Godot --path Arena --resolution 1206x556 --script tests/_boost_capture.gd -- --out=DIR

const FIGHT_SCENE := "res://fight/fight.tscn"
const FIXTURE := "res://fight/fixtures/stage3_config.json"
var _out := "/tmp"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	_run()


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(name))
	print("SHOT ", _out.path_join(name))


func _run() -> void:
	await process_frame
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	config["coach"] = true
	config["arena"] = "yard"
	var fight: Node = (load(FIGHT_SCENE) as PackedScene).instantiate()
	root.add_child(fight)
	await process_frame
	fight.call("start_fight", config)
	var guard := 0
	while int(fight.get("state")) != 2 and guard < 900:
		await physics_frame
		guard += 1
	for i in 30:
		await physics_frame
	print("STATE ", fight.get("state"), " guard ", guard)
	await _shot("boost_ready_coach.png")
	var controls: Node = root.find_child("*", true, false)
	for n in root.find_children("*", "FightControls", true, false):
		controls = n
	var t := InputEventScreenTouch.new()
	t.index = 3
	t.position = controls.call("boost_centre")
	t.pressed = true
	controls.call("handle_event", t)
	for i in 3:
		await physics_frame
	await _shot("boost_pressed.png")
	t = t.duplicate()
	t.pressed = false
	controls.call("handle_event", t)
	for i in 60:
		await physics_frame
	await _shot("boost_charging.png")
	quit(0)
