extends SceneTree
## QA only (wave D, docs/wave-d-marshal-notes.md). Real fights in a real window, through the
## fight camera, stopped at each of the Marshal's beats and at the house bot's finishing
## ritual, for docs/look/marshal.html. Not referenced by any shipped scene.
##
##   Godot --path Arena --audio-driver Dummy --resolution 1206x556 \
##     --script qa/marshal_capture.gd -- --marshal-shots=DIR [--marshal-scenario=NAME,...]
##
## With `--write-movie DIR/clip.png --fixed-fps 30` and ONE scenario, Godot writes every frame
## of that scenario for a clip (docs/look/marshal/make_page.py turns them into WebP).
##
## Scenarios (what forces them, if anything, is said in the file names and on the page):
##   countdown   the fixture in the Coliseum: 3, 2, 1, FIGHT, the lift
##   count       Yard, both machines left idle: the player's knockout count, Marshal counting
##   lockup      Crush, the player driven (scripted) nose to nose into a charging opponent:
##               the rules' own lock-up break, Marshal's tow lines on the impulse tick
##   unstick     Grinder, the player driven (scripted) into the west wall: the unstick nudge
##   fire        Furnace, the opponent carries a flamethrower, the player idle: the spray
##   verdict     Yard, 14 s fight to the judges: POWER DOWN, the red bar, the crowd's verdict
##   ritual      Yard with THRESHER, 3 s count: the finishing ritual after the knockout
##   late        Grinder with GRUDGE, forced late: the late hit, the card, the back-off
##   wobble      Coliseum mid-fight, the Marshal knocked by hand (forced, for the laugh)

const FIGHT_SCENE := "res://fight/fight.tscn"
const FIXTURE := "res://fight/fixtures/stage3_config.json"
const ALL := ["countdown", "count", "lockup", "unstick", "fire", "verdict", "ritual", "late", "wobble"]

var _dir := ""
var _scenarios: Array = ALL.duplicate()
var _fight: Node = null
var _fixture: Dictionary = {}
var _saved: Array = []


func _initialize() -> void:
	for raw in OS.get_cmdline_user_args():
		var a := str(raw)
		if a.begins_with("--marshal-shots="):
			_dir = a.get_slice("=", 1)
		elif a.begins_with("--marshal-scenario="):
			_scenarios = Array(a.get_slice("=", 1).split(","))
	if _dir != "":
		DirAccess.make_dir_recursive_absolute(_dir)
	_run()


func _run() -> void:
	await process_frame
	_fight = (load(FIGHT_SCENE) as PackedScene).instantiate()
	root.add_child(_fight)
	for i in 5:
		await process_frame
	_fixture = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	for s in _scenarios:
		match str(s):
			"countdown": await countdown()
			"count": await count()
			"lockup": await lockup()
			"unstick": await unstick()
			"fire": await fire()
			"verdict": await verdict()
			"ritual": await ritual()
			"late": await late()
			"wobble": await wobble()
	print("marshal_capture: saved ", _saved.size(), " frames")
	quit(0)


# ---------------------------------------------------------------- scenarios

func countdown() -> void:
	var config := _config("coliseum", 60)
	_fight.call("start_fight", config)
	await _frames(20)
	await _until(func() -> bool: return _left() <= 2.55)
	_save("countdown_3")
	await _until(func() -> bool: return _left() <= 1.55)
	_save("countdown_2")
	await _until(func() -> bool: return _left() <= 0.55)
	_save("countdown_1")
	await _until(func() -> bool: return int(_fight.get("state")) == 2)
	await _frames(4)
	_save("countdown_fight")
	await _frames(40)
	_save("countdown_lift")
	await _frames(60)
	_save("patrol")


func count() -> void:
	var config := _config("yard", 60)
	(config["debug"] as Dictionary)["opponent_ai"] = "idle"
	_fight.call("start_fight", config)
	# Forced for the capture: the idle opponent is set down in the player's shot (the camera
	# frames the player), so its count, which the rules run, is where the lens is.
	await _frames(2)
	var bots: Array = _fight.call("bots")
	var p0: Vector3 = (bots[0].get("chassis") as Node3D).global_position
	_fight.call("set_down", bots[1], p0 + Vector3(1.6, 0.0, 1.2), Vector3(-1.0, 0.0, 0.0))
	await _until(func() -> bool: return _marshal_mode() == "count" and _bar() <= 8, 3000)
	await _frames(20)
	_save("count_8")
	await _until(func() -> bool: return _bar() <= 3, 900)
	await _frames(12)
	_save("count_3")


func lockup() -> void:
	# Forced for the capture: the two set down nose to nose in the open, the player's stick
	# held into the opponent (scripted), the opponent on "charge" with a ram (no button, so
	# nothing flips): a shoving match, which the rules break after 3 s. The break is theirs.
	var config := _config("yard", 60)
	(config["debug"] as Dictionary)["opponent_ai"] = "charge"
	((config["bots"] as Array)[1] as Dictionary)["weapon"] = "ram"
	_fight.call("start_fight", config, _hold(1.0, 0.0))
	await _frames(2)
	var bots: Array = _fight.call("bots")
	_fight.call("set_down", bots[0], Vector3(-2.6, 0.0, 2.4), Vector3(1.0, 0.0, 0.0))
	_fight.call("set_down", bots[1], Vector3(-1.75, 0.0, 2.4), Vector3(-1.0, 0.0, 0.0))
	await _until(func() -> bool: return _marshal_mode() == "tow", 3000)
	await _frames(25)
	_save("lockup_arming")
	await _until(func() -> bool: return _marshal().tow_line_visible(), 1200)
	await _frames(3)
	_save("lockup_tow")
	await _frames(12)
	_save("lockup_after")
	print("marshal_capture: lockup breaks ", _fight.get("lockup_breaks"))


func unstick() -> void:
	# Forced for the capture: the player set down facing the north wall with the stick held
	# into it (scripted). The rules' unstick nudge comes after 1.5 s wedged.
	var config := _config("yard", 60)
	(config["debug"] as Dictionary)["opponent_ai"] = "idle"
	_fight.call("start_fight", config, _hold(0.0, -1.0))
	await _frames(2)
	var bots: Array = _fight.call("bots")
	_fight.call("set_down", bots[0], Vector3(-1.0, 0.0, -4.2), Vector3(0.0, 0.0, -1.0))
	await _until(func() -> bool: return _marshal_mode() == "unstick", 3000)
	await _frames(20)
	_save("unstick_arming")
	await _until(func() -> bool: return _marshal().tow_line_visible(), 1200)
	await _frames(3)
	_save("unstick_tow")
	print("marshal_capture: unstick nudges ", _fight.get("unstick_nudges"))


func fire() -> void:
	var config := _config("furnace", 60)
	var foe: Dictionary = (config["bots"] as Array)[1]
	foe["weapon"] = "flamethrower"
	_fight.call("start_fight", config)
	await _until(func() -> bool: return _marshal().spraying(), 3600)
	await _frames(24)
	_save("fire_spray")
	await _frames(20)
	_save("fire_spray_2")


func verdict() -> void:
	var config := _config("yard", 14)
	_fight.call("start_fight", config)
	await _until(func() -> bool: return int(_fight.get("state")) == 3, 3000)
	await _frames(8)
	_save("stop_power_down")
	await _frames(50)
	_save("stop_verdict")
	print("marshal_capture: verdict events ", _fight.get("show_events"))


func ritual() -> void:
	var config := _config("yard", 60)
	var rules: Dictionary = config["rules"]
	rules["ko_count_s"] = 3
	rules["enforcer"] = "thresher"
	(config["presentation"] as Dictionary)["mischief"] = "ritual"
	_fight.call("start_fight", config)
	await _until(func() -> bool: return int(_fight.get("state")) == 3, 4000)
	_save("ritual_0_ko")
	await _until(func() -> bool: return _phase() == "approach", 600)
	await _frames(40)
	_save("ritual_1_approach")
	await _until(func() -> bool: return _phase() == "shove", 600)
	await _frames(30)
	_save("ritual_2_shove")
	await _until(func() -> bool: return _phase() in ["back", "done"], 600)
	_save("ritual_3_delivered")
	print("marshal_capture: ritual events ", _fight.get("show_events"))


func late() -> void:
	var config := _config("grinder", 60)
	var rules: Dictionary = config["rules"]
	rules["ko_count_s"] = 3
	rules["enforcer"] = "grudge"
	(config["presentation"] as Dictionary)["mischief"] = "late"
	_fight.call("start_fight", config)
	await _until(func() -> bool: return int(_fight.get("state")) == 3, 5000)
	await _until(func() -> bool: return _phase() == "shove", 900)
	await _frames(20)
	_save("late_1_shove")
	await _until(func() -> bool: return _phase() == "hit", 600)
	await _frames(10)
	_save("late_2_hit")
	await _until(func() -> bool: return _marshal().card_out(), 600)
	await _frames(14)
	_save("late_3_card")
	await _until(func() -> bool: return _phase() in ["back", "done"], 600)
	await _frames(20)
	_save("late_4_back_off")
	print("marshal_capture: late events ", _fight.get("show_events"))


func wobble() -> void:
	var config := _config("coliseum", 60)
	_fight.call("start_fight", config)
	await _until(func() -> bool: return int(_fight.get("state")) == 2, 3000)
	await _frames(150)
	_marshal().knock(Vector3(3.0, 0.5, 1.0))
	await _frames(5)
	_save("wobble_forced")
	await _frames(10)
	_save("wobble_forced_2")


# ---------------------------------------------------------------- helpers

func _config(arena_id: String, seconds: int) -> Dictionary:
	var config := _fixture.duplicate(true)
	config["arena"] = arena_id
	(config["rules"] as Dictionary)["duration_s"] = seconds
	return config


## A replay script holding the stick one way for a minute (a sparse script is idle between rows).
func _hold(x: float, y: float) -> Array:
	var rows: Array = []
	for t in range(1, 3601):
		rows.append([t, x, y, 0, 0, 0.0, 0])
	return rows


func _marshal() -> FightMarshal:
	return _fight.call("marshal") as FightMarshal


func _marshal_mode() -> String:
	var m := _marshal()
	return m.mode if m != null else ""


func _bar() -> int:
	var m := _marshal()
	return m.bar_lit() if m != null else -1


func _left() -> float:
	return FightTypes.COUNTDOWN_S - float(_fight.get("_countdown_time"))


func _phase() -> String:
	var mis: FightMischief = _fight.call("mischief")
	return mis.phase if mis != null else ""


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _until(cond: Callable, budget: int = 2000) -> void:
	var n := 0
	while not bool(cond.call()) and n < budget:
		await process_frame
		n += 1
	if n >= budget:
		print("marshal_capture: gave up waiting (%d frames)" % budget)


func _save(file_name: String) -> void:
	_saved.append(file_name)
	if _dir == "":
		return
	var img := root.get_texture().get_image()
	if img != null:
		img.save_png(_dir.path_join(file_name + ".png"))
	var where := ""
	var cam: Camera3D = _fight.call("_fight_camera")
	var m := _marshal()
	if cam != null and m != null:
		var size := cam.get_viewport().get_visible_rect().size
		var at := cam.unproject_position(m.global_position) / size
		var tgt := cam.unproject_position(m.get("_target")) / size
		where = " screen (%.2f, %.2f) target (%.2f, %.2f) height %.2f fov %.1f keep %d vp %s" % [at.x, at.y, tgt.x, tgt.y, m.global_position.y, cam.fov, cam.keep_aspect, str(size)]
	print("marshal_capture: ", file_name, " marshal ", _marshal_mode(), " bar ", _bar(), where)
