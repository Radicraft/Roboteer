extends Node
## QA autoload: `--roboteer-shots=DIR[,interval_s[,count]]` saves viewport PNGs from a desktop run
## so the main session can review frames without screen-recording permission. No effect otherwise.

var _dir := ""
var _interval := 3.0
var _count := 10
var _next := 2.0
var _taken := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--roboteer-shots="):
			var parts := arg.substr(17).split(",")
			_dir = parts[0]
			if parts.size() > 1:
				_interval = float(parts[1])
			if parts.size() > 2:
				_count = int(parts[2])
	if _dir == "":
		set_process(false)
		return
	DirAccess.make_dir_recursive_absolute(_dir)


func _process(_dt: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	if t < _next or _taken >= _count:
		return
	_next = t + _interval
	_taken += 1
	var img := get_viewport().get_texture().get_image()
	var path := "%s/shot_%02d_%05.1fs.png" % [_dir, _taken, t]
	img.save_png(path)
	print("QaShots: saved ", path)
