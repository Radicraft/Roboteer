extends Node
## QA (systems gauntlet, 2026-09-25): one fight windowed, frames saved at chosen fight times
## from the fight camera (the World viewport) and a close camera on machine A (or on the
## house bot with --sc-follow=house). Short, then quits. For docs/look/systems-gauntlet.html.
##
##   Godot --audio-driver Dummy --path Arena res://qa/systems_capture.tscn -- \
##       --sc-name=legs --sc-arena=yard --sc-a=wedge/legs/flipper --sc-b=box/4wd/ram \
##       [--sc-boss=grudge] [--sc-house=career|none|<id>] [--sc-endgame=120] [--sc-secs=180] \
##       [--sc-times=4,10,20] [--sc-seed=11] [--sc-follow=a|house] [--sc-place=x,z] [--sc-idle] --sc-out=DIR

const AG := preload("res://qa/arena_gauntlet.gd")

var _fight: Node = null
var _name := "cap"
var _arena := "yard"
var _a := "wedge/4wd/flipper"
var _b := "box/4wd/ram"
var _boss := ""
var _house := "none"
var _endgame := 120
var _secs := 180
var _times: Array = [4.0, 10.0]
var _seed := 11
var _follow := "a"
var _place := ""
var _idle := false
var _out := "/tmp"
var _frames := 0
var _started := false
var _close_vp: SubViewport = null
var _close_cam: Camera3D = null
var _log: PackedStringArray = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.split("=", true, 1)
		var v := kv[1] if kv.size() > 1 else ""
		match kv[0]:
			"--sc-name": _name = v
			"--sc-arena": _arena = v
			"--sc-a": _a = v
			"--sc-b": _b = v
			"--sc-boss": _boss = v
			"--sc-house": _house = v
			"--sc-endgame": _endgame = int(v)
			"--sc-secs": _secs = int(v)
			"--sc-seed": _seed = int(v)
			"--sc-follow": _follow = v
			"--sc-place": _place = v
			"--sc-idle": _idle = true
			"--sc-out": _out = v
			"--sc-times":
				_times = []
				for t in v.split(","):
					_times.append(float(t))
	DirAccess.make_dir_recursive_absolute(_out)
	_fight = (load("res://fight/fight.tscn") as PackedScene).instantiate()
	add_child(_fight)


func _process(_dt: float) -> void:
	_frames += 1
	if _frames == 3:
		_start()
		return
	if not _started:
		return
	if _frames == 5 and _close_vp == null:
		_make_close_view()
	var state := int(_fight.get("state"))
	var t := float(_fight.call("fight_time"))
	if state == 2 and _place != "" and int(_fight.get("_tick")) >= 1:
		var xz := _place.split(",")
		_fight.call("set_down", (_fight.get("_bots") as Array)[0], Vector3(float(xz[0]), 0.3, float(xz[1])), Vector3.RIGHT)
		_place = ""
	_track()
	if not _times.is_empty() and (t >= float(_times[0]) or state == 3):
		var at := float(_times.pop_front())
		_save("%s_%03d" % [_name, int(at)])
		if state == 3:
			_times.clear()
	if _times.is_empty() or _frames > 60 * 60 * 8:
		var f := FileAccess.open("%s/%s_log.txt" % [_out, _name], FileAccess.WRITE)
		f.store_string("\n".join(_log) + "\n")
		f.close()
		get_tree().quit(0)


func _start() -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://fight/fixtures/stage3_config.json"))
	var a: Dictionary = AG.build_from(_a, "player-1", "A")
	a["ai_skill"] = "national"
	a["temperament"] = "brawler"
	var b: Dictionary = AG.boss_build(_boss, "ai-1") if _boss != "" else AG.build_from(_b, "ai-1", "B")
	b["controller"] = "ai"
	var rules := {"mode": "fight", "duration_s": _secs, "ko_count_s": 999 if _idle else 10, "endgame_at_s": _endgame}
	if _house != "none":
		var h: Array = AG.career_house(_arena) if _house == "career" else [_house, 1.0]
		rules["enforcer"] = h[0]
		rules["enforcer_mode"] = "zone"
		rules["enforcer_speed"] = float(h[1])
	config["seed"] = _seed
	config["arena"] = _arena
	config["rules"] = rules
	var mode := "idle" if _idle else "normal"
	config["debug"] = {"opponent_ai": mode, "player_ai": mode}
	config["bots"] = [a, b]
	_log.append(JSON.stringify(rules) + " " + _a + " vs " + (_boss if _boss != "" else _b))
	_fight.call("start_fight", config)
	_started = true


func _make_close_view() -> void:
	var world := get_tree().root.find_child("World", true, false) as SubViewport
	if world == null:
		return
	_close_vp = SubViewport.new()
	_close_vp.size = Vector2i(960, 540)
	_close_vp.world_3d = world.find_world_3d()
	_close_vp.msaa_3d = Viewport.MSAA_4X
	_close_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_close_vp)
	_close_cam = Camera3D.new()
	_close_cam.fov = 40.0
	_close_vp.add_child(_close_cam)
	_close_cam.current = true


func _target() -> Node3D:
	if _follow == "house":
		var e: Node = _fight.get("_enforcer")
		if e != null and is_instance_valid(e):
			return e.get("chassis")
	var bots: Array = _fight.get("_bots") as Array
	return bots[0].get("chassis") if bots.size() > 0 and bots[0] != null else null


func _track() -> void:
	if _close_cam == null:
		return
	var tgt := _target()
	if tgt == null or not is_instance_valid(tgt):
		return
	var p := tgt.global_position
	var out := Vector3(p.x, 0.0, p.z)
	var dir := (-out).normalized() if out.length() > 0.5 else Vector3(0, 0, 1)
	_close_cam.global_position = p - dir * 2.2 + Vector3(0, 1.3, 0)
	_close_cam.look_at(p + Vector3(0, 0.1, 0), Vector3.UP)


func _save(stem: String) -> void:
	var world := get_tree().root.find_child("World", true, false) as Viewport
	for pair in [[world, "fight", 1206], [_close_vp, "close", 960]]:
		var vp: Viewport = pair[0]
		if vp == null:
			continue
		var img := vp.get_texture().get_image()
		var w := int(pair[2])
		if img.get_width() > w:
			img.resize(w, int(img.get_height() * float(w) / img.get_width()), Image.INTERPOLATE_LANCZOS)
		var path := "%s/%s_%s.jpg" % [_out, stem, pair[1]]
		img.save_jpg(path, 0.84)
		_log.append("saved %s at %.1f s" % [path.get_file(), float(_fight.call("fight_time"))])
