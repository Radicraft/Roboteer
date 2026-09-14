extends Node
## QA autoload: `--roboteer-shots=DIR[,interval_s[,count]]` saves viewport PNGs from a desktop run
## so the main session can review frames without screen-recording permission. No effect otherwise.

var _dir := ""
var _interval := 3.0
var _count := 10
var _next := 2.0
var _taken := 0
## `--roboteer-shots-on-scrap`: also take three frames (0.1, 0.45, 0.9 s) after every scrap award.
var _on_scrap := false
var _fight: Node = null
var _burst: Array = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--roboteer-shots="):
			var parts := arg.substr(17).split(",")
			_dir = parts[0]
			if parts.size() > 1:
				_interval = float(parts[1])
			if parts.size() > 2:
				_count = int(parts[2])
	_on_scrap = "--roboteer-shots-on-scrap" in OS.get_cmdline_user_args()
	if _dir == "":
		set_process(false)
		return
	DirAccess.make_dir_recursive_absolute(_dir)


func _process(_dt: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	if _on_scrap and _fight == null:
		_fight = get_tree().root.find_child("Fight", true, false)
		if _fight != null and _fight.has_signal("scrap_awarded"):
			_fight.scrap_awarded.connect(_on_scrap_awarded)
	while not _burst.is_empty() and t >= float(_burst[0]):
		_burst.pop_front()
		_save(t, "scrap")
	if t < _next or _taken >= _count:
		return
	_next = t + _interval
	_save(t, "shot")


func _on_scrap_awarded(_bot_id: String, _amount: int, _pos: Vector3) -> void:
	if _burst.size() < 6:
		var t := Time.get_ticks_msec() / 1000.0
		_burst.append_array([t + 0.1, t + 0.45, t + 0.9])


func _save(t: float, tag: String) -> void:
	_taken += 1
	# Off-screen windows are not composited by macOS, so the root viewport goes stale; the fight
	# world renders into its own SubViewport texture, which is always drawn. Prefer that.
	var vp: Viewport = get_viewport()
	var world_vp := get_tree().root.find_child("World", true, false)
	if world_vp is SubViewport:
		vp = world_vp
	var img := vp.get_texture().get_image()
	var path := "%s/%s_%02d_%05.1fs.png" % [_dir, tag, _taken, t]
	img.save_png(path)
	print("QaShots: saved ", path)
