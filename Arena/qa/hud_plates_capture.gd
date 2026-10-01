extends SceneTree
## QA only (wave E HUD plates, docs/wave-e-hud-notes.md). Starts the fixture fight in a real
## window, freezes it after the countdown and stamps every plate the fight feed draws, so the
## plates can be checked upright, uncut and unstroked at a phone's shape:
##
##   Godot --path Arena --audio-driver Dummy --resolution 1748x804 \
##     --script qa/hud_plates_capture.gd -- --hud-shots=DIR [--hud-safe=124,0,124,42] \
##     [--hud-arena=yard]
##
## Files: fight (clock 2:58, scrap 1280, both name plates with their condition bars), clock-low
## (0:10, urgent), power-down, stage-sting, payoff-sting, ko-count, result-judges, coach, intro-card,
## intro-hazard, walkout-card, walkout-compact, big-screen (the venue screen's own graphics,
## as the LED face samples them), big-screen-sting. Not referenced by any shipped scene.

const FIGHT_SCENE := "res://fight/fight.tscn"
const FIXTURE := "res://fight/fixtures/stage3_config.json"

var _dir := ""
var _arena := "yard"
var _safe := {}
var _fight: Node = null


func _initialize() -> void:
	for raw in OS.get_cmdline_user_args():
		var a := str(raw)
		if a.begins_with("--hud-shots="):
			_dir = a.get_slice("=", 1)
		elif a.begins_with("--hud-arena="):
			_arena = a.get_slice("=", 1)
		elif a.begins_with("--hud-safe="):
			var p := a.get_slice("=", 1).split(",")
			if p.size() == 4:
				_safe = {"left": float(p[0]), "top": float(p[1]), "right": float(p[2]),
					"bottom": float(p[3])}
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
	if not _safe.is_empty():
		if not config.has("presentation"):
			config["presentation"] = {}
		(config["presentation"] as Dictionary)["safe_area_px"] = _safe
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
	hud.call("set_condition", 0.72, 0.41)
	await _settle(40)
	_save("fight")
	hud.call("set_time_left", 9.2)
	hud.call("set_scrap", 45)
	hud.call("set_condition", 0.2, 0.55)
	await _settle(40)
	_save("clock-low")
	hud.call("set_time_left", 0.0)
	hud.call("show_stage_sting", "POWER DOWN", false)
	await _settle(14)
	_save("power-down")
	hud.call("show_stage_sting", "HAZARDS UP", false)
	await _settle(14)
	_save("stage-sting")
	hud.call("show_stage_sting", "INTO THE PIT", true)
	await _settle(14)
	_save("payoff-sting")
	hud.call("hide_endgame_sting")
	await _settle(14)
	hud.call("show_ko_count", 7, "Clatterbox", false)
	await _settle(10)
	_save("ko-count")
	hud.call("hide_ko_count")
	hud.call("show_result", "Judges decision", "Clatterbox")
	await _settle(30)
	_save("result-judges")
	hud.call("hide_result")
	hud.call("set_coach", true)
	hud.call("set_coach_phase", "countdown")
	await _settle(20)
	_save("coach")
	hud.call("set_coach", false)
	await _settle(4)

	var vp_size := root.get_visible_rect().size
	var intro := IntroOverlay.new()
	root.add_child(intro)
	intro.set_safe_area(_safe)
	intro.show_card("THE YARD", "Scrapyard tier. Round one of four.", false)
	await _settle(50)
	_save("intro-card")
	intro.show_card("THE CRUSHER", "A hazard. It closes every 20 seconds.", true)
	await _settle(50)
	_save("intro-hazard")
	intro.queue_free()

	var tape := TapeCardOverlay.new()
	root.add_child(tape)
	tape.set_safe_area(_safe)
	var card := {"label": "BLUE CORNER", "name": "Clatterbox", "roboteer": "Built by Penny Dread",
		"mass": "89.5 kg", "drive": "4WD", "weapon": "Flipper",
		"stats": [{"label": "TOP SPEED", "value": "4.2 m/s"}, {"label": "ARMOUR", "value": "3/5"},
			{"label": "PUSH", "value": "1,200 N"}],
		"record": "Won 2, lost 1",
		"strength": "Gets under anything with a flat nose and throws it.",
		"weakness": "Slow to turn once it has committed to a charge."}
	tape.show_card(card)
	await _settle(40)
	_save("walkout-card")
	tape.clear()
	await _settle(2)
	tape.show_card({"label": "HOUSE BOT", "name": "Thresher",
		"strength": "Sweeps the corner with a spinning drum.",
		"weakness": "Never leaves its corner."}, true)
	await _settle(40)
	_save("walkout-compact")
	tape.queue_free()

	var screen := _find_screen(root)
	if screen != null:
		await _settle(10)
		_save_viewport(screen.get("_vp") as SubViewport, "big-screen")
		screen.call("sting", "POWER DOWN", 3.0)
		await _settle(10)
		_save_viewport(screen.get("_vp") as SubViewport, "big-screen-sting")
	else:
		print("hud_plates_capture: no venue screen in ", _arena)
	print("hud_plates_capture: done at ", vp_size)
	quit(0)


func _find_screen(n: Node) -> Node:
	if n is VenueScreen:
		return n
	for c in n.get_children():
		var f := _find_screen(c)
		if f != null:
			return f
	return null


func _settle(frames: int) -> void:
	for i in frames:
		await process_frame


func _save(file_name: String) -> void:
	if _dir == "":
		return
	var img := root.get_texture().get_image()
	if img != null:
		img.save_png(_dir.path_join(file_name + ".png"))
		print("hud_plates_capture: ", file_name)


func _save_viewport(vp: SubViewport, file_name: String) -> void:
	if _dir == "" or vp == null:
		return
	var img := vp.get_texture().get_image()
	if img != null:
		img.save_png(_dir.path_join(file_name + ".png"))
		print("hud_plates_capture: ", file_name)
