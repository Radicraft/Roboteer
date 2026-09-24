extends Node3D
## Wave A (models) QA: the workshop stage with the hero build (Tinribs) on a parked
## turntable, seen from a FIXED camera, so a before and an after frame are comparable.
## Run (windowed, Forward+):
##   Godot --path Arena res://qa/hero_capture.tscn -- --roboteer-shots=DIR,3,2 \
##       --hero-cam=menu|three_quarter|flipper|wheel [--hero-yaw=38]
## `menu` is docs/look/reference-study.md 3.2 item 1: 27 degrees vertical (50 mm),
## 2.8 m out, 0.55 m above the stage top, pitched down 8 degrees.

const CAMS := {
	# name: [fov_v_deg, distance_m, yaw_deg, height_m, look_offset (bot space)]
	"menu": [27.0, 2.8, 38.0, 0.55, Vector3(0.0, 0.0, 0.0)],
	"three_quarter": [20.0, 2.4, 38.0, 0.45, Vector3(0.0, 0.0, 0.0)],
	"flipper": [16.0, 1.9, 20.0, 0.70, Vector3(0.25, 0.0, 0.0)],
	"wheel": [12.0, 1.6, 70.0, 0.20, Vector3(0.10, 0.0, 0.30)],
	"rear": [20.0, 2.4, 150.0, 0.60, Vector3(0.0, 0.0, 0.0)],
}

var _stage: Node3D = null
var _cam: Camera3D = null
var _name := "menu"
var _yaw_extra := 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hero-cam="):
			_name = a.substr(11)
		elif a.begins_with("--hero-yaw="):
			_yaw_extra = float(a.substr(11))
	_stage = WorkshopStage.new()
	_stage.name = "Stage"
	add_child(_stage)
	var cfg_text := FileAccess.get_file_as_string("res://fight/fixtures/stage3_config.json")
	var config: Dictionary = JSON.parse_string(cfg_text)
	_stage.show_bot((config["bots"] as Array)[0])
	_stage.set_auto_rotate(false)
	_cam = Camera3D.new()
	_cam.name = "HeroCam"
	add_child(_cam)
	_cam.current = true
	print("hero_capture ready, camera ", _name)


func _process(_delta: float) -> void:
	var bot := _stage.get("_bot") as Node3D
	if bot == null or _cam == null:
		return
	var c: Array = CAMS.get(_name, CAMS["menu"])
	var basis := bot.global_transform.basis
	var target := bot.global_transform * (c[4] as Vector3)
	var yaw := deg_to_rad(float(c[2]) + _yaw_extra)
	# bot +X is the nose, +Z its right; yaw swings from the nose toward the right
	var dir := (basis.x * cos(yaw) + basis.z * sin(yaw)).normalized()
	var dist := float(c[1])
	var eye := target + dir * dist + Vector3.UP * float(c[3])
	_cam.fov = float(c[0])
	_cam.look_at_from_position(eye, target + Vector3.UP * 0.02, Vector3.UP)
