extends SceneTree
## QA only (wave B intro, docs/wave-b-intro-notes.md). Plays the full fight intro in each
## arena in a real window and saves frames from it, for the contact sheet:
##
##   Godot --path Arena --audio-driver Dummy --resolution 1206x556 \
##     --script qa/intro_capture.gd -- --intro-shots=DIR [--intro-arenas=yard,crush] \
##     [--intro-mode=full|short] [--intro-sequence=12]
##
## Per arena: one frame late in each shot (the hazard mid-act), one mid-drop, and the first
## frame of the countdown (the fight camera, YOU over the machine). Files are
## <arena>_<nn>_<label>.png. `--intro-sequence=FPS` also saves every 1/FPS s of the whole
## intro as <arena>_seq_<nnn>.png. Not referenced by any shipped scene.

const FIGHT_SCENE := "res://fight/fight.tscn"
const FIXTURE := "res://fight/fixtures/stage3_config.json"
const ORDER := ["yard", "grinder", "drop_zone", "furnace", "crush", "coliseum"]

var _dir := ""
var _arenas: Array = ORDER.duplicate()
var _mode := "full"
var _seq_fps := 0.0
var _fight: Node = null


func _initialize() -> void:
	for raw in OS.get_cmdline_user_args():
		var a := str(raw)
		if a.begins_with("--intro-shots="):
			_dir = a.get_slice("=", 1)
		elif a.begins_with("--intro-arenas="):
			_arenas = Array(a.get_slice("=", 1).split(","))
		elif a.begins_with("--intro-mode="):
			_mode = a.get_slice("=", 1)
		elif a.begins_with("--intro-sequence="):
			_seq_fps = float(a.get_slice("=", 1))
	if _dir != "":
		DirAccess.make_dir_recursive_absolute(_dir)
	_run()


func _run() -> void:
	await process_frame
	_fight = (load(FIGHT_SCENE) as PackedScene).instantiate()
	root.add_child(_fight)
	for i in 5:
		await process_frame
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	for arena_id in _arenas:
		await _shoot(fixture, str(arena_id))
	quit(0)


func _shoot(fixture: Dictionary, arena_id: String) -> void:
	var config := fixture.duplicate(true)
	config["arena"] = arena_id
	config["intro"] = _mode
	(config["rules"] as Dictionary)["duration_s"] = 180
	# Freeze the intro while the venue builds and the shaders compile, then run it at 1x.
	FightIntro.test_speed = 0.0
	_fight.call("start_fight", config)
	for i in 45:
		await process_frame
	var intro: FightIntro = _fight.call("intro")
	if intro == null:
		print("intro_capture: no intro in ", arena_id)
		return
	var plan: Array = []          # [time, label]
	var t := 0.0
	var n := 0
	for s in intro.shots():
		var shot: Dictionary = s
		var dur := float(shot["dur"])
		var label := str(shot.get("title", "")).to_lower().replace(" ", "-")
		if str(shot["kind"]) == "drop":
			plan.append([t + dur * 0.55, "%02d_drop" % n])
		else:
			plan.append([t + dur * (0.82 if str(shot["kind"]) == "hazard" else 0.6),
				"%02d_%s" % [n, label if label != "" else str(shot["kind"])]])
		t += dur
		n += 1
	print("intro_capture: %s %s, %.2f s, %d shots" % [arena_id, _mode, t, n])
	FightIntro.test_speed = 1.0
	var next_seq := 0.0
	var seq_n := 0
	while intro != null and is_instance_valid(intro) and intro.holding():
		var now := intro.elapsed()
		if not plan.is_empty() and now >= float(plan[0][0]):
			_save("%s_%s" % [arena_id, str(plan[0][1])])
			plan.pop_front()
		if _seq_fps > 0.0 and now >= next_seq:
			_save("%s_seq_%03d" % [arena_id, seq_n])
			seq_n += 1
			next_seq += 1.0 / _seq_fps
		await process_frame
	# The countdown's first frames: the fight camera, YOU over the machine, the "3".
	for i in 12:
		await process_frame
	_save("%s_%02d_countdown" % [arena_id, n])


func _save(file_name: String) -> void:
	if _dir == "":
		return
	var img := root.get_texture().get_image()
	if img != null:
		img.save_png(_dir.path_join(file_name + ".png"))
