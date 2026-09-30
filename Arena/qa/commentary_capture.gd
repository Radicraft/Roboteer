extends SceneTree
## QA only (wave D commentary). Runs a real AI-vs-AI fight in a window at 2x the owner's
## phone (874 x 402 pt landscape -> 1748 x 804 px, with the phone's safe insets) and saves
## the ticker carrying personality lines, in sentence case and in capitals, plus one with a
## payoff band over the ticker:
##
##   Godot --path Arena --audio-driver Dummy --resolution 1748x804 --always-on-top \
##     --script qa/commentary_capture.gd -- --shots=DIR [--arena=furnace]
##
## Not referenced by any shipped scene.

const FIGHT_SCENE := "res://fight/fight.tscn"
const FIXTURE := "res://fight/fixtures/stage3_config.json"

var _dir := ""
var _arena := "furnace"
var _fight: Node = null


func _initialize() -> void:
	for raw in OS.get_cmdline_user_args():
		var a := str(raw)
		if a.begins_with("--shots="):
			_dir = a.get_slice("=", 1)
		elif a.begins_with("--arena="):
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
	config["seed"] = 33
	config["rules"] = {"mode": "fight", "duration_s": 180, "ko_count_s": 10, "endgame_at_s": 120}
	config["debug"] = {"opponent_ai": "normal", "player_ai": "normal"}
	(config["bots"] as Array)[1]["name"] = "Hob Nail"
	config["presentation"] = {"safe_area_px": {"left": 124, "top": 0, "right": 124, "bottom": 42},
		"haptics": false}
	_fight.call("start_fight", config)
	var hud: Node = _fight.get("_hud")
	var guard := 0
	while _fight.call("_state_name", _fight.get("state")) != "fighting" and guard < 900:
		guard += 1
		await process_frame
	# Let them close and fight a little so there is action behind the ticker.
	await _settle(60 * 5)
	var shots := [
		["ticker-sentence", "Tinribs' flipper launches Hob Nail. Air miles for Hob Nail!", false],
		["ticker-caps", "TINRIBS' FLIPPER LAUNCHES HOB NAIL. AIR MILES FOR HOB NAIL!", false],
		["ticker-long", "Nothing between Tinribs and Hob Nail on paper. Paper won't help either of them.", false],
		["ticker-payoff", "Flame on! Hob Nail holds Tinribs in the fire.", true],
	]
	for s in shots:
		if bool(s[2]):
			hud.call("show_stage_sting", "INTO THE FIRE", true)
		hud.call("say_commentary", str(s[1]), 3.0, true)
		await _settle(24)
		_save(str(s[0]))
		hud.call("hide_endgame_sting")
		await _settle(60 * 2)
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
		print("commentary_capture: ", file_name)
