extends Node
## QA only (arena art pre-production, docs/aaa/arenas.md): runs the desktop fixture fight in
## the arena named by `--roboteer-capture-arena=<id>` so QaShots can save fight-camera frames.
## Not referenced by any shipped scene. Run:
##   Godot --path Arena res://qa/arena_capture.tscn -- --roboteer-capture-arena=furnace \
##     --roboteer-player-ai=charge --roboteer-shots=DIR,4,6

var _frames := 0
var _fight: Node = null


func _ready() -> void:
	_fight = (load("res://fight/fight.tscn") as PackedScene).instantiate()
	add_child(_fight)


var _wide_at := -1.0
var _elapsed := 0.0


func _process(dt: float) -> void:
	_frames += 1
	_elapsed += dt
	if _wide_at > 0.0 and _elapsed >= _wide_at:
		_wide_at = -1.0
		_add_wide_camera()
	if _frames != 3:
		return
	var arena := "yard"
	var player_ai := "charge"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--roboteer-capture-arena="):
			arena = a.substr(25)
		elif a.begins_with("--roboteer-player-ai="):
			player_ai = a.substr(21)
		elif a.begins_with("--roboteer-capture-wide="):
			_wide_at = float(a.substr(24))
	var config: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://fight/fixtures/stage3_config.json"))
	config["arena"] = arena
	var debug: Dictionary = config.get("debug", {}) as Dictionary
	debug["player_ai"] = player_ai
	debug["opponent_ai"] = "normal"
	config["debug"] = debug
	var rules: Dictionary = config.get("rules", {}) as Dictionary
	rules["duration_s"] = 180
	config["rules"] = rules
	print("arena_capture: starting ", arena)
	_fight.call("start_fight", config)


## An establishing pose for the review page only: the rig's yaw, pulled back and lowered so
## the surroundings (or the lack of them) are in frame. The fight camera is left alone.
func _add_wide_camera() -> void:
	var world := get_tree().root.find_child("World", true, false)
	if world == null:
		return
	var cam := Camera3D.new()
	cam.fov = 28.0
	world.add_child(cam)
	var d := 22.0
	var pitch := deg_to_rad(34.0)
	var h := d * cos(pitch) / sqrt(2.0)
	cam.global_position = Vector3(-h, d * sin(pitch), -h)
	cam.look_at(Vector3(0.0, 0.3, 0.0), Vector3.UP)
	cam.current = true
