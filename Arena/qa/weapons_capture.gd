extends Node
## QA (weapons gauntlet, 2026-09-25): one weapon on a legal machine, AI driven, against a
## plain box ram in the Yard, with frames saved at the moment it fires or lands: the fight
## camera and a closer side angle that shares the fight world. Windowed, short, then quits.
##
##   Godot --audio-driver Dummy --path Arena res://qa/weapons_capture.tscn -- \
##       --wg-weapon=axe --wg-out=DIR [--wg-max=4] [--wg-secs=45] [--wg-seed=11] \
##       [--wg-opp=plain|w:flipper]
##
## Files: DIR/<weapon>_<n>_<trigger>_fight.jpg and _close.jpg, plus DIR/<weapon>_log.txt.

const Gauntlet := preload("res://qa/weapons_gauntlet.gd")

var _fight: Node = null
var _weapon := "flipper"
var _out := ""
var _max := 4
var _secs := 45.0
var _seed := 11
var _opp := "plain"
var _hull := ""
var _contact_speed := 0.8
var _frames := 0
var _started := false
var _elapsed := 0.0
var _last_trigger := -10.0
var _triggers := 0
var _pending: Array = []      # [frame_due, index, tag, which]
var _close_vp: SubViewport = null
var _close_cam: Camera3D = null
var _me: Node = null
var _foe: Node = null
var _was_up := false
var _was_lifted := false
var _last_d := 99.0
var _log: PackedStringArray = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--wg-weapon="):
			_weapon = a.substr(12)
		elif a.begins_with("--wg-out="):
			_out = a.substr(9)
		elif a.begins_with("--wg-max="):
			_max = int(a.substr(9))
		elif a.begins_with("--wg-secs="):
			_secs = float(a.substr(10))
		elif a.begins_with("--wg-seed="):
			_seed = int(a.substr(10))
		elif a.begins_with("--wg-contact="):
			_contact_speed = float(a.substr(13))
		elif a.begins_with("--wg-hull="):
			_hull = a.substr(10)
		elif a.begins_with("--wg-opp="):
			_opp = a.substr(9)
	DirAccess.make_dir_recursive_absolute(_out)
	_fight = (load("res://fight/fight.tscn") as PackedScene).instantiate()
	add_child(_fight)


func _process(dt: float) -> void:
	_frames += 1
	if _frames == 3:
		_start()
		return
	if not _started:
		return
	_elapsed += dt
	_track_close_cam()
	_watch_throw()
	for p in _pending.duplicate():
		if _frames >= int(p[0]):
			_pending.erase(p)
			_save(int(p[1]), str(p[2]), str(p[3]))
	var done := (_triggers >= _max and _pending.is_empty()) or _elapsed > _secs \
		or (int(_fight.get("state")) == 3 and _pending.is_empty() and _elapsed > 3.0)
	if done:
		_log.append("end at %.1f s, state %d, triggers %d" % [_elapsed, int(_fight.get("state")), _triggers])
		var f := FileAccess.open("%s/%s_log.txt" % [_out, _weapon], FileAccess.WRITE)
		f.store_string("\n".join(_log) + "\n")
		f.close()
		get_tree().quit(0)


func _start() -> void:
	var config: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://fight/fixtures/stage3_config.json"))
	var a: Dictionary = Gauntlet.legal_build(_weapon, "player-1", "Subject", _hull)
	a["ai_skill"] = "national"
	a["temperament"] = "brawler"
	var b: Dictionary = Gauntlet.opponent_for(_weapon, _opp)
	b["ai_skill"] = "regional"
	b["temperament"] = "technician"
	config["seed"] = _seed
	config["arena"] = "yard"
	config["rules"] = {"mode": "fight", "duration_s": 150, "ko_count_s": 10}
	config["debug"] = {"opponent_ai": "normal", "player_ai": "normal"}
	config["bots"] = [a, b]
	_log.append("build %s/%s/%s vs %s/%s seed %d" % [a["chassis"], a["drive"], _weapon,
		b["chassis"], b["weapon"], _seed])
	_fight.call("start_fight", config)
	var bots: Array = _fight.get("_bots") as Array
	_me = bots[0]
	_foe = bots[1]
	_me.weapon_fired.connect(func() -> void: _trigger("fire"))
	_foe.damage_event.connect(func(info: Dictionary) -> void:
		if str(info.get("attacker", "")) == "player-1":
			_trigger("detach" if bool(info.get("detached", false)) else "hit"))
	_make_close_view()
	_started = true


func _make_close_view() -> void:
	var world := get_tree().root.find_child("World", true, false) as SubViewport
	_close_vp = SubViewport.new()
	_close_vp.size = Vector2i(960, 540)
	_close_vp.world_3d = world.find_world_3d()
	_close_vp.msaa_3d = Viewport.MSAA_4X
	_close_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_close_vp)
	_close_cam = Camera3D.new()
	_close_cam.fov = 38.0
	_close_vp.add_child(_close_cam)
	_close_cam.current = true


func _track_close_cam() -> void:
	if _close_cam == null or _me == null or _foe == null:
		return
	var mp: Vector3 = _me.chassis.global_position
	var fp: Vector3 = _foe.chassis.global_position
	var mid := (mp + fp) * 0.5
	var dir := Vector3(fp.x - mp.x, 0.0, fp.z - mp.z)
	if dir.length() < 0.01:
		dir = Vector3.RIGHT
	dir = dir.normalized()
	var side := dir.cross(Vector3.UP).normalized()
	var span := clampf(Vector2(fp.x - mp.x, fp.z - mp.z).length(), 0.8, 3.0)
	# the side facing the middle of the arena, so the wall is behind the machines and never
	# between them and the lens
	if side.dot(-Vector3(mid.x, 0.0, mid.z)) < 0.0:
		side = -side
	var eye := mid + side * (1.2 + span * 0.7) + Vector3.UP * 0.75 - dir * 0.35
	eye.x = clampf(eye.x, -4.3, 4.3)
	eye.z = clampf(eye.z, -4.3, 4.3)
	_close_cam.look_at_from_position(eye, mid + Vector3.UP * 0.12, Vector3.UP)


func _watch_throw() -> void:
	if _foe == null:
		return
	var fy: float = _foe.chassis.global_position.y
	var up: bool = fy > 0.45
	if up and not _was_up:
		_trigger("throw")
	_was_up = up
	# a lift (lifter, wedge) and a contact at speed (ram): neither raises an event of its own
	var lifted := fy > 0.2
	if lifted and not _was_lifted:
		_trigger("lift")
	_was_lifted = lifted
	var mp: Vector3 = _me.chassis.global_position
	var d := Vector2(mp.x - _foe.chassis.global_position.x, mp.z - _foe.chassis.global_position.z).length()
	var closing: float = _me.chassis.linear_velocity.length()
	if d < 1.0 and _last_d >= 1.0 and closing > _contact_speed:
		_trigger("contact")
	_last_d = d


func _trigger(tag: String) -> void:
	if _triggers >= _max or _elapsed - _last_trigger < 1.4:
		return
	_last_trigger = _elapsed
	_triggers += 1
	var n := _triggers
	_log.append("trigger %d %s at %.2f s (fight %.2f s)" % [n, tag, _elapsed, float(_fight.call("fight_time"))])
	_pending.append([_frames + 2, n, tag, "fight"])
	_pending.append([_frames + 2, n, tag, "close"])
	_pending.append([_frames + 8, n, tag, "fight_late"])


func _save(n: int, tag: String, which: String) -> void:
	var vp: Viewport = _close_vp if which == "close" else \
		get_tree().root.find_child("World", true, false) as Viewport
	var img := vp.get_texture().get_image()
	var w := 1206 if which != "close" else 960
	if img.get_width() > w:
		img.resize(w, int(img.get_height() * float(w) / img.get_width()), Image.INTERPOLATE_LANCZOS)
	var path := "%s/%s_%d_%s_%s.jpg" % [_out, _weapon, n, tag, which]
	img.save_jpg(path, 0.86)
	_log.append("saved " + path.get_file())
